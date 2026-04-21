import Foundation

enum ProcessMatcher {
    static func matchPIDs(patterns: [Config.Pattern], raw: [RawProcess]) -> [Int32] {
        guard !patterns.isEmpty else { return [] }
        return raw.compactMap { proc in
            let hit = patterns.contains { pat in
                let haystack = (pat.matchField == .name ? proc.name : proc.command)
                return haystack.range(of: pat.match, options: .caseInsensitive) != nil
            }
            return hit ? proc.pid : nil
        }
    }

    static func group(
        tracked: [TrackedProcess],
        worktrees: [Worktree],
        excluded: [String] = []
    ) -> [WorktreeGroup] {
        let expandedExcluded = excluded.map(PathUtils.expand)
        // Sort worktrees by depth (number of path components) descending, so a
        // nested repo wins over its parent. Using component count avoids the
        // subtle bug where `/a/b` with a long single component could look
        // "deeper" than `/a/b/c/d` by raw character count.
        let sortedByDepth = worktrees.sorted {
            pathDepth($0.path) > pathDepth($1.path)
        }
        var buckets: [String: [TrackedProcess]] = [:]
        for proc in tracked {
            guard !proc.cwd.isEmpty else { continue }
            if expandedExcluded.contains(where: { PathUtils.isInside(child: proc.cwd, parent: $0) }) {
                continue
            }
            let match = sortedByDepth.first {
                PathUtils.isInside(child: proc.cwd, parent: $0.path)
            }
            if let match {
                buckets[match.path, default: []].append(proc)
            }
        }
        return worktrees.compactMap { wt in
            guard let procs = buckets[wt.path], !procs.isEmpty else { return nil }
            // Sort busiest first: CPU desc, then memory desc, then PID asc
            // for stability across ticks when several rows are at 0%.
            let sorted = procs.sorted { a, b in
                if a.cpuPercent != b.cpuPercent { return a.cpuPercent > b.cpuPercent }
                if a.memoryMB   != b.memoryMB   { return a.memoryMB   > b.memoryMB   }
                return a.pid < b.pid
            }
            return WorktreeGroup(worktree: wt, processes: sorted)
        }
    }

    private static func pathDepth(_ path: String) -> Int {
        path.split(separator: "/", omittingEmptySubsequences: true).count
    }

    // MARK: - Apps

    /// Returns PIDs whose executable path lives inside one of the tracked
    /// app bundles. A single process belongs to at most one app — whichever
    /// bundle path matches as a prefix of its exe path.
    static func matchAppPIDs(apps: [Config.AppTracked], raw: [RawProcess]) -> [Int32] {
        guard !apps.isEmpty else { return [] }
        return raw.compactMap { p in
            appPath(apps: apps, exePath: p.exePath) != nil ? p.pid : nil
        }
    }

    /// Groups tracked processes by the app bundle they belong to,
    /// returning one `AppGroup` per configured app that has ≥ 1 running
    /// process. Order matches the config's `apps` array so the UI is
    /// stable across ticks.
    static func groupApps(
        apps: [Config.AppTracked],
        tracked: [TrackedProcess],
        raw: [RawProcess]
    ) -> [AppGroup] {
        guard !apps.isEmpty else { return [] }
        let pidToExe = Dictionary(uniqueKeysWithValues: raw.map { ($0.pid, $0.exePath) })
        var buckets: [String: [TrackedProcess]] = [:]
        for p in tracked {
            let exe = pidToExe[p.pid] ?? ""
            guard let bundle = appPath(apps: apps, exePath: exe) else { continue }
            buckets[bundle, default: []].append(p)
        }
        return apps.compactMap { app in
            guard let procs = buckets[app.path], !procs.isEmpty else { return nil }
            let sorted = procs.sorted { a, b in
                if a.cpuPercent != b.cpuPercent { return a.cpuPercent > b.cpuPercent }
                if a.memoryMB   != b.memoryMB   { return a.memoryMB   > b.memoryMB   }
                return a.pid < b.pid
            }
            return AppGroup(app: app, processes: sorted)
        }
    }

    private static func appPath(apps: [Config.AppTracked], exePath: String) -> String? {
        guard !exePath.isEmpty else { return nil }
        for app in apps where exePath.hasPrefix(app.path) {
            return app.path
        }
        return nil
    }
}
