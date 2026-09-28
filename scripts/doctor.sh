#!/usr/bin/env bash
# Environment/toolchain checks for building miaotty.
set -uo pipefail

green() { printf '\033[32m%s\033[0m\n' "$1"; }
red()   { printf '\033[31m%s\033[0m\n' "$1"; }
warn()  { printf '\033[33m%s\033[0m\n' "$1"; }

status=0
need() { command -v "$1" >/dev/null 2>&1 && green "ok   $1 ($($1 --version 2>&1 | head -1))" || { red "MISS $1"; status=1; }; }
want() { command -v "$1" >/dev/null 2>&1 && green "ok   $1" || warn "opt  $1 missing"; }

echo "== spine toolchain =="
need cargo
need swift
need bun
want gh

echo
echo "== fork toolchain (needed only to build the app) =="
if command -v zig >/dev/null 2>&1; then
  zv="$(zig version)"
  if [ "$zv" = "0.15.2" ]; then green "ok   zig 0.15.2"; else warn "zig $zv (Ghostty 1.3.x needs 0.15.2)"; fi
else
  red "MISS zig (needs 0.15.2)"
fi

dev="$(xcode-select -p 2>/dev/null || true)"
if [[ "$dev" == *Xcode.app* ]]; then green "ok   xcode-select -> $dev"; else warn "xcode-select -> $dev (app build needs full Xcode)"; fi
if xcrun -f metal >/dev/null 2>&1; then green "ok   metal toolchain"; else warn "metal toolchain missing (Xcode > Settings > Components)"; fi

echo
[ "$status" -eq 0 ] && green "spine requirements satisfied" || red "missing required tools"
exit "$status"
