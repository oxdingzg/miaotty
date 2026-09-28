# ADR 0005 — Wire the integration spine into the Ghostty app

## Context

The MTP host (`MiaottyKit`) and CLI exist and interoperate, but nothing bound
the host to real terminal surfaces. To prove the spine inside the app we needed
three things: pane identity, an in-app host, and a badge surface.

## Decision

Four additive changes (patch 0002):

1. **C API `ghostty_surface_child_pid`**: `termio.Exec` publishes the spawned
   child PID to a per-surface `std.atomic.Value(pid_t)` (passed via `Config`);
   the embedded apprt exports it. Read-only, off the hot path, no new locks.
2. **App hooks**: `AppDelegate` starts the MTP host at launch (and `setenv`s
   `MIAOTTY_SOCKET`/`MIAOTTY_PROTO` so children inherit them); `SurfaceView`
   calls `MiaottyIntegration.attach(surface:to:)` after creating its surface.
3. **Local SPM package**: `MiaottyKit` is added to `Ghostty.xcodeproj` as a
   local package product (4 small pbxproj entries, mirroring Sparkle). Our Swift
   lives in the package, so the app keeps a single dependency line.
4. **`xcodebuild -scheme Ghostty`**: `-target` builds the package product but
   does not propagate its `.swiftmodule` to the app's Swift compile, so the
   import fails. The shared scheme fixes resolution; `SYMROOT/OBJROOT=build`
   keeps the output where the copy step expects it.

Badge rendering is a manual-frame `NSView` overlay (no Auto Layout, no frame
mutation during `draw`) driven by a **coalesced main-thread notification** from
the registry — never polling.

## Consequences

- Verified: `miaotty-cli pane list` returns the live pane + real child PID;
  `state set` drives the badge through `none → processing → awaiting → error →
  idle`, and the app stays alive.
- The C API and hooks are small and upstreamable; the pbxproj/`-scheme` bits are
  build-system plumbing.
- Deferred (see overlay README): per-pane `MIAOTTY_PANE_ID` env injection, so an
  agent can bind without a PID walk. Until then binding is by pane id (external
  callers) or child-PID ancestry.
- `-scheme` adds a dependency on the shared scheme existing in the checkout
  (`macos/Ghostty.xcodeproj/xcshareddata/xcschemes/Ghostty.xcscheme`), which is
  vendored in the Ghostty repo.

## Verified commands

```sh
scripts/bootstrap-ghostty.sh --apply --build        # builds the app
miaotty-cli ping
miaotty-cli pane list                                # -> id + child_pid
miaotty-cli state set --agent miao --state processing --pane <id>
# app log: "miaotty: badge pane=<id> state=processing"
```
