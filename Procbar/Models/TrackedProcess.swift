import Foundation

enum ActivityState: String, Equatable {
    case activeNow
    case recentlyActive
    case idle
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
