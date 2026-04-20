# Procbar Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a macOS menu bar utility that groups and kills local dev processes by git worktree, matching the "Instrument Panel" aesthetic described in the spec.

**Architecture:** Single-process SwiftUI app using `MenuBarExtra(.window)` for the popover and `Settings` for preferences. Services (`ConfigStore`, `WorktreeScanner`, `ProcessScanner`, `ProcessMatcher`, `ProcessKiller`) sit behind protocols so they can be unit-tested with fakes. The scanner uses Darwin `libproc` for two-phase enumeration (cheap list → expensive details for matched PIDs only). Kill sequence is SIGTERM-to-tree → wait 3s → SIGKILL survivors.

**Tech Stack:**
- Swift 5.9+, SwiftUI (macOS 13+)
- [Yams](https://github.com/jpsim/Yams) for YAML parsing (SPM dependency)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to keep the Xcode project text-based (`project.yml` → generated `.xcodeproj`)
- Darwin `libproc` via bridging header (`#include <libproc.h>`)
- XCTest for unit/integration tests

**Source of truth for design decisions:** `../specs/2026-04-17-procbar-design.md`. When a step is ambiguous, consult the spec.

**Git discipline:** Commit at the end of each task. Message format: `feat(taskN): <short summary>` for features, `test(taskN): ...`, `chore(taskN): ...`. Include task number in the subject so the plan and history stay aligned.

---

## Task 0: Project scaffold

**Files:**
- Create: `project.yml` (XcodeGen config)
- Create: `Package.swift` (not used at runtime, but helps SPM tooling recognize Yams)
- Create: `Procbar/Info.plist`
- Create: `Procbar/ProcbarApp.swift`
- Create: `Procbar/BridgingHeader.h`
- Create: `Procbar/Resources/MenuBarIcon.pdf` (placeholder — real artwork in Task 12)
- Create: `.gitignore`
- Create: `README.md`

- [ ] **Step 1: Verify toolchain.**

Run:
```bash
xcode-select -p
swift --version
brew install xcodegen  # if not present
```
Expected: Xcode command line tools path (e.g. `/Applications/Xcode.app/Contents/Developer`), Swift 5.9+, `xcodegen` version prints.

- [ ] **Step 2: Create repository structure.**

Run:
```bash
mkdir -p Procbar/{Models,Services,ViewModels,Views,DesignSystem,Resources,Utilities}
mkdir -p ProcbarTests/{Models,Services,Utilities,Fixtures}
mkdir -p ProcbarUITests   # placeholder, no tests yet
```

- [ ] **Step 3: Write `project.yml`.**

```yaml
name: Procbar
options:
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true

packages:
  Yams:
    url: https://github.com/jpsim/Yams
    from: 5.0.0

targets:
  Procbar:
    type: application
    platform: macOS
    sources:
      - path: Procbar
    resources:
      - path: Procbar/Resources
    info:
      path: Procbar/Info.plist
      properties:
        CFBundleName: Procbar
        CFBundleIdentifier: com.carlos.procbar
        CFBundleShortVersionString: "0.1.0"
        CFBundleVersion: "1"
        LSMinimumSystemVersion: "13.0"
        LSUIElement: true         # hides dock icon
        NSHumanReadableCopyright: ""
    settings:
      base:
        SWIFT_OBJC_BRIDGING_HEADER: Procbar/BridgingHeader.h
        ENABLE_HARDENED_RUNTIME: YES
        CODE_SIGN_STYLE: Automatic
        PRODUCT_BUNDLE_IDENTIFIER: com.carlos.procbar
    dependencies:
      - package: Yams

  ProcbarTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: ProcbarTests
    dependencies:
      - target: Procbar

schemes:
  Procbar:
    build:
      targets:
        Procbar: all
        ProcbarTests: [test]
    test:
      targets:
        - ProcbarTests
```

- [ ] **Step 4: Write `Procbar/BridgingHeader.h`.**

```c
#ifndef BridgingHeader_h
#define BridgingHeader_h

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>

#endif
```

- [ ] **Step 5: Write `Procbar/ProcbarApp.swift` (stub).**

```swift
import SwiftUI

@main
struct ProcbarApp: App {
    var body: some Scene {
        MenuBarExtra("Procbar", systemImage: "square.stack.3d.up.fill") {
            Text("Hello, Procbar")
                .padding()
        }
        .menuBarExtraStyle(.window)

        Settings {
            Text("Settings — to be built")
                .padding()
        }
    }
}
```

- [ ] **Step 6: Write `.gitignore`.**

```
.build/
.swiftpm/
DerivedData/
*.xcodeproj/
*.xcworkspace/
xcuserdata/
.DS_Store
```

- [ ] **Step 7: Write `README.md`.**

```markdown
# Procbar

Menu bar utility for tracking and killing dev processes across git worktrees.

## Build

```bash
xcodegen generate
open Procbar.xcodeproj
# Or:
xcodebuild -scheme Procbar -configuration Debug build
```

## Test

```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS'
```
```

- [ ] **Step 8: Generate the project and verify it builds.**

Run:
```bash
xcodegen generate
xcodebuild -scheme Procbar -configuration Debug build
```
Expected: build succeeds; `.app` produced under `build/Debug/`.

- [ ] **Step 9: Run it once to verify the menu bar icon appears and dock is hidden.**

Run:
```bash
open build/Debug/Procbar.app
```
Expected: icon shows up in the menu bar; no dock icon appears; clicking shows the "Hello, Procbar" placeholder.

- [ ] **Step 10: Commit.**

```bash
git add -A
git commit -m "feat(task0): scaffold Xcode project, Yams dep, menu bar shell"
```

---

## Task 1: Design system foundation

**Files:**
- Create: `Procbar/DesignSystem/DesignSystem.swift`
- Create: `Procbar/DesignSystem/Color+DesignSystem.swift`
- Create: `Procbar/DesignSystem/Font+DesignSystem.swift`
- Create: `ProcbarTests/DesignSystem/DesignSystemTests.swift`

- [ ] **Step 1: Write the failing test.**

`ProcbarTests/DesignSystem/DesignSystemTests.swift`:

```swift
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
```

- [ ] **Step 2: Run the test — expect failure (symbols undefined).**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/DesignSystemTests
```
Expected: compilation failure referencing `DesignSystem`.

- [ ] **Step 3: Implement `DesignSystem.swift`.**

```swift
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
```

- [ ] **Step 4: Implement `Color+DesignSystem.swift`.**

```swift
import SwiftUI
import AppKit

extension DesignSystem {
    struct ColorPair {
        let light: NSColor
        let dark: NSColor

        func resolve(in appearance: ColorScheme) -> NSColor {
            appearance == .dark ? dark : light
        }

        var swiftUI: Color {
            Color(nsColor: NSColor(name: nil) { app in
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
```

- [ ] **Step 5: Implement `Font+DesignSystem.swift`.**

```swift
import SwiftUI

extension DesignSystem {
    enum Typography {
        static let header: Font = .system(size: 13, weight: .semibold, design: .default)
        static let body: Font = .system(size: 12, weight: .medium, design: .default)
        static let bodyRegular: Font = .system(size: 12, weight: .regular, design: .default)
        static let branch: Font = .system(size: 11, weight: .regular, design: .monospaced)
        static let numeric: Font = .system(size: 11, weight: .regular, design: .monospaced)
            .monospacedDigit()
        static let pidSubtitle: Font = .system(size: 10, weight: .regular, design: .monospaced)
            .monospacedDigit()
        static let microLabel: Font = .system(size: 9, weight: .medium, design: .default)
        static let badgeValue: Font = .system(size: 10, weight: .semibold, design: .monospaced)
            .monospacedDigit()
    }
}
```

- [ ] **Step 6: Run tests — expect pass.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/DesignSystemTests
```
Expected: 3 tests pass.

- [ ] **Step 7: Commit.**

```bash
git add -A
git commit -m "feat(task1): design system (colors, typography, spacing, motion)"
```

---

## Task 2: Config models + YAML parsing

**Files:**
- Create: `Procbar/Models/Config.swift`
- Create: `ProcbarTests/Models/ConfigTests.swift`
- Create: `ProcbarTests/Fixtures/config-example.yaml`

- [ ] **Step 1: Write the fixture YAML.**

`ProcbarTests/Fixtures/config-example.yaml`:

```yaml
refresh_interval_seconds: 3
show_branch: true
launch_at_login: false

worktree_roots:
  - ~/Documents
  - ~/code

excluded_paths:
  - ~/Documents/archive

process_patterns:
  - name: "NX"
    match: "nx"
    match_field: command
  - name: "Node"
    match: "node"
    match_field: name
```

(Add to project.yml resources for the test target by listing `ProcbarTests/Fixtures` under `ProcbarTests.sources`, since XcodeGen picks it up by extension. Alternatively embed the YAML as a string in the test — this plan uses an embedded string to avoid resource plumbing; the `.yaml` file stays as a reference.)

- [ ] **Step 2: Write the failing tests.**

`ProcbarTests/Models/ConfigTests.swift`:

```swift
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
```

- [ ] **Step 3: Run tests — expect compile failure.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/ConfigTests
```
Expected: `Config` undefined.

- [ ] **Step 4: Implement `Config.swift`.**

```swift
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
        let refresh = (try? c.decode(Int.self, forKey: .refreshIntervalSeconds)) ?? 2
        let showBranch = (try? c.decode(Bool.self, forKey: .showBranch)) ?? true
        let launch = (try? c.decode(Bool.self, forKey: .launchAtLogin)) ?? false
        let roots = (try? c.decode([String].self, forKey: .worktreeRoots)) ?? []
        let excluded = (try? c.decode([String].self, forKey: .excludedPaths)) ?? []
        let patterns = (try? c.decode([Pattern].self, forKey: .processPatterns)) ?? []
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
```

- [ ] **Step 5: Run tests — expect pass.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/ConfigTests
```
Expected: 5 tests pass.

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(task2): Config model with YAML decode/encode and defaults"
```

---

## Task 3: Path utilities

**Files:**
- Create: `Procbar/Utilities/PathUtils.swift`
- Create: `ProcbarTests/Utilities/PathUtilsTests.swift`

- [ ] **Step 1: Write the failing tests.**

```swift
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
```

- [ ] **Step 2: Run — expect failure.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/PathUtilsTests
```
Expected: `PathUtils` undefined.

- [ ] **Step 3: Implement `PathUtils.swift`.**

```swift
import Foundation

enum PathUtils {
    static func expand(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        if path == "~" { return NSHomeDirectory() }
        if path.hasPrefix("~/") { return NSHomeDirectory() + String(path.dropFirst(1)) }
        return path
    }

    /// Is `child` equal to `parent` or inside it (by path component, not substring)?
    static func isInside(child: String, parent: String) -> Bool {
        let c = normalize(child)
        let p = normalize(parent)
        if c == p { return true }
        return c.hasPrefix(p + "/")
    }

    private static func normalize(_ path: String) -> String {
        guard !path.isEmpty else { return path }
        var s = path
        while s.count > 1, s.hasSuffix("/") { s.removeLast() }
        return s
    }
}
```

- [ ] **Step 4: Run — expect pass.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/PathUtilsTests
```
Expected: 3 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task3): PathUtils (tilde expansion, isInside)"
```

---

## Task 4: ConfigStore (load / save / watch)

**Files:**
- Create: `Procbar/Services/ConfigStore.swift`
- Create: `ProcbarTests/Services/ConfigStoreTests.swift`

- [ ] **Step 1: Write the failing tests.**

```swift
import XCTest
import Combine
@testable import Procbar

final class ConfigStoreTests: XCTestCase {
    private var tempDir: URL!
    private var path: URL!
    private var cancellables: Set<AnyCancellable>!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        path = tempDir.appendingPathComponent("config.yaml")
        cancellables = []
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func test_loads_default_config_and_writes_file_when_missing() throws {
        let store = ConfigStore(path: path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: path.path))

        let loaded = try store.loadOrCreateDefault()
        XCTAssertEqual(loaded, Config.defaultConfig())
        XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    }

    func test_loads_existing_file() throws {
        try "refresh_interval_seconds: 5\nworktree_roots: []\nprocess_patterns: []\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(path: path)
        let loaded = try store.loadOrCreateDefault()
        XCTAssertEqual(loaded.refreshIntervalSeconds, 5)
    }

    func test_invalid_yaml_surfaces_as_error_but_keeps_last_good() throws {
        try "refresh_interval_seconds: 2\nworktree_roots: []\nprocess_patterns: []\n"
            .write(to: path, atomically: true, encoding: .utf8)
        let store = ConfigStore(path: path)
        _ = try store.loadOrCreateDefault()

        try "this is not: valid yaml: at all: \t\n  - : :"
            .write(to: path, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try store.reload())
        XCTAssertEqual(store.current.refreshIntervalSeconds, 2, "last-good retained")
    }

    func test_save_writes_yaml_that_roundtrips() throws {
        let store = ConfigStore(path: path)
        var cfg = try store.loadOrCreateDefault()
        cfg.refreshIntervalSeconds = 7
        try store.save(cfg)
        let reloaded = try store.reload()
        XCTAssertEqual(reloaded.refreshIntervalSeconds, 7)
    }

    func test_publishes_when_file_changes() throws {
        let store = ConfigStore(path: path)
        _ = try store.loadOrCreateDefault()
        store.startWatching()
        defer { store.stopWatching() }

        let exp = expectation(description: "external change published")
        store.changes.sink { _ in exp.fulfill() }.store(in: &cancellables)

        // External write
        try "refresh_interval_seconds: 9\nworktree_roots: []\nprocess_patterns: []\n"
            .write(to: path, atomically: true, encoding: .utf8)

        wait(for: [exp], timeout: 3.0)
        XCTAssertEqual(store.current.refreshIntervalSeconds, 9)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/ConfigStoreTests
```
Expected: `ConfigStore` undefined.

- [ ] **Step 3: Implement `ConfigStore.swift`.**

```swift
import Foundation
import Combine
import os

final class ConfigStore {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "config")

    private let path: URL
    private(set) var current: Config = Config.defaultConfig()

    private let subject = PassthroughSubject<Config, Never>()
    var changes: AnyPublisher<Config, Never> { subject.eraseToAnyPublisher() }

    private var watchSource: DispatchSourceFileSystemObject?
    private var watchDescriptor: Int32 = -1
    private var watchQueue = DispatchQueue(label: "com.carlos.procbar.configwatch")
    private var debounceItem: DispatchWorkItem?

    init(path: URL) {
        self.path = path
    }

    static var defaultPath: URL {
        let xdg = ProcessInfo.processInfo.environment["XDG_CONFIG_HOME"]
        let base: URL = {
            if let xdg, !xdg.isEmpty {
                return URL(fileURLWithPath: PathUtils.expand(xdg), isDirectory: true)
            }
            return URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".config", isDirectory: true)
        }()
        return base.appendingPathComponent("procbar", isDirectory: true)
                   .appendingPathComponent("config.yaml")
    }

    @discardableResult
    func loadOrCreateDefault() throws -> Config {
        if FileManager.default.fileExists(atPath: path.path) {
            return try reload()
        }
        let dir = path.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let def = Config.defaultConfig()
        try save(def)
        current = def
        return def
    }

    @discardableResult
    func reload() throws -> Config {
        let text = try String(contentsOf: path, encoding: .utf8)
        do {
            let cfg = try Config.decode(fromYAML: text)
            current = cfg
            logger.info("Config reloaded")
            return cfg
        } catch {
            logger.error("Invalid YAML: \(error.localizedDescription, privacy: .public)")
            throw error
        }
    }

    func save(_ cfg: Config) throws {
        let text = try cfg.encodedYAML()
        try text.write(to: path, atomically: true, encoding: .utf8)
        current = cfg
    }

    func startWatching() {
        stopWatching()
        let fd = open(path.path, O_EVTONLY)
        guard fd >= 0 else {
            logger.error("Failed to open config for watching: \(String(cString: strerror(errno)), privacy: .public)")
            return
        }
        watchDescriptor = fd
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .delete, .rename],
            queue: watchQueue
        )
        source.setEventHandler { [weak self] in self?.handleFileEvent() }
        source.setCancelHandler { [weak self] in
            if let fd = self?.watchDescriptor, fd >= 0 { close(fd) }
            self?.watchDescriptor = -1
        }
        source.resume()
        watchSource = source
    }

    func stopWatching() {
        watchSource?.cancel()
        watchSource = nil
    }

    private func handleFileEvent() {
        debounceItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            do {
                let cfg = try self.reload()
                self.subject.send(cfg)
            } catch {
                // keep last-good, don't publish
            }
            // If file was deleted & recreated (atomic write), re-arm watch.
            if !FileManager.default.fileExists(atPath: self.path.path) {
                self.stopWatching()
            } else if self.watchSource == nil {
                self.startWatching()
            }
        }
        debounceItem = item
        watchQueue.asyncAfter(deadline: .now() + 0.15, execute: item)
    }
}
```

- [ ] **Step 4: Run — expect pass.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/ConfigStoreTests
```
Expected: 5 tests pass (the watch test may take up to 3s due to debounce).

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task4): ConfigStore with load/save/watch and last-good retention"
```

---

## Task 5: Worktree model + scanner

**Files:**
- Create: `Procbar/Models/Worktree.swift`
- Create: `Procbar/Services/WorktreeScanner.swift`
- Create: `ProcbarTests/Services/WorktreeScannerTests.swift`

- [ ] **Step 1: Write the failing tests.**

```swift
import XCTest
@testable import Procbar

final class WorktreeScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-wt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func test_discovers_direct_repo_and_nested_repos() throws {
        try makeGitRepo(at: root.appendingPathComponent("alpha"))
        try makeGitRepo(at: root.appendingPathComponent("beta/gamma"))
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("not-a-repo"),
            withIntermediateDirectories: true
        )

        let scanner = WorktreeScanner(branchReader: FakeBranchReader(branches: [:]))
        let result = scanner.scan(roots: [root.path], excluded: [])

        let names = Set(result.map { $0.name })
        XCTAssertEqual(names, ["alpha", "gamma"])
    }

    func test_respects_excluded_paths() throws {
        try makeGitRepo(at: root.appendingPathComponent("alpha"))
        try makeGitRepo(at: root.appendingPathComponent("beta"))

        let scanner = WorktreeScanner(branchReader: FakeBranchReader(branches: [:]))
        let result = scanner.scan(
            roots: [root.path],
            excluded: [root.appendingPathComponent("beta").path]
        )
        XCTAssertEqual(result.map { $0.name }, ["alpha"])
    }

    func test_recognizes_gitfile_worktree_pointer() throws {
        let wtDir = root.appendingPathComponent("linked-worktree")
        try FileManager.default.createDirectory(at: wtDir, withIntermediateDirectories: true)
        try "gitdir: /tmp/some-main/.git/worktrees/x".write(
            to: wtDir.appendingPathComponent(".git"),
            atomically: true, encoding: .utf8
        )
        let scanner = WorktreeScanner(branchReader: FakeBranchReader(branches: [:]))
        let result = scanner.scan(roots: [root.path], excluded: [])
        XCTAssertEqual(result.map { $0.name }, ["linked-worktree"])
    }

    func test_reads_branch_through_injected_reader() throws {
        let repo = root.appendingPathComponent("repo")
        try makeGitRepo(at: repo)
        let reader = FakeBranchReader(branches: [repo.path: "main"])
        let scanner = WorktreeScanner(branchReader: reader)
        let result = scanner.scan(roots: [root.path], excluded: [])
        XCTAssertEqual(result.first?.branch, "main")
    }

    private func makeGitRepo(at dir: URL) throws {
        try FileManager.default.createDirectory(
            at: dir.appendingPathComponent(".git"),
            withIntermediateDirectories: true
        )
    }
}

struct FakeBranchReader: GitBranchReading {
    let branches: [String: String]
    func currentBranch(at path: String) -> String? { branches[path] }
}
```

- [ ] **Step 2: Run — expect failure.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/WorktreeScannerTests
```
Expected: undefined symbols.

- [ ] **Step 3: Implement `Worktree.swift`.**

```swift
import Foundation

struct Worktree: Identifiable, Hashable {
    let path: String
    let name: String
    var branch: String?

    var id: String { path }
}
```

- [ ] **Step 4: Implement `WorktreeScanner.swift`.**

```swift
import Foundation
import os

protocol GitBranchReading {
    func currentBranch(at path: String) -> String?
}

final class WorktreeScanner {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "scanner")
    private let branchReader: GitBranchReading
    private let maxDepth: Int

    init(branchReader: GitBranchReading, maxDepth: Int = 4) {
        self.branchReader = branchReader
        self.maxDepth = maxDepth
    }

    func scan(roots: [String], excluded: [String]) -> [Worktree] {
        var out: [Worktree] = []
        let fm = FileManager.default
        let excludedResolved = excluded.map(PathUtils.expand)
        for raw in roots {
            let root = PathUtils.expand(raw)
            guard fm.fileExists(atPath: root) else { continue }
            walk(root, depth: 0, excluded: excludedResolved, into: &out)
        }
        // Dedupe by path
        var seen = Set<String>()
        return out.filter { seen.insert($0.path).inserted }
    }

    private func walk(_ dir: String, depth: Int, excluded: [String], into out: inout [Worktree]) {
        if depth > maxDepth { return }
        if excluded.contains(where: { PathUtils.isInside(child: dir, parent: $0) }) { return }

        let dotGit = (dir as NSString).appendingPathComponent(".git")
        var isDir: ObjCBool = false
        let fm = FileManager.default
        if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
            let name = (dir as NSString).lastPathComponent
            let branch = branchReader.currentBranch(at: dir)
            out.append(Worktree(path: dir, name: name, branch: branch))
            return  // don't recurse into a repo's subfolders
        }

        guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { return }
        for entry in entries {
            if entry.hasPrefix(".") { continue }
            let sub = (dir as NSString).appendingPathComponent(entry)
            var isSubDir: ObjCBool = false
            if fm.fileExists(atPath: sub, isDirectory: &isSubDir), isSubDir.boolValue {
                walk(sub, depth: depth + 1, excluded: excluded, into: &out)
            }
        }
    }
}
```

- [ ] **Step 5: Run — expect pass.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/WorktreeScannerTests
```
Expected: 4 tests pass.

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(task5): Worktree model and scanner with git-file/dir detection"
```

---

## Task 6: Git branch reader (live)

**Files:**
- Create: `Procbar/Services/GitBranchReader.swift`
- Create: `ProcbarTests/Services/GitBranchReaderTests.swift`

- [ ] **Step 1: Write the failing tests (integration — actual git).**

```swift
import XCTest
@testable import Procbar

final class GitBranchReaderTests: XCTestCase {
    func test_reads_branch_from_real_repo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-gbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        _ = runGit(["init", "-b", "trunk"], cwd: dir.path)
        // Need at least one commit before symbolic-ref works reliably on some versions
        try "x".write(to: dir.appendingPathComponent("x"), atomically: true, encoding: .utf8)
        _ = runGit(["add", "."], cwd: dir.path)
        _ = runGit(["-c", "user.email=a@a", "-c", "user.name=a", "commit", "-m", "init"], cwd: dir.path)

        let reader = LiveGitBranchReader(ttlSeconds: 0)
        XCTAssertEqual(reader.currentBranch(at: dir.path), "trunk")
    }

    func test_returns_nil_for_non_repo() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-gbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let reader = LiveGitBranchReader(ttlSeconds: 0)
        XCTAssertNil(reader.currentBranch(at: dir.path))
    }

    func test_caches_within_ttl() throws {
        // Hard to measure timing; smoke-check: calling twice returns same value even if the
        // underlying directory is removed between calls (cache returns stale).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("procbar-gbr-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        _ = runGit(["init", "-b", "xx"], cwd: dir.path)
        try "x".write(to: dir.appendingPathComponent("x"), atomically: true, encoding: .utf8)
        _ = runGit(["add", "."], cwd: dir.path)
        _ = runGit(["-c", "user.email=a@a", "-c", "user.name=a", "commit", "-m", "init"], cwd: dir.path)

        let reader = LiveGitBranchReader(ttlSeconds: 60)
        XCTAssertEqual(reader.currentBranch(at: dir.path), "xx")
        try FileManager.default.removeItem(at: dir)
        XCTAssertEqual(reader.currentBranch(at: dir.path), "xx") // from cache
    }

    @discardableResult
    private func runGit(_ args: [String], cwd: String) -> Int32 {
        let p = Process()
        p.launchPath = "/usr/bin/env"
        p.arguments = ["git"] + args
        p.currentDirectoryPath = cwd
        p.standardOutput = Pipe()
        p.standardError = Pipe()
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

Run:
```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS' -only-testing:ProcbarTests/GitBranchReaderTests
```

- [ ] **Step 3: Implement `GitBranchReader.swift`.**

```swift
import Foundation
import os

final class LiveGitBranchReader: GitBranchReading {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "scanner")
    private let ttlSeconds: TimeInterval
    private var cache: [String: (branch: String?, stamp: Date)] = [:]
    private let lock = NSLock()

    init(ttlSeconds: TimeInterval = 10) {
        self.ttlSeconds = ttlSeconds
    }

    func currentBranch(at path: String) -> String? {
        lock.lock()
        if let cached = cache[path], Date().timeIntervalSince(cached.stamp) < ttlSeconds {
            lock.unlock()
            return cached.branch
        }
        lock.unlock()

        let branch = readBranch(at: path)
        lock.lock()
        cache[path] = (branch, Date())
        lock.unlock()
        return branch
    }

    private func readBranch(at path: String) -> String? {
        let proc = Process()
        proc.launchPath = "/usr/bin/env"
        proc.arguments = ["git", "-C", path, "symbolic-ref", "--short", "HEAD"]
        let out = Pipe(); let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        do {
            try proc.run()
        } catch {
            logger.error("git spawn failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let s = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty == false) ? s : nil
    }
}
```

- [ ] **Step 4: Run — expect pass.**

Expected: 3 tests pass.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task6): LiveGitBranchReader with TTL cache"
```

---

## Task 7: libproc bridge + ProcessSource protocol

**Files:**
- Create: `Procbar/Utilities/Libproc.swift`
- Create: `Procbar/Services/ProcessSource.swift`
- Create: `Procbar/Models/ProcessSnapshot.swift`

- [ ] **Step 1: Define the domain types.**

`Procbar/Models/ProcessSnapshot.swift`:

```swift
import Foundation

struct RawProcess: Equatable, Hashable {
    let pid: Int32
    let ppid: Int32
    let name: String          // short command name (argv[0] basename, or comm)
    let command: String       // full argv joined by space, truncated at 1024 chars
}

struct ProcessDetail: Equatable, Hashable {
    let pid: Int32
    let cwd: String?
    let residentBytes: UInt64
    let cpuTicks: UInt64           // cumulative, user+system
    let wallStartSeconds: TimeInterval  // seconds since epoch of process start
    let listeningPorts: [UInt16]
}
```

- [ ] **Step 2: Declare the protocol.**

`Procbar/Services/ProcessSource.swift`:

```swift
import Foundation

protocol ProcessSource {
    /// Cheap: all processes with PID/PPID/name/command.
    func listAll() -> [RawProcess]

    /// Expensive: details for the given PIDs only. Missing PIDs are omitted.
    func fetchDetails(for pids: [Int32]) -> [Int32: ProcessDetail]
}
```

- [ ] **Step 3: Implement the live `LibprocSource`.**

`Procbar/Utilities/Libproc.swift`:

```swift
import Foundation
import Darwin
import os

final class LibprocSource: ProcessSource {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "scanner")

    func listAll() -> [RawProcess] {
        let numBytesHint = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard numBytesHint > 0 else { return [] }
        let capacity = Int(numBytesHint) / MemoryLayout<pid_t>.size * 2
        var pids = [pid_t](repeating: 0, count: capacity)
        let bytesFilled = pids.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0,
                          buf.baseAddress, Int32(buf.count * MemoryLayout<pid_t>.size))
        }
        let count = Int(bytesFilled) / MemoryLayout<pid_t>.size

        var result: [RawProcess] = []
        result.reserveCapacity(count)
        for i in 0..<count {
            let pid = pids[i]
            guard pid > 0 else { continue }
            guard let bsd = fetchBsdInfo(pid) else { continue }
            let name = withUnsafePointer(to: bsd.pbi_comm) {
                $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXCOMLEN) + 1) {
                    String(cString: $0)
                }
            }
            let command = fetchCommandLine(pid) ?? name
            result.append(RawProcess(
                pid: pid,
                ppid: Int32(bsd.pbi_ppid),
                name: name,
                command: command
            ))
        }
        return result
    }

    func fetchDetails(for pids: [Int32]) -> [Int32: ProcessDetail] {
        var out: [Int32: ProcessDetail] = [:]
        for pid in pids {
            guard let bsd = fetchBsdInfo(pid) else { continue }
            let cwd = fetchCwd(pid)
            let taskInfo = fetchTaskInfo(pid)
            let ports = fetchListeningPorts(pid)
            let startSec = TimeInterval(bsd.pbi_start_tvsec)
                + TimeInterval(bsd.pbi_start_tvusec) / 1_000_000
            out[pid] = ProcessDetail(
                pid: pid,
                cwd: cwd,
                residentBytes: taskInfo?.resident ?? 0,
                cpuTicks: taskInfo?.cpuTicks ?? 0,
                wallStartSeconds: startSec,
                listeningPorts: ports
            )
        }
        return out
    }

    // MARK: - Low level

    private func fetchBsdInfo(_ pid: pid_t) -> proc_bsdinfo? {
        var info = proc_bsdinfo()
        let size = MemoryLayout<proc_bsdinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, Int32(size))
        return ret == Int32(size) ? info : nil
    }

    private func fetchCommandLine(_ pid: pid_t) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size: size_t = 0
        if sysctl(&mib, 3, nil, &size, nil, 0) != 0 { return nil }
        guard size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        if sysctl(&mib, 3, &buf, &size, nil, 0) != 0 { return nil }
        // Layout: [argc: int32][exe_path\0][padding\0*][argv0\0][argv1\0]...
        let argcSize = MemoryLayout<Int32>.size
        guard size > argcSize else { return nil }
        var argc: Int32 = 0
        memcpy(&argc, buf, argcSize)
        var cursor = argcSize
        // skip exe path
        while cursor < size, buf[cursor] != 0 { cursor += 1 }
        // skip nulls
        while cursor < size, buf[cursor] == 0 { cursor += 1 }
        // read argc argv strings
        var args: [String] = []
        for _ in 0..<Int(argc) {
            guard cursor < size else { break }
            let start = cursor
            while cursor < size, buf[cursor] != 0 { cursor += 1 }
            let slice = Array(buf[start..<cursor])
            if let s = String(validatingUTF8: slice + [0]) {
                args.append(s)
            }
            if cursor < size { cursor += 1 }
        }
        let joined = args.joined(separator: " ")
        return joined.isEmpty ? nil : String(joined.prefix(1024))
    }

    private func fetchCwd(_ pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = MemoryLayout<proc_vnodepathinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, Int32(size))
        guard ret == Int32(size) else { return nil }
        let path = withUnsafePointer(to: info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) {
                String(cString: $0)
            }
        }
        return path.isEmpty ? nil : path
    }

    private struct TaskInfoResult {
        let resident: UInt64
        let cpuTicks: UInt64
    }

    private func fetchTaskInfo(_ pid: pid_t) -> TaskInfoResult? {
        var ti = proc_taskinfo()
        let size = MemoryLayout<proc_taskinfo>.size
        let ret = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &ti, Int32(size))
        guard ret == Int32(size) else { return nil }
        return TaskInfoResult(
            resident: ti.pti_resident_size,
            cpuTicks: ti.pti_total_user + ti.pti_total_system
        )
    }

    private func fetchListeningPorts(_ pid: pid_t) -> [UInt16] {
        let numBytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard numBytes > 0 else { return [] }
        let fdCount = Int(numBytes) / MemoryLayout<proc_fdinfo>.size
        var fds = [proc_fdinfo](repeating: proc_fdinfo(), count: fdCount)
        let filled = fds.withUnsafeMutableBufferPointer { buf -> Int32 in
            proc_pidinfo(pid, PROC_PIDLISTFDS, 0,
                         buf.baseAddress, Int32(buf.count * MemoryLayout<proc_fdinfo>.size))
        }
        let n = Int(filled) / MemoryLayout<proc_fdinfo>.size

        var ports: [UInt16] = []
        for i in 0..<n {
            let fd = fds[i]
            guard Int32(fd.proc_fdtype) == PROX_FDTYPE_SOCKET else { continue }
            var sinfo = socket_fdinfo()
            let size = MemoryLayout<socket_fdinfo>.size
            let ret = proc_pidfdinfo(pid, fd.proc_fd,
                                     PROC_PIDFDSOCKETINFO, &sinfo, Int32(size))
            guard ret == Int32(size) else { continue }
            guard sinfo.psi.soi_kind == Int16(SOCKINFO_TCP) else { continue }
            let tcp = sinfo.psi.soi_proto.pri_tcp
            // Only LISTEN state = 1 per tcp_fsm.h (TCPS_LISTEN)
            guard tcp.tcpsi_state == 1 else { continue }
            let rawPort = tcp.tcpsi_ini.insi_lport.bigEndian
            let port = UInt16(truncatingIfNeeded: UInt32(rawPort) & 0xFFFF)
            if port > 0 { ports.append(port) }
        }
        return Array(Set(ports)).sorted()
    }
}
```

- [ ] **Step 4: Build and run the app manually to smoke-test libproc bindings.**

Temporarily add in `ProcbarApp.swift`:

```swift
// inside MenuBarExtra content
Text("PIDs: \(LibprocSource().listAll().count)")
```

Run:
```bash
xcodebuild -scheme Procbar -configuration Debug build && open build/Debug/Procbar.app
```
Expected: a number close to `ps ax | wc -l` ±5. Then revert the temporary text.

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task7): libproc bridge, ProcessSource protocol, and RawProcess/ProcessDetail models"
```

