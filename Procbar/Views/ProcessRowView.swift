import SwiftUI

struct ProcessRowView: View {
    let process: TrackedProcess
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var killCoordinator: KillCoordinator
    @State private var stopState: StopState = .idle

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            identityZone
            meterZone
            resourceZone
            Spacer(minLength: 4)
            actionZone
        }
        .frame(height: DesignSystem.Spacing.rowHeight)
        .contentShape(Rectangle())
    }

    private var identityZone: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                ActivityDot(state: process.activity)
                Text(process.displayName.uppercased())
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(nameColor)
            }
            Text("PID \(process.pid)")
                .font(DesignSystem.Typography.pidSubtitle)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
        }
        .frame(width: 140, alignment: .leading)
    }

    private var meterZone: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f%%", process.cpuPercent))
                .font(DesignSystem.Typography.numeric)
                .foregroundStyle(
                    process.activity == .idle
                        ? DesignSystem.Color.textTertiary.swiftUI
                        : DesignSystem.Color.textPrimary.swiftUI
                )
            CPUBar(percent: process.cpuPercent)
        }
        .frame(width: 80, alignment: .leading)
    }

    private var resourceZone: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("MEM").font(DesignSystem.Typography.microLabel)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(formatMem(process.memoryMB))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            }
            HStack(spacing: 4) {
                Text("PORT").font(DesignSystem.Typography.microLabel)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(process.ports.isEmpty ? "—" : ":\(process.ports[0])")
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            }
        }
        .frame(width: 90, alignment: .leading)
    }

    private var actionZone: some View {
        VStack(alignment: .trailing, spacing: 3) {
            uptimeOrIdleLabel
            StopButton(state: stopState) {
                if stopState == .terminating {
                    killCoordinator.forceKill(process: process)
                    stopState = .killing
                } else {
                    killCoordinator.gracefulKill(process: process) { gone in
                        stopState = gone ? .done : .killing
                    }
                    stopState = .terminating
                }
            }
        }
    }

    private var nameColor: Color {
        process.activity == .idle
            ? DesignSystem.Color.textSecondary.swiftUI
            : DesignSystem.Color.textPrimary.swiftUI
    }

    @ViewBuilder
    private var uptimeOrIdleLabel: some View {
        if process.activity == .idle, let idle = process.idleSeconds {
            Text("idle \(formatUptime(idle))")
                .font(DesignSystem.Typography.pidSubtitle)
                .foregroundStyle(DesignSystem.Color.accent.swiftUI)
        } else {
            Text(formatUptime(process.uptimeSeconds))
                .font(DesignSystem.Typography.pidSubtitle)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
        }
    }

    private func formatMem(_ mb: Double) -> String {
        mb < 1024 ? String(format: "%.0f MB", mb) : String(format: "%.2f GB", mb / 1024)
    }

    private func formatUptime(_ s: TimeInterval) -> String {
        let i = Int(s)
        if i < 60 { return "\(i)s" }
        if i < 3_600 { return "\(i / 60)m" }
        if i < 86_400 { return "\(i / 3600)h" }
        return "\(i / 86_400)d"
    }
}
