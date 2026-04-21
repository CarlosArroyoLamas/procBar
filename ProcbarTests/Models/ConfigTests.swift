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

    func test_activity_defaults_applied_when_missing() throws {
        let yaml = "worktree_roots: []\nprocess_patterns: []"
        let cfg = try Config.decode(fromYAML: yaml)
        XCTAssertEqual(cfg.activity.activeThresholdPercent, 1.0, accuracy: 0.001)
        XCTAssertEqual(cfg.activity.recentWindowMinutes, 15)
        XCTAssertEqual(cfg.activity.dormantWindowDays, 1)
    }

    func test_activity_values_parsed_and_clamped() throws {
        let yaml = """
        worktree_roots: []
        process_patterns: []
        activity:
          active_threshold_percent: 2.5
          recent_window_minutes: 30
          dormant_window_days: 7
        """
        let cfg = try Config.decode(fromYAML: yaml)
        XCTAssertEqual(cfg.activity.activeThresholdPercent, 2.5, accuracy: 0.001)
        XCTAssertEqual(cfg.activity.recentWindowMinutes, 30)
        XCTAssertEqual(cfg.activity.dormantWindowDays, 7)

        let tooBig = """
        worktree_roots: []
        process_patterns: []
        activity:
          active_threshold_percent: -1
          recent_window_minutes: 99999
          dormant_window_days: 9999
        """
        let cfg2 = try Config.decode(fromYAML: tooBig)
        XCTAssertEqual(cfg2.activity.activeThresholdPercent, 0.0)
        XCTAssertEqual(cfg2.activity.recentWindowMinutes, 1440)
        XCTAssertEqual(cfg2.activity.dormantWindowDays, 365)
    }
}