---

## Task 8: ProcessScanner (two-phase + CPU% delta)

**Files:**
- Create: `Procbar/Services/ProcessScanner.swift`
- Create: `Procbar/Models/TrackedProcess.swift`
- Create: `ProcbarTests/Services/ProcessScannerTests.swift`

- [ ] **Step 1: Model.**

`Procbar/Models/TrackedProcess.swift`:

```swift
import Foundation

struct TrackedProcess: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let displayName: String
    let command: String
    let cwd: String
    let cpuPercent: Double      // 0..100+
    let memoryMB: Double
    let ports: [UInt16]
    let uptimeSeconds: TimeInterval
    var id: Int32 { pid }
}
```

- [ ] **Step 2: Write the failing tests using a fake `ProcessSource`.**

`ProcbarTests/Services/ProcessScannerTests.swift`:

```swift
import XCTest
@testable import Procbar

final class ProcessScannerTests: XCTestCase {
    func test_second_sample_computes_nonzero_cpu_percent_when_ticks_advance() {
        let now: () -> Date = {
            var t = Date(timeIntervalSince1970: 1_700_000_000)
            return {
                defer { t = t.addingTimeInterval(1.0) }
                return t
            }()
        }()
        let fake = FakeProcessSource()
        fake.raw = [RawProcess(pid: 10, ppid: 1, name: "vite", command: "vite dev")]

        fake.detailsByPid = [10: ProcessDetail(
            pid: 10, cwd: "/tmp/wt", residentBytes: 10_000_000,
            cpuTicks: 1_000, wallStartSeconds: 1_699_999_000, listeningPorts: [3000]
        )]
        let scanner = ProcessScanner(source: fake, clock: now)
        _ = scanner.sample(matchPIDs: [10])

        fake.detailsByPid[10] = ProcessDetail(
            pid: 10, cwd: "/tmp/wt", residentBytes: 10_000_000,
            cpuTicks: 2_000, wallStartSeconds: 1_699_999_000, listeningPorts: [3000]
        )
        let second = scanner.sample(matchPIDs: [10])

        let t = second.tracked.first!
        XCTAssertEqual(t.pid, 10)
        XCTAssertGreaterThan(t.cpuPercent, 0)
        XCTAssertEqual(t.memoryMB, 10_000_000.0 / 1_048_576.0, accuracy: 0.01)
        XCTAssertEqual(t.ports, [3000])
    }

    func test_returns_empty_tracked_when_no_match_pids() {
        let fake = FakeProcessSource()
        fake.raw = [RawProcess(pid: 7, ppid: 1, name: "x", command: "x")]
        let scanner = ProcessScanner(source: fake, clock: { Date() })
        let result = scanner.sample(matchPIDs: [])
        XCTAssertTrue(result.tracked.isEmpty)
        XCTAssertEqual(result.all.count, 1)
    }
}

final class FakeProcessSource: ProcessSource {
    var raw: [RawProcess] = []
    var detailsByPid: [Int32: ProcessDetail] = [:]
    func listAll() -> [RawProcess] { raw }
    func fetchDetails(for pids: [Int32]) -> [Int32: ProcessDetail] {
        var o: [Int32: ProcessDetail] = [:]
        for p in pids { if let d = detailsByPid[p] { o[p] = d } }
        return o
    }
}
```

