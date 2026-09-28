# Agent integration

Hooks that report agent state to miaotty over MTP. Two paths:

1. **With the `@miao/miaotty` plugin** (preferred): the plugin reports state from
   inside the agent process, with exact pane binding via `MIAOTTY_PANE_ID`.
2. **Zero-install fallback** (this directory): a shell hook calls `miaotty-cli`
   when the agent has no plugin, or the plugin failed to load.

Both paths go through the same MTP method (`agent.state.set`), so the terminal
side does not care which one is active.

## Resolution order (design: state plane)

`MIAOTTY_PANE_ID` env → `--tty` match → `agent_pid` parent-chain lookup → drop
(`no_pane`, recorded as an event but not badged).

## Hooks

| Agent | File | Wire it via |
|-------|------|-------------|
| miao | `miao/hook.sh` | `.miao/plugins/miaotty` or a session hook |
| claude | `claude/hook.sh` | Claude Code hooks (Stop / Notification / PreToolUse) |
| codex | `codex/hook.sh` | codex hook config |
| opencode | `opencode/hook.sh` | plugin `event` hook |

Generic usage:

```sh
hook.sh processing
hook.sh idle ses_abc
hook.sh awaiting ses_abc
```
