import { modelSpec } from "./models.ts";
import {
  type AiEffort,
  type AiFeature,
  aiFeatures,
  type AiProvider,
  aiProviders,
  type AiRoute,
  type AiThinking,
} from "./types.ts";

// Per-feature AI settings, all server-side secrets:
//
//   AI_<FEATURE>_PROVIDER           required: anthropic | openai_compatible | gemini
//   AI_<FEATURE>_MODEL              required: a model in models.ts for that provider
//   AI_<FEATURE>_MAX_OUTPUT_TOKENS  required: 1–128000
//   AI_<FEATURE>_TIMEOUT_MS         required: 1000–600000
//   AI_<FEATURE>_BASE_URL           openai_compatible only, and required there: https API base,
//                                   e.g. https://api.deepseek.com/v1 (host must match models.ts)
//   AI_<FEATURE>_THINKING           off (default) | adaptive
//   AI_<FEATURE>_EFFORT             low | medium | high (unset = the model's default)
//   AI_<FEATURE>_EVALUATED          true once the feature's eval passed | false (default)
//
// Keys (required): ANTHROPIC_API_KEY, OPENAI_COMPATIBLE_API_KEY_<FEATURE>, GEMINI_API_KEY. Gemini also needs
// GEMINI_PAID_DATA_TERMS_ACCEPTED=true (AI_SAFETY_SPEC §10). <FEATURE> is the feature in upper
// case, e.g. AI_COACH_CHAT_MODEL.
//
// Any missing or invalid setting returns null: the feature takes its existing rules path.

export type Env = (name: string) => string | undefined;

const maxOutputTokensLimit = 128_000;
const timeoutLimitMs = 600_000;
const thinkingSettings: readonly AiThinking[] = ["off", "adaptive"];
const effortSettings: readonly AiEffort[] = ["low", "medium", "high"];

// The key stays out of the route object (it is logged, compared and passed around); call()
// looks it up here, so only a route built by route() can send a request.
const routeKeys = new WeakMap<AiRoute, string>();

export function routeApiKey(route: AiRoute): string | null {
  return routeKeys.get(route) ?? null;
}

const defaultEnv: Env = (name) => Deno.env.get(name);

const integerSetting = (raw: string | undefined, min: number, max: number): number | null => {
  if (raw === undefined || !/^[0-9]+$/.test(raw)) return null;
  const value = Number(raw);
  return value >= min && value <= max ? value : null;
};

const optional = (raw: string | undefined): string | undefined =>
  raw === undefined || raw.trim() === "" ? undefined : raw.trim();

function providerKey(provider: AiProvider, feature: AiFeature, env: Env): string | undefined {
  switch (provider) {
    case "anthropic":
      return optional(env("ANTHROPIC_API_KEY"));
    case "openai_compatible":
      return optional(env(`OPENAI_COMPATIBLE_API_KEY_${feature.toUpperCase()}`));
    case "gemini":
      return env("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true"
        ? optional(env("GEMINI_API_KEY"))
        : undefined;
  }
}

function parseBaseUrl(raw: string, hosts: readonly string[]): string | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (
    url.protocol !== "https:" || !hosts.includes(url.hostname) || url.username || url.password ||
    url.search || url.hash || url.port
  ) return null;
  return `${url.origin}${url.pathname.replace(/\/+$/, "")}`;
}

export function route(feature: AiFeature, env: Env = defaultEnv): AiRoute | null {
  if (!(aiFeatures as readonly string[]).includes(feature)) return null;
  const setting = (name: string) => optional(env(`AI_${feature.toUpperCase()}_${name}`));

  const provider = setting("PROVIDER");
  if (!provider || !(aiProviders as readonly string[]).includes(provider)) return null;
  const model = setting("MODEL");
  if (!model) return null;
  const spec = modelSpec(provider as AiProvider, model);
  if (!spec) return null;

  const thinking = setting("THINKING") ?? "off";
  if (!(thinkingSettings as readonly string[]).includes(thinking)) return null;
  if (spec.provider === "openai_compatible" && spec.thinking[thinking as AiThinking] === null) {
    return null;
  }

  const effort = setting("EFFORT");
  if (effort !== undefined) {
    if (!(effortSettings as readonly string[]).includes(effort)) return null;
    if (!spec.efforts.includes(effort as AiEffort)) return null;
  }

  const maxOutputTokens = integerSetting(setting("MAX_OUTPUT_TOKENS"), 1, maxOutputTokensLimit);
  const timeoutMs = integerSetting(setting("TIMEOUT_MS"), 1_000, timeoutLimitMs);
  if (maxOutputTokens === null || timeoutMs === null) return null;

  const evaluatedSetting = setting("EVALUATED") ?? "false";
  if (evaluatedSetting !== "true" && evaluatedSetting !== "false") return null;

  const rawBaseUrl = setting("BASE_URL");
  let baseUrl: string | undefined;
  if (spec.provider === "openai_compatible") {
    if (!rawBaseUrl) return null;
    const parsed = parseBaseUrl(rawBaseUrl, spec.hosts);
    if (!parsed) return null;
    baseUrl = parsed;
  } else if (rawBaseUrl !== undefined) {
    return null;
  }

  const apiKey = providerKey(spec.provider, feature, env);
  if (!apiKey) return null;

  const result: AiRoute = Object.freeze({
    feature,
    provider: spec.provider,
    providerLabel: spec.label,
    model,
    ...(baseUrl === undefined ? {} : { baseUrl }),
    thinking: thinking as AiThinking,
    ...(effort === undefined ? {} : { effort: effort as AiEffort }),
    maxOutputTokens,
    timeoutMs,
    evaluated: evaluatedSetting === "true",
  });
  routeKeys.set(result, apiKey);
  return result;
}
