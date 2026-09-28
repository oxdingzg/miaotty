# ADR 0008 — Left tabs panel + right details panel

Status: accepted.

## Context

Otty's window has a left vertical **tabs** panel and a right **details** panel
(Info / Outline / Git / Files). Miaotty needs the same. Ghostty has no side
panels and no `NSSplitView`; its macOS window is a single SwiftUI
`TerminalView` hosting a recursive split tree.

## Decision

Add two togglable side panels around the terminal area:

1. **Layout injection point**: `TerminalView.body` wraps the split tree in
   `MiaottyPanelLayout` (a `HSplitView` with the left/right panels). Panel
   visibility lives on `BaseTerminalController` (`miaottyShowTabsPanel` /
   `miaottyShowDetailsPanel`), declared on the `TerminalViewModel` protocol so
   the SwiftUI view observes it. Toggles are `@IBAction toggleTabsPanel:` /
   `toggleDetailsPanel:` (View menu; ⌘⇧L / ⌘⌥D).
2. **Panels are new Swift files** under `macos/Sources/Miaotty/Panels/`
   (mirrored to `miaotty/overlay/macos/Sources/Miaotty/Panels/`): tabs list
   (KVO on `NSWindow.tabGroup`, click to switch, `+` new tab), and details
   (Info: cwd/actions/process/ports; Outline: command history; Git; Files).
   When a panel is hidden, a thin edge strip reveals a show button on hover.
3. **Command history data plane** (feeds Outline): a new `HistoryRegistry` in
   `MiaottyKit` (same lock/revision/onChange model as `AgentRegistry`), MTP
   methods `history.add` / `history.list`, `miaotty-cli history:add|list`, and a
   zsh hook installed by the app. The (patched) Ghostty zsh integration sources
   `$MIAOTTY_SHELL_HOOK`, whose `preexec` calls `miaotty-cli history:add`. This
   keeps command capture in the app/CLI layer — no Zig core parsing.

## Consequences

- Patches 0004 add 4 upstream hunks (`TerminalView.swift`,
  `BaseTerminalController.swift`, `MainMenu.xib`, the zsh integration). All new
  logic stays in the `Miaotty` namespace.
- The zsh integration file is GPLv3 (from Kitty); the added source line inherits
  that license. Only zsh is wired; bash/fish hooks are a follow-up.
- **Build quirk**: the app's `xcodebuild` uses a relative `OBJROOT=build`, so the
  local `MiaottyKit` SPM package emits into its own `build/` dir. `bootstrap-ghostty.sh`
  pre-builds the package and mirrors its products into the app build dir so a
  from-scratch build resolves `import MiaottyKit`.

## Verified

- App menu has `Toggle Tabs Panel` / `Toggle Details Panel`; toggling shows the
  panels (AX: `TABS`, `WORKING DIRECTORY`, `PROCESS`, `PORTS`).
- `history.add` → `history.list` round-trips over MTP; the Outline tab renders
  the commands + cwd headers for the focused pane.
- Patch series 0001–0004 applies cleanly on a fresh `v1.3.1` checkout.
