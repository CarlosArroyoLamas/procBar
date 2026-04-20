# Procbar — Design Spec

**Status:** Design / vision document.
**Date:** 2026-04-17.
**Scope:** A personal macOS menu bar utility that surfaces and manages local development processes across multiple git worktrees. Single-user tool, not distributed.

This document defines **what procbar is, why it exists, and how it should be built**. A separate implementation plan (see `../plans/`) breaks this into executable steps.

---

## 1. Problem

When working across multiple git worktrees in parallel, a developer ends up with many long-lived dev processes running simultaneously: NX task runners, Vite dev servers, Node servers, Postgres, Redis, webpack watchers, etc. Each worktree can spawn several.

The problem:
- **macOS Activity Monitor** shows a flat list of hundreds of processes with no notion of *which worktree they belong to*.
- `ps`/`lsof`/`htop` work but require context switching to a terminal and manual filtering.
- Finding and killing "the Vite server for worktree X" means visually scanning PIDs and guessing from `cwd`.
- Orphaned dev servers silently hold ports, spike CPU, and drain battery.

**Procbar** is a macOS menu bar app that groups tracked dev processes by their git worktree, shows the info a developer actually cares about (PID, CPU, memory, listening port, uptime), and lets the user kill them — gracefully and tree-aware — with a single click.

---

## 2. Out of scope (v1)

- Cross-platform support (macOS only).
- Starting or restarting processes from procbar.
- Tailing stdout/stderr logs.
- Tracking processes you don't own (no root/sudo kills).
- Distribution (code signing, notarization, auto-update, Homebrew cask). Local build-and-run only.
- Telemetry of any kind.

---

## 3. Core design decisions

