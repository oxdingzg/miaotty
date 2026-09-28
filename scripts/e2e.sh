#!/usr/bin/env bash
# End-to-end integration spine test: Swift host  <->  Rust CLI over MTP.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

cargo build --manifest-path "$root/miaotty/cli/Cargo.toml" >/dev/null
swift build --package-path "$root/miaotty/macos/MiaottyKit" >/dev/null

CLI="$root/miaotty/cli/target/debug/miaotty-cli"
HOST="$(swift build --package-path "$root/miaotty/macos/MiaottyKit" --show-bin-path)/miaotty-host"
SOCK="$(mktemp -d)/miaotty.sock"

"$HOST" --socket "$SOCK" >/dev/null 2>&1 &
HP=$!
trap 'kill $HP 2>/dev/null || true; rm -rf "$(dirname "$SOCK")"' EXIT
for _ in $(seq 1 60); do [ -S "$SOCK" ] && break; sleep 0.05; done

fail=0
check() { # name, expected-substring, actual
  if grep -q "$2" <<<"$3"; then echo "  ok: $1"; else echo "  FAIL: $1 -> $3"; fail=1; fi
}

out="$("$CLI" --socket "$SOCK" ping)";            check "ping proto" '"proto": 1' "$out"
out="$("$CLI" --socket "$SOCK" state:miao --state processing --pane pane_3)"
                                                  check "state set revision" '"revision": 1' "$out"
out="$("$CLI" --socket "$SOCK" state list)";      check "state list" 'pane_3' "$out"
out="$("$CLI" --socket "$SOCK" state:miao --state idle --pane pane_3)"
                                                  check "state lww" '"revision": 2' "$out"
out="$("$CLI" --socket "$SOCK" state list)";      check "state lww value" '"state": "idle"' "$out"

[ "$fail" -eq 0 ] && echo "e2e OK" || { echo "e2e FAILED"; exit 1; }
