import { type ModelSpec, modelSpec, vendorHosts, vendorLabels } from "./models.ts";
import {
  type AiEffort,
  type AiFeature,
  aiFeatures,
  type AiProvider,
  aiProviders,
  type AiRoute,
  type AiThinking,
  type AiVendor,
} from "./types.ts";

// Per-feature AI settings, all server-side secrets:
//
//   AI_<FEATURE>_PROVIDER           required: anthropic | openai_compatible | gemini
//   AI_<FEATURE>_MODEL              required: a model in models.ts for that provider
//   AI_<FEATURE>_MAX_OUTPUT_TOKENS  required: 1–32000
//   AI_<FEATURE>_TIMEOUT_MS         required: 1000–150000 (inside the Edge Function wall clock)
//   AI_<FEATURE>_BASE_URL           openai_compatible only, and required there: the https API
//                                   base on the vendor's host, e.g. https://api.deepseek.com/v1
//   AI_<FEATURE>_THINKING           off (default) | adaptive
//   AI_<FEATURE>_EFFORT             low | medium | high (unset = the model's default)
//   AI_<FEATURE>_EVALUATED          true once the feature's eval passed | false (default)
//   AI_<FEATURE>_VENDOR             unset (the model's vendor) | router
//
// Keys (required): ANTHROPIC_API_KEY, OPENAI_COMPATIBLE_API_KEY_<FEATURE>, GEMINI_API_KEY.
// Gemini also needs GEMINI_PAID_DATA_TERMS_ACCEPTED=true (AI_SAFETY_SPEC §10). <FEATURE> is the
// feature in upper case, e.g. AI_COACH_CHAT_MODEL.
//
// VENDOR=router sends an OpenAI-compatible model's request to any https BASE_URL, for synthetic
// evals through a router. The route's vendor is then "router", which no athlete notice names,
// so call() never sends an athlete's data through it.
//
// Any missing or invalid setting returns null: the feature takes its existing rules path. So
// does a setting that would be accepted and then ignored (an effort the request cannot carry,
// thinking "off" on a model that cannot turn it off).

export type Env = (name: string) => string | undefined;

const maxOutputTokensLimit = 32_000;
const timeoutLimitMs = 150_000;
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

/** The API base, or null when it is not https on an allowed host (any host when hosts is null). */
function parseBaseUrl(raw: string, hosts: readonly string[] | null): string | null {
  let url: URL;
  try {
    url = new URL(raw);
  } catch {
    return null;
  }
  if (url.protocol !== "https:" || url.username || url.password || url.search || url.hash) {
    return null;
  }
  if (hosts !== null && (!hosts.includes(url.hostname) || url.port)) return null;
  return `${url.origin}${url.pathname.replace(/\/+$/, "")}`;
}

function thinkingAllowed(spec: ModelSpec, thinking: AiThinking): boolean {
  switch (spec.provider) {
    case "anthropic":
      return thinking === "adaptive" || spec.thinkingOff !== null;
    case "openai_compatible":
      return spec.thinking[thinking] !== null;
    case "gemini":
      return true;
  }
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

  const vendorSetting = setting("VENDOR");
  if (vendorSetting !== undefined && vendorSetting !== "router") return null;
  if (vendorSetting === "router" && spec.provider !== "openai_compatible") return null;
  const vendor: AiVendor = vendorSetting === "router" ? "router" : spec.vendor;

  const thinking = setting("THINKING") ?? "off";
  if (!(thinkingSettings as readonly string[]).includes(thinking)) return null;
  if (!thinkingAllowed(spec, thinking as AiThinking)) return null;

  const effort = setting("EFFORT");
  if (effort !== undefined) {
    if (!(effortSettings as readonly string[]).includes(effort)) return null;
    if (!spec.efforts.includes(effort as AiEffort)) return null;
    if (spec.effortNeedsThinking && thinking !== "adaptive") return null;
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
    const hosts = vendor === "router" ? null : vendorHosts[spec.vendor] ?? [];
    const parsed = parseBaseUrl(rawBaseUrl, hosts);
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
    vendor,
    providerLabel: vendorLabels[vendor],
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
