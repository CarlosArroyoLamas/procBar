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