- [ ] **Step 3: Run — expect failure.**

- [ ] **Step 4: Implement `ProcessScanner.swift`.**

```swift
import Foundation

struct ScanResult {
    let all: [RawProcess]
    let tracked: [TrackedProcess]
    let timestamp: Date
}

final class ProcessScanner {
    private let source: ProcessSource
    private let clock: () -> Date
    private let hzPerCore: Double
    private var lastSample: (date: Date, ticksByPid: [Int32: UInt64])?

    init(source: ProcessSource, clock: @escaping () -> Date = Date.init) {
        self.source = source
        self.clock = clock
        let ncpu = Double(ProcessInfo.processInfo.activeProcessorCount)
        // Mach absolute ticks: user/system are in terms of nanoseconds on modern Darwin.
        // proc_pidinfo(PROC_PIDTASKINFO) returns user+system in mach_timebase ns.
        // We treat `cpuTicks` as nanoseconds and compute: (Δns / Δwall_ns) * 100 / ncpu.
        self.hzPerCore = ncpu  // scale divisor
        _ = ncpu  // keeps compiler happy if ncpu unused
    }

    /// Caller supplies the set of PIDs that matched patterns (cheap list). The scanner
    /// pulls expensive details only for those.
    func sample(matchPIDs: [Int32]) -> ScanResult {
        let now = clock()
        let all = source.listAll()
        let detail = source.fetchDetails(for: matchPIDs)
        let lastTicks = lastSample?.ticksByPid ?? [:]
        let lastDate = lastSample?.date
        let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? 0

        var tracked: [TrackedProcess] = []
        var nextTicks: [Int32: UInt64] = [:]

        let byPid = Dictionary(uniqueKeysWithValues: all.map { ($0.pid, $0) })
        for pid in matchPIDs {
            guard let raw = byPid[pid], let d = detail[pid] else { continue }
            nextTicks[pid] = d.cpuTicks
            let cpu: Double
            if elapsed > 0.05, let last = lastTicks[pid] {
                let deltaNs = Double(d.cpuTicks &- last)
                let elapsedNs = elapsed * 1_000_000_000
                cpu = max(0, min(800, (deltaNs / elapsedNs) * 100.0 / hzPerCore))
            } else {
                cpu = 0
            }
            let startDate = Date(timeIntervalSince1970: d.wallStartSeconds)
            tracked.append(TrackedProcess(
                pid: raw.pid,
                ppid: raw.ppid,
                displayName: raw.name,
                command: raw.command,
                cwd: d.cwd ?? "",
                cpuPercent: cpu,
                memoryMB: Double(d.residentBytes) / 1_048_576.0,
                ports: d.listeningPorts,
                uptimeSeconds: max(0, now.timeIntervalSince(startDate))
            ))
        }
        lastSample = (now, nextTicks)
        return ScanResult(all: all, tracked: tracked, timestamp: now)
    }
}
```

