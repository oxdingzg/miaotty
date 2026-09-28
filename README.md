# miaotty

A fast, native macOS terminal built for the `miao` AI coding agent — and for any agent.

> `miaotty` = `miao` + `tty`. Open source (MIT), forked from [Ghostty](https://ghostty.org) for the
> terminal core (Metal renderer, VT, PTY, shell integration), extended with a control/agent layer.

## Status

Scaffold + **working Ghostty fork build**.

- The Ghostty fork **builds on this machine**: `zig build -Doptimize=ReleaseFast
  -Dxcframework-target=native` → `vendor/ghostty/zig-out/miaotty.app` (arm64,
  ReleaseFast, Metal). See `docs/ADR/0004-xcode26-build.md` for the Xcode 26 /
  macOS 26 workarounds and `scripts/bootstrap-ghostty.sh` to reproduce.
- The **badge spine runs inside the app** (`docs/ADR/0005-app-integration.md`):
  `miaotty-cli pane list` returns live panes + child PIDs, and `state set` drives
  an on-pane agent badge (processing / awaiting / error / idle).
- **Pane identity & env binding** (`docs/ADR/0006-identity-and-env-binding.md`):
  the core generates a pane id and injects `MIAOTTY_PANE_ID` at spawn; the CLI
  defaults `--pane` from it; the app announces `TERM_PROGRAM=miaotty` and
  installs agent hooks under `~/.local/share/miaotty/` on launch.
- The **integration spine** is implemented and verified end-to-end:
  - **MTP** (Miaotty Terminal Protocol) — one versioned, capability-negotiated contract for the
    state / context / control / UI planes. Single JSON-Schema source, codegen for Rust, Swift, TS.
  - **`miaotty-cli`** (Rust) — control CLI, including a dev `mock-host`.
  - **`MiaottyKit`** (Swift) — the in-app host: MTP server, agent-state registry, extension points.
  - **`@miao/miaotty`** (TS) — miao plugin (server + TUI entries).
  - shell / agent integration resources, performance budgets and gates.

## Layout

```
miaotty/
├── proto/            MTP schema (single source of truth) + codegen
├── cli/              Rust workspace: `mtp` crate + `miaotty-cli`
├── macos/MiaottyKit/ Swift package: host, registry, extension points
├── plugin/           @miao/miaotty (miao integration)
├── resources/        shell-integration + agent-integration
├── bench/            performance budgets + harness
└── scripts/          bootstrap, build, doctor, codegen
docs/                 ADRs (public) and private design docs (gitignored)
```

## Quick start (spine only)

```sh
# 1) generate protocol types (Rust/Swift/TS) from proto/mtp.schema.json
scripts/codegen.sh

# 2) build + test the Rust CLI
cd miaotty/cli && cargo test && cargo build

# 3) build the Swift host (needs Xcode)
swift build --package-path miaotty/macos/MiaottyKit

# 4) end-to-end: start the dev host, then talk to it
miaotty/cli/target/debug/miaotty-cli mock-host &      # or: swift run --package-path ... miaotty-host
miaotty/cli/target/debug/miaotty-cli ping
miaotty/cli/target/debug/miaotty-cli state set --agent miao --state processing --pane pane_1
miaotty/cli/target/debug/miaotty-cli state list
```

## Principles

1. **Performance first** — everything we add lives off the `input → pty → vt → metal` hot path.
2. **Fork additive** — internal upstream symbols stay untouched; our code lives under `miaotty/` and a
   few clearly-marked patch points.
3. **Contract first** — implementations (plugin / CLI / in-process) can change; MTP does not.
4. **Fail open** — terminal never depends on an agent; AI off ⇒ performance equals Ghostty.

See `docs/ADR/` for decisions and `docs/private/` (local only) for the full design set.
