# ADR 0006 — Pane identity, env binding, and product identity

## Context

The first integration increment bound agents to panes only by an app-generated
UUID (external callers) or by child-PID ancestry. Agent hooks had to pass
`--pane` explicitly, and the terminal still announced itself as `ghostty`.

## Decision

1. **Core owns the pane id.** `Surface` generates a 32-hex id at creation and
   injects it into the child environment as `MIAOTTY_PANE_ID` (alongside the
   already-inherited `MIAOTTY_SOCKET`). Exposed to the app via
   `ghostty_surface_pane_id()`; the Swift glue uses it instead of a UUID.
2. **The CLI defaults `--pane` from `MIAOTTY_PANE_ID`.** Hooks need no
   arguments; the zero-install hook is now just `miaotty-cli state:<agent>`.
   PID/tty matching remains the fallback for processes outside a pane.
3. **Announce as miaotty.** `TERM_PROGRAM=miaotty` (used by miao's
   auto-enable) and `CFBundleDisplayName = miaotty` (menu bar / About).
4. **Keep bundle identity for now.** `PRODUCT_BUNDLE_IDENTIFIER`
   (`com.mitchellh.ghostty`), the `Ghostty.app` product name, and URL schemes are
   unchanged. Renaming them touches code signing, notarization, the Sparkle
   feed, AppleScript automation, and the test targets, and depends on the
   distribution decision (open question in the tech plan).
5. **Ship hooks via install-on-launch.** The app writes the agent hook scripts
   and shell env to `~/.local/share/miaotty/...` on startup (idempotent),
   avoiding changes to Ghostty's resource pipeline.

## Consequences

- Pane binding is O(1) and survives nested/short-lived processes; no PID walk on
  the hot path.
- `miaotty/resources/**` remains the canonical fallback for CLI-only users; the
  app installs equivalent scripts.
- The product is user-visibly `miaotty` while remaining a drop-in Ghostty
  build; a full rebrand is a later, distribution-gated change.

## Verified (no GUI)

- `scripts/e2e.sh`: `MIAOTTY_PANE_ID=envpane miaotty-cli state:miao …` binds to
  `envpane` without `--pane`.
- Built app `Info.plist` → `CFBundleDisplayName = miaotty`; the binary contains
  `TERM_PROGRAM=miaotty`.
- `cargo test`/`clippy`/`fmt`, `swift test` (3/3), plugin `tsc`, codegen
  reproducibility all pass.
