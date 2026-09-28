import { MTPClient, currentPaneID } from "./client.js";
import type { Event, TuiPlugin } from "./types.js";

const AGENT = "miao";

function sessionID(event: Event): string | undefined {
  const v = event.properties?.sessionID ?? event.properties?.session_id;
  return typeof v === "string" ? v : undefined;
}

function isBusy(event: Event): boolean {
  const status = event.properties?.status as { type?: string } | string | undefined;
  if (typeof status === "string") return status === "busy";
  return status?.type === "busy";
}

/**
 * miao **TUI** plugin: the precise state source. It runs in the TUI process,
 * which holds MIAOTTY_PANE_ID, so binding is exact (no pid walking).
 * It also contributes UI back into miao (sidebar slot / toast).
 */
export const tui: TuiPlugin = async (api) => {
  const mtp = new MTPClient();
  const pane = currentPaneID();

  const report = (state: string, event?: Event): void => {
    if (!pane) return;
    void mtp
      .stateSet({ agent: AGENT, state, pane_id: pane, session_id: event ? sessionID(event) : undefined })
      .catch(() => {});
  };

  api.event.on("session.status", (e) => report(isBusy(e) ? "processing" : "idle", e));
  api.event.on("session.idle", (e) => report("idle", e));
  api.event.on("permission.asked", (e) => report("awaiting", e));

  // Contribute a sidebar entry (host slot); the scaffold registers a no-op
  // component — wire the real pane list once the UI plane lands.
  api.slots?.register({ id: "miaotty.sidebar" });

  return Promise.resolve();
};

export default tui;
