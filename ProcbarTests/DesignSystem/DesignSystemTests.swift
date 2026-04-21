import XCTest
import SwiftUI
@testable import Procbar

final class DesignSystemTests: XCTestCase {
    func test_spacing_scale_is_consistent() {
        XCTAssertEqual(DesignSystem.Spacing.rowHeight, 46)
        XCTAssertEqual(DesignSystem.Spacing.popoverWidth, 560)
        XCTAssertEqual(DesignSystem.Spacing.outerHorizontal, 18)
        XCTAssertEqual(DesignSystem.Spacing.outerVertical, 14)
        XCTAssertEqual(DesignSystem.Spacing.sectionGap, 16)

        // Row interior must fit identity + meter + resource columns plus the
        // stop button without overflowing the popover's inner width. If this
        // assertion fires, the popover will clip horizontally (the bug that
        // showed up with the original 340pt width).
        let columns =
            DesignSystem.Spacing.identityColumnWidth +
            DesignSystem.Spacing.meterColumnWidth +
            DesignSystem.Spacing.resourceColumnWidth +
            DesignSystem.Spacing.stopButtonSize +
            40 // spacing between four children + minimum Spacer + action-column breathing room
        let innerWidth =
            DesignSystem.Spacing.popoverWidth - 2 * DesignSystem.Spacing.outerHorizontal
        XCTAssertGreaterThanOrEqual(innerWidth, columns,
            "Row columns must fit inside popover width minus horizontal padding.")
    }

    func test_motion_constants_match_spec() {
        let rowAppear = DesignSystem.Motion.rowAppear
        XCTAssertEqual(rowAppear.response, 0.25, accuracy: 0.001)
        XCTAssertEqual(rowAppear.damping, 0.9, accuracy: 0.001)

        XCTAssertEqual(DesignSystem.Motion.cpuBar.response, 0.4, accuracy: 0.001)
        XCTAssertEqual(DesignSystem.Motion.rowDisappear.response, 0.3, accuracy: 0.001)
    }

    func test_palette_keys_exist_for_light_and_dark() {
        // Sanity: colors resolve and aren't all equal (would mean a typo).
        let accentDark = DesignSystem.Color.accent.resolve(in: .dark)
        let accentLight = DesignSystem.Color.accent.resolve(in: .light)
        XCTAssertNotEqual(accentDark, accentLight)
    }
}