- [ ] **Step 5: Run — expect pass.**

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(task8): ProcessScanner with two-phase sampling and CPU% delta"
```

---

## Task 9: ProcessMatcher (pure filter + group)

**Files:**
- Create: `Procbar/Services/ProcessMatcher.swift`
- Create: `Procbar/Models/WorktreeGroup.swift`
- Create: `ProcbarTests/Services/ProcessMatcherTests.swift`

- [ ] **Step 1: Model.**

```swift
import Foundation

struct WorktreeGroup: Identifiable, Hashable {
    let worktree: Worktree
    let processes: [TrackedProcess]
    var id: String { worktree.path }
}
```

- [ ] **Step 2: Write the failing tests.**

```swift
import XCTest
@testable import Procbar

final class ProcessMatcherTests: XCTestCase {
    func test_matches_by_name_case_insensitive() {
        let patterns = [Config.Pattern(name: "Node", match: "node", matchField: .name)]
        let raw = [
            RawProcess(pid: 1, ppid: 0, name: "Node", command: "Node --version"),
            RawProcess(pid: 2, ppid: 0, name: "ls",   command: "ls")
        ]
        let out = ProcessMatcher.matchPIDs(patterns: patterns, raw: raw)
        XCTAssertEqual(out, [1])
    }

    func test_matches_by_command() {
        let patterns = [Config.Pattern(name: "NX", match: "nx", matchField: .command)]
        let raw = [RawProcess(pid: 1, ppid: 0, name: "node", command: "node /path/nx serve")]
        XCTAssertEqual(ProcessMatcher.matchPIDs(patterns: patterns, raw: raw), [1])
    }

    func test_groups_tracked_by_worktree_cwd() {
        let wt1 = Worktree(path: "/a", name: "a", branch: "main")
        let wt2 = Worktree(path: "/b", name: "b", branch: "feat")
        let tracked = [
            mkTracked(pid: 1, cwd: "/a/src"),
            mkTracked(pid: 2, cwd: "/b"),
            mkTracked(pid: 3, cwd: "/x")    // not in any worktree → dropped
        ]
        let groups = ProcessMatcher.group(tracked: tracked, worktrees: [wt1, wt2])
        XCTAssertEqual(groups.count, 2)
        XCTAssertEqual(groups[0].processes.map(\.pid), [1])
        XCTAssertEqual(groups[1].processes.map(\.pid), [2])
    }

    func test_respects_excluded_paths() {
        let wt = Worktree(path: "/a", name: "a", branch: nil)
        let tracked = [mkTracked(pid: 1, cwd: "/a/node_modules/x")]
        let groups = ProcessMatcher.group(
            tracked: tracked, worktrees: [wt],
            excluded: ["/a/node_modules"]
        )
        XCTAssertTrue(groups.isEmpty)
    }

    private func mkTracked(pid: Int32, cwd: String) -> TrackedProcess {
        TrackedProcess(pid: pid, ppid: 0, displayName: "x", command: "x",
                       cwd: cwd, cpuPercent: 0, memoryMB: 0, ports: [],
                       uptimeSeconds: 0)
    }
}
```

- [ ] **Step 3: Run — expect failure.**

- [ ] **Step 4: Implement `ProcessMatcher.swift`.**

```swift
import Foundation

enum ProcessMatcher {
    static func matchPIDs(patterns: [Config.Pattern], raw: [RawProcess]) -> [Int32] {
        guard !patterns.isEmpty else { return [] }
        return raw.compactMap { proc in
            let hit = patterns.contains { pat in
                let haystack = (pat.matchField == .name ? proc.name : proc.command)
                return haystack.range(of: pat.match, options: .caseInsensitive) != nil
            }
            return hit ? proc.pid : nil
        }
    }

    static func group(
        tracked: [TrackedProcess],
        worktrees: [Worktree],
        excluded: [String] = []
    ) -> [WorktreeGroup] {
        let expandedExcluded = excluded.map(PathUtils.expand)
        var buckets: [String: [TrackedProcess]] = [:]
        for proc in tracked {
            guard !proc.cwd.isEmpty else { continue }
            if expandedExcluded.contains(where: { PathUtils.isInside(child: proc.cwd, parent: $0) }) {
                continue
            }
            let match = worktrees
                .sorted { $0.path.count > $1.path.count } // deepest wins
                .first { PathUtils.isInside(child: proc.cwd, parent: $0.path) }
            if let match {
                buckets[match.path, default: []].append(proc)
            }
        }
        return worktrees.compactMap { wt in
            guard let procs = buckets[wt.path], !procs.isEmpty else { return nil }
            return WorktreeGroup(worktree: wt, processes: procs.sorted { $0.pid < $1.pid })
        }
    }
}
```

- [ ] **Step 5: Run — expect pass.**

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(task9): ProcessMatcher pure filter+group"
```

---

## Task 10: ProcessKiller (tree build + graceful kill)

**Files:**
- Create: `Procbar/Services/ProcessKiller.swift`
- Create: `ProcbarTests/Services/ProcessKillerTests.swift`

- [ ] **Step 1: Write the failing tests.**

```swift
import XCTest
@testable import Procbar

final class ProcessKillerTests: XCTestCase {
    func test_buildTree_returns_self_and_descendants() {
        let raw = [
            RawProcess(pid: 1, ppid: 0, name: "a", command: "a"),
            RawProcess(pid: 2, ppid: 1, name: "b", command: "b"),
            RawProcess(pid: 3, ppid: 2, name: "c", command: "c"),
            RawProcess(pid: 4, ppid: 0, name: "d", command: "d")
        ]
        let tree = ProcessKiller.tree(rootPID: 1, among: raw)
        XCTAssertEqual(Set(tree), Set([1, 2, 3]))
    }

    func test_buildTree_handles_cycles_safely() {
        // pathological: 1 → 2 → 1. Should still terminate.
        let raw = [
            RawProcess(pid: 1, ppid: 2, name: "a", command: "a"),
            RawProcess(pid: 2, ppid: 1, name: "b", command: "b")
        ]
        let tree = ProcessKiller.tree(rootPID: 1, among: raw)
        XCTAssertEqual(Set(tree), Set([1, 2]))
    }

    func test_kill_sends_sigterm_then_sigkill_on_timeout() throws {
        let sender = FakeKillSender(alwaysAlive: true)
        let killer = ProcessKiller(sender: sender, graceSeconds: 0.1)
        let exp = expectation(description: "done")
        killer.gracefulKill(tree: [5, 6]) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(sender.terms, [5, 6])
        XCTAssertEqual(sender.kills, [5, 6])
    }

    func test_kill_skips_sigkill_when_process_exits_early() throws {
        let sender = FakeKillSender(alwaysAlive: false)
        let killer = ProcessKiller(sender: sender, graceSeconds: 0.1)
        let exp = expectation(description: "done")
        killer.gracefulKill(tree: [5]) { exp.fulfill() }
        wait(for: [exp], timeout: 1.0)
        XCTAssertEqual(sender.terms, [5])
        XCTAssertTrue(sender.kills.isEmpty)
    }
}

final class FakeKillSender: KillSender {
    var terms: [Int32] = []
    var kills: [Int32] = []
    let alwaysAlive: Bool
    init(alwaysAlive: Bool) { self.alwaysAlive = alwaysAlive }
    func sigterm(_ pid: Int32) { terms.append(pid) }
    func sigkill(_ pid: Int32) { kills.append(pid) }
    func isAlive(_ pid: Int32) -> Bool { alwaysAlive }
}
```

