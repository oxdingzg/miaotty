# ADR 0007 — Rebrand the app to miaotty

Status: accepted. Supersedes the "keep bundle identity for now" decision in
ADR-0006 (item 4).

## Context

ADR-0006 changed only `CFBundleDisplayName` and `TERM_PROGRAM`; it deliberately
kept `CFBundleName`, the bundle id and the product name as Ghostty pending the
distribution decision. As a result the running app was still visibly Ghostty:
the menu bar, the About panel, the quit/error dialogs, default window titles and
the AppleScript dictionary all said "Ghostty", and the bundle id
`com.mitchellh.ghostty` collided with an installed upstream Ghostty (shared
LaunchServices registration).

## Decision

Make the app user-visibly and identity-wise `miaotty`:

1. `PRODUCT_NAME = miaotty` for the macOS app target. This is what drives
   `CFBundleName` (the menu-bar name); `INFOPLIST_FILE`/`CFBundleName` cannot
   override the generated value, and there is no `INFOPLIST_KEY_CFBundleName`.
2. `PRODUCT_BUNDLE_IDENTIFIER = io.miaotty.terminal` (and `.debug` for Debug).
   A distinct id removes the collision with an installed Ghostty.
3. Rebrand all user-visible strings: app menu, About panel + description +
   links, quit/execute dialogs, default window titles (`👻 Ghostty` → `miaotty`),
   settings/error/app-intent strings, and `Ghostty.sdef`.
4. Follow the new bundle name in the build: the `zig build` copy/open steps use
   `macos/build/<config>/miaotty.app`.

The executable **filename** stays `ghostty` (`EXECUTABLE_NAME`) to avoid touching
internal CLI/path references; only the bundle/product/menu identity changes.

## Consequences

- Menu bar, About, Dock/Finder, quit dialog and window titles read `miaotty`;
  `CFBundleName`/`CFBundleDisplayName`/`CFBundleIdentifier` are all miaotty.
- The build emits `zig-out/miaotty.app`; a stray upstream Ghostty can coexist.
- Still deferred (distribution-gated): the app **icon** (still the ghost), URL
  schemes, the Sparkle feed/public key, and notarization — the app is ad-hoc
  signed.

## Verified

- `vendor/ghostty/zig-out/miaotty.app/Contents/Info.plist`:
  `CFBundleName = miaotty`, `CFBundleIdentifier = io.miaotty.terminal`.
- Launching the built app: app-menu AX title = `miaotty`; About panel static
  texts = `miaotty` / `A fast, native macOS terminal built for the miao AI
  coding agent.`; app menu shows `About miaotty`, `Hide miaotty`, `Quit miaotty`.
- `miaotty-cli pane list` still returns live panes against the rebuilt app.
- Patch series (0001+0002+0003) applies cleanly on a fresh `v1.3.1` checkout.
