/**
 * @miao/miaotty — miao ↔ miaotty integration.
 *
 * miao loads server and TUI plugins as separate entries:
 *   - `./server` — terminal tools + context injection (server process)
 *   - `./tui`    — precise pane binding + UI contributions (TUI process)
 *
 * Zero-install fallback: hooks under `resources/agent-integration/miao/` call
 * `miaotty-cli state:miao …` directly when this package is not installed.
 */
export { server } from "./server.js";
export { tui } from "./tui.js";
export { MTPClient, defaultSocket, currentPaneID } from "./client.js";
