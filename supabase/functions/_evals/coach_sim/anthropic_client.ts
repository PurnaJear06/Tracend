// The simulator without the eval router: the Coach on the production Claude route the environment
// sets (AI_COACH_CHAT_PROVIDER=anthropic, AI_COACH_CHAT_MODEL and the rest, ANTHROPIC_API_KEY),
// through the same gateway path coach-chat uses, and the athlete and the judges on Claude's
// Messages API with the same key. Eval code only: nothing here is imported by a function.
import type { TokenCounts } from "../../_shared/ai/models.ts";
import { models } from "../../_shared/ai/models.ts";
import { anthropicMessagesUrl, anthropicVersion } from "../../_shared/ai/adapters/anthropic.ts";
import { type Env, route } from "../../_shared/ai/routes.ts";
import type { AiRoute } from "../../_shared/ai/types.ts";
import { record, tokenCount } from "../../_shared/ai/adapters/adapter.ts";
import {
  type CoachGenerateFactory,
  gatewayGenerate,
  normalizedModelId,
  priceTokens,
  productionCoachModel,
} from "../live_model.ts";
import { excerpt, headerNote, type WireError } from "./diagnostics.ts";
import type { ChatResult, RouterChat } from "./router_client.ts";
import { type ChatMode, messagesMode } from "./wire.ts";

/** The Claude models the direct run may use, as Anthropic names them. */
export const anthropicModels: readonly string[] = [
  "claude-haiku-5-5",
  "claude-sonnet-5-5",
  "claude-opus-5-5",
];

/** Claude's token usage as token counts. */
export function anthropicTokens(usage: unknown): TokenCounts {
  const counts = record(usage);
  return {
    inputTokens: tokenCount(counts?.input_tokens),
    outputTokens: tokenCount(counts?.output_tokens),
    cacheReadTokens: tokenCount(counts?.cache_read_input_tokens),
    cacheWriteTokens: tokenCount(counts?.cache_creation_input_tokens),
  };
}

/** The text blocks of a Messages API answer (thinking blocks are skipped, as the gateway does). */
function textBlocks(message: Record<string, unknown> | null): string {
  const content = Array.isArray(message?.content) ? message.content as unknown[] : [];
  return content.map((item) => {
    const part = record(item);
    return part?.type === "text" && typeof part.text === "string" ? part.text : "";
  }).join("");
}

/**
 * The gateway's fetch, metered: `onUsage` sees the tokens of every answer, `onAnswer` its text
 * and `onError` every failed call (status and redacted body). The request and the answer pass
 * through unchanged.
 */
export function meteredAnthropicFetch(
  onUsage: (tokens: TokenCounts) => void,
  onError: ((error: WireError) => void) | undefined,
  onAnswer: ((text: string) => void) | undefined,
  secrets: readonly string[],
  fetcher: typeof fetch = fetch,
): typeof fetch {
  return async (input, init) => {
    let response: Response;
    try {
      response = await fetcher(input, init);
    } catch (error) {
      const timedOut = error instanceof Error &&
        (error.name === "TimeoutError" || error.name === "AbortError");
      onError?.({
        kind: timedOut ? "timeout" : "network",
        status: null,
        body: error instanceof Error ? `${error.name}: ${error.message}` : "network",
      });
      throw error;
    }
    const raw = await response.text();
    if (!response.ok) {
      onError?.({
        kind: "http",
        status: response.status,
        body: excerpt(`${headerNote(response.headers)}${raw}`, secrets),
      });
    } else {
      try {
        const message = record(JSON.parse(raw));
        onUsage(anthropicTokens(message?.usage));
        const text = textBlocks(message);
        if (text) onAnswer?.(text);
        if (message?.stop_reason === "max_tokens") {
          onError?.({ kind: "truncated", status: response.status, body: "stop_reason=max_tokens" });
        }
      } catch {
        onError?.({ kind: "unreadable", status: response.status, body: excerpt(raw, secrets) });
      }
    }
    return new Response(raw, {
      status: response.status,
      statusText: response.statusText,
      headers: response.headers,
    });
  };
}

export type AnthropicGateway = Readonly<{
  coachRoute: AiRoute;
  coachModel: string;
  /** Whether the route's model is the production Coach model. */
  production: boolean;
  choice: string;
  apiKey: string;
  /** The production gateway path on the route, metered like the router route. */
  generateWith: CoachGenerateFactory;
}>;

