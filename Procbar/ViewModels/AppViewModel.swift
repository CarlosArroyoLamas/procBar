import Foundation
import Combine
import SwiftUI
import os

@MainActor
final class AppViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "ui")

    @Published private(set) var groups: [WorktreeGroup] = []
    @Published private(set) var isActive: Bool = false
    @Published var configError: String?

    private let scanner: ProcessScanner
    private let worktreesProvider: () -> [Worktree]
    private let configProvider: () -> Config
    private var timer: Timer?
    private let scanQueue = DispatchQueue(label: "com.carlos.procbar.scan", qos: .userInitiated)

    init(scanner: ProcessScanner,
         worktreesProvider: @escaping () -> [Worktree],
         configProvider: @escaping () -> Config) {
        self.scanner = scanner
        self.worktreesProvider = worktreesProvider
        self.configProvider = configProvider
    }

    func start() {
        stop()
        let interval = TimeInterval(configProvider().refreshIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.scheduleTick()
        }
        scheduleTick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTick() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.tickOnce() }
        }
    }

    func tickOnce() {
        let cfg = configProvider()
        let wts = worktreesProvider()
        let rawAll = scanner.sample(matchPIDs: [], activity: cfg.activity).all
        let matched = ProcessMatcher.matchPIDs(patterns: cfg.processPatterns, raw: rawAll)
        let result = scanner.sample(matchPIDs: matched, activity: cfg.activity)
        let grouped = ProcessMatcher.group(
            tracked: result.tracked,
            worktrees: wts,
            excluded: cfg.excludedPaths
        )
        self.groups = grouped
        self.isActive = !grouped.isEmpty
    }
}
