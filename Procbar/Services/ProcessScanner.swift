import Foundation

struct ScanResult {
    let all: [RawProcess]
    let tracked: [TrackedProcess]
    let timestamp: Date
}

final class ProcessScanner {
    private let source: ProcessSource
    private let clock: () -> Date
    private let hzPerCore: Double
    private var lastSample: (date: Date, ticksByPid: [Int32: UInt64])?

    init(source: ProcessSource, clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.clock = clock
        let ncpu = Double(ProcessInfo.processInfo.activeProcessorCount)
        // Mach absolute ticks: user/system are in terms of nanoseconds on modern Darwin.
        // proc_pidinfo(PROC_PIDTASKINFO) returns user+system in mach_timebase ns.
        // We treat `cpuTicks` as nanoseconds and compute: (Δns / Δwall_ns) * 100 / ncpu.
        self.hzPerCore = ncpu
    }

    /// Caller supplies the set of PIDs that matched patterns (cheap list). The scanner
    /// pulls expensive details only for those.
    func sample(matchPIDs: [Int32]) -> ScanResult {
        let now = clock()
        let all = source.listAll()
        let detail = source.fetchDetails(for: matchPIDs)
        let lastTicks = lastSample?.ticksByPid ?? [:]
        let lastDate = lastSample?.date
        let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? 0

        var tracked: [TrackedProcess] = []
        var nextTicks: [Int32: UInt64] = [:]

        let byPid = Dictionary(uniqueKeysWithValues: all.map { ($0.pid, $0) })
        for pid in matchPIDs {
            guard let raw = byPid[pid], let d = detail[pid] else { continue }
            nextTicks[pid] = d.cpuTicks
            let cpu: Double
            if elapsed > 0.05, let last = lastTicks[pid] {
                let deltaNs = Double(d.cpuTicks &- last)
                let elapsedNs = elapsed * 1_000_000_000
                cpu = max(0, min(800, (deltaNs / elapsedNs) * 100.0 / hzPerCore))
            } else {
                cpu = 0
            }
            let startDate = Date(timeIntervalSince1970: d.wallStartSeconds)
            tracked.append(TrackedProcess(
                pid: raw.pid,
                ppid: raw.ppid,
                displayName: raw.name,
                command: raw.command,
                cwd: d.cwd ?? "",
                cpuPercent: cpu,
                memoryMB: Double(d.residentBytes) / 1_048_576.0,
                ports: d.listeningPorts,
                uptimeSeconds: max(0, now.timeIntervalSince(startDate))
            ))
        }
        lastSample = (now, nextTicks)
        return ScanResult(all: all, tracked: tracked, timestamp: now)
    }
}
