#!/usr/bin/env bash
# Regenerate MTP types (Rust/Swift/TS) from proto/mtp.schema.json.
# The generated Rust is rustfmt'd here so codegen output stays canonical and
# `cargo fmt --check` / the CI drift check both pass.
set -euo pipefail
root="$(cd "$(dirname "$0")/.." && pwd)"
command -v bun >/dev/null || { echo "bun is required" >&2; exit 1; }
bun "$root/miaotty/proto/codegen.ts"
if command -v rustfmt >/dev/null 2>&1; then
  rustfmt --edition 2021 "$root/miaotty/cli/crates/mtp/src/types.rs"
fi
