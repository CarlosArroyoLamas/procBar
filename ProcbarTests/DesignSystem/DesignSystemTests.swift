import XCTest
import SwiftUI
@testable import Procbar

final class DesignSystemTests: XCTestCase {
    func test_spacing_scale_is_consistent() {
        XCTAssertEqual(DesignSystem.Spacing.rowHeight, 34)
        XCTAssertEqual(DesignSystem.Spacing.popoverWidth, 340)
        XCTAssertEqual(DesignSystem.Spacing.outerHorizontal, 14)
        XCTAssertEqual(DesignSystem.Spacing.outerVertical, 10)
        XCTAssertEqual(DesignSystem.Spacing.sectionGap, 12)
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
