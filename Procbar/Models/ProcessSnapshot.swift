import Foundation

struct RawProcess: Equatable, Hashable {
    let pid: Int32
    let ppid: Int32
    let name: String          // short command name (argv[0] basename, or comm)
    let command: String       // full argv joined by space, truncated at 1024 chars
}

struct ProcessDetail: Equatable, Hashable {
    let pid: Int32
    let cwd: String?
    let residentBytes: UInt64
    let cpuTicks: UInt64           // cumulative, user+system
    let wallStartSeconds: TimeInterval  // seconds since epoch of process start
    let listeningPorts: [UInt16]
}
