// How the live Coach evals reach a model, shared by coach_chat_eval.ts (operations: answer rate,
// latency, cache), coach_bank/run.ts (the answer bank) and coach_sim/run.ts (the simulated
// athlete).
//
// Gateway route (A6, A9): when the AI_COACH_CHAT_* settings make a route (for example
// AI_COACH_CHAT_PROVIDER=anthropic, AI_COACH_CHAT_MODEL=claude-haiku-5-5,
// AI_COACH_CHAT_MAX_OUTPUT_TOKENS=4096, AI_COACH_CHAT_TIMEOUT_MS=30000 and ANTHROPIC_API_KEY),
// questions go through generateCoachChatViaGateway, the path coach-chat takes with those
// settings. Without one they go through today's DeepSeek path (DEEPSEEK_API_KEY), or through an
// OpenAI-compatible router when EVAL_BASE_URL and EVAL_API_KEY are set (EVAL_MODEL overrides the
// model name). A router run is a smoke test, not production latency: it waits up to routerTiming
// for each attempt.
//
// Router gateway route (routerGatewayFromEnv): the production gateway path (lookups, proposals,
// library citations, every guard) over the eval router. The route takes its request shape and
// prices from routerCarrierModel, the router entry of the model table; routerModelFetch then
// names the model that should answer: the production Coach model when the router lists it, else
// EVAL_COACH_MODEL or EVAL_MODEL, else the carrier itself. The wire format is OpenAI-compatible
// JSON mode, not the Claude Messages API production uses, so a run measures the model and the
// production prompt, guards and loop, not the vendor's own request.
import { costUsd, type ModelPrice, models, type TokenCounts } from "../_shared/ai/models.ts";
import { type Env, route } from "../_shared/ai/routes.ts";
import type { AiCallDeps, AiRoute } from "../_shared/ai/types.ts";
import { type ChatMode, defaultChatMode, jsonObjectIn } from "./coach_sim/wire.ts";
import { excerpt, headerNote, htmlText, type WireError } from "./coach_sim/diagnostics.ts";
import type { CoachContributions } from "../_shared/coach_context/host.ts";
import type { CoachLookupRunner } from "../_shared/coach_lookups/runner.ts";
import {
  type CoachChatGeneration,
  type CoachChatTiming,
  coachChatTiming,
  generateCoachChat,
} from "../_shared/providers/coach_chat_provider.ts";
import { selectCoachChatRoute } from "../_shared/providers/coach_chat_provider_route.ts";
import { generateCoachChatViaGateway } from "../_shared/providers/coach_chat_provider_gateway.ts";

export type GenerateInput = Readonly<{
  question: string;
  context: Record<string, unknown>;
  contextKind: string;
  contributions: CoachContributions | null;
  /** Runs the lookups the model asks for (gateway path only; today's DeepSeek path has none). */
  lookups?: CoachLookupRunner;
  /** False for a conversation the athlete asked Coach not to remember (no fact suggestions). */
  factSuggestions?: boolean;
}>;

export type Generate = (input: GenerateInput) => Promise<CoachChatGeneration>;

export type LiveModel = Readonly<{
  generate: Generate;
  endpoint: string;
  /** The model answering; with a strong route set, both models, the default first. */
  model: string;
  /** Every model that may answer a question (the default route's and the strong route's). */
  models: readonly string[];
  /** A router run: latency says nothing about production. */
  router: boolean;
  /** Set on the gateway path. */
  coachRoute?: AiRoute;
}>;

export const deepseekChatUrl = "https://api.deepseek.com/v1/chat/completions";

// A router adds its own queue and hop, so its replies often exceed the production attempt limits:
// on 2026-09-28 NaraRouter's fastest reply took 21 s and every other call hit the 28 s limit.
// Router runs wait longer so they measure the answers rather than the router's speed.
export const routerTiming: CoachChatTiming = Object.freeze({
  totalDeadlineMs: 190_000,
  initialAttemptMs: 120_000,
  repairAttemptMs: 60_000,
});

