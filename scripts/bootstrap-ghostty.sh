#!/usr/bin/env bash
# Bootstrap the Ghostty fork and (optionally) build the macOS app.
#
#   scripts/bootstrap-ghostty.sh                    # show plan + toolchain status
#   scripts/bootstrap-ghostty.sh --apply            # install zig, clone, patch
#   scripts/bootstrap-ghostty.sh --apply --build    # ...then build the app
#   scripts/bootstrap-ghostty.sh --apply --build --universal   # arm64 + x86_64
#
# Reproduces the known-good recipe for Ghostty 1.3.1 on this machine
# (Xcode 26 / macOS 26). See miaotty/overlay/README.md for the gory details.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
TAG="v1.3.1"
ZIG_VERSION="0.15.2"
APPLY=0
BUILD=0
UNIVERSAL=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --build) APPLY=1; BUILD=1; shift ;;
    --universal) UNIVERSAL=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

ZIG_DIR="$root/miaotty/tools/zig"
ZIG="$ZIG_DIR/zig"
SHIM_DIR="$root/scripts/xcrun-sdk-shim"
DEST="$root/vendor/ghostty"
SDK="$("$SHIM_DIR/xcrun" --show-sdk-path)"

echo "upstream    : $TAG -> $DEST"
echo "zig         : $ZIG_VERSION ($ZIG_DIR)"
echo "sdk (zig)   : $SDK"
echo

echo "== toolchain =="
[ -x "$ZIG" ] && echo "  zig        : $("$ZIG" version)" || echo "  zig        : MISSING (will fetch)"
dev="$(xcode-select -p 2>/dev/null || echo none)"
echo "  xcode-select: $dev"
xcrun -f metal >/dev/null 2>&1 && echo "  metal      : present" || echo "  metal      : MISSING -> xcodebuild -downloadComponent MetalToolchain"
echo

if [ "$APPLY" -eq 0 ]; then
  echo "plan only. re-run with --apply (--build to build)."
  exit 0
fi

# 1) Zig 0.15.2
if [ ! -x "$ZIG" ]; then
  echo "== fetching zig $ZIG_VERSION =="
  mkdir -p "$ZIG_DIR"
  curl -fsSL "https://ziglang.org/download/$ZIG_VERSION/zig-aarch64-macos-$ZIG_VERSION.tar.xz" \
    | tar -xJ -C "$ZIG_DIR" --strip-components=1
fi
echo "zig: $("$ZIG" version)"

# 2) upstream checkout
if [ -d "$DEST/.git" ]; then
  echo "== upstream already present ($(git -C "$DEST" describe --tags 2>/dev/null || echo '?')) =="
else
  echo "== cloning upstream $TAG =="
  mkdir -p "$(dirname "$DEST")"
  git clone --depth 1 --branch "$TAG" https://github.com/ghostty-org/ghostty.git "$DEST"
fi

# 3) patch series
echo "== applying overlay patches =="
for p in "$root"/miaotty/overlay/patches/*.patch; do
  if git -C "$DEST" apply --reverse --check "$p" 2>/dev/null; then
    echo "  ok (already applied): $(basename "$p")"
  elif git -C "$DEST" apply --check "$p" 2>/dev/null; then
    git -C "$DEST" apply "$p"
    echo "  applied: $(basename "$p")"
  else
    echo "  SKIP (does not apply cleanly): $(basename "$p")" >&2
  fi
done

# 3b) overlay source files (new files; the app target auto-syncs Sources/)
if [ -d "$root/miaotty/overlay/macos/Sources" ]; then
  mkdir -p "$DEST/macos/Sources"
  cp -R "$root/miaotty/overlay/macos/Sources/." "$DEST/macos/Sources/"
  echo "  copied overlay sources -> macos/Sources"
fi

# 4) build
if [ "$BUILD" -eq 1 ]; then
  echo "== building (this takes a while) =="
  export PATH="$SHIM_DIR:$ZIG_DIR:$PATH"
  target=native
  [ "$UNIVERSAL" -eq 1 ] && target=universal
  ( cd "$DEST" && zig build -Doptimize=ReleaseFast -Dxcframework-target="$target" )
  echo
  echo "built: $DEST/zig-out/Ghostty.app ($target)"
  "$DEST/zig-out/Ghostty.app/Contents/MacOS/ghostty" +version | head -1
fi
