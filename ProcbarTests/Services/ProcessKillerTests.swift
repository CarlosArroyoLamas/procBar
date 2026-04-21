import XCTest
@testable import Procbar

final class ProcessKillerTests: XCTestCase {
    func test_buildTree_returns_self_and_descendants() {
        let raw = [
            RawProcess(pid: 1, ppid: 0, name: "a", command: "a"),
            RawProcess(pid: 2, ppid: 1, name: "b", command: "b"),
            RawProcess(pid: 3, ppid: 2, name: "c", command: "c"),
            RawProcess(pid: 4, ppid: 0, name: "d", command: "d")
        ]
        let tree = ProcessKiller.tree(rootPID: 1, among: raw)
        XCTAssertEqual(Set(tree), Set([1, 2, 3]))
    }

    func test_buildTree_handles_cycles_safely() {
        // pathological: 1 → 2 → 1. Should still terminate.
        let raw = [
            RawProcess(pid: 1, ppid: 2, name: "a", command: "a"),
            RawProcess(pid: 2, ppid: 1, name: "b", command: "b")
        ]
        let tree = ProcessKiller.tree(rootPID: 1, among: raw)
        XCTAssertEqual(Set(tree), Set([1, 2]))
    }

    func test_kill_sends_sigterm_then_sigkill_on_timeout() throws {
        let sender = FakeKillSender(alwaysAlive: true)
        let killer = ProcessKiller(sender: sender, graceSeconds: 0.1)
        let exp = expectation(description: "done")
        var reported: KillOutcome?
        killer.gracefulKill(tree: [5, 6]) { outcome in
            reported = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(sender.terms, [5, 6])
        XCTAssertEqual(sender.kills, [5, 6])
        XCTAssertEqual(reported, .escalatedToSigkill)
    }

    func test_kill_skips_sigkill_when_process_exits_early() throws {
        let sender = FakeKillSender(alwaysAlive: false)
        let killer = ProcessKiller(sender: sender, graceSeconds: 0.1)
        let exp = expectation(description: "done")
        var reported: KillOutcome?
        killer.gracefulKill(tree: [5]) { outcome in
            reported = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(sender.terms, [5])
        XCTAssertTrue(sender.kills.isEmpty)
        XCTAssertEqual(reported, .exitedGracefully)
    }

    func test_forceKill_reports_forced() throws {
        let sender = FakeKillSender(alwaysAlive: false)
        let killer = ProcessKiller(sender: sender, graceSeconds: 0.1)
        let exp = expectation(description: "done")
        var reported: KillOutcome?
        killer.forceKill(tree: [5]) { outcome in
            reported = outcome
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        XCTAssertTrue(sender.terms.isEmpty)
        XCTAssertEqual(sender.kills, [5])
        XCTAssertEqual(reported, .forced)
    }
}

final class FakeKillSender: KillSender {
    var terms: [Int32] = []
    var kills: [Int32] = []
    let alwaysAlive: Bool
    init(alwaysAlive: Bool) { self.alwaysAlive = alwaysAlive }
    func sigterm(_ pid: Int32) { terms.append(pid) }
    func sigkill(_ pid: Int32) { kills.append(pid) }
    func isAlive(_ pid: Int32) -> Bool { alwaysAlive }
}
