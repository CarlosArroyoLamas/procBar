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
}
