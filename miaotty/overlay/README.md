# Overlay

Everything miaotty adds on top of the Ghostty fork. The upstream checkout lives
at `vendor/ghostty/` (gitignored; recreated by `scripts/bootstrap-ghostty.sh`)
and is kept **additive**: we only apply a tiny, tracked patch series, never edit
upstream files ad hoc.

## Patch series

| Patch | Why |
|-------|-----|
| [`patches/0001-xcode26-libtool-ranlib.patch`](./patches/0001-xcode26-libtool-ranlib.patch) | Zig 0.15.2 emits `ar` archives whose index Apple `libtool` (cctools_ld on Xcode 26) silently drops members from while merging — including the whole Zig core and C++ deps (imgui, oniguruma). Result: the macOS app fails to link with undefined `ghostty_*` / C++ symbols. The patch runs `ranlib` over every libtool input first, which rewrites the index so libtool keeps all members. |
| [`patches/0002-miaotty-app-integration.patch`](./patches/0002-miaotty-app-integration.patch) | Wires the integration spine into the app: (1) `ghostty_surface_child_pid` + `ghostty_surface_pane_id` C API — a per-surface atomic PID and a core-generated pane id; (2) per-pane `MIAOTTY_PANE_ID` env injection at spawn; (3) `TERM_PROGRAM=miaotty`; (4) 3-line hooks in `SurfaceView` (attach) + `AppDelegate` (start host); (5) local SPM package `MiaottyKit` in `Ghostty.xcodeproj`; (6) `xcodebuild -scheme Ghostty` with `SYMROOT/OBJROOT=build` (`-target` builds SPM products but does not propagate their `.swiftmodule`); (7) `CFBundleDisplayName = miaotty`. |

New (non-patch) source files live under [`macos/Sources/Miaotty/`](./macos/Sources/Miaotty/) and are copied into the checkout by `scripts/bootstrap-ghostty.sh`. The app target uses a `fileSystemSynchronizedGroups` `Sources/` group, so new files need no pbxproj entries. The same glue **installs the agent hook scripts + shell env** to `~/.local/share/miaotty/{agent-integration,shell-integration}` on launch (idempotent), so they ship without touching Ghostty's resource pipeline.

## Deferred (by decision, not missing)

- **Bundle identity rename** (`PRODUCT_BUNDLE_IDENTIFIER`, product/app-bundle name, URL schemes): the user-visible name is now `miaotty` and `TERM_PROGRAM=miaotty`, but the bundle id and `Ghostty.app` product name are intentionally kept until the distribution decision (signing / notarization / Sparkle feed / tests). See `docs/ADR/0006-identity-and-env-binding.md`.

## Build toolchain quirks (Xcode 26 / macOS 26)

- **Zig 0.15.2 cannot link the macOS 26 SDK.** Point zig at the 15.4 SDK via the
  `scripts/xcrun-sdk-shim` shim (prepended to `PATH`); `SDKROOT`/`--sysroot` are
  not honored for the `zig build` runner.
- The app's `xcodebuild` step needs **`xcode-select` pointing at full Xcode**
  (`DEVELOPER_DIR` is not inherited by that step) and the **Metal Toolchain**
  (`xcodebuild -downloadComponent MetalToolchain`).
- `scripts/bootstrap-ghostty.sh` wires all of the above.
