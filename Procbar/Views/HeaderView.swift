import SwiftUI

struct HeaderView: View {
    let processCount: Int
    let worktreeCount: Int
    let appCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                .frame(width: 14, height: 14)
            Text("Procbar")
                .font(DesignSystem.Typography.header)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            Spacer()
            Text(summary)
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
        }
        .frame(height: DesignSystem.Spacing.headerHeight)
    }

    private var summary: String {
        var parts: [String] = ["\(processCount) PROC"]
        if worktreeCount > 0 { parts.append("\(worktreeCount) WT") }
        if appCount > 0      { parts.append("\(appCount) APPS") }
        return parts.joined(separator: " · ")
    }
}
