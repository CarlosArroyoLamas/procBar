import Foundation

enum ActivityState: String, Equatable {
    /// CPU is above the threshold right now.
    case activeNow
    /// Idle for less than `recent_window_minutes` (default 15).
    case recent
    /// Idle between `recent_window_minutes` and `dormant_window_days`.
    case stale
    /// Idle for more than `dormant_window_days` (default 1 day).
    case dormant

    /// Old three-state alias retained so unmigrated code still compiles.
    @available(*, deprecated, renamed: "recent")
    static var recentlyActive: ActivityState { .recent }

    /// Old three-state alias for what is now split into `.stale` + `.dormant`.
    @available(*, deprecated, renamed: "stale")
    static var idle: ActivityState { .stale }
}

struct TrackedProcess: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let displayName: String
    let command: String
    let cwd: String
    let cpuPercent: Double      // 0..100+
    let memoryMB: Double
    let ports: [UInt16]
    let uptimeSeconds: TimeInterval
    let activity: ActivityState
    let idleSeconds: TimeInterval?  // nil when activity != .idle
    var id: Int32 { pid }
}
