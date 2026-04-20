import XCTest
@testable import Procbar

final class ConfigTests: XCTestCase {
    func test_decode_full_config() throws {
        let yaml = """
        refresh_interval_seconds: 3
        show_branch: true
        launch_at_login: false
        worktree_roots:
          - ~/Documents
          - ~/code
        excluded_paths:
          - ~/Documents/archive
        process_patterns:
          - name: NX
            match: nx
            match_field: command
          - name: Node
            match: node
            match_field: name
        """
        let cfg = try Config.decode(fromYAML: yaml)

        XCTAssertEqual(cfg.refreshIntervalSeconds, 3)
        XCTAssertTrue(cfg.showBranch)
        XCTAssertFalse(cfg.launchAtLogin)
        XCTAssertEqual(cfg.worktreeRoots, ["~/Documents", "~/code"])
        XCTAssertEqual(cfg.excludedPaths, ["~/Documents/archive"])
        XCTAssertEqual(cfg.processPatterns.count, 2)
        XCTAssertEqual(cfg.processPatterns[0].name, "NX")
        XCTAssertEqual(cfg.processPatterns[0].match, "nx")
        XCTAssertEqual(cfg.processPatterns[0].matchField, .command)
        XCTAssertEqual(cfg.processPatterns[1].matchField, .name)
    }

    func test_decode_applies_defaults_when_optional_fields_missing() throws {
        let yaml = """
        worktree_roots: [~/code]
        process_patterns:
          - name: Vite
            match: vite
            match_field: command
        """
        let cfg = try Config.decode(fromYAML: yaml)
        XCTAssertEqual(cfg.refreshIntervalSeconds, 2)
        XCTAssertTrue(cfg.showBranch)
        XCTAssertFalse(cfg.launchAtLogin)
        XCTAssertEqual(cfg.excludedPaths, [])
    }

    func test_clamps_refresh_interval_out_of_range() throws {
        let tooLow = "refresh_interval_seconds: 0\nworktree_roots: []\nprocess_patterns: []"
        let tooHigh = "refresh_interval_seconds: 99\nworktree_roots: []\nprocess_patterns: []"
        XCTAssertEqual(try Config.decode(fromYAML: tooLow).refreshIntervalSeconds, 1)
        XCTAssertEqual(try Config.decode(fromYAML: tooHigh).refreshIntervalSeconds, 30)
    }

    func test_invalid_match_field_throws() {
        let yaml = """
        worktree_roots: []
        process_patterns:
          - name: Thing
            match: thing
            match_field: bogus
        """
        XCTAssertThrowsError(try Config.decode(fromYAML: yaml))
    }

    func test_roundtrip_encode_decode() throws {
        let original = Config.defaultConfig()
        let yaml = try original.encodedYAML()
        let decoded = try Config.decode(fromYAML: yaml)
        XCTAssertEqual(decoded, original)
    }
}
