import type { ProviderAnswer, ProviderCall } from "./adapters/adapter.ts";
import { anthropicAdapter } from "./adapters/anthropic.ts";
import { geminiAdapter } from "./adapters/gemini.ts";
import { openAiCompatibleAdapter } from "./adapters/openai_compatible.ts";
import { isSupportedSchema, matchesSchema } from "./json_schema.ts";
import { logAiCall } from "./log.ts";
import { costUsd, type ModelSpec, modelSpec } from "./models.ts";
import { routeApiKey } from "./routes.ts";
import type { AiCallDeps, AiFailure, AiRequest, AiResult, AiUsage } from "./types.ts";

// The one way features call an AI model (Contract 1). The caller owns consent lookup and the
// budget (AiBudget.reserve before call, settle after); the gateway refuses a request whose
// consented vendor differs from the route's before anything is sent, sends one request,
// maps the answer, prices it from models.ts and logs one scrubbed `ai_call` line.

type Prepared = Readonly<{
  call: ProviderCall;
  read: (payload: unknown) => ProviderAnswer | null;
}>;

function prepare(request: AiRequest, spec: ModelSpec, apiKey: string): Prepared | null {
  switch (spec.provider) {
    case "anthropic": {
      const call = anthropicAdapter.build(request, spec, apiKey);
      return call && { call, read: anthropicAdapter.read };
    }
    case "openai_compatible": {
      const call = openAiCompatibleAdapter.build(request, spec, apiKey);
      return call && { call, read: openAiCompatibleAdapter.read };
    }
    case "gemini": {
      const call = geminiAdapter.build(request, spec, apiKey);
      return call && { call, read: geminiAdapter.read };
    }
  }
}

/** Decoded size of standard base64, or null when the text is not standard base64. */
export function base64Bytes(base64: string): number | null {
  if (base64.length === 0 || base64.length % 4 !== 0 || !/^[A-Za-z0-9+/]+={0,2}$/.test(base64)) {
    return null;
  }
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return (base64.length / 4) * 3 - padding;
}

/**
 * Requests every provider can take: the conversation ends with the athlete's turn (Claude 5
 * models reject an assistant prefill), no text part is blank, images are valid base64 within
 * the model's size limit in user turns, and a JSON schema uses only keywords the gateway can
 * check.
 */
function isSendable(request: AiRequest, spec: ModelSpec): boolean {
  const { messages, system, output } = request;
  if (messages.length === 0 || messages[messages.length - 1].role !== "user") return false;
  if (system.some((part) => part.type !== "text" || part.text.trim() === "")) return false;
  for (const message of messages) {
    if (message.content.length === 0) return false;
    for (const part of message.content) {
      if (part.type === "text") {
        if (part.text.trim() === "") return false;
        continue;
      }
      const bytes = base64Bytes(part.base64);
      if (
        message.role !== "user" || part.mediaType !== "image/jpeg" || bytes === null ||
        bytes > spec.maxImageBytes
      ) return false;
    }
  }
  return output.kind === "text" || isSupportedSchema(output.schema);
}

function retryAfterSeconds(header: string | null): number | undefined {
  const value = header?.trim();
  if (!value) return undefined;
  if (/^[0-9]+$/.test(value)) return Number(value);
  const at = Date.parse(value);
  return Number.isNaN(at) ? undefined : Math.max(0, Math.ceil((at - Date.now()) / 1000));
}

const failure = (
  reason: AiFailure,
  usage: AiUsage | null,
  retryAfter?: number,
): AiResult =>
  retryAfter === undefined
    ? { ok: false, reason, usage }
    : { ok: false, reason, usage, retryAfterSeconds: retryAfter };

export async function call(request: AiRequest, deps: AiCallDeps = {}): Promise<AiResult> {
  const fetcher = deps.fetch ?? fetch;
  const now = deps.now ?? (() => performance.now());
  const started = now();
  const { route } = request;
  let httpStatus: number | null = null;

  const finish = (result: AiResult): AiResult => {
    logAiCall({
      feature: route.feature,
      provider: route.provider,
      vendor: route.vendor,
      model: route.model,
      outcome: result.ok ? "ok" : result.reason,
      usage: result.usage,
      latencyMs: now() - started,
      httpStatus,
      stop: result.ok ? result.stop : null,
    });
    return result;
  };

  // The athlete agreed to a named vendor; nothing goes anywhere else. No notice names the
  // eval router, so an athlete's request never reaches it.
  if (request.consentVendor !== route.vendor) {
    return finish(failure("consent_provider_mismatch", null));
  }
  const spec = modelSpec(route.provider, route.model);
  const apiKey = routeApiKey(route);
  const prepared = spec && apiKey && isSendable(request, spec)
    ? prepare(request, spec, apiKey)
    : null;
  if (!spec || !prepared) return finish(failure("provider_error", null));

  const controller = new AbortController();
  const abort = () => controller.abort();
  const timer = setTimeout(abort, route.timeoutMs);
  request.signal?.addEventListener("abort", abort, { once: true });
  if (request.signal?.aborted) abort();
  try {
    if (controller.signal.aborted) return finish(failure("timeout", null));
    let response: Response;
    try {
      response = await fetcher(prepared.call.url, {
        method: "POST",
        signal: controller.signal,
        headers: prepared.call.headers,
        body: JSON.stringify(prepared.call.body),
      });
    } catch {
      return finish(failure(controller.signal.aborted ? "timeout" : "network", null));
    }
    httpStatus = response.status;
    if (!response.ok) {
      // Error bodies may echo request content, so they are never read.
      await response.body?.cancel().catch(() => undefined);
      const retryAfter = retryAfterSeconds(response.headers.get("retry-after"));
      if (response.status === 429) return finish(failure("rate_limited", null, retryAfter));
      if (response.status === 529 || response.status === 503) {
        return finish(failure("overloaded", null, retryAfter));
      }
      return finish({
        ok: false,
        reason: "provider_error",
        usage: null,
        httpStatus: response.status,
      });
    }
    let payload: unknown;
    try {
      payload = await response.json();
    } catch {
      return finish(failure(controller.signal.aborted ? "timeout" : "provider_error", null));
    }

    const answer = prepared.read(payload);
    if (!answer) return finish(failure("provider_error", null));
    // Every answer that arrived was billed, so every outcome from here carries its usage.
    const usage: AiUsage = { ...answer.tokens, costUsd: costUsd(spec.price, answer.tokens) };
    if (answer.finish === "refused") return finish(failure("refused", usage));
    if (answer.finish === "other") return finish(failure("provider_error", usage));
    const stop = answer.finish;
    const model = answer.model && answer.model.length <= 100 ? answer.model : route.model;

    if (request.output.kind === "json") {
      let json: unknown;
      try {
        json = JSON.parse(answer.text);
      } catch {
        return finish(failure("invalid_output", usage));
      }
      if (!matchesSchema(json, request.output.schema)) {
        return finish(failure("invalid_output", usage));
      }
      return finish({ ok: true, text: answer.text, json, usage, model, stop });
    }
    if (!answer.text.trim()) return finish(failure("provider_error", usage));
    return finish({ ok: true, text: answer.text, usage, model, stop });
  } finally {
    clearTimeout(timer);
    request.signal?.removeEventListener("abort", abort);
  }
}