// Sends the unchanged production request to another OpenAI-compatible endpoint. Routers switch
// thinking with `reasoning_effort` rather than DeepSeek's native `thinking` field, so a request
// that turns thinking off also says so in their terms.
export function routedFetch(baseUrl: string, fetcher: typeof fetch = fetch): typeof fetch {
  const target = `${baseUrl.replace(/\/+$/, "")}/chat/completions`;
  return (input, init) => {
    if (String(input) !== deepseekChatUrl) return fetcher(input, init);
    let body = init?.body;
    if (typeof body === "string") {
      const payload = JSON.parse(body);
      if (payload.thinking?.type === "disabled" && payload.reasoning_effort === undefined) {
        payload.reasoning_effort = "none";
      }
      body = JSON.stringify(payload);
    }
    return fetcher(target, { ...init, body });
  };
}

/**
 * The gateway path with the route chosen per question by `selectCoachChatRoute`, as coach-chat
 * does: a question that needs analysis takes the strong route (AI_COACH_CHAT_STRONG_*) when it is
 * set and names the default route's vendor (the eval's stand-in for the athlete's notice).
 */
export function gatewayGenerate(
  coachRoute: AiRoute,
  strong: () => AiRoute | null = () => route("coach_chat_strong"),
  deps: AiCallDeps = {},
  timing: CoachChatTiming = coachChatTiming,
): Generate {
  return ({ question, context, contextKind, contributions, lookups, factSuggestions }) =>
    generateCoachChatViaGateway(
      {
        question,
        context,
        contextKind,
        route: selectCoachChatRoute(question, coachRoute, strong, coachRoute.vendor).route,
        consentVendor: coachRoute.vendor,
        ...(contributions ? { contributions } : {}),
        ...(lookups ? { lookups } : {}),
        // Production offers proposals on the gateway route, so the bank measures with them.
        proposals: true,
        factSuggestions: factSuggestions !== false,
      },
      deps,
      timing,
    );
}

// ---- the router gateway route ---------------------------------------------------------------

/**
 * The model production Coach chat answers with: `AI_COACH_CHAT_MODEL` in the cutover runbook
 * (docs/runbooks/phase2-claude-cutover.md, "What moves"), set on 2026-10-16. Read from the docs,
 * never from the production secrets; the optional stronger route is not part of it.
 */
export const productionCoachModel = "claude-haiku-5-5";

/** The model-table entry a router route is built on: its request fields and its list prices. */
export const routerCarrierModel = "deepseek-v4-flash";

/** Output tokens and attempt limit of a router Coach turn (production's 4,096; a router's wait). */
export const routerCoachMaxOutputTokens = 4_096;
export const routerCoachTimeoutMs = 120_000;

/** A model id reduced for comparison: lower case, separators as "-", no vendor prefix. */
export function normalizedModelId(id: string): string {
  const flat = id.toLowerCase().replace(/[._:\s/]+/g, "-");
  return flat.replace(/^(?:anthropic|deepseek|openai|google|qwen|groq)-(?=.)/, "");
}

/** The router's id for a model (an exact or normalized match), or null when it is not listed. */
export function matchModel(available: readonly string[], wanted: string): string | null {
  if (available.includes(wanted)) return wanted;
  const target = normalizedModelId(wanted);
  return available.find((id) => normalizedModelId(id) === target) ??
    available.find((id) => normalizedModelId(id).endsWith(target)) ?? null;
}

/** The list price of a model the table knows (matched like matchModel), or null. */
export function knownPrice(model: string): ModelPrice | null {
  const key = matchModel(Object.keys(models), model) ??
    Object.keys(models).find((name) => normalizedModelId(model).endsWith(normalizedModelId(name)));
  return key ? models[key].price : null;
}

/**
 * What the router says about one model in its listing (GET /models): the entry as JSON, cut to 300
 * characters, or a short reason. Public metadata only; the key is never part of it.
 */
