import SwiftUI

/// Compact system-wide metrics panel at the top of the popover: CPU load,
/// memory, swap, thermal state, load average, uptime. Think "cockpit
/// cluster" — everything the user glances at before drilling into a
/// specific worktree or app.
struct SystemSectionView: View {
    let snapshot: SystemSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 14) {
                meter(
                    label: "CPU",
                    value: String(format: "%.0f%%", snapshot.cpuUsagePercent),
                    barPercent: snapshot.cpuUsagePercent
                )
                Spacer(minLength: 8)
                thermalIndicator
            }

            HStack(spacing: 14) {
                meter(
                    label: "MEM",
                    value: memoryValueString,
                    barPercent: snapshot.memoryUsedPercent
                )
                Spacer(minLength: 8)
                loadAndUptime
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Subviews

    private func meter(label: String, value: String, barPercent: Double) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                .frame(width: 28, alignment: .leading)
            Text(value)
                .font(DesignSystem.Typography.numeric)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                .frame(width: 92, alignment: .leading)
            CPUBar(percent: barPercent)
        }
    }

    private var thermalIndicator: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(thermalColor)
                .frame(width: 6, height: 6)
            Text("THERMAL")
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            Text(thermalLabel)
                .font(DesignSystem.Typography.numeric)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
        }
        .help(thermalHelp)
    }

    private var loadAndUptime: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                Text("LOAD")
                    .font(DesignSystem.Typography.microLabel)
                    .tracking(0.8)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(String(format: "%.1f · %.1f · %.1f",
                            snapshot.loadAverage1,
                            snapshot.loadAverage5,
                            snapshot.loadAverage15))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                    .help("Load average over 1, 5, and 15 minutes")
            }
            HStack(spacing: 4) {
                Text("UP")
                    .font(DesignSystem.Typography.microLabel)
                    .tracking(0.8)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(formatUptime(snapshot.uptimeSeconds))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                    .help("Time since kernel boot")
            }
        }
    }

    // MARK: - Helpers

    private var memoryValueString: String {
        "\(formatBytes(snapshot.memoryUsedBytes)) / \(formatBytes(snapshot.memoryTotalBytes))"
    }

    private func formatBytes(_ bytes: UInt64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        if gb >= 10 { return String(format: "%.0f GB", gb) }
        if gb >= 1  { return String(format: "%.1f GB", gb) }
        let mb = Double(bytes) / (1024 * 1024)
        return String(format: "%.0f MB", mb)
    }

    private func formatUptime(_ s: TimeInterval) -> String {
        let i = Int(s)
        let days = i / 86_400
        let hours = (i % 86_400) / 3_600
        if days > 0 { return "\(days)d \(hours)h" }
        let mins = (i % 3_600) / 60
        if hours > 0 { return "\(hours)h \(mins)m" }
        return "\(mins)m"
    }

    private var thermalColor: Color {
        switch snapshot.thermalState {
        case .nominal:  return DesignSystem.Color.activeDot.swiftUI
        case .fair:     return DesignSystem.Color.recentDot.swiftUI
        case .serious:  return DesignSystem.Color.staleDot.swiftUI
        case .critical: return DesignSystem.Color.dormantDot.swiftUI
        @unknown default: return DesignSystem.Color.idleDot.swiftUI
        }
    }

    private var thermalLabel: String {
        switch snapshot.thermalState {
        case .nominal:  return "Nominal"
        case .fair:     return "Fair"
        case .serious:  return "Serious"
        case .critical: return "Critical"
        @unknown default: return "—"
        }
    }

    private var thermalHelp: String {
        switch snapshot.thermalState {
        case .nominal:  return "Thermal pressure nominal — CPU at full performance."
        case .fair:     return "Thermal pressure fair — slight ramp-down possible."
        case .serious:  return "Thermal pressure serious — CPU throttling to cool down."
        case .critical: return "Thermal pressure critical — heavy throttling, possible shutdown risk."
        @unknown default: return "Unknown thermal state."
        }
    }
}
