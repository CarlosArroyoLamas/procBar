import SwiftUI

enum StopState { case idle, terminating, killing, done }

struct StopButton: View {
    let state: StopState
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        borderColor,
                        lineWidth: state == .terminating ? 1.5 : 1
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(fillColor)
                    )
                if state == .terminating {
                    Circle()
                        .trim(from: 0, to: 1)
                        .rotation(.degrees(-90))
                        .stroke(
                            DesignSystem.Color.accent.swiftUI,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: 18, height: 18)
                        .opacity(0.8)
                }
                Text(glyph)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(glyphColor)
            }
            .frame(
                width: DesignSystem.Spacing.stopButtonSize,
                height: DesignSystem.Spacing.stopButtonSize
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var glyph: String {
        switch state {
        case .idle:        return "⏻"
        case .terminating: return "◻︎"
        case .killing:     return "✕"
        case .done:        return "✓"
        }
    }

    private var borderColor: Color {
        switch state {
        case .killing: return DesignSystem.Color.warning.swiftUI
        case .done:    return DesignSystem.Color.success.swiftUI
        default:       return DesignSystem.Color.hairline.swiftUI
        }
    }

    private var fillColor: Color {
        switch state {
        case .killing: return DesignSystem.Color.warning.swiftUI
        case .done:    return DesignSystem.Color.success.swiftUI.opacity(0.2)
        default:       return hovering ? DesignSystem.Color.warning.swiftUI : .clear
        }
    }

    private var glyphColor: Color {
        switch state {
        case .killing:       return .white
        default:             return hovering
            ? .white
            : DesignSystem.Color.textSecondary.swiftUI
        }
    }
}
