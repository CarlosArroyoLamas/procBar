import Foundation
import Darwin
import Darwin.Mach

/// Polls system-wide resource metrics (CPU, memory, swap, thermal state,
/// load average, uptime) via public Mach / sysctl APIs. No private SMC
/// code — Apple does not expose per-core temperature publicly, so we use
/// `ProcessInfo.thermalState` as the thermal-pressure proxy.
///
/// The monitor caches the last CPU-tick snapshot so consecutive calls
/// can compute a delta (CPU usage is a rate, not an instantaneous value).
final class SystemMonitor {
    private struct CPUTicks {
        let user: UInt64
        let system: UInt64
        let idle: UInt64
        let nice: UInt64
        var total: UInt64 { user &+ system &+ idle &+ nice }
        var active: UInt64 { user &+ system &+ nice }
    }

    private let stateQueue = DispatchQueue(label: "com.carlos.procbar.sysmon.state")
    private var lastTicks: CPUTicks?

    /// Takes one snapshot. Safe to call from a background queue; internal
    /// state is guarded so the view model can call it on its scan queue.
    func sample() -> SystemSnapshot {
        let cpu    = sampleCPU()
        let memory = sampleMemory()
        let swap   = sampleSwap()
        let load   = sampleLoadAverage()
        let uptime = sampleUptime()
        let thermal = ProcessInfo.processInfo.thermalState
        return SystemSnapshot(
            cpuUsagePercent: cpu,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            swapUsedBytes: swap.used,
            swapTotalBytes: swap.total,
            thermalState: thermal,
            loadAverage1: load.0,
            loadAverage5: load.1,
            loadAverage15: load.2,
            uptimeSeconds: uptime
        )
    }

    // MARK: - CPU

    private func sampleCPU() -> Double {
        var cpuCount: natural_t = 0
        var infoArray: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0

        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &infoArray,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info = infoArray else { return 0 }
        defer {
            let size = vm_size_t(MemoryLayout<integer_t>.stride) * vm_size_t(infoCount)
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), size)
        }

        var agg = CPUTicks(user: 0, system: 0, idle: 0, nice: 0)
        var u: UInt64 = 0, s: UInt64 = 0, i: UInt64 = 0, n: UInt64 = 0
        for core in 0..<Int(cpuCount) {
            let base = core * Int(CPU_STATE_MAX)
            u &+= UInt64(info[base + Int(CPU_STATE_USER)])
            s &+= UInt64(info[base + Int(CPU_STATE_SYSTEM)])
            i &+= UInt64(info[base + Int(CPU_STATE_IDLE)])
            n &+= UInt64(info[base + Int(CPU_STATE_NICE)])
        }
        agg = CPUTicks(user: u, system: s, idle: i, nice: n)

        return stateQueue.sync {
            defer { lastTicks = agg }
            guard let prev = lastTicks else { return 0 }
            let totalDelta  = Double(agg.total  &- prev.total)
            let activeDelta = Double(agg.active &- prev.active)
            guard totalDelta > 0 else { return 0 }
            return max(0, min(100, activeDelta / totalDelta * 100.0))
        }
    }

    // MARK: - Memory

    private func sampleMemory() -> (used: UInt64, total: UInt64) {
        let pageSize = UInt64(vm_kernel_page_size)
        var vmStats = vm_statistics64_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &vmStats) { ptr -> kern_return_t in
            ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { reb in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, reb, &count)
            }
        }
        guard result == KERN_SUCCESS else {
            return (0, sampleMemTotal())
        }
        // "App memory" view: active + wired + compressed (mirrors Activity Monitor).
        let used = (UInt64(vmStats.active_count)
                  + UInt64(vmStats.wire_count)
                  + UInt64(vmStats.compressor_page_count)) * pageSize
        return (used, sampleMemTotal())
    }

    private func sampleMemTotal() -> UInt64 {
        var size: UInt64 = 0
        var len = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &size, &len, nil, 0)
        return size
    }

    // MARK: - Swap

    private func sampleSwap() -> (used: UInt64, total: UInt64) {
        var swap = xsw_usage()
        var len = MemoryLayout<xsw_usage>.size
        guard sysctlbyname("vm.swapusage", &swap, &len, nil, 0) == 0 else {
            return (0, 0)
        }
        return (UInt64(swap.xsu_used), UInt64(swap.xsu_total))
    }

    // MARK: - Load average

    private func sampleLoadAverage() -> (Double, Double, Double) {
        var loads = [Double](repeating: 0, count: 3)
        getloadavg(&loads, 3)
        return (loads[0], loads[1], loads[2])
    }

    // MARK: - Uptime

    private func sampleUptime() -> TimeInterval {
        var boot = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &boot, &size, nil, 0) == 0 else {
            return 0
        }
        let bootDate = Date(timeIntervalSince1970: TimeInterval(boot.tv_sec))
        return Date().timeIntervalSince(bootDate)
    }
}
