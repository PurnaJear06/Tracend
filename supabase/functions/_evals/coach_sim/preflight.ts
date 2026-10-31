// The check before a simulation: one tiny request to each model the run will use (Coach, athlete,
// judge), in the mode the run will use. When a request fails the preflight tries the other modes
// (without response_format, with max_completion_tokens) and, for the Coach, the other spellings of
// the model id the router lists; it keeps the first that works and reports what each attempt got
// (status and redacted body). When nothing works the run does not start: a run on a broken route
// only measures the fallback.
import { type RouterFetchOptions, routerModelFetch } from "../live_model.ts";
import { excerpt, type WireError } from "./diagnostics.ts";
import { normalizedModelId } from "../live_model.ts";
import { type RouterChat, routerChat } from "./router_client.ts";
import { type ChatMode, chatModes, describeMode, jsonObjectIn, messagesMode } from "./wire.ts";

export type PreflightRole = "coach" | "athlete" | "judge";

export type PreflightAttempt = Readonly<{
  model: string;
  mode: ChatMode;
  ok: boolean;
  status: number | null;
  /** What came back: the redacted start of the error body, or of the reply. */
  detail: string;
}>;

export type PreflightResult = Readonly<{
  role: PreflightRole;
  /** The model asked for (the Coach: the router's id for it). */
  wanted: string;
  /** The model id and mode that worked, null when none did. */
  working: Readonly<{ model: string; mode: ChatMode }> | null;
  attempts: readonly PreflightAttempt[];
}>;

const probeSystem = 'Reply with a JSON object and nothing else: {"ok": true}.';
const probeUser = "Preflight check. Reply now.";
/** Enough for a reasoning model that thinks briefly before the 10 tokens of the answer. */
const probeMaxTokens = 400;

/** Whether the probe's reply is the JSON object asked for, as the gateway parses it (strictly). */
const strictObject = (text: string): boolean => {
  try {
    const parsed = JSON.parse(text);
    return Boolean(parsed) && typeof parsed === "object" && !Array.isArray(parsed);
  } catch {
    return false;
  }
};

export type PreflightInput = Readonly<{
  baseUrl: string;
  apiKey: string;
  fetcher?: typeof fetch;
  /** Modes to try in order (default: JSON mode first, then the others). */
  modes?: readonly ChatMode[];
  /** The answer schema, for a Coach probe in structured mode. */
  schema?: Record<string, unknown>;
  /** Waits before the retries of a call the router failed in passing (default 5 s, then 15 s). */
  retryDelaysMs?: readonly number[];
}>;

/**
 * The Coach's route: the gateway's own request shape (carrier fields, JSON mode, max_tokens)
 * rewritten for each candidate model id and mode by `routerModelFetch`, exactly as the run does.
 * `candidates` are the router's ids for the Coach model, the preferred first.
 */
