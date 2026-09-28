/**
 * Minimal, duck-typed views of the miao plugin API.
 *
 * TODO: replace with the real types from `@opencode-ai/plugin` once this package
 * is built inside the miao workspace. We keep local shapes so the scaffold
 * compiles and typechecks standalone.
 */

export interface Event {
  type: string;
  properties?: Record<string, unknown>;
}

export interface ToolDefinition {
  description?: string;
  args?: Record<string, unknown>;
  execute(args: Record<string, unknown>, ctx?: unknown): Promise<unknown>;
}

export interface PluginInput {
  client?: unknown;
  directory?: string;
  worktree?: string;
}

export interface Hooks {
  event?: (input: { event: Event }) => Promise<void>;
  tool?: Record<string, ToolDefinition>;
  "shell.env"?: (
    input: { cwd: string; sessionID?: string },
    output: { env: Record<string, string> },
  ) => Promise<void>;
  "permission.ask"?: (input: unknown, output: { status: "ask" | "deny" | "allow" }) => Promise<void>;
  "experimental.chat.system.transform"?: (
    input: { sessionID?: string },
    output: { system: string[] },
  ) => Promise<void>;
}

export type Plugin = (input: PluginInput) => Promise<Hooks>;

export interface TuiEventBus {
  on(type: string, handler: (event: Event) => void): () => void;
}

export interface TuiPluginApi {
  app: { version: string };
  event: TuiEventBus;
  client: unknown;
  ui?: {
    toast?: (input: { message: string; variant?: string }) => void;
  };
  slots?: { register(plugin: unknown): string };
  route?: { register(routes: unknown[]): () => void; navigate(name: string, params?: Record<string, unknown>): void };
}

export type TuiPlugin = (
  api: TuiPluginApi,
  options?: unknown,
  meta?: unknown,
) => Promise<void>;
