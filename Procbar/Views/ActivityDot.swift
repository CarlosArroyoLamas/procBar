import SwiftUI

struct ActivityDot: View {
    let state: ActivityState
    @State private var bumped = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 6, height: 6)
            .scaleEffect(bumped ? 1.35 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: bumped)
            .help(tooltip)
            .onChange(of: state) { newValue in
                if newValue == .activeNow {
                    bumped = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { bumped = false }
                }
            }
    }

    private var color: Color {
        switch state {
        case .activeNow: return DesignSystem.Color.activeDot.swiftUI
        case .recent:    return DesignSystem.Color.recentDot.swiftUI
        case .stale:     return DesignSystem.Color.staleDot.swiftUI
        case .dormant:   return DesignSystem.Color.dormantDot.swiftUI
        }
    }

    private var tooltip: String {
        switch state {
        case .activeNow: return "Active now — CPU above threshold this tick"
        case .recent:    return "Active within the last 15 minutes"
        case .stale:     return "Idle for more than 15 minutes"
        case .dormant:   return "Idle for more than 1 day — probably forgotten"
        }
    }
}
