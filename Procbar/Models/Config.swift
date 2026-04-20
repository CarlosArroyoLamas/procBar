import Foundation
import Yams

struct Config: Codable, Equatable {
    enum MatchField: String, Codable, Equatable {
        case command
        case name
    }

    struct Pattern: Codable, Equatable {
        var name: String
        var match: String
        var matchField: MatchField

        enum CodingKeys: String, CodingKey {
            case name
            case match
            case matchField = "match_field"
        }
    }

    var refreshIntervalSeconds: Int
    var showBranch: Bool
    var launchAtLogin: Bool
    var worktreeRoots: [String]
    var excludedPaths: [String]
    var processPatterns: [Pattern]

    enum CodingKeys: String, CodingKey {
        case refreshIntervalSeconds = "refresh_interval_seconds"
        case showBranch             = "show_branch"
        case launchAtLogin          = "launch_at_login"
        case worktreeRoots          = "worktree_roots"
        case excludedPaths          = "excluded_paths"
        case processPatterns        = "process_patterns"
    }

    init(
        refreshIntervalSeconds: Int = 2,
        showBranch: Bool = true,
        launchAtLogin: Bool = false,
        worktreeRoots: [String] = [],
        excludedPaths: [String] = [],
        processPatterns: [Pattern] = []
    ) {
        self.refreshIntervalSeconds = max(1, min(30, refreshIntervalSeconds))
        self.showBranch = showBranch
        self.launchAtLogin = launchAtLogin
        self.worktreeRoots = worktreeRoots
        self.excludedPaths = excludedPaths
        self.processPatterns = processPatterns
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let refresh = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 2
        let showBranch = try c.decodeIfPresent(Bool.self, forKey: .showBranch) ?? true
        let launch = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        let roots = try c.decodeIfPresent([String].self, forKey: .worktreeRoots) ?? []
        let excluded = try c.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        let patterns = try c.decodeIfPresent([Pattern].self, forKey: .processPatterns) ?? []
        self.init(
            refreshIntervalSeconds: refresh,
            showBranch: showBranch,
            launchAtLogin: launch,
            worktreeRoots: roots,
            excludedPaths: excluded,
            processPatterns: patterns
        )
    }

    static func decode(fromYAML yaml: String) throws -> Config {
        let decoder = YAMLDecoder()
        return try decoder.decode(Config.self, from: yaml)
    }

    func encodedYAML() throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.indent = 2
        return try encoder.encode(self)
    }

    static func defaultConfig() -> Config {
        Config(
            refreshIntervalSeconds: 2,
            showBranch: true,
            launchAtLogin: false,
            worktreeRoots: ["~/Documents", "~/code"],
            excludedPaths: [],
            processPatterns: [
                .init(name: "NX",       match: "nx",       matchField: .command),
                .init(name: "Vite",     match: "vite",     matchField: .command),
                .init(name: "Node",     match: "node",     matchField: .name),
                .init(name: "Postgres", match: "postgres", matchField: .name)
            ]
        )
    }
}
