import SwiftUI

struct ActivityDot: View {
    let state: ActivityState
    @State private var bumped = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .scaleEffect(bumped ? 1.3 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: bumped)
            .onChange(of: state) { newValue in
                if newValue == .activeNow {
                    bumped = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { bumped = false }
                }
            }
    }

    private var color: Color {
        switch state {
        case .activeNow:       return DesignSystem.Color.success.swiftUI
        case .recentlyActive:  return DesignSystem.Color.accent.swiftUI
        case .idle:            return DesignSystem.Color.idleDot.swiftUI
        }
    }
}
