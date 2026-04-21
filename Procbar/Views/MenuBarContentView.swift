import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var appContext: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                processCount: vm.groups.reduce(0) { $0 + $1.processes.count }
                            + vm.apps.reduce(0) { $0 + $1.processes.count },
                worktreeCount: vm.groups.count,
                appCount: vm.apps.count
            )
            HairlineDivider().padding(.bottom, 6)

            if let err = vm.configError {
                ConfigErrorPill(message: err) { appContext.openSettings() }
                    .padding(.bottom, 6)
            }

            if vm.groups.isEmpty && vm.apps.isEmpty {
                EmptyStateView(
                    title: "All quiet.",
                    actionTitle: nil,
                    action: nil
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: DesignSystem.Spacing.sectionGap) {
                        if !vm.groups.isEmpty {
                            ForEach(vm.groups) { group in
                                WorktreeSectionView(group: group)
                            }
                        }

                        if !vm.apps.isEmpty {
                            if !vm.groups.isEmpty {
                                HairlineDivider().padding(.vertical, 4)
                            }
                            Text("APPLICATIONS")
                                .font(DesignSystem.Typography.microLabel)
                                .tracking(0.8)
                                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                            VStack(spacing: 0) {
                                ForEach(vm.apps) { appGroup in
                                    AppSectionView(group: appGroup)
                                }
                            }
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: DesignSystem.Spacing.popoverMaxHeight)
            }

            if !vm.groups.isEmpty || !vm.apps.isEmpty {
                ActivityLegend()
                    .padding(.top, 6)
            }

            HairlineDivider().padding(.top, 4)
            FooterView(
                openPreferences: { appContext.openSettings() },
                openConfigFile:  { appContext.openConfigFile() },
                quit:            { NSApplication.shared.terminate(nil) }
            )
        }
        .frame(
            width: DesignSystem.Spacing.popoverWidth - 2 * DesignSystem.Spacing.outerHorizontal,
            alignment: .leading
        )
        .padding(.horizontal, DesignSystem.Spacing.outerHorizontal)
        .padding(.vertical, DesignSystem.Spacing.outerVertical)
        .frame(
            width: DesignSystem.Spacing.popoverWidth,
            alignment: .leading
        )
        .background(DesignSystem.Color.background.swiftUI)
    }
}

struct ConfigErrorPill: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("CONFIG ERROR — \(message.uppercased())")
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(DesignSystem.Color.warning.swiftUI)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

/// Compact activity-state legend that shows above the footer so a user can
/// map the dots back to their meaning without hovering each one.
struct ActivityLegend: View {
    var body: some View {
        HStack(spacing: 14) {
            entry(color: DesignSystem.Color.activeDot.swiftUI,  label: "ACTIVE")
            entry(color: DesignSystem.Color.recentDot.swiftUI,  label: "<15m")
            entry(color: DesignSystem.Color.staleDot.swiftUI,   label: "15m–1d")
            entry(color: DesignSystem.Color.dormantDot.swiftUI, label: "1d+")
            Spacer()
        }
        .padding(.bottom, 4)
    }

    private func entry(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
        }
    }
}

struct EmptyStateView: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.textSecondary.swiftUI)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Color.accent.swiftUI)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