- [ ] **Step 2: Run — expect failure.**

- [ ] **Step 3: Implement `ProcessKiller.swift`.**

```swift
import Foundation
import Darwin
import os

protocol KillSender {
    func sigterm(_ pid: Int32)
    func sigkill(_ pid: Int32)
    func isAlive(_ pid: Int32) -> Bool
}

final class SystemKillSender: KillSender {
    func sigterm(_ pid: Int32) { _ = kill(pid, SIGTERM) }
    func sigkill(_ pid: Int32) { _ = kill(pid, SIGKILL) }
    func isAlive(_ pid: Int32) -> Bool { kill(pid, 0) == 0 || errno != ESRCH }
}

final class ProcessKiller {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "kill")
    private let sender: KillSender
    private let graceSeconds: Double
    private let queue = DispatchQueue(label: "com.carlos.procbar.kill")

    init(sender: KillSender = SystemKillSender(), graceSeconds: Double = 3.0) {
        self.sender = sender
        self.graceSeconds = graceSeconds
    }

    static func tree(rootPID: Int32, among raw: [RawProcess]) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for p in raw { children[p.ppid, default: []].append(p.pid) }
        var out: [Int32] = []
        var seen: Set<Int32> = []
        var stack: [Int32] = [rootPID]
        while let top = stack.popLast() {
            if seen.insert(top).inserted {
                out.append(top)
                stack.append(contentsOf: children[top] ?? [])
            }
        }
        return out
    }

    /// Sends SIGTERM to every PID, waits `graceSeconds`, then SIGKILL to survivors.
    /// Completion is called on the internal queue when the sequence finishes.
    func gracefulKill(tree pids: [Int32], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for pid in pids { self.sender.sigterm(pid) }
            let deadline = DispatchTime.now() + self.graceSeconds
            let pollInterval: Double = 0.1
            var allGone = false
            while DispatchTime.now() < deadline {
                if pids.allSatisfy({ !self.sender.isAlive($0) }) { allGone = true; break }
                Thread.sleep(forTimeInterval: pollInterval)
            }
            if !allGone {
                for pid in pids where self.sender.isAlive(pid) {
                    self.sender.sigkill(pid)
                }
            }
            completion?()
        }
    }

    /// Immediate escalation (used for second-click fast path).
    func forceKill(tree pids: [Int32], completion: (() -> Void)? = nil) {
        queue.async { [weak self] in
            guard let self else { return }
            for pid in pids { self.sender.sigkill(pid) }
            completion?()
        }
    }
}
```

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task10): ProcessKiller with tree-building and graceful→force escalation"
```

---

## Task 11: AppViewModel (timer + published state)

**Files:**
- Create: `Procbar/ViewModels/AppViewModel.swift`
- Create: `ProcbarTests/ViewModels/AppViewModelTests.swift`

- [ ] **Step 1: Write the failing test.**

```swift
import XCTest
import Combine
@testable import Procbar

final class AppViewModelTests: XCTestCase {
    func test_tick_populates_groups_from_matcher_output() {
        let source = FakeProcessSource()
        source.raw = [RawProcess(pid: 1, ppid: 0, name: "node", command: "node /wt/a/index.js")]
        source.detailsByPid = [1: ProcessDetail(
            pid: 1, cwd: "/wt/a",
            residentBytes: 2_000_000, cpuTicks: 1_000,
            wallStartSeconds: Date().timeIntervalSince1970 - 60,
            listeningPorts: [3000]
        )]
        let scanner = ProcessScanner(source: source)
        let wt = [Worktree(path: "/wt/a", name: "a", branch: "main")]
        let cfg = Config(
            worktreeRoots: ["/wt"],
            processPatterns: [.init(name: "Node", match: "node", matchField: .name)]
        )
        let vm = AppViewModel(scanner: scanner, worktreesProvider: { wt }, configProvider: { cfg })
        vm.tickOnce()
        XCTAssertEqual(vm.groups.count, 1)
        XCTAssertEqual(vm.groups.first?.processes.map(\.pid), [1])
        XCTAssertTrue(vm.isActive)
    }
}
```

- [ ] **Step 2: Run — expect compile failure.**

- [ ] **Step 3: Implement `AppViewModel.swift`.**

```swift
import Foundation
import Combine
import SwiftUI
import os

@MainActor
final class AppViewModel: ObservableObject {
    private let logger = Logger(subsystem: "com.carlos.procbar", category: "ui")

    @Published private(set) var groups: [WorktreeGroup] = []
    @Published private(set) var isActive: Bool = false
    @Published var configError: String?

    private let scanner: ProcessScanner
    private let worktreesProvider: () -> [Worktree]
    private let configProvider: () -> Config
    private var timer: Timer?
    private let scanQueue = DispatchQueue(label: "com.carlos.procbar.scan", qos: .userInitiated)

    init(scanner: ProcessScanner,
         worktreesProvider: @escaping () -> [Worktree],
         configProvider: @escaping () -> Config) {
        self.scanner = scanner
        self.worktreesProvider = worktreesProvider
        self.configProvider = configProvider
    }

    func start() {
        stop()
        let interval = TimeInterval(configProvider().refreshIntervalSeconds)
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.scheduleTick()
        }
        scheduleTick()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func scheduleTick() {
        scanQueue.async { [weak self] in
            guard let self else { return }
            Task { @MainActor in self.tickOnce() }
        }
    }

    func tickOnce() {
        let cfg = configProvider()
        let wts = worktreesProvider()
        let rawAll = scanner.sample(matchPIDs: []).all
        let matched = ProcessMatcher.matchPIDs(patterns: cfg.processPatterns, raw: rawAll)
        let result = scanner.sample(matchPIDs: matched)
        let grouped = ProcessMatcher.group(
            tracked: result.tracked,
            worktrees: wts,
            excluded: cfg.excludedPaths
        )
        self.groups = grouped
        self.isActive = !grouped.isEmpty
    }
}
```

> Note: `tickOnce()` calls `scanner.sample(matchPIDs: [])` purely to grab `.all` cheaply — the CPU% delta is computed on the *second* call with the real PID set. For v1 this is acceptable; if scans get expensive, split `ProcessScanner.listRaw()` out.

- [ ] **Step 4: Run — expect pass.**

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task11): AppViewModel polling + grouped state publishing"
```

---

## Task 12: Menu bar icon artwork

**Files:**
- Create: `Procbar/Resources/Assets.xcassets/Contents.json`
- Create: `Procbar/Resources/Assets.xcassets/MenuBarIcon.imageset/Contents.json`
- Create: `Procbar/Resources/Assets.xcassets/MenuBarIcon.imageset/menu-bar.pdf` (or .svg → compiled)

- [ ] **Step 1: Generate the vector artwork.**

Create `Procbar/Resources/menu-bar.svg`:

```xml
<svg width="18" height="18" viewBox="0 0 18 18" xmlns="http://www.w3.org/2000/svg">
  <rect x="2" y="4"  width="11" height="2" rx="1" fill="black"/>
  <rect x="2" y="8"  width="7"  height="2" rx="1" fill="black"/>
  <rect x="2" y="12" width="9"  height="2" rx="1" fill="black"/>
</svg>
```

Convert to PDF (Xcode needs PDF for template images):
```bash
# rsvg-convert is in librsvg; install via: brew install librsvg
rsvg-convert -f pdf -o Procbar/Resources/Assets.xcassets/MenuBarIcon.imageset/menu-bar.pdf Procbar/Resources/menu-bar.svg
```

If rsvg isn't available, open `menu-bar.svg` in Preview.app → Export as PDF.

- [ ] **Step 2: Write `Assets.xcassets/Contents.json`.**

```json
{ "info" : { "author" : "xcode", "version" : 1 } }
```

- [ ] **Step 3: Write `MenuBarIcon.imageset/Contents.json`.**

```json
{
  "images" : [
    { "filename" : "menu-bar.pdf", "idiom" : "universal" }
  ],
  "info" : { "author" : "xcode", "version" : 1 },
  "properties" : { "template-rendering-intent" : "template", "preserves-vector-representation" : true }
}
```

- [ ] **Step 4: Update `ProcbarApp.swift` to use the asset.**

```swift
MenuBarExtra {
    MenuBarContentView()        // built in next task
} label: {
    Image("MenuBarIcon")
        .renderingMode(.template)
}
.menuBarExtraStyle(.window)
```

- [ ] **Step 5: Regenerate project and build.**

```bash
xcodegen generate
xcodebuild -scheme Procbar -configuration Debug build && open build/Debug/Procbar.app
```
Expected: the three-bar equalizer glyph appears in the menu bar, adopting system light/dark correctly.

- [ ] **Step 6: Commit.**

```bash
git add -A
git commit -m "feat(task12): menu bar template icon (three-bar instrument glyph)"
```

---

## Task 13: MenuBarContentView (popover shell)

**Files:**
- Create: `Procbar/Views/MenuBarContentView.swift`
- Create: `Procbar/Views/HeaderView.swift`
- Create: `Procbar/Views/FooterView.swift`
- Create: `Procbar/Views/HairlineDivider.swift`

- [ ] **Step 1: Write `HairlineDivider.swift`.**

```swift
import SwiftUI

struct HairlineDivider: View {
    var body: some View {
        Rectangle()
            .fill(DesignSystem.Color.hairline.swiftUI)
            .frame(height: DesignSystem.Spacing.hairline)
    }
}
```

- [ ] **Step 2: Write `HeaderView.swift`.**

```swift
import SwiftUI

struct HeaderView: View {
    let processCount: Int
    let worktreeCount: Int

    var body: some View {
        HStack(spacing: 8) {
            Image("MenuBarIcon")
                .renderingMode(.template)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                .frame(width: 14, height: 14)
            Text("Procbar")
                .font(DesignSystem.Typography.header)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            Spacer()
            Text("\(processCount) PROC · \(worktreeCount) WT")
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
        }
        .frame(height: DesignSystem.Spacing.headerHeight)
    }
}
```

- [ ] **Step 3: Write `FooterView.swift`.**

```swift
import SwiftUI

struct FooterView: View {
    let openPreferences: () -> Void
    let openConfigFile: () -> Void
    let quit: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            FooterButton(title: "PREFERENCES", action: openPreferences)
            FooterButton(title: "OPEN CONFIG", action: openConfigFile)
            FooterButton(title: "QUIT", action: quit)
            Spacer()
        }
        .frame(height: DesignSystem.Spacing.footerHeight)
    }
}

private struct FooterButton: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(
                    hovering
                    ? DesignSystem.Color.textPrimary.swiftUI
                    : DesignSystem.Color.textSecondary.swiftUI
                )
                .underline(hovering, color: DesignSystem.Color.textPrimary.swiftUI)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
```

- [ ] **Step 4: Write `MenuBarContentView.swift`.**

```swift
import SwiftUI

struct MenuBarContentView: View {
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var appContext: AppContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HeaderView(
                processCount: vm.groups.reduce(0) { $0 + $1.processes.count },
                worktreeCount: vm.groups.count
            )
            HairlineDivider().padding(.bottom, 6)

            if let err = vm.configError {
                ConfigErrorPill(message: err) { appContext.openSettings() }
                    .padding(.bottom, 6)
            }

            if vm.groups.isEmpty {
                EmptyStateView(
                    title: "All quiet.",
                    actionTitle: nil,
                    action: nil
                )
                .frame(maxWidth: .infinity)
                .padding(.vertical, 20)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: DesignSystem.Spacing.sectionGap) {
                        ForEach(vm.groups) { group in
                            WorktreeSectionView(group: group)
                        }
                    }
                    .padding(.bottom, 6)
                }
                .frame(maxHeight: 480)
            }

            HairlineDivider().padding(.top, 4)
            FooterView(
                openPreferences: { appContext.openSettings() },
                openConfigFile:  { appContext.openConfigFile() },
                quit:            { NSApplication.shared.terminate(nil) }
            )
        }
        .padding(.horizontal, DesignSystem.Spacing.outerHorizontal)
        .padding(.vertical, DesignSystem.Spacing.outerVertical)
        .frame(width: DesignSystem.Spacing.popoverWidth)
        .background(DesignSystem.Color.background.swiftUI)
    }
}

struct ConfigErrorPill: View {
    let message: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text("CONFIG ERROR — \(message.uppercased())")
                .font(DesignSystem.Typography.microLabel)
                .tracking(0.8)
                .foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(DesignSystem.Color.warning.swiftUI)
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct EmptyStateView: View {
    let title: String
    let actionTitle: String?
    let action: (() -> Void)?

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.textSecondary.swiftUI)
            if let actionTitle, let action {
                Button(action: action) {
                    Text(actionTitle)
                        .font(DesignSystem.Typography.bodyRegular)
                        .foregroundStyle(DesignSystem.Color.accent.swiftUI)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

- [ ] **Step 5: Add `AppContext.swift` to wire environment.**

`Procbar/ViewModels/AppContext.swift`:

```swift
import Foundation
import AppKit
import SwiftUI

