import SwiftUI

struct WorktreeSectionView: View {
    let group: WorktreeGroup
    @EnvironmentObject var vm: AppViewModel
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(DesignSystem.Motion.section.animation) { expanded.toggle() } }) {
                VStack(alignment: .leading, spacing: 3) {
                    headerRow
                    summaryRow
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            HairlineDivider()

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.processes.enumerated()), id: \.element.id) { idx, proc in
                        ProcessRowView(process: proc)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 4)),
                                    removal: .opacity
                                )
                            )
                            .animation(
                                DesignSystem.Motion.rowAppear.animation
                                    .delay(Double(idx) * DesignSystem.Motion.rowStaggerMs / 1000.0),
                                value: proc.pid
                            )
                    }
                }
            }
        }
    }

    private var headerRow: some View {
        HStack(spacing: 6) {
            Image(systemName: expanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            Text(group.worktree.name)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            if vm.showBranch, let branch = group.worktree.branch {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 9))
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(branch)
                    .font(DesignSystem.Typography.branch)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            }
            Spacer()
            CountBadge(value: group.processes.count)
        }
        .frame(minHeight: DesignSystem.Spacing.sectionHeaderHeight - 12)
    }

    private var summaryRow: some View {
        let agg = aggregate(group.processes)
        return HStack(spacing: 14) {
            summaryItem(label: "CPU", value: String(format: "%.0f%%", agg.cpuPercent),
                        warning: agg.cpuPercent >= 80)
            summaryItem(label: "MEM", value: agg.formattedMemory, warning: false)
            summaryItem(label: "PORTS",
                        value: agg.ports.isEmpty ? "—" : agg.formattedPorts,
                        warning: false)
            Spacer()
        }
        .padding(.leading, 15) // align with header text (past the chevron)
        .padding(.bottom, 4)
    }

    private func summaryItem(label: String, value: String, warning: Bool) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            Text(value)
                .font(DesignSystem.Typography.numeric)
                .foregroundStyle(
                    warning
                        ? DesignSystem.Color.warning.swiftUI
                        : DesignSystem.Color.textSecondary.swiftUI
                )
        }
    }

    // MARK: - Aggregation

    private struct Aggregate {
        let cpuPercent: Double
        let memoryMB: Double
        let ports: [UInt16]

        var formattedMemory: String {
            memoryMB < 1024
                ? String(format: "%.0f MB", memoryMB)
                : String(format: "%.1f GB", memoryMB / 1024)
        }

        var formattedPorts: String {
            let visible = Array(ports.prefix(4))
            let joined = visible.map { ":\($0)" }.joined(separator: " ")
            return ports.count > visible.count
                ? "\(joined) +\(ports.count - visible.count)"
                : joined
        }
    }

    private func aggregate(_ procs: [TrackedProcess]) -> Aggregate {
        let cpu = procs.reduce(0.0) { $0 + $1.cpuPercent }
        let mem = procs.reduce(0.0) { $0 + $1.memoryMB }
        let ports = Array(Set(procs.flatMap(\.ports))).sorted()
        return Aggregate(cpuPercent: cpu, memoryMB: mem, ports: ports)
    }
}
