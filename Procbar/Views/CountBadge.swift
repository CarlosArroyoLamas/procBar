import SwiftUI

struct CountBadge: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(DesignSystem.Typography.badgeValue)
            .foregroundStyle(DesignSystem.Color.accent.swiftUI)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(DesignSystem.Color.accent.swiftUI.opacity(0.15))
            .clipShape(Capsule())
    }
}
