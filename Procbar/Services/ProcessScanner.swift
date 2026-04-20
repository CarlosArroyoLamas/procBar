import Foundation

struct ScanResult {
    let all: [RawProcess]
    let tracked: [TrackedProcess]
    let timestamp: Date
}

final class ProcessScanner {
    private let source: ProcessSource
    private let clock: () -> Date
    private var lastSample: (date: Date, ticksByPid: [Int32: UInt64])?
    private var lastActiveAt: [Int32: Date] = [:]

    init(source: ProcessSource, clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.clock = clock
    }

    /// Caller supplies the set of PIDs that matched patterns (cheap list). The scanner
    /// pulls expensive details only for those.
    ///
    /// Pass the activity config alongside matchPIDs so thresholds can be reconfigured
    /// live without restarting the scanner.
    func sample(matchPIDs: [Int32], activity: Config.ActivityConfig = .init()) -> ScanResult {
        let now = clock()
        let all = source.listAll()
        let detail = source.fetchDetails(for: matchPIDs)
        let lastTicks = lastSample?.ticksByPid ?? [:]
        let lastDate = lastSample?.date
        let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? 0

        var tracked: [TrackedProcess] = []
        var nextTicks: [Int32: UInt64] = [:]

        let byPid = Dictionary(uniqueKeysWithValues: all.map { ($0.pid, $0) })
        let recentWindow = TimeInterval(activity.recentWindowMinutes * 60)

        for pid in matchPIDs {
            guard let raw = byPid[pid], let d = detail[pid] else { continue }
            nextTicks[pid] = d.cpuTicks
            let cpu: Double
            if elapsed > 0.05, let last = lastTicks[pid] {
                let deltaNs   = Double(d.cpuTicks &- last)
                let elapsedNs = elapsed * 1_000_000_000
                let ncpu      = Double(ProcessInfo.processInfo.activeProcessorCount)
                cpu = max(0, min(800, (deltaNs / elapsedNs) * 100.0 / ncpu))
            } else {
                cpu = 0
            }

            // Activity resolution
            let threshold = activity.activeThresholdPercent
            let firstSeen = (lastActiveAt[pid] == nil)
            if cpu > threshold || firstSeen {
                // first time seeing this PID — seed as active
                lastActiveAt[pid] = now
            }
            let since = now.timeIntervalSince(lastActiveAt[pid]!)
            let state: ActivityState
            let idle: TimeInterval?
            if cpu > threshold || firstSeen {
                state = .activeNow; idle = nil
            } else if since < recentWindow {
                state = .recentlyActive; idle = nil
            } else {
                state = .idle; idle = since
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
                uptimeSeconds: max(0, now.timeIntervalSince(startDate)),
                activity: state,
                idleSeconds: idle
            ))
        }

        // Evict entries for PIDs that no longer appear in the full listing.
        let alivePIDs = Set(all.map { $0.pid })
        lastActiveAt = lastActiveAt.filter { alivePIDs.contains($0.key) }

        lastSample = (now, nextTicks)
        return ScanResult(all: all, tracked: tracked, timestamp: now)
    }
}
