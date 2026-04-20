import SwiftUI

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Color.hairline.swiftUI)
            .frame(height: DesignSystem.Spacing.hairline)
    }
}
