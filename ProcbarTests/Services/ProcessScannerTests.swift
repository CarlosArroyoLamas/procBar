import XCTest
@testable import Procbar

final class ProcessScannerTests: XCTestCase {
    func test_second_sample_computes_nonzero_cpu_percent_when_ticks_advance() {
        var clockTime = Date(timeIntervalSince1970: 1_700_000_000)
        let now: () -> Date = {
            defer { clockTime = clockTime.addingTimeInterval(1.0) }
            return clockTime
        }
        let fake = FakeProcessSource()
        fake.raw = [RawProcess(pid: 10, ppid: 1, name: "vite", command: "vite dev")]

        fake.detailsByPid = [10: ProcessDetail(
            pid: 10, cwd: "/tmp/wt", residentBytes: 10_000_000,
            cpuTicks: 1_000, wallStartSeconds: 1_699_999_000, listeningPorts: [3000]
        )]
        let scanner = ProcessScanner(source: fake, clock: now)
        _ = scanner.sample(matchPIDs: [10])

        fake.detailsByPid[10] = ProcessDetail(
            pid: 10, cwd: "/tmp/wt", residentBytes: 10_000_000,
            cpuTicks: 2_000, wallStartSeconds: 1_699_999_000, listeningPorts: [3000]
        )
        let second = scanner.sample(matchPIDs: [10])

        let t = second.tracked.first!
        XCTAssertEqual(t.pid, 10)
        XCTAssertGreaterThan(t.cpuPercent, 0)
        XCTAssertEqual(t.memoryMB, 10_000_000.0 / 1_048_576.0, accuracy: 0.01)
        XCTAssertEqual(t.ports, [3000])
    }

    func test_returns_empty_tracked_when_no_match_pids() {
        let fake = FakeProcessSource()
        fake.raw = [RawProcess(pid: 7, ppid: 1, name: "x", command: "x")]
        let scanner = ProcessScanner(source: fake, clock: { Date() })
        let result = scanner.sample(matchPIDs: [])
        XCTAssertTrue(result.tracked.isEmpty)
        XCTAssertEqual(result.all.count, 1)
    }
}

final class FakeProcessSource: ProcessSource {
    var raw: [RawProcess] = []
    var detailsByPid: [Int32: ProcessDetail] = [:]
    func listAll() -> [RawProcess] { raw }
    func fetchDetails(for pids: [Int32]) -> [Int32: ProcessDetail] {
        var o: [Int32: ProcessDetail] = [:]
        for p in pids { if let d = detailsByPid[p] { o[p] = d } }
        return o
    }
}
