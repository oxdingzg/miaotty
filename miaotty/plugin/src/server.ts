import { MTPClient, currentPaneID, defaultSocket } from "./client.js";
import type { Hooks, Plugin } from "./types.js";

const AGENT = "miao";

function sessionID(event: { properties?: Record<string, unknown> }): string | undefined {
  const v = event.properties?.sessionID ?? event.properties?.session_id;
  return typeof v === "string" ? v : undefined;
}

/**
 * miao **server** plugin: registers terminal tools + injects terminal context.
 * Runs in the miao server process; pane binding still comes from the pane
 * environment when available (the TUI plugin is the precise source).
 */
export const server: Plugin = async (): Promise<Hooks> => {
  const mtp = new MTPClient();
  const pane = currentPaneID();

  return {
    // Keep miao's own shells aware of the terminal's MTP endpoint.
    "shell.env": async (_input, output) => {
      if (process.env.MIAOTTY_SOCKET) output.env.MIAOTTY_SOCKET = process.env.MIAOTTY_SOCKET;
      if (pane) output.env.MIAOTTY_PANE_ID = pane;
    },

    // Tell the model it can act on the terminal.
    "experimental.chat.system.transform": async (_input, output) => {
      if (!pane) return;
      output.system.push(
        `You are running inside miaotty (pane ${pane}). ` +
          `Use the terminal_context / terminal_action tools to read and control the terminal.`,
      );
    },

    tool: {
      terminal_context: {
        description: "Read the current pane's bounded context (cwd, selection, git, screen tail).",
        args: {},
        async execute() {
          if (!pane) return { available: false, reason: "not in a miaotty pane" };
          try {
            return await mtp.call("context", "get", { pane_id: pane });
          } catch (e) {
            return { available: false, reason: String((e as { message?: string })?.message ?? e) };
          }
        },
      },
      terminal_action: {
        description: "Invoke a terminal action (open_file, split, send, run, notify, jump).",
        args: { action: "string", args: "object" },
        async execute(args) {
          if (!pane) return { ok: false, reason: "not in a miaotty pane" };
          try {
            return await mtp.call("action", "invoke", { id: String(args.action), args: args.args ?? {}, pane_id: pane });
          } catch (e) {
            return { ok: false, reason: String((e as { message?: string })?.message ?? e) };
          }
        },
      },
    },

    event: async ({ event }) => {
      if (!pane) return;
      if (event.type === "permission.asked") {
        await mtp
          .stateSet({ agent: AGENT, state: "awaiting", pane_id: pane, session_id: sessionID(event) })
          .catch(() => {});
      }
    },
  };
};

export default server;
export { defaultSocket };
