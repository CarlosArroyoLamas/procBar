import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let popoverWidth: CGFloat = 340
        static let rowHeight: CGFloat = 34
        static let sectionGap: CGFloat = 12
        static let outerHorizontal: CGFloat = 14
        static let outerVertical: CGFloat = 10
        static let hairline: CGFloat = 1
        static let headerHeight: CGFloat = 28
        static let sectionHeaderHeight: CGFloat = 26
        static let footerHeight: CGFloat = 30
        static let cpuBarHeight: CGFloat = 2
        static let cpuBarWidth: CGFloat = 80
        static let stopButtonSize: CGFloat = 24
    }

    struct MotionSpec {
        let response: Double
        let damping: Double

        var animation: Animation {
            .spring(response: response, dampingFraction: damping)
        }
    }

    enum Motion {
        static let rowAppear    = MotionSpec(response: 0.25, damping: 0.9)
        static let rowDisappear = MotionSpec(response: 0.3,  damping: 0.85)
        static let cpuBar       = MotionSpec(response: 0.4,  damping: 0.85)
        static let section      = MotionSpec(response: 0.28, damping: 0.9)
        static let rowStaggerMs: Double = 30
        static let killGraceSeconds: Double = 3.0
        static let killSuccessFlashMs: Double = 200
        static let killFailureFlashMs: Double = 120
    }
}