@MainActor
final class AppContext: ObservableObject {
    let configPath: URL

    init(configPath: URL) { self.configPath = configPath }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func openConfigFile() {
        NSWorkspace.shared.open(configPath)
    }
}
```

- [ ] **Step 6: Commit (UI still calls into empty-state path; next task adds sections).**

```bash
git add -A
git commit -m "feat(task13): popover shell (header, footer, empty state, hairlines)"
```

---

## Task 14: WorktreeSectionView

**Files:**
- Create: `Procbar/Views/WorktreeSectionView.swift`
- Create: `Procbar/Views/CountBadge.swift`

- [ ] **Step 1: Write `CountBadge.swift`.**

```swift
import SwiftUI

struct CountBadge: View {
    let value: Int
    var body: some View {
        Text("\(value)")
            .font(DesignSystem.Typography.badgeValue)
            .foregroundStyle(DesignSystem.Color.accent.swiftUI)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(DesignSystem.Color.accent.swiftUI.opacity(0.15))
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 2: Write `WorktreeSectionView.swift`.**

```swift
import SwiftUI

struct WorktreeSectionView: View {
    let group: WorktreeGroup
    @State private var expanded = true

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: { withAnimation(DesignSystem.Motion.section.animation) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                    Text(group.worktree.name)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
                    if let branch = group.worktree.branch {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 9))
                            .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                        Text(branch)
                            .font(DesignSystem.Typography.branch)
                            .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                    }
                    Spacer()
                    CountBadge(value: group.processes.count)
                }
                .frame(height: DesignSystem.Spacing.sectionHeaderHeight)
            }
            .buttonStyle(.plain)

            HairlineDivider()

            if expanded {
                VStack(spacing: 0) {
                    ForEach(Array(group.processes.enumerated()), id: \.element.id) { idx, proc in
                        ProcessRowView(process: proc)
                            .transition(
                                .asymmetric(
                                    insertion: .opacity.combined(with: .offset(y: 4)),
                                    removal: .opacity
                                )
                            )
                            .animation(
                                DesignSystem.Motion.rowAppear.animation
                                    .delay(Double(idx) * DesignSystem.Motion.rowStaggerMs / 1000.0),
                                value: proc.pid
                            )
                    }
                }
            }
        }
    }
}
```

- [ ] **Step 3: Commit.**

```bash
git add -A
git commit -m "feat(task14): WorktreeSectionView with collapsible group and count badge"
```

---

## Task 15: ProcessRowView + CPU meter + Stop button

**Files:**
- Create: `Procbar/Views/ProcessRowView.swift`
- Create: `Procbar/Views/CPUBar.swift`
- Create: `Procbar/Views/StopButton.swift`

- [ ] **Step 1: Write `CPUBar.swift`.**

```swift
import SwiftUI

struct CPUBar: View {
    let percent: Double          // 0..100+

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(DesignSystem.Color.hairline.swiftUI)
                Rectangle()
                    .fill(tint)
                    .frame(width: geo.size.width * CGFloat(min(percent, 100) / 100))
                    .animation(DesignSystem.Motion.cpuBar.animation, value: percent)
            }
        }
        .frame(width: DesignSystem.Spacing.cpuBarWidth,
               height: DesignSystem.Spacing.cpuBarHeight)
        .clipShape(RoundedRectangle(cornerRadius: 1))
    }

    private var tint: Color {
        percent >= 80
            ? DesignSystem.Color.warning.swiftUI
            : DesignSystem.Color.accent.swiftUI
    }
}
```

- [ ] **Step 2: Write `StopButton.swift`.**

```swift
import SwiftUI

enum StopState { case idle, terminating, killing, done }

struct StopButton: View {
    let state: StopState
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(
                        borderColor,
                        lineWidth: state == .terminating ? 1.5 : 1
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(fillColor)
                    )
                if state == .terminating {
                    Circle()
                        .trim(from: 0, to: 1)
                        .rotation(.degrees(-90))
                        .stroke(
                            DesignSystem.Color.accent.swiftUI,
                            style: StrokeStyle(lineWidth: 1.5, lineCap: .round)
                        )
                        .frame(width: 18, height: 18)
                        .opacity(0.8)
                }
                Text(glyph)
                    .font(.system(size: 11, weight: .semibold, design: .default))
                    .foregroundStyle(glyphColor)
            }
            .frame(
                width: DesignSystem.Spacing.stopButtonSize,
                height: DesignSystem.Spacing.stopButtonSize
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var glyph: String {
        switch state {
        case .idle:        return "⏻"
        case .terminating: return "◻︎"
        case .killing:     return "✕"
        case .done:        return "✓"
        }
    }

    private var borderColor: Color {
        switch state {
        case .killing: return DesignSystem.Color.warning.swiftUI
        case .done:    return DesignSystem.Color.success.swiftUI
        default:       return DesignSystem.Color.hairline.swiftUI
        }
    }

    private var fillColor: Color {
        switch state {
        case .killing: return DesignSystem.Color.warning.swiftUI
        case .done:    return DesignSystem.Color.success.swiftUI.opacity(0.2)
        default:       return hovering ? DesignSystem.Color.warning.swiftUI : .clear
        }
    }

    private var glyphColor: Color {
        switch state {
        case .killing:       return .white
        default:             return hovering
            ? .white
            : DesignSystem.Color.textSecondary.swiftUI
        }
    }
}
```

- [ ] **Step 3: Write `ProcessRowView.swift`.**

```swift
import SwiftUI

struct ProcessRowView: View {
    let process: TrackedProcess
    @EnvironmentObject var vm: AppViewModel
    @EnvironmentObject var killCoordinator: KillCoordinator
    @State private var stopState: StopState = .idle

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            identityZone
            meterZone
            resourceZone
            Spacer(minLength: 4)
            actionZone
        }
        .frame(height: DesignSystem.Spacing.rowHeight)
        .contentShape(Rectangle())
    }

    private var identityZone: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(process.displayName.uppercased())
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            Text("PID \(process.pid)")
                .font(DesignSystem.Typography.pidSubtitle)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
        }
        .frame(width: 140, alignment: .leading)
    }

    private var meterZone: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(String(format: "%.0f%%", process.cpuPercent))
                .font(DesignSystem.Typography.numeric)
                .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            CPUBar(percent: process.cpuPercent)
        }
        .frame(width: 80, alignment: .leading)
    }

    private var resourceZone: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text("MEM").font(DesignSystem.Typography.microLabel)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(formatMem(process.memoryMB))
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            }
            HStack(spacing: 4) {
                Text("PORT").font(DesignSystem.Typography.microLabel)
                    .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
                Text(process.ports.isEmpty ? "—" : ":\(process.ports[0])")
                    .font(DesignSystem.Typography.numeric)
                    .foregroundStyle(DesignSystem.Color.textPrimary.swiftUI)
            }
        }
        .frame(width: 90, alignment: .leading)
    }

    private var actionZone: some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text(formatUptime(process.uptimeSeconds))
                .font(DesignSystem.Typography.pidSubtitle)
                .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
            StopButton(state: stopState) {
                if stopState == .terminating {
                    killCoordinator.forceKill(process: process)
                    stopState = .killing
                } else {
                    killCoordinator.gracefulKill(process: process) { gone in
                        stopState = gone ? .done : .killing
                    }
                    stopState = .terminating
                }
            }
        }
    }

    private func formatMem(_ mb: Double) -> String {
        mb < 1024 ? String(format: "%.0f MB", mb) : String(format: "%.2f GB", mb / 1024)
    }

    private func formatUptime(_ s: TimeInterval) -> String {
        let i = Int(s)
        if i < 60 { return "\(i)s" }
        if i < 3_600 { return "\(i / 60)m" }
        if i < 86_400 { return "\(i / 3600)h" }
        return "\(i / 86_400)d"
    }
}
```

- [ ] **Step 4: Add `KillCoordinator.swift`.**

`Procbar/ViewModels/KillCoordinator.swift`:

```swift
import Foundation
import SwiftUI

@MainActor
final class KillCoordinator: ObservableObject {
    private let killer: ProcessKiller
    private let sourceFactory: () -> [RawProcess]

    init(killer: ProcessKiller, sourceFactory: @escaping () -> [RawProcess]) {
        self.killer = killer
        self.sourceFactory = sourceFactory
    }

    func gracefulKill(process: TrackedProcess, completion: @escaping (Bool) -> Void) {
        let tree = ProcessKiller.tree(rootPID: process.pid, among: sourceFactory())
        killer.gracefulKill(tree: tree) {
            DispatchQueue.main.async {
                completion(true)
            }
        }
    }

    func forceKill(process: TrackedProcess) {
        let tree = ProcessKiller.tree(rootPID: process.pid, among: sourceFactory())
        killer.forceKill(tree: tree)
    }
}
```

- [ ] **Step 5: Commit.**

```bash
git add -A
git commit -m "feat(task15): ProcessRowView + CPU bar + Stop button state machine"
```

---

## Task 16: SettingsView (preferences form)

**Files:**
- Create: `Procbar/Views/SettingsView.swift`

- [ ] **Step 1: Implement.**

```swift
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appContext: AppContext
    @State private var cfg: Config = .defaultConfig()
    @State private var loadError: String?

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            rootsTab.tabItem { Label("Worktrees", systemImage: "folder") }
            patternsTab.tabItem { Label("Patterns", systemImage: "text.magnifyingglass") }
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear(perform: load)
    }

    private var generalTab: some View {
        Form {
            Stepper(value: $cfg.refreshIntervalSeconds, in: 1...30) {
                Text("Refresh interval: \(cfg.refreshIntervalSeconds) s")
            }
            Toggle("Show git branch in section headers", isOn: $cfg.showBranch)
            Toggle("Launch at login", isOn: $cfg.launchAtLogin)
                .onChange(of: cfg.launchAtLogin) { newValue in
                    LoginItem.setEnabled(newValue)
                    save()
                }
            Button("Open config file…") { appContext.openConfigFile() }
            if let err = loadError {
                Text(err)
                    .font(DesignSystem.Typography.bodyRegular)
                    .foregroundStyle(DesignSystem.Color.warning.swiftUI)
            }
        }
        .onChange(of: cfg.refreshIntervalSeconds) { _ in save() }
        .onChange(of: cfg.showBranch) { _ in save() }
    }

    private var rootsTab: some View {
        VStack(alignment: .leading) {
            Text("Worktree roots").font(DesignSystem.Typography.header)
            EditableListView(items: $cfg.worktreeRoots, placeholder: "~/Documents")
                .onChange(of: cfg.worktreeRoots) { _ in save() }
            Text("Excluded paths").font(DesignSystem.Typography.header).padding(.top, 12)
            EditableListView(items: $cfg.excludedPaths, placeholder: "~/Documents/archive")
                .onChange(of: cfg.excludedPaths) { _ in save() }
        }
    }

    private var patternsTab: some View {
        VStack(alignment: .leading) {
            Text("Process patterns").font(DesignSystem.Typography.header)
            Text("A process is tracked if its name or full command matches any pattern (case-insensitive substring).")
                .font(DesignSystem.Typography.bodyRegular)
                .foregroundStyle(DesignSystem.Color.textSecondary.swiftUI)
            PatternListView(patterns: $cfg.processPatterns)
                .onChange(of: cfg.processPatterns) { _ in save() }
        }
    }

    private func load() {
        do {
            let store = ConfigStore(path: appContext.configPath)
            cfg = try store.loadOrCreateDefault()
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func save() {
        do {
            try ConfigStore(path: appContext.configPath).save(cfg)
            loadError = nil
        } catch {
            loadError = error.localizedDescription
        }
    }
}

private struct EditableListView: View {
    @Binding var items: [String]
    let placeholder: String

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(items.indices, id: \.self) { i in
                HStack {
                    TextField(placeholder, text: $items[i])
                        .textFieldStyle(.roundedBorder)
                    Button(role: .destructive) { items.remove(at: i) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain)
                }
            }
            Button("+ Add") { items.append("") }
                .buttonStyle(.plain)
                .foregroundStyle(DesignSystem.Color.accent.swiftUI)
        }
    }
}

private struct PatternListView: View {
    @Binding var patterns: [Config.Pattern]

    var body: some View {
        VStack(alignment: .leading) {
            ForEach(patterns.indices, id: \.self) { i in
                HStack {
                    TextField("Display name", text: $patterns[i].name).frame(width: 120)
                    TextField("Match substring", text: $patterns[i].match).frame(width: 160)
                    Picker("", selection: $patterns[i].matchField) {
                        Text("command").tag(Config.MatchField.command)
                        Text("name").tag(Config.MatchField.name)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 140)
                    Button(role: .destructive) { patterns.remove(at: i) } label: {
                        Image(systemName: "minus.circle")
                    }.buttonStyle(.plain)
                }
            }
            Button("+ Add pattern") {
                patterns.append(.init(name: "", match: "", matchField: .command))
            }
            .buttonStyle(.plain)
            .foregroundStyle(DesignSystem.Color.accent.swiftUI)
        }
    }
}
```

- [ ] **Step 2: Commit.**

```bash
git add -A
git commit -m "feat(task16): SettingsView (general/worktrees/patterns tabs)"
```

---

## Task 17: First-run + config error handling + wiring

**Files:**
- Modify: `Procbar/ProcbarApp.swift`

- [ ] **Step 1: Rewrite `ProcbarApp.swift` to wire everything together.**

```swift
import SwiftUI
import Combine

@main
struct ProcbarApp: App {
    @StateObject private var vm: AppViewModel
    @StateObject private var appContext: AppContext
    @StateObject private var killCoordinator: KillCoordinator

    private let configStore: ConfigStore
    private let worktreeScanner = WorktreeScanner(branchReader: LiveGitBranchReader())
    private let processScanner: ProcessScanner
    private let processSource = LibprocSource()
    private var cancellables = Set<AnyCancellable>()

    init() {
        let path = ConfigStore.defaultPath
        let store = ConfigStore(path: path)
        self.configStore = store

        // Bootstrap config or surface error to UI.
        var initialCfg = Config.defaultConfig()
        var initialError: String?
        do {
            initialCfg = try store.loadOrCreateDefault()
        } catch {
            initialError = error.localizedDescription
        }

        let scanner = ProcessScanner(source: processSource)
        self.processScanner = scanner

        let ctx = AppContext(configPath: path)

        let killer = ProcessKiller(sender: SystemKillSender())
        let source = processSource
        let coord = KillCoordinator(killer: killer, sourceFactory: { source.listAll() })

        let worktreesProvider: () -> [Worktree] = { [worktreeScanner] in
            worktreeScanner.scan(
                roots: store.current.worktreeRoots,
                excluded: store.current.excludedPaths
            )
        }
        let configProvider: () -> Config = { store.current }

        let viewModel = AppViewModel(
            scanner: scanner,
            worktreesProvider: worktreesProvider,
            configProvider: configProvider
        )
        viewModel.configError = initialError

        _vm = StateObject(wrappedValue: viewModel)
        _appContext = StateObject(wrappedValue: ctx)
        _killCoordinator = StateObject(wrappedValue: coord)

        store.startWatching()
        // Wire reloads (timer cadence might need to change on config change).
        store.changes
            .receive(on: RunLoop.main)
            .sink { _ in
                viewModel.stop()
                viewModel.start()
            }
            .store(in: &cancellables)

        viewModel.start()
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarContentView()
                .environmentObject(vm)
                .environmentObject(appContext)
                .environmentObject(killCoordinator)
        } label: {
            Image("MenuBarIcon").renderingMode(.template)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environmentObject(appContext)
        }
    }
}
```

- [ ] **Step 2: Build and run.**

```bash
xcodegen generate
xcodebuild -scheme Procbar -configuration Debug build && open build/Debug/Procbar.app
```
Expected: menu bar icon appears. First run creates `~/.config/procbar/config.yaml`. Popover shows "All quiet." if no patterns match. Editing the YAML externally causes the popover to reflect changes within ~2 s.

- [ ] **Step 3: Commit.**

```bash
git add -A
git commit -m "feat(task17): wire app (config bootstrap, live reload, coordinator, menu bar)"
```

---

## Task 18: Launch at login (SMAppService)

**Files:**
- Create: `Procbar/Utilities/LoginItem.swift`

- [ ] **Step 1: Implement.**

```swift
import Foundation
import ServiceManagement
import os

enum LoginItem {
    private static let logger = Logger(subsystem: "com.carlos.procbar", category: "ui")

    static func setEnabled(_ enabled: Bool) {
        guard #available(macOS 13.0, *) else { return }
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else {
                if SMAppService.mainApp.status == .enabled {
                    try SMAppService.mainApp.unregister()
                }
            }
        } catch {
            logger.error("Login item toggle failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    static var isEnabled: Bool {
        guard #available(macOS 13.0, *) else { return false }
        return SMAppService.mainApp.status == .enabled
    }
}
```

- [ ] **Step 2: Commit.**

```bash
git add -A
git commit -m "feat(task18): Launch at login via SMAppService"
```

---

## Task 19: Manual smoke test + developer notes

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Expand README with smoke test checklist.**

Append to `README.md`:

```markdown
## Smoke test (manual, before each release)

1. Delete `~/.config/procbar/config.yaml` if present.
2. `xcodegen generate && open build/Debug/Procbar.app` — expect menu bar icon, no dock icon.
3. First run: config file created, popover says "All quiet." when no processes match.
4. In another terminal, from a worktree under `~/Documents`, run `npx vite preview` (or any node server). Within 2 s it appears under the correct worktree with branch name.
5. CPU bar animates as the server loads.
6. Click Stop: SIGTERM fires, arc animates, row disappears before 3 s.
7. Start a zombie-spawning process; Stop should clean up children (verify with `ps`).
8. Edit config externally (`echo "refresh_interval_seconds: 5" >> ~/.config/procbar/config.yaml`), popover reloads within 2 s.
9. Toggle "Launch at login" in Settings; verify with `launchctl list | grep com.carlos.procbar`.
10. Quit from the footer; `ps aux | grep Procbar` shows none.

## Troubleshooting

- **Icon missing from menu bar:** confirm `LSUIElement` is `true` in Info.plist and the Assets catalog compiled (check `build/Debug/Procbar.app/Contents/Resources/Assets.car`).
- **Branch names missing:** `/usr/bin/env git` must be resolvable in the app's PATH. For sandboxed installs you may need to set PATH in `Info.plist`.
- **Ports never show:** macOS 14+ may gate `proc_pidfdinfo` with `PROC_PIDFDSOCKETINFO` behind entitlements — check Console.app for denied syscalls and add `com.apple.security.get-task-allow` if needed during development.
```

- [ ] **Step 2: Commit.**

```bash
git add -A
git commit -m "docs(task19): smoke test checklist and troubleshooting notes"
```

---

## Task 20: Activity state (dot + idle time)

**Why this is its own task:** this feature touches the scanner, models, view-model, and one view. The base plan was written before this feature was added to the spec. Task 20 captures the additions as a cohesive patch that can be reviewed together.

**Files:**
- Modify: `Procbar/Models/Config.swift` (add `ActivityConfig`)
- Modify: `Procbar/Models/TrackedProcess.swift` (add `activity` and `idleSeconds`)
- Modify: `Procbar/Services/ProcessScanner.swift` (maintain `lastActiveAt`; compute state)
- Modify: `Procbar/DesignSystem/Color+DesignSystem.swift` (add `idleDot` pair)
- Create: `Procbar/Views/ActivityDot.swift`
- Modify: `Procbar/Views/ProcessRowView.swift` (dot + idle swap)
- Modify: `ProcbarTests/Models/ConfigTests.swift` (activity defaults + parsing)
- Modify: `ProcbarTests/Services/ProcessScannerTests.swift` (activity transitions)

- [ ] **Step 1: Extend `Config.swift`.**

Add nested type:

```swift
extension Config {
    struct ActivityConfig: Codable, Equatable {
        var activeThresholdPercent: Double
        var recentWindowMinutes: Int

        enum CodingKeys: String, CodingKey {
            case activeThresholdPercent = "active_threshold_percent"
            case recentWindowMinutes    = "recent_window_minutes"
        }

        init(activeThresholdPercent: Double = 1.0, recentWindowMinutes: Int = 5) {
            self.activeThresholdPercent = max(0, activeThresholdPercent)
            self.recentWindowMinutes    = max(1, min(240, recentWindowMinutes))
        }
    }
}
```

Add stored property on `Config` and include in `CodingKeys` + `init(from:)` + `defaultConfig()`:

```swift
var activity: ActivityConfig
// CodingKeys:
case activity
// init:
let activity = (try? c.decode(ActivityConfig.self, forKey: .activity)) ?? ActivityConfig()
// defaultConfig():
activity: ActivityConfig(),
```

Also update the main `init(refreshIntervalSeconds:...)` signature to accept `activity: ActivityConfig = ActivityConfig()`.

- [ ] **Step 2: Extend `TrackedProcess.swift`.**

```swift
enum ActivityState: String, Equatable {
    case activeNow
    case recentlyActive
    case idle
}

struct TrackedProcess: Identifiable, Hashable {
    let pid: Int32
    let ppid: Int32
    let displayName: String
    let command: String
    let cwd: String
    let cpuPercent: Double
    let memoryMB: Double
    let ports: [UInt16]
    let uptimeSeconds: TimeInterval
    let activity: ActivityState
    let idleSeconds: TimeInterval?  // nil when activity != .idle
    var id: Int32 { pid }
}
```

- [ ] **Step 3: Extend `ProcessScanner.swift`.**

```swift
final class ProcessScanner {
    // existing:
    private var lastSample: (date: Date, ticksByPid: [Int32: UInt64])?
    // new:
    private var lastActiveAt: [Int32: Date] = [:]

    // Add to init():
    // (unchanged signature)

    /// Pass the activity config alongside matchPIDs so thresholds can be reconfigured
    /// live without restarting the scanner.
    func sample(matchPIDs: [Int32], activity: Config.ActivityConfig = .init()) -> ScanResult {
        let now = clock()
        let all = source.listAll()
        let detail = source.fetchDetails(for: matchPIDs)
        let lastTicks = lastSample?.ticksByPid ?? [:]
        let lastDate = lastSample?.date
        let elapsed = lastDate.map { now.timeIntervalSince($0) } ?? 0

        var tracked: [TrackedProcess] = []
        var nextTicks: [Int32: UInt64] = [:]

        let byPid = Dictionary(uniqueKeysWithValues: all.map { ($0.pid, $0) })
        let recentWindow = TimeInterval(activity.recentWindowMinutes * 60)

        for pid in matchPIDs {
            guard let raw = byPid[pid], let d = detail[pid] else { continue }
            nextTicks[pid] = d.cpuTicks
            let cpu: Double
            if elapsed > 0.05, let last = lastTicks[pid] {
                let deltaNs   = Double(d.cpuTicks &- last)
                let elapsedNs = elapsed * 1_000_000_000
                let ncpu      = Double(ProcessInfo.processInfo.activeProcessorCount)
                cpu = max(0, min(800, (deltaNs / elapsedNs) * 100.0 / ncpu))
            } else {
                cpu = 0
            }

            // Activity resolution
            let threshold = activity.activeThresholdPercent
            if cpu > threshold {
                lastActiveAt[pid] = now
            } else if lastActiveAt[pid] == nil {
                // first time seeing this PID — seed as active
                lastActiveAt[pid] = now
            }
            let since = now.timeIntervalSince(lastActiveAt[pid]!)
            let state: ActivityState
            let idle: TimeInterval?
            if cpu > threshold {
                state = .activeNow; idle = nil
            } else if since < recentWindow {
                state = .recentlyActive; idle = nil
            } else {
                state = .idle; idle = since
            }

            let startDate = Date(timeIntervalSince1970: d.wallStartSeconds)
            tracked.append(TrackedProcess(
                pid: raw.pid,
                ppid: raw.ppid,
                displayName: raw.name,
                command: raw.command,
                cwd: d.cwd ?? "",
                cpuPercent: cpu,
                memoryMB: Double(d.residentBytes) / 1_048_576.0,
                ports: d.listeningPorts,
                uptimeSeconds: max(0, now.timeIntervalSince(startDate)),
                activity: state,
                idleSeconds: idle
            ))
        }

        // Evict entries for PIDs that no longer appear in the full listing.
        let alivePIDs = Set(all.map { $0.pid })
        lastActiveAt = lastActiveAt.filter { alivePIDs.contains($0.key) }

        lastSample = (now, nextTicks)
        return ScanResult(all: all, tracked: tracked, timestamp: now)
    }
}
```

Remove the original `hzPerCore` helper — replaced with inline `ncpu` above.

Note: `AppViewModel.tickOnce()` must pass the activity config. Update:

```swift
let result = scanner.sample(matchPIDs: matched, activity: cfg.activity)
```

- [ ] **Step 4: Add idle-dot color.**

In `Color+DesignSystem.swift`:

```swift
static let idleDot = ColorPair(
    light: NSColor(hex: 0x9A9AA0),
    dark:  NSColor(hex: 0x5C5C65)
)
```

- [ ] **Step 5: Create `ActivityDot.swift`.**

```swift
import SwiftUI

struct ActivityDot: View {
    let state: ActivityState
    @State private var bumped = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 5, height: 5)
            .scaleEffect(bumped ? 1.3 : 1.0)
            .animation(.spring(response: 0.18, dampingFraction: 0.65), value: bumped)
            .onChange(of: state) { newValue in
                if newValue == .activeNow {
                    bumped = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { bumped = false }
                }
            }
    }

    private var color: Color {
        switch state {
        case .activeNow:       return DesignSystem.Color.success.swiftUI
        case .recentlyActive:  return DesignSystem.Color.accent.swiftUI
        case .idle:            return DesignSystem.Color.idleDot.swiftUI
        }
    }
}
```

- [ ] **Step 6: Update `ProcessRowView.swift`.**

Replace `identityZone` and `actionZone` with:

```swift
private var identityZone: some View {
    VStack(alignment: .leading, spacing: 1) {
        HStack(spacing: 6) {
            ActivityDot(state: process.activity)
            Text(process.displayName.uppercased())
                .font(DesignSystem.Typography.body)
                .foregroundStyle(nameColor)
        }
        Text("PID \(process.pid)")
            .font(DesignSystem.Typography.pidSubtitle)
            .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
    }
    .frame(width: 140, alignment: .leading)
}

private var actionZone: some View {
    VStack(alignment: .trailing, spacing: 3) {
        uptimeOrIdleLabel
        StopButton(state: stopState) { /* unchanged */ }
    }
}

private var nameColor: Color {
    process.activity == .idle
        ? DesignSystem.Color.textSecondary.swiftUI
        : DesignSystem.Color.textPrimary.swiftUI
}

@ViewBuilder
private var uptimeOrIdleLabel: some View {
    if process.activity == .idle, let idle = process.idleSeconds {
        Text("idle \(formatUptime(idle))")
            .font(DesignSystem.Typography.pidSubtitle)
            .foregroundStyle(DesignSystem.Color.accent.swiftUI)
    } else {
        Text(formatUptime(process.uptimeSeconds))
            .font(DesignSystem.Typography.pidSubtitle)
            .foregroundStyle(DesignSystem.Color.textTertiary.swiftUI)
    }
}
```

Also update `meterZone` so CPU% dims for idle:

```swift
private var meterZone: some View {
    VStack(alignment: .leading, spacing: 2) {
        Text(String(format: "%.0f%%", process.cpuPercent))
            .font(DesignSystem.Typography.numeric)
            .foregroundStyle(
                process.activity == .idle
                    ? DesignSystem.Color.textTertiary.swiftUI
                    : DesignSystem.Color.textPrimary.swiftUI
            )
        CPUBar(percent: process.cpuPercent)
    }
    .frame(width: 80, alignment: .leading)
}
```

- [ ] **Step 7: Extend config tests.**

Append to `ConfigTests.swift`:

```swift
func test_activity_defaults_applied_when_missing() throws {
    let yaml = "worktree_roots: []\nprocess_patterns: []"
    let cfg = try Config.decode(fromYAML: yaml)
    XCTAssertEqual(cfg.activity.activeThresholdPercent, 1.0, accuracy: 0.001)
    XCTAssertEqual(cfg.activity.recentWindowMinutes, 5)
}

func test_activity_values_parsed_and_clamped() throws {
    let yaml = """
    worktree_roots: []
    process_patterns: []
    activity:
      active_threshold_percent: 2.5
      recent_window_minutes: 10
    """
    let cfg = try Config.decode(fromYAML: yaml)
    XCTAssertEqual(cfg.activity.activeThresholdPercent, 2.5, accuracy: 0.001)
    XCTAssertEqual(cfg.activity.recentWindowMinutes, 10)

    let tooBig = """
    worktree_roots: []
    process_patterns: []
    activity:
      active_threshold_percent: -1
      recent_window_minutes: 99999
    """
    let cfg2 = try Config.decode(fromYAML: tooBig)
    XCTAssertEqual(cfg2.activity.activeThresholdPercent, 0.0)
    XCTAssertEqual(cfg2.activity.recentWindowMinutes, 240)
}
```

- [ ] **Step 8: Extend scanner tests.**

Append to `ProcessScannerTests.swift`:

```swift
func test_activity_transitions_active_recent_idle() {
    var clockTime = Date(timeIntervalSince1970: 1_700_000_000)
    let clock: () -> Date = { clockTime }
    let fake = FakeProcessSource()
    fake.raw = [RawProcess(pid: 10, ppid: 1, name: "vite", command: "vite dev")]
    fake.detailsByPid = [10: ProcessDetail(
        pid: 10, cwd: "/tmp/wt", residentBytes: 1_000,
        cpuTicks: 0, wallStartSeconds: 1_699_999_000, listeningPorts: []
    )]
    let scanner = ProcessScanner(source: fake, clock: clock)
    let cfg = Config.ActivityConfig(activeThresholdPercent: 1.0, recentWindowMinutes: 5)

    // t=0: first sample. Cpu=0 but first-seen PID is seeded as active.
    var r = scanner.sample(matchPIDs: [10], activity: cfg)
    XCTAssertEqual(r.tracked.first?.activity, .activeNow)

    // t=+1s, large tick delta → active now.
    clockTime = clockTime.addingTimeInterval(1)
    fake.detailsByPid[10]?.cpuTicks = 500_000_000  // ~50% on a 1-core basis
    r = scanner.sample(matchPIDs: [10], activity: cfg)
    XCTAssertEqual(r.tracked.first?.activity, .activeNow)

    // t=+2s, no tick delta → cpu≈0 → recently active (within 5 min window).
    clockTime = clockTime.addingTimeInterval(1)
    fake.detailsByPid[10]?.cpuTicks = 500_000_000
    r = scanner.sample(matchPIDs: [10], activity: cfg)
    XCTAssertEqual(r.tracked.first?.activity, .recentlyActive)

    // t=+10min, still no delta → idle.
    clockTime = clockTime.addingTimeInterval(10 * 60)
    r = scanner.sample(matchPIDs: [10], activity: cfg)
    XCTAssertEqual(r.tracked.first?.activity, .idle)
    XCTAssertNotNil(r.tracked.first?.idleSeconds)
    XCTAssertGreaterThan(r.tracked.first!.idleSeconds!, 590) // ~10 min
}
```

Note: `FakeProcessSource.detailsByPid` needs mutability on `cpuTicks`. Update `ProcessDetail` to `var cpuTicks`, or store a mutable copy in the fake. Simplest: change `ProcessDetail` so all fields are `var`:

```swift
struct ProcessDetail: Equatable, Hashable {
    var pid: Int32
    var cwd: String?
    var residentBytes: UInt64
    var cpuTicks: UInt64
    var wallStartSeconds: TimeInterval
    var listeningPorts: [UInt16]
}
```

- [ ] **Step 9: Run the full test suite.**

```bash
xcodebuild test -scheme Procbar -destination 'platform=macOS'
```
Expected: all tests pass, including the new activity tests.

- [ ] **Step 10: Manual smoke test.**

1. Launch a dev server in a worktree; observe green dot + live CPU bar.
2. Idle the server (no requests) for ~10 seconds; dot stays green during CPU activity, drops to amber once CPU ≤ threshold.
3. Wait 5+ minutes; dot turns gray and the right column shows `idle 5m`, ticking up.
4. Trigger activity (hit the dev server); dot springs back to green with the 180ms scale bump.

- [ ] **Step 11: Commit.**

```bash
git add -A
git commit -m "feat(task20): per-process activity state (dot + idle indicator)"
```

---

## Spec coverage self-check

| Spec section | Task(s) | Status |
|---|---|---|
| §3 core decisions — MenuBarExtra, libproc, Yams, two-phase, SMAppService, DispatchSource | 0, 2, 7, 8, 18 | covered |
| §4 user-facing behavior — icon, popover, rows, kill, preferences | 12, 13, 14, 15, 16 | covered |
| §5 configuration model — YAML, defaults, first-run, tilde, discovery | 2, 3, 4, 5, 17 | covered |
| §6 architecture — all nine components | 1–17 | covered |
| §7 testing — ProcessMatcher, ConfigStore, killer tree-build | 2, 4, 9, 10 | covered (unit); integration for scanner via manual + libproc smoke |
| §8 visual & UX — palette, typography, layout, motion, signature CPU bar | 1, 12–15 | covered |
| §4.3 activity state — active/recent/idle, idle time swap, dot bump | 20 | covered |
| §9 success criteria — responsiveness, graceful kill, live reload, low overhead, distinct look | 4, 10, 15, 17, 19 | covered |

---

## Notes for the executor

- Every code block above is canonical — copy verbatim. Do not substitute "similar" code from memory.
- `xcodegen generate` must be re-run whenever `project.yml` changes (new files added under `sources:` are picked up automatically since `createIntermediateGroups: true`).
- If `xcodebuild test` hits a sandbox error on `DispatchSource` file watching inside `ConfigStoreTests`, relax the test target's sandbox or move temp dirs under `NSTemporaryDirectory()` — already the case in the tests above.
- `LibprocSource` uses deprecated/kernel-level APIs; treat compiler warnings about `PROC_PIDTBSDINFO` etc. as expected. Don't try to "modernize" them — there is no modern alternative.
- Don't change tracking colors from the palette without updating `DesignSystem.Color` in one place. Views must not hardcode hex values.
- If a task's tests pass but the app feels off (misaligned row columns, bar wrong tint), treat that as a failed task — run the manual smoke test and fix before moving on.
