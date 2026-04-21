import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var appContext: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                processCount: vm.groups.reduce(0) { $0 + $1.processes.count },
                worktreeCount: vm.groups.count
            )
            HairlineDivider().padding(.bottom, 6)

            if let err = vm.configError {
                ConfigErrorPill(message: err) { appContext.openSettings() }
                    .padding(.bottom, 6)
            }

            if vm.groups.isEmpty {
                EmptyStateView(
                    title: "All quiet.",
                    actionTitle: nil,
                    action: nil
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.sectionGap) {
                        ForEach(vm.groups) { group in
                            WorktreeSectionView(group: group)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: DesignSystem.Spacing.popoverMaxHeight)
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