export async function routerModelEntry(
  baseUrl: string,
  apiKey: string,
  id: string,
  fetcher: typeof fetch = fetch,
): Promise<string> {
  try {
    const response = await fetcher(`${baseUrl.replace(/\/+$/, "")}/models`, {
      headers: { Authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) return `the listing answered HTTP ${response.status}`;
    const body = await response.json() as { data?: { id?: unknown }[] };
    const entry = body.data?.find((item) => item.id === id);
    return entry ? excerpt(JSON.stringify(entry), [apiKey]) : "not in the listing";
  } catch {
    return "the listing could not be read";
  }
}

/** The model ids an OpenAI-compatible router lists (GET /models), or null when it cannot say. */
export async function routerModels(
  baseUrl: string,
  apiKey: string,
  fetcher: typeof fetch = fetch,
): Promise<string[] | null> {
  try {
    const response = await fetcher(`${baseUrl.replace(/\/+$/, "")}/models`, {
      headers: { Authorization: `Bearer ${apiKey}` },
      signal: AbortSignal.timeout(20_000),
    });
    if (!response.ok) {
      await response.body?.cancel();
      return null;
    }
    const body = await response.json() as { data?: { id?: unknown }[] };
    if (!Array.isArray(body.data)) return null;
    return body.data.map((item) => item.id).filter((id): id is string => typeof id === "string");
  } catch {
    return null;
  }
}

const isClaude = (model: string) => model.toLowerCase().includes("claude");
const isDeepSeek = (model: string) => model.toLowerCase().includes("deepseek");

export type RouterFetchOptions = Readonly<{
  /** How the model is asked (default: JSON mode, max_tokens, as the gateway builds the request). */
  mode?: ChatMode;
  /** Sees every failed call: the status and the redacted start of the body. */
  onError?: (error: WireError) => void;
  /** Strings that must never appear in a recorded body (the router key). */
  secrets?: readonly string[];
  /**
   * Waits before each retry of a call the router failed in passing (502, 503, 504, or no answer
   * at all). The router is a hop of its own and has answered "temporarily unavailable" for minutes
   * at a time; production's gateway has no such retry, so this is the harness's, not the Coach's.
   */
  retryDelaysMs?: readonly number[];
}>;

/** Statuses a router returns while an upstream model or the router itself is briefly down. */
export const transientStatuses: ReadonlySet<number> = new Set([502, 503, 504]);

const anthropicFinish: Readonly<Record<string, string>> = {
  end_turn: "stop",
  stop_sequence: "stop",
  max_tokens: "length",
};

const abortNames = new Set(["AbortError", "TimeoutError"]);

/**
 * Sends the gateway's router request with `model` in place of the carrier, and the request fields
 * that model takes: a DeepSeek model keeps thinking off and says so in the router's terms; any
 * other model drops DeepSeek's thinking field, and a Claude model also the temperature (Claude 5
 * takes only default sampling, and production's request sends none). `onUsage` sees the tokens of
 * every answer. The mode can drop `response_format` (the production prompt already asks for the
 * JSON; a reply that wraps it in a fence or prose is cleaned to the bare object, which is all the
 * gateway's strict parse needs) and rename `max_tokens`; `onError` sees every failed call.
 */
export function routerModelFetch(
  model: string,
  fetcher: typeof fetch = fetch,
  onUsage: (tokens: TokenCounts) => void = () => {},
  options: RouterFetchOptions = {},
): typeof fetch {
  const mode = options.mode ?? defaultChatMode;
  const secrets = options.secrets ?? [];
  const report = (kind: WireError["kind"], status: number | null, body: string) =>
    options.onError?.({ kind, status, body: excerpt(body, secrets) });
  return async (input, init) => {
    let body = init?.body;
    if (typeof body === "string") {
      const payload = JSON.parse(body);
      payload.model = model;
      if (isDeepSeek(model)) {
        if (payload.thinking?.type === "disabled" && payload.reasoning_effort === undefined) {
          payload.reasoning_effort = "none";
        }
      } else {
        delete payload.thinking;
        if (isClaude(model)) delete payload.temperature;
      }
      if (!mode.responseFormat) delete payload.response_format;
      if (mode.maxTokensField === "max_completion_tokens" && payload.max_tokens !== undefined) {
        payload.max_completion_tokens = payload.max_tokens;
        delete payload.max_tokens;
      }
      body = JSON.stringify(payload);
    }
    const delays = options.retryDelaysMs ?? [2_000, 6_000];
    let response: Response | undefined;
    for (let attempt = 0; response === undefined; attempt++) {
      const retryable = attempt < delays.length && init?.signal?.aborted !== true;
      try {
        const answered = await fetcher(input, { ...init, body });
        if (retryable && transientStatuses.has(answered.status)) {
          await answered.body?.cancel().catch(() => undefined);
          await new Promise((resolve) => setTimeout(resolve, delays[attempt]));
          continue;
        }
        response = answered;
      } catch (error) {
        const name = error instanceof Error ? error.name : "";
        if (retryable && !abortNames.has(name)) {
          await new Promise((resolve) => setTimeout(resolve, delays[attempt]));
          continue;
        }
        report(
          abortNames.has(name) ? "timeout" : "network",
          null,
          error instanceof Error ? `${name}: ${error.message}` : "network",
        );
        throw error;
      }
    }
    if (!response.ok) {
      report(
        "http",
        response.status,
        `${headerNote(response.headers)}${htmlText(await response.clone().text().catch(() => ""))}`,
      );
      return response;
    }
    let raw = "";
    let payload: Record<string, unknown>;
    try {
      raw = await response.clone().text();
      payload = JSON.parse(raw);
    } catch {
      // The gateway reads the body itself and reports an unreadable answer.
      report("unreadable", response.status, raw);
      return response;
    }
    const usage = payload.usage;
    if (usage && typeof usage === "object") onUsage(tokensOf(usage as Record<string, unknown>));
    const choice = Array.isArray(payload.choices)
      ? payload.choices[0] as Record<string, unknown> | undefined
      : undefined;
    const message = choice?.message as Record<string, unknown> | undefined;
    if (!choice || !message) {
      report("no_choices", response.status, raw);
      return response;
    }
    // The gateway reads only OpenAI's finish reasons; a router that passes Claude's own through
    // (end_turn, max_tokens) is translated, anything else is reported and left as it is.
    const finish = anthropicFinish[String(choice.finish_reason)];
    if (finish) choice.finish_reason = finish;
    else if (!["stop", "length", "content_filter"].includes(String(choice.finish_reason))) {
      report("finish", response.status, `finish_reason=${String(choice.finish_reason)}`);
    }
    let changed = Boolean(finish);
    if (!mode.responseFormat && typeof message.content === "string") {
      let parses = true;
      try {
        JSON.parse(message.content);
      } catch {
        parses = false;
      }
      const object = parses ? null : jsonObjectIn(message.content);
      if (object) {
        message.content = JSON.stringify(object);
        changed = true;
      }
    }
    if (changed) {
      return new Response(JSON.stringify(payload), {
        status: response.status,
        statusText: response.statusText,
        headers: { "content-type": "application/json" },
      });
    }
    return response;
  };
}

/** OpenAI-style usage as token counts, cached prompt tokens apart (as the gateway counts them). */
export function tokensOf(usage: Record<string, unknown>): TokenCounts {
  const count = (value: unknown) =>
    typeof value === "number" && Number.isFinite(value) && value > 0 ? Math.round(value) : 0;
  const prompt = count(usage.prompt_tokens);
  const details = usage.prompt_tokens_details as Record<string, unknown> | undefined;
  const cached = Math.min(
    prompt,
    count(usage.prompt_cache_hit_tokens) || count(details?.cached_tokens),
  );
  return {
    inputTokens: prompt - cached,
    outputTokens: count(usage.completion_tokens),
    cacheReadTokens: cached,
    cacheWriteTokens: 0,
  };
}

/** A price for a model the table does not know: Sonnet-class, so an estimate never undercounts. */
export const assumedPrice: ModelPrice = Object.freeze({
  input: 3,
  output: 15,
  cacheRead: 3,
  cacheWrite: 3,
});

/** The list-price cost of tokens for a model, and whether the price was assumed. */
export function priceTokens(model: string, tokens: TokenCounts): { usd: number; assumed: boolean } {
  const price = knownPrice(model);
  return { usd: costUsd(price ?? assumedPrice, tokens), assumed: price === null };
}

export type CoachGenerateFactory = (
  onUsage: (tokens: TokenCounts) => void,
  onError?: (error: WireError) => void,
) => Generate;

export type RouterGateway =
  & LiveModel
  & Readonly<{
    coachRoute: AiRoute;
    /** The router's id of the model that answers as the Coach. */
    coachModel: string;
    /** Whether that is the production Coach model. */
    production: boolean;
    /** How the model was chosen, for the report. */
    choice: string;
    /** Every model id the router listed, empty when it could not list them. */
    available: readonly string[];
    baseUrl: string;
    apiKey: string;
    /**
     * The gateway path with the Coach model, telling `onUsage` the tokens of every call and
     * `onError` every failed one.
     */
    generateWith: CoachGenerateFactory;
    /** The same for another model id or request mode (what the preflight found working). */
    generateFor: (route: Readonly<{ model: string; mode: ChatMode }>) => CoachGenerateFactory;
  }>;

/**
 * The production gateway path over the eval router (EVAL_BASE_URL, EVAL_API_KEY). The Coach model
 * is EVAL_COACH_MODEL when set, else the production model when the router lists it, else
 * EVAL_MODEL or the carrier. Nothing here reads a production setting.
 */
export async function routerGatewayFromEnv(
  env: Env = (name) => Deno.env.get(name),
  fetcher: typeof fetch = fetch,
): Promise<RouterGateway | { error: string }> {
  const baseUrl = env("EVAL_BASE_URL")?.trim() ?? "";
  const apiKey = env("EVAL_API_KEY")?.trim() ?? "";
  if (!baseUrl || !apiKey) {
    return { error: "EVAL_BASE_URL and EVAL_API_KEY are required. Nothing was sent." };
  }
  const coachRoute = route("coach_chat", (name) =>
    ({
      AI_COACH_CHAT_PROVIDER: "openai_compatible",
      AI_COACH_CHAT_MODEL: routerCarrierModel,
      AI_COACH_CHAT_VENDOR: "router",
      AI_COACH_CHAT_BASE_URL: baseUrl,
      AI_COACH_CHAT_MAX_OUTPUT_TOKENS: String(routerCoachMaxOutputTokens),
      AI_COACH_CHAT_TIMEOUT_MS: String(routerCoachTimeoutMs),
      OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: apiKey,
    } as Record<string, string>)[name]);
  if (!coachRoute) return { error: `EVAL_BASE_URL is not an https API base: ${baseUrl}` };
  const available = await routerModels(baseUrl, apiKey, fetcher) ?? [];
  const override = env("EVAL_COACH_MODEL")?.trim();
  const production = matchModel(available, productionCoachModel);
  const fallback = env("EVAL_MODEL")?.trim() || routerCarrierModel;
  const coachModel = override || production || fallback;
  const choice = override
    ? `EVAL_COACH_MODEL set to ${override}`
    : production
    ? `the router lists the production model ${productionCoachModel} as ${production}`
    : available.length === 0
    ? `the router did not list its models, so the production model ${productionCoachModel} could not be found; using ${fallback}`
    : `the router does not list the production model ${productionCoachModel}; using ${fallback}`;
  const generateFor =
    (played: Readonly<{ model: string; mode: ChatMode }>): CoachGenerateFactory =>
    (onUsage, onError) =>
      gatewayGenerate(
        coachRoute,
        () => null,
        {
          fetch: routerModelFetch(played.model, fetcher, onUsage, {
            mode: played.mode,
            secrets: [apiKey],
            ...(onError ? { onError } : {}),
          }),
        },
        routerTiming,
      );
  const generateWith = generateFor({ model: coachModel, mode: defaultChatMode });
  return {
    generate: generateWith(() => {}),
    generateWith,
    generateFor,
    endpoint: `${new URL(baseUrl).host} gateway route`,
    model: `${coachModel} (priced as ${routerCarrierModel})`,
    models: [coachModel],
    router: true,
    coachRoute,
    coachModel,
    production: normalizedModelId(coachModel) === normalizedModelId(productionCoachModel),
    choice,
    available,
    baseUrl,
    apiKey,
  };
}

/** The model the environment points at, or null (with a message) when no key is set. */
export function liveModelFromEnv(): LiveModel | { error: string } {
  const coachRoute = route("coach_chat");
  if (coachRoute) {
    const strongRoute = route("coach_chat_strong");
    const models = strongRoute && strongRoute.model !== coachRoute.model
      ? [coachRoute.model, strongRoute.model]
      : [coachRoute.model];
    return {
      generate: gatewayGenerate(coachRoute),
      endpoint: `${coachRoute.providerLabel} gateway route`,
      model: models.join(" + strong "),
      models,
      router: false,
      coachRoute,
    };
  }
  const baseUrl = Deno.env.get("EVAL_BASE_URL")?.trim() ?? "";
  const apiKey = baseUrl ? Deno.env.get("EVAL_API_KEY") : Deno.env.get("DEEPSEEK_API_KEY");
  if (!apiKey) {
    return {
      error: `${baseUrl ? "EVAL_API_KEY" : "DEEPSEEK_API_KEY"} is required. Nothing was sent.`,
    };
  }
  // The router key travels in the same Authorization header the provider builds.
  Deno.env.set("DEEPSEEK_API_KEY", apiKey);
  Deno.env.set("COACH_AI_ENABLED", "true");
  Deno.env.set("COACH_MODEL_PROVIDER", "deepseek");
  // NaraRouter lists the model as deepseek-v4-flash; DeepSeek itself as deepseek-flash.
  const model = Deno.env.get("EVAL_MODEL")?.trim() ||
    (baseUrl ? "deepseek-v4-flash" : "deepseek-flash");
  Deno.env.set("DEEPSEEK_MODEL", model);
  const fetcher = baseUrl ? routedFetch(baseUrl) : fetch;
  const timing: CoachChatTiming = baseUrl ? routerTiming : coachChatTiming;
  return {
    generate: ({ question, context, contextKind, contributions }) =>
      generateCoachChat(question, context, contextKind, fetcher, timing, contributions),
    endpoint: baseUrl ? new URL(baseUrl).host : new URL(deepseekChatUrl).host,
    model,
    models: [model],
    router: Boolean(baseUrl),
  };
}

// A Mac that sleeps mid-request kills the connection; the monotonic clock stops while it sleeps
// and the wall clock does not. Such a run measures the host, not the model, so it runs again (at
// most twice) and the summary counts the reruns.
export const hostSleep = { reruns: 0 };

export async function runAwake<T>(run: () => Promise<T>): Promise<T> {
  for (let tries = 0;; tries++) {
    const wall = Date.now();
    const monotonic = performance.now();
    const result = await run();
    const sleptMs = Date.now() - wall - (performance.now() - monotonic);
    if (sleptMs < 5_000 || tries >= 2) return result;
    hostSleep.reruns++;
  }
}

/** Runs the jobs with at most `concurrency` at a time, each started in order. */
export async function runPool<T>(
  jobs: readonly (() => Promise<T>)[],
  concurrency: number,
  stop: () => boolean = () => false,
): Promise<T[]> {
  const results: T[] = [];
  let next = 0;
  const workers = Array.from({ length: Math.max(1, concurrency) }, async () => {
    while (next < jobs.length && !stop()) {
      const job = jobs[next++];
      results.push(await job());
    }
  });
  await Promise.all(workers);
  return results;
}
