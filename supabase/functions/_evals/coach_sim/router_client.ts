// The simulator's other model calls, the athlete and the judges, over the same eval router
// (EVAL_BASE_URL, EVAL_API_KEY). They are synthetic and never reach a production path, so they
// use a plain OpenAI-compatible chat call instead of the gateway, which only knows the models in
// its price table. Cost is counted at the model's list price when the table knows it, else at an
// assumed Sonnet-class price, so the estimate never undercounts.
import type { TokenCounts } from "../../_shared/ai/models.ts";
import { normalizedModelId, priceTokens, tokensOf } from "../live_model.ts";
import { type CallSource, excerpt, headerNote, type WireError } from "./diagnostics.ts";
import { type ChatMode, defaultChatMode } from "./wire.ts";

export { type ChatMode, chatModes, defaultChatMode, describeMode, jsonObjectIn } from "./wire.ts";

export type ChatRequest = Readonly<{
  model: string;
  system: string;
  user: string;
  maxTokens: number;
  /** Ask for a JSON object (response_format json_object), when the model's mode allows it. */
  json: boolean;
  /** Who is asking, for the error log. */
  source: CallSource;
}>;

export type ChatResult =
  | Readonly<{ ok: true; text: string; model: string; tokens: TokenCounts; costUsd: number }>
  | Readonly<
    { ok: false; reason: string; costUsd: number } & WireError
  >;

export type RouterChat = (request: ChatRequest) => Promise<ChatResult>;

export type RouterChatOptions = Readonly<{
  fetcher?: typeof fetch;
  timeoutMs?: number;
  /** Wait before the first retry of a call that failed in passing (the second waits three times as long). */
  retryDelayMs?: number;
  /** The mode a model is asked in (default: JSON mode, max_tokens). */
  modeFor?: (model: string) => ChatMode;
}>;

const isClaude = (model: string) => normalizedModelId(model).startsWith("claude");
const isDeepSeek = (model: string) => model.toLowerCase().includes("deepseek");

/** A failure worth asking again: no answer, or a server or rate-limit answer. */
const worthRetrying = (failure: Extract<ChatResult, { ok: false }>) =>
  failure.kind !== "empty" && failure.kind !== "no_choices" &&
  (failure.status === null || failure.status >= 500 || failure.status === 429 ||
    failure.status === 408);

/** A chat call to the router, retried twice when it fails before an answer arrives. */
export function routerChat(
  baseUrl: string,
  apiKey: string,
  options: RouterChatOptions = {},
): RouterChat {
  const fetcher = options.fetcher ?? fetch;
  const url = `${baseUrl.replace(/\/+$/, "")}/chat/completions`;
  const fail = (
    kind: WireError["kind"],
    status: number | null,
    body: string,
    reason: string,
    costUsd = 0,
  ): Extract<ChatResult, { ok: false }> => ({
    ok: false,
    reason,
    costUsd,
    kind,
    status,
    body: excerpt(body, [apiKey]),
  });
  const once = async (request: ChatRequest): Promise<ChatResult> => {
    const mode = options.modeFor?.(request.model) ?? defaultChatMode;
    const body: Record<string, unknown> = {
      model: request.model,
      [mode.maxTokensField]: request.maxTokens,
      messages: [
        { role: "system", content: request.system },
        { role: "user", content: request.user },
      ],
    };
    // Claude 5 takes only default sampling; the others answer more steadily at a low temperature.
    if (!isClaude(request.model)) body.temperature = 0.3;
    // A reasoning model spends the output budget thinking and can return an empty answer.
    if (isDeepSeek(request.model)) body.reasoning_effort = "none";
    if (request.json && mode.responseFormat) body.response_format = { type: "json_object" };
    let response: Response;
    try {
      response = await fetcher(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(options.timeoutMs ?? 120_000),
      });
    } catch (error) {
      const timedOut = error instanceof Error && error.name === "TimeoutError";
      return fail(
        timedOut ? "timeout" : "network",
        null,
        error instanceof Error ? `${error.name}: ${error.message}` : "network",
        error instanceof Error ? error.name : "network",
      );
    }
    if (!response.ok) {
      const text = await response.text().catch(() => "");
      return fail(
        "http",
        response.status,
        `${headerNote(response.headers)}${text}`,
        `http ${response.status}`,
      );
    }
    let raw = "";
    let payload: Record<string, unknown>;
    try {
      raw = await response.text();
      payload = JSON.parse(raw);
    } catch {
      return fail("unreadable", response.status, raw, "unreadable answer");
    }
    const tokens = tokensOf((payload.usage ?? {}) as Record<string, unknown>);
    const costUsd = priceTokens(request.model, tokens).usd;
    const choice = Array.isArray(payload.choices)
      ? payload.choices[0] as Record<string, unknown> | undefined
      : undefined;
    if (!choice) {
      return fail("no_choices", response.status, raw, "no choices in the answer", costUsd);
    }
    const text = (choice.message as Record<string, unknown> | undefined)?.content;
    if (typeof text !== "string" || text.trim() === "") {
      return fail(
        "empty",
        response.status,
        `empty content; finish_reason=${
          String(choice.finish_reason)
        } completion_tokens=${tokens.outputTokens} max_tokens=${request.maxTokens}`,
        "empty answer",
        costUsd,
      );
    }
    return {
      ok: true,
      text,
      model: typeof payload.model === "string" ? payload.model : request.model,
      tokens,
      costUsd,
    };
  };
  return async (request) => {
    // Two retries, after the delay and three times it, of a call the router failed in passing.
    const delay = options.retryDelayMs ?? 3_000;
    let spent = 0;
    for (let attempt = 0;; attempt++) {
      const result = await once(request);
      if (result.ok) return result;
      spent += result.costUsd;
      if (attempt >= 2 || !worthRetrying(result)) return { ...result, costUsd: spent };
      await new Promise((resolve) => setTimeout(resolve, attempt === 0 ? delay : delay * 3));
    }
  };
}

/**
 * The first model in `preferences` the router lists (matched like the gateway route's model),
 * skipping any in `exclude`; when the router could not list its models, the first preference not
 * excluded. Null when nothing fits.
 */
export function pickModel(
  available: readonly string[],
  preferences: readonly string[],
  exclude: readonly string[],
): string | null {
  const excluded = new Set(exclude.map(normalizedModelId));
  const allowed = (id: string) => !excluded.has(normalizedModelId(id));
  if (available.length === 0) return preferences.find(allowed) ?? null;
  const usable = available.filter(allowed);
  for (const wanted of preferences) {
    const target = normalizedModelId(wanted);
    const found = usable.find((id) => normalizedModelId(id) === target) ??
      usable.find((id) => normalizedModelId(id).endsWith(target)) ??
      usable.find((id) => normalizedModelId(id).startsWith(target));
    if (found) return found;
  }
  return null;
}

/** Judges: a strong model, never the Coach's own. */
export const judgePreferences: readonly string[] = [
  "claude-sonnet-5-5",
  "claude-opus-5-5",
  "gpt-5",
  "gemini-3.5-pro",
  "gemini-3-pro",
  "deepseek-v4-pro",
  "qwen3.8",
  "deepseek-v4-flash",
];

/** The athlete: a cheap model that writes natural messages, preferably not the Coach's. */
export const athletePreferences: readonly string[] = [
  "deepseek-v4-flash",
  "gemini-3.5-flash",
  "qwen3.8",
  "gpt-5-mini",
  "claude-haiku-5-5",
];