| Decision | Choice | Why |
|---|---|---|
| Form factor | Mac menu bar app | Always-accessible, non-intrusive, matches the "glanceable status + quick action" use case. |
| Tech stack | Swift 5.9+ / SwiftUI | Native menu bar integration, no runtime to ship, direct access to Darwin `libproc` APIs, fast. |
| Menu bar API | SwiftUI `MenuBarExtra(.window)` (macOS 13+) | Pure SwiftUI. No manual `NSStatusItem`/`NSPopover` plumbing. Settings scene handles preferences. |
| Min macOS | 13 (Ventura) | `SMAppService` for login items, `MenuBarExtra`, mature SwiftUI. |
| Architecture | Single-process app | No daemon needed — all tracked processes are owned by the user, so no privileged helper required. |
| Process enumeration | Darwin `libproc` (`proc_listpids`, `proc_pidinfo`, `proc_pidpath`) | Much faster and lower-overhead than shelling out to `ps`/`lsof` on every poll. |
| Scan strategy | Two-phase: (1) cheap list of all PIDs with name+command, (2) expensive details (`cwd`, ports, rusage) *only* for matched candidates | Keeps poll cycle under a few ms even with 600+ processes on the system. |
| CPU% calculation | Per-PID tick deltas between consecutive polls, divided by wall-clock elapsed, normalized per core | `libproc` gives cumulative ticks; instantaneous CPU% requires two samples. |
| Activity tracking | Per-PID "last active" timestamp maintained across scans; derived state: `active now` / `recently active` / `idle` | Lets the user spot forgotten/orphaned dev servers at a glance, not just instantaneous load. |
| Port detection | `proc_pidfdinfo` with `PROC_PIDFDSOCKETINFO` (TCP `LISTEN` state only) | Native syscall, avoids shelling out to `lsof`. |
| Process grouping | Auto-discovery of git worktrees under configured roots, with `.git` detection | Matches the user's mental model of "what's running in which workspace." |
| Kill behavior | SIGTERM to process tree → wait 3s → SIGKILL survivors | Graceful shutdown preferred; kills orphan children reliably. |
| Configuration | YAML file (source of truth) + SwiftUI Settings scene that edits it | File is diff-able, version-controllable, fast to edit; GUI provides discoverability. |
| Config location | `$XDG_CONFIG_HOME/procbar/config.yaml`, defaulting to `~/.config/procbar/config.yaml` | Respects XDG when set, predictable otherwise. |
| YAML library | [Yams](https://github.com/jpsim/Yams) (Swift Package Manager) | De facto standard, actively maintained, straightforward Codable support. |
| Refresh | Polling, default 2s, configurable (1–30s) | Event-driven process monitoring on macOS is not trivial; 2s polling is cheap enough. |
| Config watching | `DispatchSource.makeFileSystemObjectSource` on the config file | Lighter than full FSEvents for a single-file watch; built-in. |
| Logging | `os.Logger` with subsystem `com.carlos.procbar`, categories `scanner`, `kill`, `config`, `ui` | Inspectable via `Console.app`, integrates with Instruments. |
| Testability | All scanners/killers behind protocols (`ProcessSource`, `KillSender`, `GitBranchReader`) | Allows unit tests to inject deterministic fakes without touching real system processes. |

---

## 4. User-facing behavior

### 4.1 Menu bar icon

- A small monochrome SF Symbol (e.g., `rectangle.stack.badge.person.crop`) with a colored status dot:
  - **Green**: one or more tracked processes currently running.
  - **Gray**: no tracked processes running.
- Click toggles a popover.

### 4.2 Popover UI

- **Header row**: "N processes across M worktrees" + a small refresh indicator.
- **Body**: one collapsible section per discovered worktree that has at least one matching process. Empty worktrees are hidden by default. Section header shows:
  - Worktree folder name (e.g., `bringr`).
  - Current git branch in muted text.
  - Process count badge.
- **Process rows** (one per matching process):
  - A small **activity dot** (4pt) directly left of the name:
    - Green = active now (CPU above threshold in the current sample).
    - Amber = recently active (below threshold now, but was active in the last `recent_window_minutes`).
    - Gray = idle (no activity for at least `recent_window_minutes`).
  - Icon / short name derived from the configured pattern (e.g., "NX", "Vite").
  - PID.
  - CPU% (current sample).
  - Resident memory (MB).
  - Listening TCP port(s), if any.
  - Right column: **uptime** when active or recently active; **"idle Xm"** when idle. Format: `idle 47m`, `idle 3h`, `idle 2d`.
  - A "Stop" button on the right.
- **Footer**: `Preferences…` · `Open Config…` · `Quit`.

### 4.3 Activity state

- On each poll, the scanner records the timestamp of the most recent sample where `cpu_percent > active_threshold_percent` per PID. This `lastActiveAt` map survives across ticks but drops entries for PIDs that have disappeared.
- State resolution for every tracked process:
  - **Active now** — current sample's CPU% > `active_threshold_percent`.
  - **Recently active** — not active now, but `now − lastActiveAt < recent_window_minutes`.
  - **Idle** — no `lastActiveAt` within the recent window (or never recorded).
- `idle_seconds` reported to the UI equals `now − lastActiveAt` when idle, otherwise `nil`.
- A newly observed PID is seeded with `lastActiveAt = now` on first sight; the first time a process appears it is always considered active so a freshly-spawned dev server doesn't immediately display as "idle".

### 4.4 Kill action

- Clicking "Stop" triggers graceful kill:
  1. Send `SIGTERM` to the process and every descendant.
  2. Show an in-row progress spinner for up to 3 seconds.
  3. After 3 seconds, send `SIGKILL` to any surviving PIDs in the tree.
  4. Remove the row when all tree members are gone.
- If the user clicks Stop a second time during the grace period, skip to `SIGKILL` immediately.

### 4.5 Preferences window

A simple SwiftUI form that reads and writes the YAML config. Fields:
- **Worktree roots**: list of absolute paths to scan for worktrees.
- **Excluded paths**: list of absolute paths to ignore.
- **Process patterns**: list of `{ displayName, match, matchField }` rows (add/edit/remove).
- **Refresh interval (seconds)**: integer, default 2, min 1, max 30.
- **Show git branch**: toggle.
- **Launch at login**: toggle (uses `SMAppService`).
- **Open config file in default editor**: button.

Changes saved in the preferences window write to the YAML file; FSEvents triggers a live reload.

---

## 5. Configuration model

### 5.1 Example config

```yaml
refresh_interval_seconds: 2
show_branch: true
launch_at_login: true

worktree_roots:
  - ~/Documents
  - ~/code

excluded_paths:
  - ~/Documents/archive

# Activity thresholds. CPU% at or below active_threshold_percent is "not active"
# for that sample. "Recently active" means the process was active sometime in
# the last recent_window_minutes. Beyond that window it is shown as idle.
activity:
  active_threshold_percent: 1.0
  recent_window_minutes: 5

# A process is "tracked" if its name OR command line matches any pattern
# AND its cwd is inside one of the discovered worktrees (and not excluded).
process_patterns:
  - name: "NX"
    match: "nx"
    match_field: command   # command | name
  - name: "Vite"
    match: "vite"
    match_field: command
  - name: "Node"
    match: "node"
    match_field: name
  - name: "Postgres"
    match: "postgres"
    match_field: name
```

### 5.2 Matching rules

- A process matches a pattern if `match` (as a substring, case-insensitive) is found in the chosen `match_field`.
- A matched process is *tracked* only if its `cwd` is inside one of the discovered worktree paths and not under any `excluded_paths` entry.
- A process without a reachable `cwd` (e.g., permission denied) is ignored.
- All path fields in the config (`worktree_roots`, `excluded_paths`) support leading `~` — the app expands to the user's home directory before use.

### 5.3 First run

- On first launch, if `~/.config/procbar/config.yaml` does not exist, the app creates it from the example config in §5.1 and opens the Preferences window so the user can adjust roots and patterns immediately.

### 5.4 Worktree discovery

- For each path in `worktree_roots`, walk up to 4 directory levels deep.
- A directory is a worktree if it contains a `.git` directory **or** a `.git` file (pointer used by linked worktrees).
- For each discovered worktree, cache: absolute path, display name (`basename`), current branch (via `git symbolic-ref --short HEAD`, cached for 10s).
- Rescan worktrees every 30s (cheap) and on config change.

---

## 6. Architecture

Single macOS app target. All code runs in one process.

### 6.1 Components

| Component | Responsibility |
|---|---|
| `ProcbarApp` | SwiftUI `@main`. Declares `MenuBarExtra` (popover content) and `Settings` (preferences). Wires top-level dependencies. |
| `MenuBarContentView` (SwiftUI) | Renders grouped worktrees and process rows. Bound to `AppViewModel`. |
| `SettingsView` (SwiftUI) | Renders the preferences form, writes to config on change. |
| `ConfigStore` | Loads, validates, watches, and saves the YAML config. Publishes config changes. |
| `WorktreeScanner` | Walks `worktree_roots`, detects `.git`, resolves current branch. Produces a list of `Worktree` records. |
| `ProcessScanner` | Two-phase `libproc` enumeration behind `ProcessSource` protocol. Phase 1: cheap PID + name + command list. Phase 2 (matched PIDs only): `cwd`, CPU ticks, RSS, listening ports. Maintains previous snapshot for CPU% delta calculation, plus a `lastActiveAt: [Int32: Date]` map used to derive per-process activity state (active now / recently active / idle). |
| `ProcessMatcher` | Pure function: given config + scanner output + worktrees, returns the grouped, filtered list shown in the UI. |
| `ProcessKiller` | Builds the descendant PID tree from the last scanner snapshot; performs graceful kill with timeout. Behind `KillSender` protocol so tests don't actually spawn/kill processes. |
| `AppViewModel` | `ObservableObject` that owns the timer, pulls scanner output every `refresh_interval_seconds`, and publishes the current grouped state + a global "active" flag for the menu bar icon. |
| `DesignSystem` | Centralized palette, typography, spacing, corner radii, and motion constants. All views pull from here. |

### 6.2 Data flow

```
Timer (2s) ──► ProcessScanner ──┐
                                │
ConfigStore ───────────────────►┼──► ProcessMatcher ──► AppViewModel ──► PopoverView
                                │
WorktreeScanner (30s) ─────────►┘

User clicks Stop ──► ProcessKiller ──► (SIGTERM tree) ──► wait 3s ──► (SIGKILL survivors) ──► next poll cleans up UI
```

### 6.3 Concurrency

- Scanning runs on a background `DispatchQueue` (user-initiated QoS).
- The view model publishes on the main queue.
- The kill sequence runs in a detached `Task`; UI only reflects result via the next poll.

### 6.4 Error handling

All failures are non-fatal and logged to a ring buffer visible from the preferences window ("Diagnostics" tab, v1.1 — not required for v1):
- Invalid YAML: keep last-known-good config, show a small red dot on the menu bar icon until resolved.
- Permission denied on `proc_pidinfo` for a PID: silently skip that PID.
- `git symbolic-ref` failure: omit branch name for that worktree, don't retry in this cycle.
- Kill failure: log, leave the row visible, let the next poll reconcile.

---

## 7. Testing approach

- **Unit tests**: `ProcessMatcher` (given config + fake scanner output → expected groups), `ConfigStore` (YAML parsing edge cases), `ProcessKiller` tree-building (given a flat PID/PPID list → correct descendant set).
- **Integration tests**: `ProcessScanner` against a known subprocess this test harness spawns (verify cwd, ports, lifecycle).
- **Manual smoke test** before each build: launch, point at a root with real worktrees, verify grouping, branch display, kill action.

Skipped in v1: UI snapshot tests (low ROI for a personal tool), E2E tests (the manual smoke test covers it).

---

## 8. Visual & UX design

### 8.1 Aesthetic direction — "Instrument Panel"

Procbar is a diagnostic instrument, not a chat app. The aesthetic commits to:

- **Quiet by default, loud only when something's hot.** Near-monochrome graphite with a single amber accent that emerges as processes work harder.
- **Mono numerics, tabular alignment.** Every readout — PID, CPU%, MEM, port, uptime — sits in a fixed column of SF Mono with tabular figures. The eye scans down a row of numbers the way it reads a cockpit cluster.
- **Hairline structure.** Rows separated by 1pt hairlines, not cards or shadows. Density is earned, not decorated.
- **Motion as signal, not seasoning.** The CPU meter breathes. The status dot pulses only when things are alive. Nothing else animates unless it has to.

The app must feel native on macOS — respect system dark/light mode, use native materials — but its personality is specifically a piece of pro equipment, not a consumer app.

### 8.2 Palette (all centralized in `DesignSystem.Color`)

**Dark mode:**

| Role | Hex |
|---|---|
| Background | `#0E0E10` (warm near-black; pure black reads too clinical for long sessions) |
| Surface / elevated row | `#16161A` |
| Hairline | `rgba(255, 255, 255, 0.10)` |
| Text primary | `#F2F2F5` |
| Text secondary | `#8A8A94` |
| Text tertiary | `#5C5C65` |
| Accent — amber/phosphor | `#FFB020` (CPU bar warm, count badge, branch icon, **recently-active dot**) |
| Warning — hot red | `#FF5B49` (CPU ≥ 80%, Stop button on hover, SIGKILL flash) |
| Success — cool green | `#4FD97C` (200ms confirmation when a kill completes gracefully, **active-now dot**) |
| Idle dot | `#5C5C65` (same as text-tertiary — reads as "off") |

**Light mode:**

| Role | Hex |
|---|---|
| Background | `#FAFAF7` (warm paper) |
| Surface | `#FFFFFF` |
| Hairline | `rgba(0, 0, 0, 0.10)` |
| Text primary | `#131316` |
| Text secondary | `#5C5C65` |
| Text tertiary | `#9A9AA0` |
| Accent — amber | `#C9820A` (recently-active dot) |
| Warning | `#C7341E` |
| Success | `#2F8C4C` (active-now dot) |
| Idle dot | `#9A9AA0` |

### 8.3 Typography (`DesignSystem.Typography`)

| Role | Font | Size | Weight | Tracking |
|---|---|---|---|---|
| Popover header title | SF Pro Display | 13 | Semibold | -0.3 |
| Worktree name | SF Pro Text | 12 | Medium | 0 |
| Process display name | SF Pro Text | 12 | Medium | 0 |
| Branch name | SF Mono | 11 | Regular | +0.2 |
| Numeric readouts (PID, CPU%, MEM, port, uptime) | SF Mono (tabular figures) | 11 | Regular | 0 |
| Micro-labels ("MEM", "PORT", footer buttons) | SF Pro Text | 9 | Medium, uppercase | +0.8 |
| Count badge value | SF Mono | 10 | Semibold | 0 |

### 8.4 Popover layout

- **Width:** 340pt. **Corner radius:** 10pt.
- **Outer padding:** 14pt horizontal, 10pt vertical.
- **Section spacing:** 12pt between worktree groups.

**Header row (28pt):**
- Left: app glyph (12pt) + "Procbar" wordmark.
- Right: tertiary text `N PROCESSES · M WORKTREES`, uppercase micro-label.

**Worktree section header (26pt):**
- Left to right: disclosure chevron (8pt tertiary), worktree folder name (body/medium), a single hairline gap, branch name prefixed by a branch glyph (SF Mono 11pt, text-tertiary).
- Far right: count badge — pill 20×16pt, amber bg at 15% opacity, amber text, mono 10pt.
- 1pt hairline directly below.

**Process row (34pt) — four zones, left to right:**

1. **Identity (140pt):** 4pt **activity dot** (green / amber / gray) followed by display name in body/medium. PID in mono 10pt tertiary below (e.g., `PID 12345`). The dot scales +20% (spring, 180ms) the moment a process transitions to active, giving a subtle "came alive" signal without animating constantly.
2. **Load meter (80pt):** CPU% in mono 11pt on top, right-aligned. Below it, **the signature CPU bar** — 2pt tall, 80pt wide, rounded 1pt. Empty background is hairline color; fill is amber, width scaled to CPU%. Fill turns warning-red when CPU ≥ 80%. Animates to new value with a damped spring. When a process is idle, the fill is 0 and the label reads `0%` in tertiary (not primary) so the row visually recedes.
3. **Resource detail (70pt):** two stacked micro rows. Top: label `MEM` + value `234 MB`. Bottom: label `PORT` + value `:3000` (or `—` if none). Labels uppercase 9pt tertiary, values mono 11pt primary.
4. **Action (60pt):** uptime in mono 10pt tertiary top-right when active or recently active (`14m`, `2h`, `3d`). When idle, replaced with `idle 47m` in amber 10pt (so the user's eye lands on stale rows). Below it, the Stop button — 24×24pt square, 1pt hairline border, 6pt corner radius, centered glyph.

**Footer row (30pt):**
- Three text buttons, 14pt gaps: `Preferences`, `Open Config`, `Quit`.
- Micro-labels, text-secondary. Hover: text-primary + 1pt underline.

### 8.5 Menu bar icon

Custom template image at 18×18pt (PDF, single channel so macOS handles dark/light inversion):

```
┌──────────────┐
│  ████████    │
│  █████       │
│  ██████      │
└──────────────┘
```

Three horizontal bars of varying length, stacked — reads as "instrument panel" or "equalizer":

- **Active** (≥1 tracked process): bars at full opacity.
- **Idle** (zero tracked processes): bars at 40% opacity.
- **Config error**: superimpose a 3pt amber dot in the lower-right corner of the icon.

No colored status dot on the icon itself; the pulse behavior lives only inside the popover. This keeps the menu bar line quiet and respectful of other items.

### 8.6 Motion (`DesignSystem.Motion`)

| Event | Animation |
|---|---|
| Popover open/close | Default AppKit behavior. No override. |
| Row appear | opacity 0→1, y-offset +4→0, spring(response: 0.25, damping: 0.9), staggered 30ms per row within a section. |
| Row disappear (after kill) | opacity 1→0 + height collapse to 0, spring(response: 0.3, damping: 0.85). Siblings spring up. |
| CPU bar value change | spring(response: 0.4, damping: 0.85). |
| Section expand/collapse | spring(response: 0.28, damping: 0.9). |
| Stop button — idle | `⏻` glyph, text-secondary. |
| Stop button — pressed / SIGTERM phase | Glyph rotates to `◻︎`, border pulses amber, a 24pt counter-clockwise progress arc fills over 3s. |
| Stop button — SIGKILL fallback | Glyph becomes `✕`, 120ms red fill flash, then row disappears. |
| Kill success (process exited gracefully during grace) | 200ms green tint on row background, then row disappears. |
| Second Stop click during grace | Immediate SIGKILL path (skip arc, red flash, vanish). |

### 8.7 Signature element

The one thing a user will remember: **the live CPU bar under each process name.** A small amber line that breathes with CPU load. You open the popover and you can *see* which processes are working hard without reading a single digit. The rest of the aesthetic — monochrome, hairline, mono-numeric — is deliberately quiet so this one element reads as a pulse.

### 8.8 Empty states

| State | Copy | Action |
|---|---|---|
| No config file found (first run) | Automatically created; Settings opens to intro tab. | — |
| Config file invalid | Amber dot on menu bar icon. Popover header shows a single red pill: `CONFIG ERROR — SEE SETTINGS` that opens Settings. | Click pill → Settings. |
| No worktrees discovered | Centered text-secondary: *"No worktrees under configured roots."* | Text button beneath: *"Edit configuration…"* |
| Worktrees found, nothing tracked | Centered text-secondary: *"All quiet."* | None. The user knows. |
| Settings with zero patterns | Dashed hairline placeholder row with *"+ Add pattern"* button. | Add row. |

### 8.9 Accessibility

- VoiceOver labels composed per row: `"{display name}, PID {pid}, {cpu} percent CPU, {mem} megabytes, port {port}, uptime {uptime}. Stop button."`
- Full keyboard navigation inside the popover: arrow keys move between rows, Enter triggers default row action (no-op in v1), Space on Stop button fires the kill.
- Dynamic Type honored up to "Large"; above that, font sizes clamp to preserve row layout.
- All hit targets ≥ 24×24pt.
- Color is never the sole signal: CPU high-load state adds a subtle right-edge tick on the bar in addition to the red tint.

---

## 9. Success criteria

Procbar v1 is successful if:

1. Opening the menu bar popover shows all running NX/Vite/Node/Postgres processes across every open worktree, correctly grouped, within 2 seconds of any change.
2. One click graceful-kills a dev server and all its children, with no lingering orphans.
3. Adding a new process pattern in the config file takes effect within a second without restarting the app.
4. CPU overhead of procbar itself, when idle with ~10 tracked processes across 5 worktrees, is under 1% on an average Mac.
5. The developer no longer opens Activity Monitor to hunt for stray dev servers.
6. The popover feels visually distinct from generic "AI-slop" macOS utilities — monochrome palette, mono numerics, signature CPU meter — and is pleasant to look at for the dozens of times per day it gets opened.

---

## 10. Non-goals for v1 that may be considered later

- **Log tailing** — attach to stdout/stderr of tracked processes via a sidecar.
- **Start/restart** — save launch commands per project, run from the menu.
- **Port conflict warnings** — flag when two tracked processes listen on the same port.
- **Notifications** — macOS notification when a tracked process crashes unexpectedly.
- **Per-worktree config** — allow a `.procbar.yaml` inside a worktree to extend global patterns.
