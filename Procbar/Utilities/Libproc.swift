import Foundation
import Darwin
import os

final class LibprocSource: ProcessSource {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "scanner")

    func listAll() -> [RawProcess] {
        let numBytesHint = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard numBytesHint > 0 else { return [] }
        let capacity = Int(numBytesHint) / MemoryLayout<pid_t>.size * 2
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesFilled = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0,
                          buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }
        let count = Int(bytesFilled) / MemoryLayout<pid_t>.size

        var result: [RawProcess] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard let bsd = fetchBsdInfo(pid) else { continue }
            let name = withUnsafePointer(to: bsd.pbi_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }
            let command = fetchCommandLine(pid) ?? name
            result.append(RawProcess(
                pid: pid,
                ppid: Int32(bsd.pbi_ppid),
                name: name,
                command: command
            ))
        }
        return result
    }

    func fetchDetails(for pids: [Int32]) -> [Int32: ProcessDetail] {
        var out: [Int32: ProcessDetail] = [:]
        for pid in pids {
            guard let bsd = fetchBsdInfo(pid) else { continue }
            let cwd = fetchCwd(pid)
            let taskInfo = fetchTaskInfo(pid)
            let ports = fetchListeningPorts(pid)
            let startSec = TimeInterval(bsd.pbi_start_tvsec)
                + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
            out[pid] = ProcessDetail(
                pid: pid,
                cwd: cwd,
                residentBytes: taskInfo?.resident ?? 0,
                cpuTicks: taskInfo?.cpuTicks ?? 0,
                wallStartSeconds: startSec,
                listeningPorts: ports
            )
        }
        return out
    }

    // MARK: - Low level

    private func fetchBsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        return ret == Int32(size) ? info : nil
    }

    private func fetchCommandLine(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 { return nil }
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buf, &size, nil, 0) != 0 { return nil }
        // Layout: [argc: int32][exe_path\0][padding\0*][argv0\0][argv1\0]...
        let argcSize = MemoryLayout<Int32>.size
        guard size > argcSize else { return nil }
        var argc: Int32 = 0
        memcpy(&argc, buf, argcSize)
        var cursor = argcSize
        // skip exe path
        while cursor < size, buf[cursor] != 0 { cursor += 1 }
        // skip nulls
        while cursor < size, buf[cursor] == 0 { cursor += 1 }
        // read argc argv strings
        var args: [String] = []
        for _ in 0..<Int(argc) {
            guard cursor < size else { break }
            let start = cursor
            while cursor < size, buf[cursor] != 0 { cursor += 1 }
            let slice = Array(buf[start..<cursor])
            if let s = String(validatingUTF8: slice + [0]) {
                args.append(s)
            }
            if cursor < size { cursor += 1 }
        }
        let joined = args.joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.prefix(1024))
    }

    private func fetchCwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size))
        guard ret == Int32(size) else { return nil }
        let path = withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }

    private struct TaskInfoResult {
        let resident: UInt64
        let cpuTicks: UInt64
    }

    private func fetchTaskInfo(_ pid: pid_t) -> TaskInfoResult? {
        var ti = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(size))
        guard ret == Int32(size) else { return nil }
        return TaskInfoResult(
            resident: ti.pti_resident_size,
            cpuTicks: ti.pti_total_user + ti.pti_total_system
        )
    }

    private func fetchListeningPorts(_ pid: pid_t) -> [UInt16] {
        let numBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard numBytes > 0 else { return [] }
        let fdCount = Int(numBytes) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let filled = fds.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0,
                         buf.baseAddress, Int32(buf.count * MemoryLayout<proc_fdinfo>.size))
        }
        let n = Int(filled) / MemoryLayout<proc_fdinfo>.size

        var ports: [UInt16] = []
        for i in 0..<n {
            let fd = fds[i]
            guard Int32(fd.proc_fdtype) == PROX_FDTYPE_SOCKET else { continue }
            var sinfo = socket_fdinfo()
            let size = MemoryLayout<socket_fdinfo>.size
            let ret = proc_pidfdinfo(pid, fd.proc_fd,
                                     PROC_PIDFDSOCKETINFO, &sinfo, Int32(size))
            guard ret == Int32(size) else { continue }
            guard sinfo.psi.soi_kind == Int16(SOCKINFO_TCP) else { continue }
            let tcp = sinfo.psi.soi_proto.pri_tcp
            // Only LISTEN state = 1 per tcp_fsm.h (TCPS_LISTEN)
            guard tcp.tcpsi_state == 1 else { continue }
            // insi_lport is a CInt holding a port number in NETWORK byte
            // order (big-endian) in its low 16 bits. To get a host-order
            // UInt16 we take the low 16 bits and byte-swap — equivalent to
            // ntohs() in C.
            let raw32 = UInt32(bitPattern: tcp.tcpsi_ini.insi_lport)
            let low16 = UInt16(truncatingIfNeeded: raw32)
            let port = UInt16(bigEndian: low16)
            if port > 0 { ports.append(port) }
        }
        return Array(Set(ports)).sorted()
    }
}
