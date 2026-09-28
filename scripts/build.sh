#!/usr/bin/env bash
# Build every scaffold component that does not need the Ghostty fork.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"

echo "== codegen =="
"$root/scripts/codegen.sh"

echo "== rust (mtp + miaotty-cli) =="
cargo build --manifest-path "$root/miaotty/cli/Cargo.toml"

echo "== swift (MiaottyKit) =="
swift build --package-path "$root/miaotty/macos/MiaottyKit"

echo "== miao plugin =="
( cd "$root/miaotty/plugin" && bun install --frozen-lockfile 2>/dev/null || bun install; bun run typecheck )

echo "build OK"
