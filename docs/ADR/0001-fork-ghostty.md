# ADR 0001 — Fork Ghostty with an additive overlay

## Context

miaotty needs a native macOS terminal: Metal rendering, a fast VT state machine,
PTY handling, shell integration, terminfo, AppleScript, auto-update. Building all
of that from scratch is a multi-year effort; the differentiators we actually
want (agent-aware UI, a control plane, an IDE-ish sidebar) are a small layer on
top.

## Decision

Fork [Ghostty](https://ghostty.org) (MIT) and make **additive-only** changes:

- Our code lives under `miaotty/` (Swift `MiaottyKit`, Rust `miaotty-cli`, TS
  `@miao/miaotty`, resources, proto).
- **Internal upstream symbols, file names and crate names stay untouched.** Only
  user-facing identity is renamed (app name, bundle id, URL schemes,
  `TERM_PROGRAM`, env-var prefix). This keeps upstream merges cheap.
- A small, fixed set of patch points inside the checkout:
  1. expose `ghostty_surface_child_pid()` + pane metadata (read-only C API),
  2. an app-startup hook that installs the MTP host,
  3. `Info.plist` / bundle metadata.

## Consequences

- We inherit Ghostty's performance ceiling and its fast-moving upstream. We pin
  a release tag (1.3.1) and track `ghostty-org/ghostty` as `upstream`.
- Self-hosted components (IPC, badges, sidebar, editor) must not enter the
  `input → pty → vt → metal` hot path (see ADR 0003 and the performance budget).
- The pbxproj is the riskiest file to touch, so our Swift lives in a local SPM
  package (`MiaottyKit`) with a single dependency line in the project.
- We must never copy Otty's proprietary scripts/HTML; OSC codes are public.

## Bootstrap

`scripts/bootstrap-ghostty.sh` (plan by default; `--apply` to clone, `--build`
to build). Building the app additionally needs Zig 0.15.2, full Xcode selected,
and the Metal toolchain — the scaffold (proto/cli/MiaottyKit/plugin) builds
without them.
