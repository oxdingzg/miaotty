#!/bin/sh
# Report codex agent state to miaotty (zero-install fallback).
# Usage: hook.sh <processing|idle|awaiting|error> [session-id]
set -eu
state="${1:-}"
[ -n "$state" ] || { echo "usage: $0 <state> [session-id]" >&2; exit 2; }
session="${2:-}"
exe="${MIAOTTY_CLI:-miaotty-cli}"
command -v "$exe" >/dev/null 2>&1 || exit 0

set -- state:codex --state "$state"
[ -n "$session" ] && set -- "$@" --session "$session"
[ -n "${MIAOTTY_PANE_ID:-}" ] && set -- "$@" --pane "$MIAOTTY_PANE_ID"

"$exe" "$@" >/dev/null 2>&1 || true
