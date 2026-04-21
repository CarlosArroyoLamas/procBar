import Foundation
import Yams

struct Config: Codable, Equatable {
    enum MatchField: String, Codable, Equatable {
        case command
        case name
    }

    enum TemperatureUnit: String, Codable, Equatable {
        case celsius
        case fahrenheit

        var symbol: String {
            switch self {
            case .celsius:    return "°C"
            case .fahrenheit: return "°F"
            }
        }

        /// Converts a raw sensor reading (always °C from the HID API) to
        /// this unit.
        func display(fromCelsius c: Double) -> Double {
            switch self {
            case .celsius:    return c
            case .fahrenheit: return c * 9.0 / 5.0 + 32.0
            }
        }
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
    var activity: ActivityConfig
    var apps: [AppTracked]
    var temperatureUnit: TemperatureUnit

    enum CodingKeys: String, CodingKey {
        case refreshIntervalSeconds = "refresh_interval_seconds"
        case showBranch             = "show_branch"
        case launchAtLogin          = "launch_at_login"
        case worktreeRoots          = "worktree_roots"
        case excludedPaths          = "excluded_paths"
        case processPatterns        = "process_patterns"
        case activity
        case apps
        case temperatureUnit        = "temperature_unit"
    }

    init(
        refreshIntervalSeconds: Int = 2,
        showBranch: Bool = true,
        launchAtLogin: Bool = false,
        worktreeRoots: [String] = [],
        excludedPaths: [String] = [],
        processPatterns: [Pattern] = [],
        activity: ActivityConfig = ActivityConfig(),
        apps: [AppTracked] = [],
        temperatureUnit: TemperatureUnit = .celsius
    ) {
        self.refreshIntervalSeconds = max(1, min(30, refreshIntervalSeconds))
        self.showBranch = showBranch
        self.launchAtLogin = launchAtLogin
        self.worktreeRoots = worktreeRoots
        self.excludedPaths = excludedPaths
        self.processPatterns = processPatterns
        self.activity = activity
        self.apps = apps
        self.temperatureUnit = temperatureUnit
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let refresh = try c.decodeIfPresent(Int.self, forKey: .refreshIntervalSeconds) ?? 2
        let showBranch = try c.decodeIfPresent(Bool.self, forKey: .showBranch) ?? true
        let launch = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
        let roots = try c.decodeIfPresent([String].self, forKey: .worktreeRoots) ?? []
        let excluded = try c.decodeIfPresent([String].self, forKey: .excludedPaths) ?? []
        let patterns = try c.decodeIfPresent([Pattern].self, forKey: .processPatterns) ?? []
        let activity = (try? c.decode(ActivityConfig.self, forKey: .activity)) ?? ActivityConfig()
        let apps = try c.decodeIfPresent([AppTracked].self, forKey: .apps) ?? []
        let tempUnit = try c.decodeIfPresent(TemperatureUnit.self, forKey: .temperatureUnit) ?? .celsius
        self.init(
            refreshIntervalSeconds: refresh,
            showBranch: showBranch,
            launchAtLogin: launch,
            worktreeRoots: roots,
            excludedPaths: excluded,
            processPatterns: patterns,
            activity: activity,
            apps: apps,
            temperatureUnit: tempUnit
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
            ],
            activity: ActivityConfig()
        )
    }
}

extension Config {
    /// A Mac app whose entire process tree (main + helpers/renderers)
    /// should be tracked as one aggregated group. Matching is by exe-path
    /// prefix against `path` (the absolute .app bundle path).
    struct AppTracked: Codable, Equatable, Hashable, Identifiable {
        var name: String
        var path: String

        var id: String { path }
    }
}

extension Config {
    struct ActivityConfig: Codable, Equatable {
        /// CPU% above this is `.activeNow` (green).
        var activeThresholdPercent: Double
        /// Idle below this window is `.recent` (yellow). Default 15 min.
        var recentWindowMinutes: Int
        /// Idle at or above this window is `.dormant` (red). Default 1 day.
        /// Anything between `recentWindowMinutes` and this is `.stale`
        /// (orange).
        var dormantWindowDays: Int

        enum CodingKeys: String, CodingKey {
            case activeThresholdPercent = "active_threshold_percent"
            case recentWindowMinutes    = "recent_window_minutes"
            case dormantWindowDays      = "dormant_window_days"
        }

        init(
            activeThresholdPercent: Double = 1.0,
            recentWindowMinutes: Int = 15,
            dormantWindowDays: Int = 1
        ) {
            self.activeThresholdPercent = max(0, activeThresholdPercent)
            self.recentWindowMinutes    = max(1, min(1440, recentWindowMinutes))
            self.dormantWindowDays      = max(1, min(365, dormantWindowDays))
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let pct  = try c.decodeIfPresent(Double.self, forKey: .activeThresholdPercent) ?? 1.0
            let mins = try c.decodeIfPresent(Int.self, forKey: .recentWindowMinutes) ?? 15
            let days = try c.decodeIfPresent(Int.self, forKey: .dormantWindowDays) ?? 1
            self.init(
                activeThresholdPercent: pct,
                recentWindowMinutes: mins,
                dormantWindowDays: days
            )
        }
    }
}
