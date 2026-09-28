# Shell integration

miaotty reuses the terminal core's (Ghostty's) shell integration for OSC
133/7/9;4 prompt marking, cwd reporting and progress. This directory holds only
the miaotty-specific additions.

The app injects these into every pane's environment (see `PaneEnv`):

| Variable | Purpose |
|----------|---------|
| `MIAOTTY_SOCKET` | MTP host socket path |
| `MIAOTTY_PANE_ID` | stable id of this pane (exact agent binding) |
| `MIAOTTY_PROTO` | MTP protocol version |

`miaotty-env.sh` documents the contract and provides a best-effort `miaotty`
wrapper for `state`/`view`/`edit` subcommands. It is intentionally tiny: the
real prompt/title work stays in the core integration.