export async function preflightCoach(
  input: PreflightInput & Readonly<{ candidates: readonly string[] }>,
): Promise<PreflightResult> {
  const fetcher = input.fetcher ?? fetch;
  const attempts: PreflightAttempt[] = [];
  const url = `${input.baseUrl.replace(/\/+$/, "")}/chat/completions`;
  const modes = input.modes ?? chatModes;
  for (const [index, model] of input.candidates.entries()) {
    let tried = 0;
    for (const mode of modes) {
      // Another spelling is only a guess at the id: one that the router does not know or forbids is
      // not asked again, and one that errors on the server is asked in two modes only.
      const last = attempts.at(-1);
      if (index > 0 && tried > 0 && [401, 403, 404].includes(last?.status ?? 0)) break;
      if (index > 0 && tried >= 2 && (last?.status ?? 0) >= 500) break;
      tried++;
      const seen: { error?: WireError } = {};
      const options: RouterFetchOptions = {
        mode,
        retryDelaysMs: input.retryDelaysMs ?? [5_000, 15_000],
        secrets: [input.apiKey],
        ...(input.schema ? { schema: input.schema } : {}),
        onError: (error) => {
          seen.error ??= error;
        },
      };
      const send = routerModelFetch(model, fetcher, undefined, options);
      const started = performance.now();
      let text: string | null = null;
      try {
        const response = await send(url, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${input.apiKey}`,
          },
          signal: AbortSignal.timeout(60_000),
          // The gateway's request for the router carrier, before the model's own fields.
          body: JSON.stringify({
            model: "deepseek-v4-flash",
            max_tokens: probeMaxTokens,
            thinking: { type: "disabled" },
            temperature: 0.1,
            response_format: { type: "json_object" },
            messages: [
              { role: "system", content: probeSystem },
              { role: "user", content: probeUser },
            ],
          }),
        });
        if (response.ok) {
          const payload = await response.json();
          const content = payload?.choices?.[0]?.message?.content;
          text = typeof content === "string" ? content : null;
        }
      } catch {
        // The wire error was recorded by routerModelFetch.
      }
      // The gateway rejects a finish reason it does not know, so a reply with one is no pass.
      const ok = text !== null && strictObject(text) && seen.error?.kind !== "finish";
      attempts.push({
        model,
        mode,
        ok,
        status: seen.error?.status ?? (text === null ? null : 200),
        detail: ok
          ? `reply ${excerpt(text!, [input.apiKey])} in ${
            ((performance.now() - started) / 1000).toFixed(1)
          } s`
          : seen.error
          ? `${seen.error.kind}: ${seen.error.body}`
          : `no JSON object in the reply: ${excerpt(text ?? "", [input.apiKey])}`,
      });
      if (ok) {
        return { role: "coach", wanted: input.candidates[0], working: { model, mode }, attempts };
      }
    }
  }
  return { role: "coach", wanted: input.candidates[0], working: null, attempts };
}

/** The athlete's or a judge's route: the chat client the run uses, with a JSON-asking request. */
export async function preflightChat(
  input: PreflightInput & Readonly<{ role: "athlete" | "judge"; model: string }>,
): Promise<PreflightResult> {
  const attempts: PreflightAttempt[] = [];
  for (const mode of input.modes ?? chatModes) {
    const chat = routerChat(input.baseUrl, input.apiKey, {
      ...(input.fetcher ? { fetcher: input.fetcher } : {}),
      modeFor: () => mode,
      retryDelayMs: input.retryDelaysMs?.[0] ?? 5_000,
      timeoutMs: 60_000,
    });
    const result = await chat({
      model: input.model,
      system: probeSystem,
      user: probeUser,
      maxTokens: probeMaxTokens,
      json: true,
      source: input.role,
    });
    const ok = result.ok && jsonObjectIn(result.text) !== null;
    attempts.push({
      model: input.model,
      mode,
      ok,
      status: result.ok ? 200 : result.status,
      detail: result.ok
        ? ok
          ? `reply ${excerpt(result.text, [input.apiKey])}`
          : `no JSON object in the reply: ${excerpt(result.text, [input.apiKey])}`
        : `${result.kind}: ${result.body}`,
    });
    if (ok) {
      return {
        role: input.role,
        wanted: input.model,
        working: { model: input.model, mode },
        attempts,
      };
    }
  }
  return { role: input.role, wanted: input.model, working: null, attempts };
}

/**
 * A model on Claude's Messages API (the direct run): one tiny JSON-asking request through the
 * client the run uses. The Coach's probe checks the key and the model id; its turns then go
 * through the gateway's own Claude request.
 */
export async function preflightDirect(
  chat: RouterChat,
  role: PreflightRole,
  model: string,
  secrets: readonly string[],
): Promise<PreflightResult> {
  const result = await chat({
    model,
    system: probeSystem,
    user: probeUser,
    maxTokens: probeMaxTokens,
    json: true,
    source: role,
  });
  const ok = result.ok && jsonObjectIn(result.text) !== null;
  const attempt: PreflightAttempt = {
    model,
    mode: messagesMode,
    ok,
    status: result.ok ? 200 : result.status,
    detail: result.ok
      ? ok
        ? `reply ${excerpt(result.text, [...secrets])}`
        : `no JSON object in the reply: ${excerpt(result.text, [...secrets])}`
      : `${result.kind}: ${result.body}`,
  };
  return {
    role,
    wanted: model,
    working: ok ? { model, mode: messagesMode } : null,
    attempts: [attempt],
  };
}

/**
 * The ids to try for a model: the router's own first, the other listed spellings of it, then the
 * usual spellings the listing does not show (dotted, hyphenated, vendor-prefixed).
 */
export function idCandidates(available: readonly string[], model: string): string[] {
  const target = normalizedModelId(model);
  const spellings = available.filter((id) => normalizedModelId(id) === target);
  const dotted = target.replace(/-(\d+)-(\d+)$/, "-$1.$2");
  const vendor = target.startsWith("claude") ? "anthropic/" : "";
  const variants = [target, dotted, `${vendor}${target}`, `${vendor}${dotted}`]
    .filter((id) => id !== model);
  return [...new Set([model, ...spellings, ...variants])];
}

export type PreflightDecision =
  | Readonly<{ proceed: true }>
  | Readonly<{ proceed: false; message: string }>;

/** Go when every role has a working route; otherwise stop and say which role failed. */
export function decidePreflight(results: readonly PreflightResult[]): PreflightDecision {
  const failed = results.filter((result) => result.working === null);
  if (failed.length === 0) return { proceed: true };
  return {
    proceed: false,
    message: `Preflight failed: no working request for ${
      failed.map((result) => `${result.role} \`${result.wanted}\``).join(", ")
    }. The run did not start.`,
  };
}

/** The preflight as report lines: what was tried, the status and body of each, and what won. */
export function renderPreflight(results: readonly PreflightResult[]): string[] {
  return results.flatMap((result) => [
    `${result.role} \`${result.wanted}\`: ${
      result.working
        ? `works as \`${result.working.model}\` in ${describeMode(result.working.mode)}${
          result.attempts[0]?.mode === result.working.mode ? "" : " (the first mode tried failed)"
        }`
        : "NO WORKING REQUEST"
    }`,
    ...result.attempts.map((attempt) =>
      `  - ${attempt.ok ? "ok" : "failed"}: \`${attempt.model}\`, ${describeMode(attempt.mode)}: ${
        attempt.status === null ? "no response" : `HTTP ${attempt.status}`
      }: ${attempt.detail}`
    ),
  ]);
}
