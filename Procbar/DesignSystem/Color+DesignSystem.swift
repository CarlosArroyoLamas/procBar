import SwiftUI
import AppKit

extension DesignSystem {
    struct ColorPair {
        let light: NSColor
        let dark: NSColor

        func resolve(in appearance: ColorScheme) -> NSColor {
            appearance == .dark ? dark : light
        }

        var swiftUI: SwiftUI.Color {
            SwiftUI.Color(nsColor: NSColor(name: nil) { app in
                app.bestMatch(from: [.darkAqua, .vibrantDark]) == nil ? self.light : self.dark
            })
        }
    }

    enum Color {
        static let background = ColorPair(
            light: NSColor(hex: 0xFAFAF7),
            dark:  NSColor(hex: 0x0E0E10)
        )
        static let surface = ColorPair(
            light: NSColor(hex: 0xFFFFFF),
            dark:  NSColor(hex: 0x16161A)
        )
        static let hairline = ColorPair(
            light: NSColor.black.withAlphaComponent(0.10),
            dark:  NSColor.white.withAlphaComponent(0.10)
        )
        static let textPrimary = ColorPair(
            light: NSColor(hex: 0x131316),
            dark:  NSColor(hex: 0xF2F2F5)
        )
        static let textSecondary = ColorPair(
            light: NSColor(hex: 0x5C5C65),
            dark:  NSColor(hex: 0x8A8A94)
        )
        static let textTertiary = ColorPair(
            light: NSColor(hex: 0x9A9AA0),
            dark:  NSColor(hex: 0x5C5C65)
        )
        static let accent = ColorPair(
            light: NSColor(hex: 0xC9820A),
            dark:  NSColor(hex: 0xFFB020)
        )
        static let warning = ColorPair(
            light: NSColor(hex: 0xC7341E),
            dark:  NSColor(hex: 0xFF5B49)
        )
        static let success = ColorPair(
            light: NSColor(hex: 0x2F8C4C),
            dark:  NSColor(hex: 0x4FD97C)
        )
        static let idleDot = ColorPair(
            light: NSColor(hex: 0x9A9AA0),
            dark:  NSColor(hex: 0x5C5C65)
        )

        // Activity dot palette. Green→yellow→orange→red traffic-light ramp,
        // each hue calibrated so it's distinct both in light and dark mode.
        static let activeDot = ColorPair(
            light: NSColor(hex: 0x2F8C4C),
            dark:  NSColor(hex: 0x4FD97C)
        )
        static let recentDot = ColorPair(
            light: NSColor(hex: 0xBF8E0A),
            dark:  NSColor(hex: 0xF5CC3D)
        )
        static let staleDot = ColorPair(
            light: NSColor(hex: 0xC96A0E),
            dark:  NSColor(hex: 0xFF9033)
        )
        static let dormantDot = ColorPair(
            light: NSColor(hex: 0xC7341E),
            dark:  NSColor(hex: 0xFF5B49)
        )
    }
}

extension NSColor {
    convenience init(hex: UInt32) {
        let r = CGFloat((hex >> 16) & 0xFF) / 255.0
        let g = CGFloat((hex >>  8) & 0xFF) / 255.0
        let b = CGFloat( hex        & 0xFF) / 255.0
        self.init(srgbRed: r, green: g, blue: b, alpha: 1.0)
    }
}
