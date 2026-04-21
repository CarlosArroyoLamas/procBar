import Foundation

/// An aggregated view of all running processes that belong to a tracked
/// Mac application bundle (matched by exe-path prefix).
///
/// The UI shows one row per `AppGroup` with summed CPU, summed memory, the
/// union of listening ports, and a single "Stop" button that kills every
/// PID in `processes`.
struct AppGroup: Identifiable, Hashable {
    let app: Config.AppTracked
    let processes: [TrackedProcess]

    var id: String { app.path }

    var totalCPU: Double {
        processes.reduce(0.0) { $0 + $1.cpuPercent }
    }

    var totalMemoryMB: Double {
        processes.reduce(0.0) { $0 + $1.memoryMB }
    }

    var ports: [UInt16] {
        Array(Set(processes.flatMap(\.ports))).sorted()
    }

    /// Longest uptime across the bundle's processes (the app's "age").
    var uptimeSeconds: TimeInterval {
        processes.map(\.uptimeSeconds).max() ?? 0
    }

    /// Activity is the highest-intensity state across the bundle. If any
    /// process is active now the group is active now; else if any is
    /// recent the group is recent; and so on.
    var activity: ActivityState {
        var highest: ActivityState = .dormant
        for p in processes {
            switch (highest, p.activity) {
            case (_, .activeNow):                     return .activeNow
            case (.dormant, .recent), (.stale, .recent):
                highest = .recent
            case (.dormant, .stale):
                highest = .stale
            default:
                break
            }
        }
        return highest
    }
}