/**
 * The production Coach route from the environment (the AI_COACH_CHAT_* settings production uses,
 * with ANTHROPIC_API_KEY), or why there is none. Only a Claude route qualifies: the athlete and
 * the judges use the same key.
 */
export function anthropicGatewayFromEnv(
  env: Env = (name) => Deno.env.get(name),
  fetcher: typeof fetch = fetch,
): AnthropicGateway | { error: string } {
  const coachRoute = route("coach_chat", env);
  if (!coachRoute) {
    return {
      error:
        "Set EVAL_BASE_URL and EVAL_API_KEY (the eval router), or the AI_COACH_CHAT_* route with ANTHROPIC_API_KEY. Nothing was sent.",
    };
  }
  if (coachRoute.provider !== "anthropic") {
    return { error: `The direct run needs a Claude Coach route, not ${coachRoute.provider}.` };
  }
  const apiKey = env("ANTHROPIC_API_KEY")?.trim() ?? "";
  const production = normalizedModelId(coachRoute.model) ===
    normalizedModelId(productionCoachModel);
  return {
    coachRoute,
    coachModel: coachRoute.model,
    production,
    choice: production
      ? `the production route (AI_COACH_CHAT_MODEL ${coachRoute.model}) on Anthropic directly`
      : `AI_COACH_CHAT_MODEL set to ${coachRoute.model} on Anthropic directly`,
    apiKey,
    generateWith: (onUsage, onError, onAnswer) =>
      gatewayGenerate(coachRoute, () => null, {
        fetch: meteredAnthropicFetch(onUsage, onError, onAnswer, [apiKey], fetcher),
      }),
  };
}

export type AnthropicChatOptions = Readonly<{
  fetcher?: typeof fetch;
  timeoutMs?: number;
  /** Wait before the first retry of a call that failed in passing (the second waits three times as long). */
  retryDelayMs?: number;
}>;

/** A failure worth asking again: no answer, a server error, a rate limit or an overload. */
const worthRetrying = (failure: Extract<ChatResult, { ok: false }>) =>
  failure.kind !== "empty" && failure.kind !== "truncated" &&
  (failure.status === null || failure.status >= 500 || failure.status === 429 ||
    failure.status === 408);

/**
 * The athlete's and the judges' calls on Claude's Messages API, with the same result as the
 * router client: thinking off as the model allows (production's setting), no sampling options
 * (Claude 5 takes the defaults), JSON asked in the prompt. Retried twice when it fails in passing.
 */
export function anthropicChat(apiKey: string, options: AnthropicChatOptions = {}): RouterChat {
  const fetcher = options.fetcher ?? fetch;
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
  const once: RouterChat = async (request) => {
    const spec = models[request.model];
    const body: Record<string, unknown> = {
      model: request.model,
      max_tokens: request.maxTokens,
      system: request.system,
      messages: [{ role: "user", content: request.user }],
    };
    if (spec?.provider === "anthropic" && spec.thinkingOff !== null) {
      body.thinking = { type: spec.thinkingOff };
    }
    let response: Response;
    try {
      response = await fetcher(anthropicMessagesUrl, {
        method: "POST",
        headers: {
          "content-type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": anthropicVersion,
        },
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
    const raw = await response.text().catch(() => "");
    if (!response.ok) {
      return fail(
        "http",
        response.status,
        `${headerNote(response.headers)}${raw}`,
        `http ${response.status}`,
      );
    }
    let message: Record<string, unknown> | null;
    try {
      message = record(JSON.parse(raw));
    } catch {
      return fail("unreadable", response.status, raw, "unreadable answer");
    }
    const tokens = anthropicTokens(message?.usage);
    const costUsd = priceTokens(request.model, tokens).usd;
    const stop = String(message?.stop_reason);
    const text = textBlocks(message);
    if (stop === "max_tokens") {
      return fail(
        "truncated",
        response.status,
        `stop_reason=max_tokens output_tokens=${tokens.outputTokens} max_tokens=${request.maxTokens}; text so far ${text.length} chars`,
        "truncated at max_tokens",
        costUsd,
      );
    }
    if (text.trim() === "") {
      return fail(
        "empty",
        response.status,
        `empty content; stop_reason=${stop} output_tokens=${tokens.outputTokens}`,
        "empty answer",
        costUsd,
      );
    }
    return {
      ok: true,
      text,
      model: typeof message?.model === "string" ? message.model : request.model,
      tokens,
      costUsd,
      finishReason: stop,
    };
  };
  return async (request) => {
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

/** The mode every direct call is made in, for the preflight and the report. */
export const directMode: ChatMode = messagesMode;
