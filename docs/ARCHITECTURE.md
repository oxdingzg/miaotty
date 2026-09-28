# Architecture

miaotty is a native macOS terminal: it forks [Ghostty](https://ghostty.org) for
the terminal core (Metal renderer, VT, PTY, shell integration) and adds an
additive control/agent layer on top. This document records the durable decisions
behind that shape and how the fork is wired. Build mechanics and the patch series
live in [`miaotty/overlay/README.md`](../miaotty/overlay/README.md); the one-page
pitch is in the [root README](../README.md).

[English](ARCHITECTURE.md) · [中文](ARCHITECTURE.zh-CN.md)

For earlier, decision-by-decision history (ADRs 0001–0008), see the git log —
this document supersedes them.

## 1. Fork Ghostty with an additive overlay

**Context.** miaotty needs a native macOS terminal — Metal rendering, a fast VT
state machine, PTY handling, shell integration, terminfo, AppleScript,
auto-update. Building that from scratch is a multi-year effort; the
differentiators we actually want (agent-aware UI, a control plane, an IDE-ish
sidebar) are a small layer on top.

**Decision.** Fork Ghostty (MIT) and make additive-only changes:

- Our code lives under `miaotty/` — Swift `MiaottyKit`, Rust `miaotty-cli`, TS
  `@miao/miaotty`, resources, proto.
- Internal upstream symbols, file names and crate names stay untouched. Only
  user-facing identity is renamed (app name, bundle id, URL schemes,
  `TERM_PROGRAM`, env-var prefix), which keeps upstream merges cheap.
- A small, fixed set of patch points inside the checkout: expose
  `ghostty_surface_child_pid()` / `ghostty_surface_pane_id()` (read-only C API),
  an app-startup hook that installs the MTP host, and `Info.plist` / bundle
  metadata.

**Consequences.** We inherit Ghostty's performance ceiling and its fast-moving
upstream; we pin a release tag (1.3.1) and track `ghostty-org/ghostty` as
`upstream`. Self-hosted components (IPC, badges, sidebar) must not enter the
`input → pty → vt → metal` hot path (§3). The pbxproj is the riskiest file to
touch, so our Swift lives in a local SPM package (`MiaottyKit`) with a single
dependency line. We never copy Otty's proprietary scripts/HTML; OSC codes are
public.

`scripts/bootstrap-ghostty.sh` reproduces the fork setup (plan by default;
`--apply` to clone and patch, `--build` to build).

## 2. MTP: one contract, many transports

**Context.** miao and miaotty must feel like one product, but their
implementations change independently (today a plugin + CLI + socket; later
possibly in-process embedding or remote). Hard-coding one integration mechanism
couples the two release cycles and risks version skew.

**Decision.** Define **MTP (Miaotty Terminal Protocol)** as the stable contract,
with a single JSON-Schema source (`miaotty/proto/mtp.schema.json`) and codegen
for Rust, Swift and TypeScript.

- One connection, one envelope (`req`/`res`/`evt`), four planes: **state,
  context, control, UI**.
- Versioned (`v`) with a capability handshake (`hello`/`welcome`); new fields are
  optional and unknown capabilities/fields are ignored.
- Transport is abstracted (Unix socket primary; stdio and in-process later).
- State is idempotent and last-write-wins per key `(pane, session)`, with a
  monotonic `seq` and a `revision` for reconciliation.

**Consequences.** Implementations can be swapped without a protocol change — a
Swift host and a Rust CLI already interoperate over MTP. Codegen drift is a CI
failure; the schema is the only place types are edited. Peers must handle version
skew and degrade gracefully (the terminal never depends on the agent). Ad-hoc
CLI-only integration is the zero-install fallback level, not the contract;
in-process embedding is not precluded.

## 3. Performance first: baseline the thread model before touching hot paths

Performance is miaotty's first product property, and the fastest path is the one
we do not add to: `input → pty → vt → metal`. Badge updates, IPC, plugins and the
sidebar must never appear there. We cannot honor that boundary without knowing
which thread/queue does the PTY read, VT parse, render commit and present in the
forked build.

**Decision.** Before writing any code that touches terminal behavior:

1. **Document the upstream thread model** — enumerate the threads/queues of the
   forked build (PTY read, VT parse, render/commit, present, main) and the allowed
   contact points for our code (pane lifecycle events; a single coalesced
   main-thread apply point).
2. **Capture baselines** for every budget in `miaotty/bench/budgets.json` (frame
   time, key→glyph latency, throughput, cold start, memory) on the target machine.
3. **Wire CI gates** so a >5% regression on a hard budget fails the build.

**Consequences.** All additions are event-driven, coalescible, bounded and
disable-able; with every extra turned off, performance must be within noise of
Ghostty. Anti-patterns are explicit: no I/O, locks or allocations on the hot path;
no synchronous IPC; no polling timers; no per-frame scans; no unbounded queues.

> **Open:** the thread-model write-up (step 1) is not done yet and blocks hot-path
> work.

## 4. How the fork is wired

Everything here is additive and lives behind the patch points in §1. The patch
series itself is documented in
[`miaotty/overlay/README.md`](../miaotty/overlay/README.md).

### 4.1 Build on Xcode 26 / macOS 26

Ghostty 1.3.1 predates Xcode 26, and building it on macOS 26 surfaced three
independent blockers:

1. **Zig 0.15.2 cannot link the macOS 26 SDK** (undefined
   `__availability_version_check` / libSystem symbols). Pointing zig at the macOS
   15.4 SDK fixes it, but `SDKROOT` / `--sysroot` are not honored for the
   `zig build` runner — only the SDK that `xcrun --show-sdk-path` reports.
2. **The Metal Toolchain is a separate Xcode component** and must be installed
   (`xcodebuild -downloadComponent MetalToolchain`); the default `metal` binary
   is a stub until then.
3. **Apple `libtool` silently drops archive members** produced by Zig 0.15.2 —
   the Zig core object and C++ deps (imgui, oniguruma) vanish from the
   `libtool -static` merge. Rewriting each archive's index with `ranlib` before
   the merge fixes it.

**Decision.** Reproduce the build with a tracked recipe: the
`scripts/xcrun-sdk-shim/xcrun` shim (forces the 15.4 SDK for zig), the ranlib
patch, and `scripts/bootstrap-ghostty.sh` (installs Zig 0.15.2, clones the pinned
tag, applies patches, builds).

**Consequences.** Exactly one upstream file (`src/build/LibtoolStep.zig`) is
patched, and it is a genuine upstream fix candidate. The build is not "just
`zig build`": it needs the shim, a full `xcode-select`, and the Metal Toolchain.
When upstream writes libtool-compatible archives, the ranlib patch becomes
unnecessary.

### 4.2 Wire the spine into the app

The MTP host and CLI exist and interoperate, but nothing bound the host to real
terminal surfaces. Four additive changes wire it in:

1. **C API `ghostty_surface_child_pid`** — `termio.Exec` publishes the spawned
   child PID to a per-surface `std.atomic.Value(pid_t)`; the embedded apprt
   exports it. Read-only, off the hot path, no new locks.
2. **App hooks** — `AppDelegate` starts the MTP host at launch and `setenv`s
   `MIAOTTY_SOCKET` / `MIAOTTY_PROTO` so children inherit them; `SurfaceView`
   calls `MiaottyIntegration.attach(surface:to:)` after creating its surface.
3. **Local SPM package** — `MiaottyKit` is added to `Ghostty.xcodeproj` as a
   local package product (mirroring Sparkle), so the app keeps a single
   dependency line.
4. **`xcodebuild -scheme Ghostty`** — `-target` builds the package product but
   does not propagate its `.swiftmodule`, so the import fails; the shared scheme
   fixes resolution, and `SYMROOT/OBJROOT=build` keeps the output where the copy
   step expects it.

Badge rendering is a manual-frame `NSView` overlay (no Auto Layout, no frame
mutation during `draw`) driven by a **coalesced main-thread notification** from
the registry — never polling.

### 4.3 Pane identity, env binding and product identity

- **Core owns the pane id.** `Surface` generates a 32-hex id at creation and
  injects it into the child environment as `MIAOTTY_PANE_ID` (alongside
  `MIAOTTY_SOCKET`), exposed to the app via `ghostty_surface_pane_id()`. Binding
  is O(1) and survives nested/short-lived processes — no PID walk on the hot
  path.
- **The CLI defaults `--pane` from `MIAOTTY_PANE_ID`**, so hooks need no
  arguments; PID/tty matching remains the fallback for processes outside a pane.
- **The app is user-visibly `miaotty`.** `TERM_PROGRAM=miaotty`,
  `PRODUCT_NAME = miaotty` (which drives `CFBundleName`, the menu-bar name — the
  generated value cannot be overridden via `INFOPLIST_FILE`), and
  `PRODUCT_BUNDLE_IDENTIFIER = io.miaotty.terminal`. The distinct id removes the
  LaunchServices collision with an installed upstream Ghostty. All user-visible
  strings (app menu, About panel, quit/error dialogs, default window titles,
  settings/error/intent strings, `Ghostty.sdef`) are rebranded. The executable
  **filename** stays `ghostty` (`EXECUTABLE_NAME`) to avoid touching internal
  CLI/path references.
- **Hooks ship via install-on-launch.** The app writes the agent hook scripts and
  shell env to `~/.local/share/miaotty/...` on startup (idempotent), avoiding
  changes to Ghostty's resource pipeline. `miaotty/resources/**` stays the
  canonical fallback for CLI-only users.

**Deferred** (distribution-gated): the app icon (still the ghost), URL schemes,
the Sparkle feed/public key, and notarization — the app is ad-hoc signed.

### 4.4 Side panels and command history

Otty's window has a left vertical **tabs** panel and a right **details** panel
(Info / Outline / Git / Files); Ghostty has no side panels and no `NSSplitView`,
its macOS window being a single SwiftUI `TerminalView` hosting a recursive split
tree. miaotty adds two togglable panels around the terminal area:

- **Layout injection point** — `TerminalView.body` wraps the split tree in
  `MiaottyPanelLayout` (an `HSplitView`). Panel visibility lives on
  `BaseTerminalController` (`miaottyShowTabsPanel` / `miaottyShowDetailsPanel`),
  declared on the `TerminalViewModel` protocol so the SwiftUI view observes it;
  toggles are `@IBAction toggleTabsPanel:` / `toggleDetailsPanel:` (View menu;
  ⌘⇧L / ⌘⌥D).
- **Panels are new Swift files** under `macos/Sources/Miaotty/Panels/` (mirrored
  to `miaotty/overlay/macos/Sources/Miaotty/Panels/`): the tabs list (KVO on
  `NSWindow.tabGroup`, click to switch, `+` for a new tab) and the details panel
  (Info: cwd/actions/process/ports; Outline: command history; Git; Files). When a
  panel is hidden, a thin edge strip reveals a show button on hover.
- **Command history data plane** — a `HistoryRegistry` in `MiaottyKit` (same
  lock/revision/onChange model as `AgentRegistry`), MTP methods
  `history.add` / `history.list`, and a zsh hook installed by the app. The
  patched Ghostty zsh integration sources `$MIAOTTY_SHELL_HOOK`, whose `preexec`
  calls `miaotty-cli history:add` — command capture stays in the app/CLI layer,
  with no Zig core parsing.

**Consequences.** The patches add four upstream hunks (`TerminalView.swift`,
`BaseTerminalController.swift`, `MainMenu.xib`, the zsh integration); all new
logic stays in the `Miaotty` namespace. The zsh integration file is GPLv3 (from
Kitty), and only zsh is wired so far.
