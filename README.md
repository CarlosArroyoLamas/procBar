# Procbar

Menu bar utility for tracking and killing dev processes across git worktrees.

See `specs/2026-04-17-procbar-design.md` for the design and `plans/2026-04-17-procbar-implementation-plan.md` for the build plan.

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

## Smoke test (manual, before each release)

1. Delete `~/.config/procbar/config.yaml` if present.
2. `xcodegen generate && xcodebuild -scheme Procbar -configuration Debug build && open "$(find ~/Library/Developer/Xcode/DerivedData -name Procbar.app -path '*/Debug/*' | head -1)"` — expect menu bar icon, no dock icon.
3. First run: config file created at `~/.config/procbar/config.yaml`; popover says "All quiet." when no processes match.
4. In another terminal, from a worktree under `~/Documents` (or any configured root), run `npx vite preview` (or any node server). Within 2 s it appears under the correct worktree with branch name.
5. CPU bar animates as the server loads. Activity dot is green when active, amber within 5 min of last activity, gray after that.
6. Click Stop: SIGTERM fires, progress arc winds for up to 3 s, row disappears. A second click during the arc fast-paths to SIGKILL.
7. Start a zombie-spawning process; Stop should clean up children (verify with `ps`).
8. Edit config externally (`echo "refresh_interval_seconds: 5" >> ~/.config/procbar/config.yaml`), popover reloads within 2 s.
9. Toggle "Launch at login" in Settings; verify with `launchctl list | grep com.carlos.procbar`.
10. Quit from the footer; `ps aux | grep Procbar` shows none.

## Troubleshooting

- **Icon missing from menu bar:** confirm `LSUIElement` is `true` in Info.plist and the Assets catalog compiled (check `Procbar.app/Contents/Resources/Assets.car`).
- **Branch names missing:** `/usr/bin/env git` must be resolvable in the app's PATH. For sandboxed installs you may need to set PATH in Info.plist or embed an absolute path in `GitBranchReader`.
- **Ports never show:** macOS 14+ may gate `proc_pidfdinfo` with `PROC_PIDFDSOCKETINFO` behind entitlements — check Console.app for denied syscalls and add `com.apple.security.get-task-allow` during development.
- **App doesn't appear after `open`:** check `log stream --predicate 'subsystem == "com.carlos.procbar"'` — the app logs config/scanner/kill/ui categories there.

## Project layout

```
Procbar/
├── DesignSystem/   # palette, typography, spacing, motion (centralized)
├── Models/         # Config, Worktree, ProcessSnapshot, TrackedProcess, WorktreeGroup
├── Services/       # ConfigStore, WorktreeScanner, GitBranchReader, ProcessScanner,
│                   # ProcessMatcher, ProcessKiller, ProcessSource (protocol)
├── Utilities/      # Libproc (Darwin bridge), PathUtils, LoginItem
├── ViewModels/     # AppViewModel, AppContext, KillCoordinator
├── Views/          # MenuBarContentView + subviews, SettingsView
└── ProcbarApp.swift  # @main, wires everything

ProcbarTests/      # 37 unit/integration tests, mirror Procbar/ layout
project.yml        # XcodeGen source of truth
```
