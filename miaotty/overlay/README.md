# Overlay

Everything miaotty adds on top of the Ghostty fork. The upstream checkout lives
at `vendor/ghostty/` (gitignored; recreated by `scripts/bootstrap-ghostty.sh`)
and is kept **additive**: we only apply a tiny, tracked patch series, never edit
upstream files ad hoc.

## Patch series

| Patch | Why |
|-------|-----|
| [`patches/0001-xcode26-libtool-ranlib.patch`](./patches/0001-xcode26-libtool-ranlib.patch) | Zig 0.15.2 emits `ar` archives whose index Apple `libtool` (cctools_ld on Xcode 26) silently drops members from while merging — including the whole Zig core and C++ deps (imgui, oniguruma). Result: the macOS app fails to link with undefined `ghostty_*` / C++ symbols. The patch runs `ranlib` over every libtool input first, which rewrites the index so libtool keeps all members. |
| [`patches/0002-miaotty-app-integration.patch`](./patches/0002-miaotty-app-integration.patch) | Wires the integration spine into the app: (1) `ghostty_surface_child_pid` C API — a per-surface atomic PID published by `termio.Exec`; (2) 3-line hooks in `SurfaceView` (attach) + `AppDelegate` (start host); (3) local SPM package `MiaottyKit` added to `Ghostty.xcodeproj`; (4) `xcodebuild` uses `-scheme Ghostty` (with `SYMROOT/OBJROOT=build`) because `-target` builds SPM products but does not propagate their `.swiftmodule` to the app. |

New (non-patch) source files live under [`macos/Sources/Miaotty/`](./macos/Sources/Miaotty/) and are copied into the checkout by `scripts/bootstrap-ghostty.sh`. The app target uses a `fileSystemSynchronizedGroups` `Sources/` group, so new files need no pbxproj entries.

## Planned (not yet applied)

Designed but still upstream-side work:

1. **Per-pane env injection** — set `MIAOTTY_PANE_ID` in `termio.Exec` at spawn so agents bind in O(1) without a PID walk.
2. **Bundle metadata** — rename app name / bundle id / URL schemes / `TERM_PROGRAM`.
3. **Resources** — bundle `miaotty/resources/**` (shell + agent integration, terminfo).

## Build toolchain quirks (Xcode 26 / macOS 26)

- **Zig 0.15.2 cannot link the macOS 26 SDK.** Point zig at the 15.4 SDK via the
  `scripts/xcrun-sdk-shim` shim (prepended to `PATH`); `SDKROOT`/`--sysroot` are
  not honored for the `zig build` runner.
- The app's `xcodebuild` step needs **`xcode-select` pointing at full Xcode**
  (`DEVELOPER_DIR` is not inherited by that step) and the **Metal Toolchain**
  (`xcodebuild -downloadComponent MetalToolchain`).
- `scripts/bootstrap-ghostty.sh` wires all of the above.
