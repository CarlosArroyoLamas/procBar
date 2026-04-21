import SwiftUI

enum DesignSystem {
    enum Spacing {
        static let popoverWidth: CGFloat = 560
        static let popoverMaxHeight: CGFloat = 720
        static let rowHeight: CGFloat = 46
        static let sectionGap: CGFloat = 16
        static let outerHorizontal: CGFloat = 18
        static let outerVertical: CGFloat = 14
        static let hairline: CGFloat = 1
        static let headerHeight: CGFloat = 36
        static let sectionHeaderHeight: CGFloat = 32
        static let footerHeight: CGFloat = 36
        static let cpuBarHeight: CGFloat = 3
        static let cpuBarWidth: CGFloat = 140
        static let stopButtonSize: CGFloat = 28

        // Per-row column widths for the process list.
        static let identityColumnWidth: CGFloat = 190
        static let meterColumnWidth: CGFloat = 140
        static let resourceColumnWidth: CGFloat = 120
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
