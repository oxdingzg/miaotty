# Overlay

Everything miaotty adds on top of the Ghostty fork. The upstream checkout lives
at `vendor/ghostty/` (gitignored; recreated by `scripts/bootstrap-ghostty.sh`)
and is kept **additive**: we only apply a tiny, tracked patch series, never edit
upstream files ad hoc.

## Patch series

| Patch | Why |
|-------|-----|
| [`patches/0001-xcode26-libtool-ranlib.patch`](./patches/0001-xcode26-libtool-ranlib.patch) | Zig 0.15.2 emits `ar` archives whose index Apple `libtool` (cctools_ld on Xcode 26) silently drops members from while merging — including the whole Zig core and C++ deps (imgui, oniguruma). Result: the macOS app fails to link with undefined `ghostty_*` / C++ symbols. The patch runs `ranlib` over every libtool input first, which rewrites the index so libtool keeps all members. |

Apply against the pinned tag:

```sh
cd vendor/ghostty
git apply ../../miaotty/overlay/patches/0001-xcode26-libtool-ranlib.patch
```

## Planned (not yet applied)

These are the additive change points designed in the tech plan; they land here
as patches + new files once the integration spine is wired to the core:

1. **C API**: expose `ghostty_surface_child_pid()` and pane metadata (read-only).
2. **App hook**: install the MTP host at app startup (a few lines).
3. **Bundle metadata**: rename app name / bundle id / URL schemes / `TERM_PROGRAM`.
4. **`MiaottyKit`**: add `miaotty/macos/MiaottyKit` as a local SPM dependency
   (one line in `macos/Ghostty.xcodeproj`).
5. **Resources**: `miaotty/resources/**` (shell + agent integration, terminfo).

## Build toolchain quirks (Xcode 26 / macOS 26)

- **Zig 0.15.2 cannot link the macOS 26 SDK.** Point zig at the 15.4 SDK via the
  `scripts/xcrun-sdk-shim` shim (prepended to `PATH`); `SDKROOT`/`--sysroot` are
  not honored for the `zig build` runner.
- The app's `xcodebuild` step needs **`xcode-select` pointing at full Xcode**
  (`DEVELOPER_DIR` is not inherited by that step) and the **Metal Toolchain**
  (`xcodebuild -downloadComponent MetalToolchain`).
- `scripts/bootstrap-ghostty.sh` wires all of the above.
