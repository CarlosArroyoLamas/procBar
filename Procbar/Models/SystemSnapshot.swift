import Foundation

struct SystemSnapshot: Equatable {
    /// Total CPU utilization across all cores, 0..100.
    var cpuUsagePercent: Double
    /// Bytes in active + wired + compressed memory (the "used" number
    /// familiar from Activity Monitor's Memory tab).
    var memoryUsedBytes: UInt64
    /// `hw.memsize` — installed RAM.
    var memoryTotalBytes: UInt64
    /// `vm.swapusage.xsu_used`.
    var swapUsedBytes: UInt64
    /// `vm.swapusage.xsu_total`.
    var swapTotalBytes: UInt64
    /// Public thermal-pressure state from ProcessInfo. Apple exposes
    /// this as a coarse hint rather than a °C number.
    var thermalState: ProcessInfo.ThermalState
    /// `getloadavg` — 1-min / 5-min / 15-min.
    var loadAverage1: Double
    var loadAverage5: Double
    var loadAverage15: Double
    /// Seconds since kernel boot.
    var uptimeSeconds: TimeInterval

    var memoryUsedPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100.0
    }
}
