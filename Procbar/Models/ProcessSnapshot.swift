import Foundation

struct RawProcess: Equatable, Hashable {
    let pid: Int32
    let ppid: Int32
    let name: String          // short command name (argv[0] basename, or comm)
    let command: String       // full argv joined by space, truncated at 1024 chars
    let exePath: String       // absolute path to executable (from proc_pidpath)

    init(pid: Int32, ppid: Int32, name: String, command: String, exePath: String = "") {
        self.pid = pid
        self.ppid = ppid
        self.name = name
        self.command = command
        self.exePath = exePath
    }
}

struct ProcessDetail: Equatable, Hashable {
    var pid: Int32
    var cwd: String?
    var residentBytes: UInt64
    var cpuTicks: UInt64           // cumulative, user+system
    var wallStartSeconds: TimeInterval  // seconds since epoch of process start
    var listeningPorts: [UInt16]
}
