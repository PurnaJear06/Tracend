// How the live Coach evals reach a model, shared by coach_chat_eval.ts (operations: answer rate,
// latency, cache) and coach_bank/run.ts (the answer bank).
//
// Gateway route (A6, A9): when the AI_COACH_CHAT_* settings make a route (for example
// AI_COACH_CHAT_PROVIDER=anthropic, AI_COACH_CHAT_MODEL=claude-haiku-5-5,
// AI_COACH_CHAT_MAX_OUTPUT_TOKENS=4096, AI_COACH_CHAT_TIMEOUT_MS=30000 and ANTHROPIC_API_KEY),
// questions go through generateCoachChatViaGateway, the path coach-chat takes with those
// settings. Without one they go through today's DeepSeek path (DEEPSEEK_API_KEY), or through an
// OpenAI-compatible router when EVAL_BASE_URL and EVAL_API_KEY are set (EVAL_MODEL overrides the
// model name). A router run is a smoke test, not production latency: it waits up to routerTiming
// for each attempt.
import { route } from "../_shared/ai/routes.ts";
import type { AiCallDeps, AiRoute } from "../_shared/ai/types.ts";
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
): Generate {
  return ({ question, context, contextKind, contributions, lookups, factSuggestions }) =>
    generateCoachChatViaGateway({
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
    }, deps);
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
