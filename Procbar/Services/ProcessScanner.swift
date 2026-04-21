import Foundation
import Darwin.Mach

struct ScanResult {
    let all: [RawProcess]
    let tracked: [TrackedProcess]
    let timestamp: Date
}

/// Two-phase process scanner.
///
/// Intended flow per tick:
/// 1. Call `listRaw()` once — cheap enumeration (PID/PPID/name/command).
/// 2. Let a matcher filter the list into a small set of tracked PIDs.
/// 3. Call `sampleDetails(matchPIDs:raw:activity:)` — pulls expensive details
///    (`cwd`, ports, rusage) for *only* those PIDs and computes CPU% / activity.
///
/// The scanner maintains per-PID state (`lastSample`, `lastActiveAt`) so
/// consecutive ticks can derive deltas. Access is serialized through an
/// internal serial queue to keep the scanner safe to call from a background
/// dispatch queue. The `sample(...)` convenience wrapper is retained for
/// tests and backwards compatibility.
final class ProcessScanner {
    private let source: ProcessSource
    private let clock: () -> Date
    private let stateQueue = DispatchQueue(label: "com.carlos.procbar.scanner.state")
    private var lastSample: (date: Date, ticksByPid: [Int32: UInt64])?
    private var lastActiveAt: [Int32: Date] = [:]

    /// Mach-absolute-time → nanoseconds conversion factor. On Intel Macs
    /// it's 1:1; on Apple Silicon it's roughly 125/3 (a tick ≈ 41.67 ns).
    /// `pti_total_user`/`pti_total_system` from `proc_pidinfo` are
    /// reported in mach ticks despite the struct naming suggesting
    /// otherwise, so we must convert before treating them as time.
    private let machTicksToNanos: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let numer = Double(info.numer == 0 ? 1 : info.numer)
        let denom = Double(info.denom == 0 ? 1 : info.denom)
        return numer / denom
    }()

    init(source: ProcessSource, clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.clock = clock
    }

    /// Phase 1 — cheap enumeration of all running processes.
    /// Safe to call from any thread; delegates to the underlying `ProcessSource`.
    func listRaw() -> [RawProcess] {
        source.listAll()
    }

    /// Phase 2 — pulls expensive details for `matchPIDs` using the pre-fetched
    /// `raw` list. Computes CPU% from tick deltas between consecutive calls
    /// and resolves each PID's activity state against `activity`.
    func sampleDetails(
        matchPIDs: [Int32],
        raw: [RawProcess],
        activity: Config.ActivityConfig
    ) -> ScanResult {
        let now = clock()
        let detail = source.fetchDetails(for: matchPIDs)
        let byPid = Dictionary(uniqueKeysWithValues: raw.map { ($0.pid, $0) })
        let recentWindow = TimeInterval(activity.recentWindowMinutes * 60)

        return stateQueue.sync {
            let lastTicks = lastSample?.ticksByPid ?? [:]
            let lastDate = lastSample?.date
            let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? 0

            var tracked: [TrackedProcess] = []
            var nextTicks: [Int32: UInt64] = [:]

            for pid in matchPIDs {
                guard let rp = byPid[pid], let d = detail[pid] else { continue }
                nextTicks[pid] = d.cpuTicks

                // CPU% is per-core (Activity Monitor convention): 100% = one
                // core fully saturated, 800% = eight cores saturated, etc.
                // Kernel-reported ticks are mach-absolute units; convert to
                // nanoseconds via the cached timebase before dividing by
                // wall-clock nanoseconds.
                let cpu: Double
                if elapsed > 0.05, let last = lastTicks[pid] {
                    let deltaTicks = Double(d.cpuTicks &- last)
                    let deltaNs   = deltaTicks * machTicksToNanos
                    let elapsedNs = elapsed * 1_000_000_000
                    cpu = max(0, min(800, (deltaNs / elapsedNs) * 100.0))
                } else {
                    cpu = 0
                }

                let threshold = activity.activeThresholdPercent
                let firstSeen = (lastActiveAt[pid] == nil)
                if cpu > threshold || firstSeen {
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
                    pid: rp.pid,
                    ppid: rp.ppid,
                    displayName: rp.name,
                    command: rp.command,
                    cwd: d.cwd ?? "",
                    cpuPercent: cpu,
                    memoryMB: Double(d.residentBytes) / 1_048_576.0,
                    ports: d.listeningPorts,
                    uptimeSeconds: max(0, now.timeIntervalSince(startDate)),
                    activity: state,
                    idleSeconds: idle
                ))
            }

            // Evict activity entries for PIDs that no longer appear.
            let alivePIDs = Set(raw.map { $0.pid })
            lastActiveAt = lastActiveAt.filter { alivePIDs.contains($0.key) }

            lastSample = (now, nextTicks)
            return ScanResult(all: raw, tracked: tracked, timestamp: now)
        }
    }

    /// Convenience: do both phases in one call. Kept so existing tests and
    /// one-off callers don't need to know about the split.
    func sample(matchPIDs: [Int32], activity: Config.ActivityConfig = .init()) -> ScanResult {
        let raw = listRaw()
        return sampleDetails(matchPIDs: matchPIDs, raw: raw, activity: activity)
    }
}
