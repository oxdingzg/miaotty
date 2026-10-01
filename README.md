# miaotty

> [!IMPORTANT]
> **A personal, temporary tool — not maintained. Use [mtty](https://mtty.dev/mtty) instead.**
>
> miaotty was a personal macOS prototype built to try out an agent-aware terminal for
> [miao](https://mtty.dev/miao). That work continues as **mtty**, a cross-platform terminal
> (macOS, Linux, Windows) written in Rust:
>
> - Website: <https://mtty.dev/mtty> · Docs: <https://mtty.dev/docs/mtty>
> - Source and releases: [oxdingzg/miao-term](https://github.com/oxdingzg/miao-term)
>
> This repository is kept only for reference. It gets no fixes, releases or support, and
> its build depends on the author's own machine setup. (mtty itself was also called
> `miaotty` up to v0.0.5; that is the miao-term application, not this repository.)
>
> The text below is the prototype's original README.


A fast, native macOS terminal built for the `miao` AI coding agent — and for any agent.

> `miaotty` = `miao` + `tty`. Open source (MIT), forked from [Ghostty](https://ghostty.org) for the
> terminal core (Metal renderer, VT, PTY, shell integration), extended with a control/agent layer.

[English](README.md) · [中文](README.zh-CN.md)

## Status

Scaffold + **working Ghostty fork build**.

- The Ghostty fork **builds on this machine**: `zig build -Doptimize=ReleaseFast
  -Dxcframework-target=native` → `vendor/ghostty/zig-out/miaotty.app` (arm64,
  ReleaseFast, Metal). See `docs/ARCHITECTURE.md` §4.1 for the Xcode 26 /
  macOS 26 workarounds and `scripts/bootstrap-ghostty.sh` to reproduce.
- The **badge spine runs inside the app** (`docs/ARCHITECTURE.md` §4.2):
  `miaotty-cli pane list` returns live panes + child PIDs, and `state set` drives
  an on-pane agent badge (processing / awaiting / error / idle).
- **Pane identity & env binding** (`docs/ARCHITECTURE.md` §4.3):
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
├── overlay/          additive Ghostty fork glue: tracked patch series + Swift UI
├── plugin/           @miao/miaotty (miao integration)
├── resources/        shell-integration + agent-integration
├── bench/            performance budgets + harness
└── tools/            local toolchain (zig; fetched by bootstrap, gitignored)
scripts/              bootstrap, build, doctor, codegen, e2e
docs/                 Architecture doc (public); design docs live in docs/private/ (local)
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

See `docs/ARCHITECTURE.md` for decisions and `docs/private/` (local only) for the full design set.

## License

MIT — see [`LICENSE`](./LICENSE). The terminal core is forked from
[Ghostty](https://ghostty.org) (MIT). The patched zsh integration is derived
from [Kitty](https://sw.kovidgoyal.net/kitty/) and remains GPLv3 (see
`docs/ARCHITECTURE.md` §4.4).
