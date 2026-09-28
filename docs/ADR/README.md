# Architecture Decision Records

Public, durable decisions for miaotty. Private/design-context material lives in
`docs/private/` (gitignored).

| ADR | Title | Status |
|-----|-------|--------|
| [0001](./0001-fork-ghostty.md) | Fork Ghostty with an additive overlay | accepted |
| [0002](./0002-mtp-protocol.md) | MTP: one contract, many transports | accepted |
| [0003](./0003-thread-model-baseline.md) | Baseline Ghostty's thread model before touching hot paths | accepted |
| [0004](./0004-xcode26-build.md) | Build Ghostty 1.3.1 on Xcode 26 / macOS 26 (sdk shim, ranlib patch, toolchain) | accepted |
| [0005](./0005-app-integration.md) | Wire the integration spine into the app (child-pid C API, host hook, SPM, badge) | accepted |
| [0006](./0006-identity-and-env-binding.md) | Pane identity, `MIAOTTY_PANE_ID` env binding, and product identity | accepted |

Format: context → decision → consequences. Keep ADRs short and append-only;
supersede rather than rewrite.
