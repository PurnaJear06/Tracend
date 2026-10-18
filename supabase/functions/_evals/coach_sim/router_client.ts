// The simulator's other model calls, the athlete and the judges, over the same eval router
// (EVAL_BASE_URL, EVAL_API_KEY). They are synthetic and never reach a production path, so they
// use a plain OpenAI-compatible chat call instead of the gateway, which only knows the models in
// its price table. Cost is counted at the model's list price when the table knows it, else at an
// assumed Sonnet-class price, so the estimate never undercounts.
import type { TokenCounts } from "../../_shared/ai/models.ts";
import { normalizedModelId, priceTokens, tokensOf } from "../live_model.ts";

export type ChatRequest = Readonly<{
  model: string;
  system: string;
  user: string;
  maxTokens: number;
  /** Ask for a JSON object (response_format json_object). */
  json: boolean;
}>;

export type ChatResult =
  | Readonly<{ ok: true; text: string; model: string; tokens: TokenCounts; costUsd: number }>
  | Readonly<{ ok: false; reason: string; costUsd: number }>;

export type RouterChat = (request: ChatRequest) => Promise<ChatResult>;

export type RouterChatOptions = Readonly<{
  fetcher?: typeof fetch;
  timeoutMs?: number;
  /** Wait before the one retry of a failed call. */
  retryDelayMs?: number;
}>;

const isClaude = (model: string) => normalizedModelId(model).startsWith("claude");

/** A chat call to the router, retried once when it fails before an answer arrives. */
export function routerChat(
  baseUrl: string,
  apiKey: string,
  options: RouterChatOptions = {},
): RouterChat {
  const fetcher = options.fetcher ?? fetch;
  const url = `${baseUrl.replace(/\/+$/, "")}/chat/completions`;
  const once = async (request: ChatRequest): Promise<ChatResult> => {
    const body: Record<string, unknown> = {
      model: request.model,
      max_tokens: request.maxTokens,
      messages: [
        { role: "system", content: request.system },
        { role: "user", content: request.user },
      ],
    };
    // Claude 5 takes only default sampling; the others answer more steadily at a low temperature.
    if (!isClaude(request.model)) body.temperature = 0.3;
    if (request.json) body.response_format = { type: "json_object" };
    let response: Response;
    try {
      response = await fetcher(url, {
        method: "POST",
        headers: { "Content-Type": "application/json", Authorization: `Bearer ${apiKey}` },
        body: JSON.stringify(body),
        signal: AbortSignal.timeout(options.timeoutMs ?? 120_000),
      });
    } catch (error) {
      return { ok: false, reason: error instanceof Error ? error.name : "network", costUsd: 0 };
    }
    if (!response.ok) {
      await response.body?.cancel();
      return { ok: false, reason: `http ${response.status}`, costUsd: 0 };
    }
    let payload: Record<string, unknown>;
    try {
      payload = await response.json();
    } catch {
      return { ok: false, reason: "unreadable answer", costUsd: 0 };
    }
    const tokens = tokensOf((payload.usage ?? {}) as Record<string, unknown>);
    const costUsd = priceTokens(request.model, tokens).usd;
    const choice = Array.isArray(payload.choices)
      ? payload.choices[0] as Record<string, unknown>
      : undefined;
    const text = (choice?.message as Record<string, unknown> | undefined)?.content;
    if (typeof text !== "string" || text.trim() === "") {
      return { ok: false, reason: "empty answer", costUsd };
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
    const first = await once(request);
    if (first.ok) return first;
    await new Promise((resolve) => setTimeout(resolve, options.retryDelayMs ?? 3_000));
    const second = await once(request);
    return second.ok ? second : { ...second, costUsd: first.costUsd + second.costUsd };
  };
}

/**
 * The JSON object in a model's text: the whole text, or the first fenced block, or the outermost
 * braces. Null when none parses to an object.
 */
export function jsonObjectIn(text: string): Record<string, unknown> | null {
  const candidates = [
    text.trim(),
    text.match(/```(?:json)?\s*([\s\S]*?)```/i)?.[1]?.trim(),
    text.includes("{") ? text.slice(text.indexOf("{"), text.lastIndexOf("}") + 1) : undefined,
  ];
  for (const candidate of candidates) {
    if (!candidate) continue;
    try {
      const parsed = JSON.parse(candidate);
      if (parsed && typeof parsed === "object" && !Array.isArray(parsed)) return parsed;
    } catch {
      // The next candidate.
    }
  }
  return null;
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
