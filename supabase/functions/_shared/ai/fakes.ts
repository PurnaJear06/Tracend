// Test helpers for the AI gateway: settings, a recording fake fetch and log capture. No test
// touches the network.

import { type Env, route } from "./routes.ts";
import type { AiFeature, AiRoute } from "./types.ts";

export const syntheticKey = "synthetic-test-key";

export const envOf = (values: Record<string, string>): Env => (name) =>
  Object.hasOwn(values, name) ? values[name] : undefined;

/** Complete settings for one feature; values override or (with "") remove a setting. */
export function settings(
  feature: AiFeature,
  values: Record<string, string> = {},
): Record<string, string> {
  const prefix = `AI_${feature.toUpperCase()}_`;
  const base: Record<string, string> = {
    [`${prefix}PROVIDER`]: "anthropic",
    [`${prefix}MODEL`]: "claude-sonnet-5-5",
    [`${prefix}MAX_OUTPUT_TOKENS`]: "2000",
    [`${prefix}TIMEOUT_MS`]: "20000",
    ANTHROPIC_API_KEY: syntheticKey,
  };
  for (const [name, value] of Object.entries(values)) {
    const key = name.startsWith("AI_") || name.includes("API_KEY") || name.startsWith("GEMINI_")
      ? name
      : `${prefix}${name}`;
    if (value === "") delete base[key];
    else base[key] = value;
  }
  return base;
}

/** A route built by route(), so the gateway can find its key. */
export function routeFor(feature: AiFeature, values: Record<string, string> = {}): AiRoute {
  const result = route(feature, envOf(settings(feature, values)));
  if (!result) throw new Error("test settings did not make a route");
  return result;
}

export type Sent = Readonly<{
  url: string;
  headers: Record<string, string>;
  body: Record<string, unknown>;
  signal: AbortSignal | null;
}>;

export function fakeFetch(
  respond: (sent: Sent) => Response | Promise<Response>,
): { fetch: typeof fetch; sent: Sent[] } {
  const sent: Sent[] = [];
  const fetcher = (input: string | URL | Request, init?: RequestInit) => {
    const request: Sent = {
      url: String(input),
      headers: { ...(init?.headers as Record<string, string>) },
      body: JSON.parse(String(init?.body)),
      signal: init?.signal ?? null,
    };
    sent.push(request);
    return Promise.resolve(respond(request));
  };
  return { fetch: fetcher as typeof fetch, sent };
}

export const jsonResponse = (body: unknown, status = 200, headers: Record<string, string> = {}) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json", ...headers },
  });

/** A Claude Messages API answer. */
export function claudeMessage(
  overrides: Record<string, unknown> = {},
  usage: Record<string, unknown> = {},
): Record<string, unknown> {
  return {
    id: "msg_synthetic",
    type: "message",
    role: "assistant",
    model: "claude-sonnet-5-5",
    content: [{ type: "text", text: "Keep today's plan." }],
    stop_reason: "end_turn",
    usage: {
      input_tokens: 1000,
      output_tokens: 200,
      cache_read_input_tokens: 0,
      cache_creation_input_tokens: 0,
      ...usage,
    },
    ...overrides,
  };
}

/** Runs fn with console output captured; returns the lines it wrote. */
export async function captureLogs<T>(
  fn: () => Promise<T>,
): Promise<{ result: T; lines: string[] }> {
  const lines: string[] = [];
  const saved = {
    log: console.log,
    warn: console.warn,
    error: console.error,
    debug: console.debug,
  };
  const capture = (...args: unknown[]) => {
    lines.push(args.map(String).join(" "));
  };
  console.log = capture;
  console.warn = capture;
  console.error = capture;
  console.debug = capture;
  try {
    return { result: await fn(), lines };
  } finally {
    Object.assign(console, saved);
  }
}
