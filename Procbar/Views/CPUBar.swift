import SwiftUI

struct CPUBar: View {
    let percent: Double          // 0..100+

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DesignSystem.Color.hairline.swiftUI)
                Rectangle()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(min(percent, 100) / 100))
                    .animation(DesignSystem.Motion.cpuBar.animation, value: percent)
            }
        }
        .frame(width: DesignSystem.Spacing.cpuBarWidth,
               height: DesignSystem.Spacing.cpuBarHeight)
        .clipShape(RoundedRectangle(cornerRadius: 1))
    }

    private var tint: Color {
        percent >= 80
            ? DesignSystem.Color.warning.swiftUI
            : DesignSystem.Color.accent.swiftUI
    }
}
