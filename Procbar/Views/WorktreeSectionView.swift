import SwiftUI

struct WorktreeSectionView: View {
    let group: WorktreeGroup
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(DesignSystem.Motion.section.animation) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                    Text(group.worktree.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                    if let branch = group.worktree.branch {
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
                .frame(height: DesignSystem.Spacing.sectionHeaderHeight)
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
}
