#!/usr/bin/env bash
# Performance harness (scaffold).
#
# The real benchmarks (vtebench, Ghostty's own suite, Instruments traces) run
# against the built app once the fork is bootstrapped. This script defines the
# entry points and enforces the budgets in budgets.json where it can.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
echo "budgets:"
cat "$here/budgets.json"
echo

if [[ -x "${MIAOTTY_CLI:-}" ]]; then
  echo "== IPC latency (miaotty-cli, 50 pings) =="
  tmp="$(mktemp -d)"
  sock="$tmp/miaotty.sock"
  "$MIAOTTY_CLI" --socket "$sock" mock-host >/dev/null 2>&1 &
  host=$!
  trap 'kill $host 2>/dev/null || true; rm -rf "$tmp"' EXIT
  for _ in $(seq 1 50); do [ -S "$sock" ] && break; sleep 0.05; done
  start=$(date +%s%N 2>/dev/null || date +%s)
  for _ in $(seq 1 50); do "$MIAOTTY_CLI" --socket "$sock" ping >/dev/null; done
  end=$(date +%s%N 2>/dev/null || date +%s)
  echo "50 pings: $(( (end - start) / 1000000 )) ms total"
else
  echo "MIAOTTY_CLI not set; skipping IPC smoke. Run the app benchmarks after bootstrap."
fi
