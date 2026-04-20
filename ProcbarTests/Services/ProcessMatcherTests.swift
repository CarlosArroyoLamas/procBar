import XCTest
@testable import Procbar

final class ProcessMatcherTests: XCTestCase {
    func test_matches_by_name_case_insensitive() {
        let patterns = [Config.Pattern(name: "Node", match: "node", matchField: .name)]
        let raw = [
            RawProcess(pid: 1, ppid: 0, name: "Node", command: "Node --version"),
            RawProcess(pid: 2, ppid: 0, name: "ls",   command: "ls")
        ]
        let out = ProcessMatcher.matchPIDs(patterns: patterns, raw: raw)
        XCTAssertEqual(out, [1])
    }

    func test_matches_by_command() {
        let patterns = [Config.Pattern(name: "NX", match: "nx", matchField: .command)]
        let raw = [RawProcess(pid: 1, ppid: 0, name: "node", command: "node /path/nx serve")]
        XCTAssertEqual(ProcessMatcher.matchPIDs(patterns: patterns, raw: raw), [1])
    }

    func test_groups_tracked_by_worktree_cwd() {
        let wt1 = Worktree(path: "/a", name: "a", branch: "main")
        let wt2 = Worktree(path: "/b", name: "b", branch: "feat")
        let tracked = [
            mkTracked(pid: 1, cwd: "/a/src"),
            mkTracked(pid: 2, cwd: "/b"),
            mkTracked(pid: 3, cwd: "/x")    // not in any worktree → dropped
        ]
        let groups = ProcessMatcher.group(tracked: tracked, worktrees: [wt1, wt2])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].processes.map(\.pid), [1])
        XCTAssertEqual(groups[1].processes.map(\.pid), [2])
    }

    func test_respects_excluded_paths() {
        let wt = Worktree(path: "/a", name: "a", branch: nil)
        let tracked = [mkTracked(pid: 1, cwd: "/a/node_modules/x")]
        let groups = ProcessMatcher.group(
            tracked: tracked, worktrees: [wt],
            excluded: ["/a/node_modules"]
        )
        XCTAssertTrue(groups.isEmpty)
    }

    private func mkTracked(pid: Int32, cwd: String) -> TrackedProcess {
        TrackedProcess(pid: pid, ppid: 0, displayName: "x", command: "x",
                       cwd: cwd, cpuPercent: 0, memoryMB: 0, ports: [],
                       uptimeSeconds: 0, activity: .activeNow, idleSeconds: nil)
    }
}
