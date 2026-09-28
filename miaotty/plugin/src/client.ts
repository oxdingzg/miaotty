import net from "node:net";
import os from "node:os";
import path from "node:path";

import type { Capability, Role } from "./protocol.js";

/** Resolve the host socket: $MIAOTTY_SOCKET, else $TMPDIR/miaotty.sock. */
export function defaultSocket(): string {
  return process.env.MIAOTTY_SOCKET ?? path.join(os.tmpdir(), "miaotty.sock");
}

/** The pane this process runs in, injected by miaotty (O(1) binding). */
export function currentPaneID(): string | undefined {
  return process.env.MIAOTTY_PANE_ID || undefined;
}

export interface MTPError {
  code: string;
  message: string;
  retryable: boolean;
}

/** Fire-and-forget MTP client with a single persistent connection. */
export class MTPClient {
  private socket: net.Socket | undefined;
  private buffer = "";
  private nextId = 1;
  private pending = new Map<number, { resolve: (v: unknown) => void; reject: (e: MTPError) => void }>();

  constructor(
    private readonly socketPath: string = defaultSocket(),
    private readonly timeoutMs = 3000,
  ) {}

  private connect(): net.Socket {
    if (this.socket && !this.socket.destroyed) return this.socket;
    const socket = net.createConnection({ path: this.socketPath });
    socket.setEncoding("utf8");
    socket.on("data", (chunk: string) => this.onData(chunk));
    socket.on("error", () => this.failAll({ code: "timeout", message: "socket error", retryable: true }));
    socket.on("close", () => {
      this.socket = undefined;
      this.failAll({ code: "timeout", message: "connection closed", retryable: true });
    });
    this.socket = socket;
    return socket;
  }

  private onData(chunk: string): void {
    this.buffer += chunk;
    let idx: number;
    while ((idx = this.buffer.indexOf("\n")) >= 0) {
      const line = this.buffer.slice(0, idx);
      this.buffer = this.buffer.slice(idx + 1);
      if (!line) continue;
      try {
        const msg = JSON.parse(line) as { kind?: string; id?: number; ok?: boolean; result?: unknown; error?: MTPError };
        if (msg.kind === "evt") continue;
        if (typeof msg.id === "number") {
          const waiter = this.pending.get(msg.id);
          if (!waiter) continue;
          this.pending.delete(msg.id);
          if (msg.ok) waiter.resolve(msg.result);
          else waiter.reject(msg.error ?? { code: "internal", message: "unknown", retryable: false });
        }
      } catch {
        // ignore malformed frame
      }
    }
  }

  private failAll(error: MTPError): void {
    for (const waiter of this.pending.values()) waiter.reject(error);
    this.pending.clear();
  }

  call(ns: string, method: string, params: Record<string, unknown> = {}): Promise<unknown> {
    const id = this.nextId++;
    const frame = JSON.stringify({
      v: 1,
      id,
      kind: "req",
      ns,
      method,
      params,
      role: "client" satisfies Role,
      ts: Date.now(),
    });
    return new Promise<unknown>((resolve, reject) => {
      const timer = setTimeout(() => {
        if (this.pending.delete(id)) reject({ code: "timeout", message: `${ns}.${method} timed out`, retryable: true });
      }, this.timeoutMs);
      const done = (fn: () => void) => {
        clearTimeout(timer);
        fn();
      };
      this.pending.set(id, {
        resolve: (v) => done(() => resolve(v)),
        reject: (e) => done(() => reject(e)),
      });
      try {
        this.connect().write(frame + "\n");
      } catch (e) {
        this.pending.delete(id);
        done(() => reject({ code: "timeout", message: String(e), retryable: true }));
      }
    });
  }

  async stateSet(params: {
    agent: string;
    state: string;
    pane_id?: string;
    session_id?: string;
    cwd?: string;
    tty?: string;
    agent_pid?: number;
    bypass?: boolean;
    error_kind?: string;
    title?: string;
  }): Promise<unknown> {
    return this.call("agent", "state.set", params as Record<string, unknown>);
  }

  close(): void {
    this.socket?.destroy();
    this.socket = undefined;
  }
}

export type { Capability };
