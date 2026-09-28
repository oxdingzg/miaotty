# ADR 0004 — Building Ghostty 1.3.1 on Xcode 26 / macOS 26

## Context

Ghostty 1.3.1 predates Xcode 26. Building it on this machine surfaced three
independent blockers, none of them miaotty's fault:

1. **Zig 0.15.2 cannot link the macOS 26 SDK.** The build runner fails with
   undefined `__availability_version_check` and libSystem symbols. Pointing zig
   at the macOS 15.4 SDK fixes it, but `SDKROOT` and `--sysroot` are not honored
   for the `zig build` runner — only the SDK that `xcrun --show-sdk-path`
   reports.
2. **The Metal Toolchain is a separate Xcode component** and must be installed
   (`xcodebuild -downloadComponent MetalToolchain`); the `metal` binary in the
   default toolchain is a stub until then.
3. **Apple `libtool` silently drops archive members** produced by Zig 0.15.2.
   The Zig core object and C++ deps (imgui, oniguruma) vanish during the
   `libtool -static` merge, so the app links with undefined `ghostty_*` / C++
   symbols. Rewriting each archive's index with `ranlib` before the merge fixes
   it (`scripts/…` and overlay patch 0001).

Additionally, the app's `xcodebuild` step does not inherit `DEVELOPER_DIR`, so
`xcode-select` must point at full Xcode.

## Decision

Reproduce the build with a tracked recipe rather than tribal knowledge:

- `scripts/xcrun-sdk-shim/xcrun` — forces the macOS 15.4 SDK for zig.
- `miaotty/overlay/patches/0001-xcode26-libtool-ranlib.patch` — ranlib the
  libtool inputs.
- `scripts/bootstrap-ghostty.sh` — installs Zig 0.15.2, clones the pinned tag,
  applies patches, and builds (`-Dxcframework-target=native` by default; the
  universal build additionally needs the x86_64 slice to link cleanly, which the
  ranlib patch now covers).

## Consequences

- The fork stays additive: exactly one upstream file (`src/build/LibtoolStep.zig`)
  is patched. The patch is a genuine upstream fix candidate (Xcode 26 +
  Zig 0.15.2 interop) and we should consider proposing it upstream.
- The build is not "just `zig build`": it needs the shim + system `xcode-select`
  + Metal Toolchain. CI/documentation must encode this.
- When upstream moves to a Zig version that writes libtool-compatible archives,
  patch 0001 becomes unnecessary.

## Verified

`zig build -Doptimize=ReleaseFast -Dxcframework-target=native` produced
`vendor/ghostty/zig-out/Ghostty.app` (arm64, ReleaseFast, Metal renderer),
reporting `Ghostty 1.3.1`.
