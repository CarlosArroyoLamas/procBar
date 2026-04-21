import SwiftUI
import AppKit

/// Renders a tracked Mac application as ONE aggregated row — summed CPU,
/// summed memory, union of ports, activity state across the bundle.
/// The Stop button kills every process in the bundle's tree (graceful by
/// default, fast-path SIGKILL on a second click).
struct AppSectionView: View {
    let group: AppGroup
    @EnvironmentObject var killCoordinator: KillCoordinator
    @State private var stopState: StopState = .idle
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(DesignSystem.Motion.section.animation) { expanded.toggle() } }) {
                aggregateRow
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if expanded && group.processes.count > 1 {
                HairlineDivider().padding(.leading, 26)
                VStack(spacing: 0) {
                    ForEach(group.processes) { proc in
                        ProcessRowView(process: proc)
                            .padding(.leading, 14)
                    }
                }
            }
        }
    }

    private var aggregateRow: some View {
        HStack(alignment: .center, spacing: 10) {
            appIdentity
            meterColumn
            resourceColumn
            Spacer(minLength: 4)
            actionColumn
        }
        .frame(height: DesignSystem.Spacing.rowHeight)
    }

    private var appIdentity: some View {
        HStack(spacing: 8) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            appIcon
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    ActivityDot(state: group.activity)
                    Text(group.app.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                        .lineLimit(1)
                }
                Text("\(group.processes.count) process\(group.processes.count == 1 ? "" : "es")")
                    .font(DesignSystem.Typography.pidSubtitle)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            }
        }
        .frame(
            width: DesignSystem.Spacing.identityColumnWidth + 16,
            alignment: .leading
        )
    }

    private var appIcon: some View {
        let icon = NSWorkspace.shared.icon(forFile: group.app.path)
        return Image(nsImage: icon)
            .resizable()
            .frame(width: 20, height: 20)
    }

    private var meterColumn: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 4) {
                Text("CPU")
                    .font(DesignSystem.Typography.microLabel)
                    .tracking(0.8)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(String(format: "%.0f%%", group.totalCPU))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            }
            CPUBar(percent: group.totalCPU)
        }
        .frame(width: DesignSystem.Spacing.meterColumnWidth, alignment: .leading)
    }

    private var resourceColumn: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("MEM")
                    .font(DesignSystem.Typography.microLabel)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(formatMem(group.totalMemoryMB))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            }
            HStack(spacing: 4) {
                Text("PORTS")
                    .font(DesignSystem.Typography.microLabel)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(group.ports.isEmpty ? "—" : formatPorts(group.ports))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                    .lineLimit(1)
            }
        }
        .frame(width: DesignSystem.Spacing.resourceColumnWidth, alignment: .leading)
    }

    private var actionColumn: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(formatUptime(group.uptimeSeconds))
                .font(DesignSystem.Typography.pidSubtitle)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            StopButton(state: stopState) {
                switch stopState {
                case .terminating:
                    stopState = .killing
                    for proc in group.processes {
                        killCoordinator.forceKill(process: proc) { _ in }
                    }
                case .idle:
                    stopState = .terminating
                    killAllGracefully()
                case .killing, .done:
                    break
                }
            }
            .help("Stop all \(group.processes.count) processes for \(group.app.name)")
        }
    }

    private func killAllGracefully() {
        let total = group.processes.count
        guard total > 0 else { return }
        var remaining = total
        var anyForced = false
        for proc in group.processes {
            killCoordinator.gracefulKill(process: proc) { outcome in
                remaining -= 1
                if outcome != .exitedGracefully { anyForced = true }
                if remaining == 0 {
                    stopState = anyForced ? .killing : .done
                }
            }
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

    private func formatPorts(_ ports: [UInt16]) -> String {
        let visible = ports.prefix(3)
        let joined = visible.map { ":\($0)" }.joined(separator: " ")
        return ports.count > visible.count
            ? "\(joined) +\(ports.count - visible.count)"
            : joined
    }
}
