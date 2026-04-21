import Foundation
import Combine
import SwiftUI
import os

/// Orchestrates polling, scanning, and publishing state to the UI.
///
/// Work is split: the expensive path (process enumeration, detail fetch,
/// worktree scan, git-branch reads) runs on a background serial queue;
/// published `@Published` properties are mutated on the main queue so SwiftUI
/// observers don't see mid-publish thread hops.
final class AppViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "ui")

    @Published private(set) var groups: [WorktreeGroup] = []
    @Published private(set) var apps: [AppGroup] = []
    @Published private(set) var system: SystemSnapshot?
    @Published private(set) var isActive: Bool = false
    @Published private(set) var showBranch: Bool = true
    @Published var configError: String?

    private let scanner: ProcessScanner
    private let systemMonitor = SystemMonitor()
    private let worktreesProvider: () -> [Worktree]
    private let configProvider: () -> Config
    private var timer: Timer?
    private let scanQueue = DispatchQueue(label: "com.carlos.procbar.scan", qos: .userInitiated)

    /// Cached worktree result. Refreshed at most every `worktreeTTL` seconds
    /// rather than on every tick — fs walks and git-HEAD reads are expensive
    /// relative to the 2s polling cadence.
    private var cachedWorktrees: [Worktree] = []
    private var cachedAt: Date?
    private let worktreeTTL: TimeInterval = 30

    init(
        scanner: ProcessScanner,
        worktreesProvider: @escaping () -> [Worktree],
        configProvider: @escaping () -> Config
    ) {
        self.scanner = scanner
        self.worktreesProvider = worktreesProvider
        self.configProvider = configProvider
    }

    @MainActor
    func start() {
        stop()
        let interval = TimeInterval(configProvider().refreshIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.scheduleTick()
        }
        scheduleTick()
    }

    @MainActor
    func stop() {
        timer?.invalidate()
        timer = nil
    }

    /// Test-friendly synchronous tick. Runs the scan inline on the current
    /// thread and publishes immediately; production path should call
    /// `scheduleTick()` so scanning stays off the main actor.
    @MainActor
    func tickOnce() {
        let snapshot = performScan(forceWorktreeRefresh: true)
        publish(snapshot: snapshot)
    }

    private func scheduleTick() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.performScan(forceWorktreeRefresh: false)
            DispatchQueue.main.async { [weak self] in
                self?.publish(snapshot: snapshot)
            }
        }
    }

    private struct Snapshot {
        let groups: [WorktreeGroup]
        let apps: [AppGroup]
        let system: SystemSnapshot
        let isActive: Bool
        let showBranch: Bool
    }

    private func performScan(forceWorktreeRefresh: Bool) -> Snapshot {
        let cfg = configProvider()
        let raw = scanner.listRaw()

        // Union of pattern-matched + app-matched PIDs so one details pass
        // covers both trackers. AppGroup uses the same TrackedProcess
        // instances as WorktreeGroup — shared tracking keeps the view model
        // consistent and the scan minimal.
        let patternPIDs = ProcessMatcher.matchPIDs(patterns: cfg.processPatterns, raw: raw)
        let appPIDs     = ProcessMatcher.matchAppPIDs(apps: cfg.apps, raw: raw)
        let allMatched  = Array(Set(patternPIDs + appPIDs))

        let result = scanner.sampleDetails(
            matchPIDs: allMatched,
            raw: raw,
            activity: cfg.activity
        )
        let worktrees = worktreesCached(force: forceWorktreeRefresh)
        let grouped = ProcessMatcher.group(
            tracked: result.tracked,
            worktrees: worktrees,
            excluded: cfg.excludedPaths
        )
        let appGroups = ProcessMatcher.groupApps(
            apps: cfg.apps,
            tracked: result.tracked,
            raw: raw
        )
        let sys = systemMonitor.sample()
        return Snapshot(
            groups: grouped,
            apps: appGroups,
            system: sys,
            isActive: !grouped.isEmpty || !appGroups.isEmpty,
            showBranch: cfg.showBranch
        )
    }

    private func worktreesCached(force: Bool) -> [Worktree] {
        if !force,
           let stamp = cachedAt,
           Date().timeIntervalSince(stamp) < worktreeTTL,
           !cachedWorktrees.isEmpty {
            return cachedWorktrees
        }
        let wts = worktreesProvider()
        cachedWorktrees = wts
        cachedAt = Date()
        return wts
    }

    @MainActor
    private func publish(snapshot: Snapshot) {
        self.groups = snapshot.groups
        self.apps = snapshot.apps
        self.system = snapshot.system
        self.isActive = snapshot.isActive
        self.showBranch = snapshot.showBranch
    }

    /// Invalidates the worktree cache so the next tick re-scans. Call when
    /// config roots change.
    func invalidateWorktreeCache() {
        scanQueue.async { [weak self] in
            self?.cachedAt = nil
            self?.cachedWorktrees = []
        }
    }
}
