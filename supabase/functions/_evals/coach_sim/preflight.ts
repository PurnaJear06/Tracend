// The check before a simulation: one tiny request to each model the run will use (Coach, athlete,
// judge), in the mode the run will use. When a request fails the preflight tries the other modes
// (without response_format, with max_completion_tokens) and, for the Coach, the other spellings of
// the model id the router lists; it keeps the first that works and reports what each attempt got
// (status and redacted body). When nothing works the run does not start: a run on a broken route
// only measures the fallback.
import { type RouterFetchOptions, routerModelFetch } from "../live_model.ts";
import { excerpt, type WireError } from "./diagnostics.ts";
import { normalizedModelId } from "../live_model.ts";
import { routerChat } from "./router_client.ts";
import { type ChatMode, chatModes, defaultChatMode, describeMode, jsonObjectIn } from "./wire.ts";

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
  for (const model of input.candidates) {
    for (const mode of input.modes ?? chatModes) {
      const seen: { error?: WireError } = {};
      const options: RouterFetchOptions = {
        mode,
        secrets: [input.apiKey],
        onError: (error) => {
          seen.error ??= error;
        },
      };
      const send = routerModelFetch(model, fetcher, undefined, options);
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
          ? `reply ${excerpt(text!, [input.apiKey])}`
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
      retryDelayMs: 1_000,
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

/** The router's ids for a model: its own first, then every other listed spelling of it. */
export function idCandidates(available: readonly string[], model: string): string[] {
  const target = normalizedModelId(model);
  const spellings = available.filter((id) => normalizedModelId(id) === target);
  return [...new Set([model, ...spellings])];
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
          result.working.mode === defaultChatMode ? "" : " (the default mode failed)"
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
