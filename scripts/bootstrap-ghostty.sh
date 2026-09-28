#!/usr/bin/env bash
# Bootstrap the Ghostty fork (the heavy, gated step).
#
# Nothing here runs destructively by default: it prints a plan. Pass --apply to
# actually clone/update the upstream checkout, and --build to attempt a build.
#
#   scripts/bootstrap-ghostty.sh                 # show plan + toolchain status
#   scripts/bootstrap-ghostty.sh --apply         # clone/update vendor/ghostty
#   scripts/bootstrap-ghostty.sh --apply --build # also build (needs Xcode+Zig)
#
# Requires (only for --build): Zig 0.15.2, full Xcode selected, Metal toolchain.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
TAG="1.3.1"
APPLY=0
BUILD=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tag) TAG="$2"; shift 2 ;;
    --apply) APPLY=1; shift ;;
    --build) BUILD=1; shift ;;
    *) echo "unknown arg: $1" >&2; exit 2 ;;
  esac
done

dest="$root/vendor/ghostty"
echo "upstream tag : $TAG"
echo "checkout     : $dest"
echo "overlay      : miaotty/ (cmake/patch points applied inside the checkout)"
echo

echo "== toolchain =="
zigv="$(zig version 2>/dev/null || echo none)"
echo "  zig     : $zigv   (need 0.15.2 for Ghostty 1.3.x)"
echo "  xcode   : $(xcode-select -p 2>/dev/null || echo none)"
xcrun -f metal >/dev/null 2>&1 && echo "  metal   : present" || echo "  metal   : MISSING (Xcode > Settings > Components)"
echo

if [ "$zigv" != "0.15.2" ]; then
  echo "NOTE: install Zig 0.15.2, e.g."
  echo "  curl -LO https://ziglang.org/download/0.15.2/zig-macos-aarch64-0.15.2.tar.xz"
  echo "  mkdir -p $root/miaotty/tools/zig && tar -xJf zig-macos-aarch64-0.15.2.tar.xz -C $root/miaotty/tools/zig --strip-components=1"
  echo
fi

if [ "$APPLY" -eq 0 ]; then
  echo "plan only. re-run with --apply to clone/update."
  exit 0
fi

if [ -d "$dest/.git" ]; then
  echo "== updating upstream =="
  git -C "$dest" fetch --tags origin
  git -C "$dest" checkout "$TAG"
else
  echo "== cloning upstream =="
  mkdir -p "$(dirname "$dest")"
  git clone --depth 1 --branch "$TAG" https://github.com/ghostty-org/ghostty.git "$dest"
fi
echo "upstream ready at $dest ($TAG)"
echo
echo "NEXT (manual, by design — see docs/ADR/0001-fork-ghostty.md):"
echo "  1. apply the overlay: copy miaotty/macos/MiaottyKit into the checkout, add"
echo "     the SPM dependency + the 4 patch points (child_pid C API, app hook, plist)."
echo "  2. switch Xcode:  sudo xcode-select --switch /Applications/Xcode.app"
echo "  3. build:  zig build -Doptimize=ReleaseFast"

if [ "$BUILD" -eq 1 ]; then
  echo
  echo "== building =="
  ( cd "$dest" && zig build -Doptimize=ReleaseFast )
  echo "built: $dest/zig-out/Ghostty.app"
fi
