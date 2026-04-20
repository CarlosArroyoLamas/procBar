import XCTest
import Combine
@testable import Procbar

final class AppViewModelTests: XCTestCase {
    @MainActor
    func test_tick_populates_groups_from_matcher_output() {
        let source = FakeProcessSource()
        source.raw = [RawProcess(pid: 1, ppid: 0, name: "node", command: "node /wt/a/index.js")]
        source.detailsByPid = [1: ProcessDetail(
            pid: 1, cwd: "/wt/a",
            residentBytes: 2_000_000, cpuTicks: 1_000,
            wallStartSeconds: Date().timeIntervalSince1970 - 60,
            listeningPorts: [3000]
        )]
        let scanner = ProcessScanner(source: source)
        let wt = [Worktree(path: "/wt/a", name: "a", branch: "main")]
        let cfg = Config(
            worktreeRoots: ["/wt"],
            processPatterns: [.init(name: "Node", match: "node", matchField: .name)]
        )
        let vm = AppViewModel(scanner: scanner, worktreesProvider: { wt }, configProvider: { cfg })
        vm.tickOnce()
        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups.first?.processes.map(\.pid), [1])
        XCTAssertTrue(vm.isActive)
    }
}
