import SwiftUI

struct FooterView: View {
    let openPreferences: () -> Void
    let openConfigFile: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            FooterButton(title: "PREFERENCES", action: openPreferences)
            FooterButton(title: "OPEN CONFIG", action: openConfigFile)
            FooterButton(title: "QUIT", action: quit)
            Spacer()
        }
        .frame(height: DesignSystem.Spacing.footerHeight)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(
                    hovering
                    ? DesignSystem.Color.textPrimary.swiftUI
                    : DesignSystem.Color.textSecondary.swiftUI
                )
                .underline(hovering, color: DesignSystem.Color.textPrimary.swiftUI)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
