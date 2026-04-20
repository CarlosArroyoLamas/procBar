import SwiftUI

extension DesignSystem {
    enum Typography {
        static let header: Font = .system(size: 13, weight: .semibold, design: .default)
        static let body: Font = .system(size: 12, weight: .medium, design: .default)
        static let bodyRegular: Font = .system(size: 12, weight: .regular, design: .default)
        static let branch: Font = .system(size: 11, weight: .regular, design: .monospaced)
        static let numeric: Font = .system(size: 11, weight: .regular, design: .monospaced)
            .monospacedDigit()
        static let pidSubtitle: Font = .system(size: 10, weight: .regular, design: .monospaced)
            .monospacedDigit()
        static let microLabel: Font = .system(size: 9, weight: .medium, design: .default)
        static let badgeValue: Font = .system(size: 10, weight: .semibold, design: .monospaced)
            .monospacedDigit()
    }
}
