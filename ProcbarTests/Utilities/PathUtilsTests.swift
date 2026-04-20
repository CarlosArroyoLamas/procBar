import XCTest
@testable import Procbar

final class PathUtilsTests: XCTestCase {
    func test_expand_tilde_to_home() {
        let home = NSHomeDirectory()
        XCTAssertEqual(PathUtils.expand("~"),             home)
        XCTAssertEqual(PathUtils.expand("~/Documents"),   "\(home)/Documents")
        XCTAssertEqual(PathUtils.expand("/abs/path"),     "/abs/path")
        XCTAssertEqual(PathUtils.expand(""),              "")
    }

    func test_isInside_basic_cases() {
        XCTAssertTrue(PathUtils.isInside(child: "/a/b/c", parent: "/a/b"))
        XCTAssertTrue(PathUtils.isInside(child: "/a/b",    parent: "/a/b"))
        XCTAssertFalse(PathUtils.isInside(child: "/a/bc",  parent: "/a/b"))     // not a substring match
        XCTAssertFalse(PathUtils.isInside(child: "/a",     parent: "/a/b"))
    }

    func test_isInside_normalizes_trailing_slashes() {
        XCTAssertTrue(PathUtils.isInside(child: "/a/b/c/", parent: "/a/b/"))
        XCTAssertTrue(PathUtils.isInside(child: "/a/b",    parent: "/a/b/"))
    }
}
