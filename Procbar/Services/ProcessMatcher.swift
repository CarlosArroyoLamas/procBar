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
        var buckets: [String: [TrackedProcess]] = [:]
        for proc in tracked {
            guard !proc.cwd.isEmpty else { continue }
            if expandedExcluded.contains(where: { PathUtils.isInside(child: proc.cwd, parent: $0) }) {
                continue
            }
            let match = worktrees
                .sorted { $0.path.count > $1.path.count } // deepest wins
                .first { PathUtils.isInside(child: proc.cwd, parent: $0.path) }
            if let match {
                buckets[match.path, default: []].append(proc)
            }
        }
        return worktrees.compactMap { wt in
            guard let procs = buckets[wt.path], !procs.isEmpty else { return nil }
            return WorktreeGroup(worktree: wt, processes: procs.sorted { $0.pid < $1.pid })
        }
    }
}
