// What went wrong when a model call failed, kept safe to print: the HTTP status and the first 300
// characters of the response body with anything that looks like a key or a token removed. Request
// headers and the key itself are never recorded. Used by the Coach, athlete and judge calls and by
// the preflight, and summarised in the report.

import { matchesSchema } from "../../_shared/ai/json_schema.ts";

/** The most characters of a response body kept. */
export const bodyExcerptChars = 300;

export type CallSource = "coach" | "athlete" | "judge";

/** What a failed call looked like on the wire. */
export type WireError = Readonly<{
  /** The HTTP status, null when no response arrived. */
  status: number | null;
  /**
   * http: a non-2xx answer; network / timeout: no answer; unreadable, no_choices, empty: a 2xx
   * answer without a reply; finish: a finish reason the gateway does not know (a router's
   * `tool_calls`, with the shape of the message); truncated: the answer ran into max_tokens;
   * wrapped: the JSON came inside a fence or prose and was cleaned to the bare object; schema: the
   * JSON does not match the answer schema (the first path that does not).
   */
  kind:
    | "http"
    | "network"
    | "timeout"
    | "unreadable"
    | "no_choices"
    | "empty"
    | "finish"
    | "truncated"
    | "wrapped"
    | "schema";
  /** The redacted start of the body, or a short description. */
  body: string;
}>;

export type ProviderError =
  & WireError
  & Readonly<{
    source: CallSource;
    model: string;
    conversation?: string;
    turn?: number;
  }>;

const redacted = "[redacted]";

// Most specific first, so a key inside a `"api_key": "..."` pair is cut once.
const secretPatterns: readonly [
  RegExp,
  string | ((match: string, ...groups: string[]) => string),
][] = [
  [
    /("?(?:api[_-]?key|x-api-key|authorization|auth[_-]?token|access[_-]?token|token|secret|password|passwd)"?\s*[:=]\s*)("?)(?:Bearer\s+)?[^\s",}\]]+/gi,
    (_match, name, quote) => `${name}${quote}${redacted}`,
  ],
  [/\bBearer\s+[A-Za-z0-9._~+/=-]+/gi, `Bearer ${redacted}`],
  [/\b(?:sk|pk|rk)-[A-Za-z0-9_-]{6,}/g, redacted],
  [/\bAIza[0-9A-Za-z_-]{20,}/g, redacted],
  [/\bgh[pousr]_[A-Za-z0-9]{20,}/g, redacted],
  [/\bxox[abprs]-[A-Za-z0-9-]{10,}/g, redacted],
  [/\beyJ[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]{8,}\.[A-Za-z0-9_-]*/g, redacted],
];

/**
 * The text with keys and tokens removed: the exact secrets given, a bearer credential, a value next
 * to a key-like name (api_key, token, authorization...), well-known key prefixes (sk-, AIza, ghp_,
 * a JWT) and any long mixed letters-and-digits run that could be one.
 */
export function redact(text: string, secrets: readonly string[] = []): string {
  let out = text;
  for (const secret of secrets) {
    if (secret.trim().length >= 6) out = out.split(secret.trim()).join(redacted);
  }
  for (const [pattern, replacement] of secretPatterns) {
    out = out.replace(pattern, replacement as string);
  }
  return out.replace(
    /[A-Za-z0-9_+/=-]{32,}/g,
    (run) => /[0-9]/.test(run) && /[A-Za-z]/.test(run) ? redacted : run,
  );
}

/** An HTML error page (a CDN's 502) reduced to its words, so the first 300 characters say something. */
export function htmlText(body: string): string {
  if (!/^\s*(?:<!doctype html|<html)/i.test(body)) return body;
  const title = body.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] ?? "";
  const text = body.replace(/<!--[\s\S]*?-->/g, " ").replace(
    /<(?:script|style)[\s\S]*?<\/(?:script|style)>/gi,
    " ",
  )
    .replace(/<[^>]+>/g, " ").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
  return `[html page] ${title.trim()} | ${text}`;
}

/** The first 300 characters of a body, after redaction (so a key cut by the limit cannot leak). */
export function excerpt(text: string, secrets: readonly string[] = []): string {
  return redact(htmlText(text), secrets).replace(/\s+/g, " ").trim().slice(0, bodyExcerptChars);
}

/**
 * Who answered, from the response headers that name no one's secrets: the server, a CDN ray id,
 * the content type and a request id. Prepended to an error body.
 */
export function headerNote(headers: Headers): string {
  const names = ["server", "cf-ray", "content-type", "x-request-id", "retry-after"];
  const found = names.flatMap((name) => {
    const value = headers.get(name);
    return value ? [`${name}=${value.slice(0, 60)}`] : [];
  });
  return found.length ? `[${found.join(" ")}] ` : "";
}

/** One line per distinct error: where it came from, the status, the body start and how often. */
export type ErrorGroup = Readonly<{
  source: CallSource;
  model: string;
  status: number | null;
  kind: WireError["kind"];
  body: string;
  count: number;
}>;

export function summariseErrors(errors: readonly ProviderError[]): ErrorGroup[] {
  const groups = new Map<string, { group: ErrorGroup; count: number }>();
  for (const error of errors) {
    const key = [error.source, error.model, error.status, error.kind, error.body].join("\u0000");
    const entry = groups.get(key);
    if (entry) entry.count++;
    else {
      groups.set(key, {
        group: {
          source: error.source,
          model: error.model,
          status: error.status,
          kind: error.kind,
          body: error.body,
          count: 0,
        },
        count: 1,
      });
    }
  }
  return [...groups.values()].map(({ group, count }) => ({ ...group, count }))
    .sort((a, b) => b.count - a.count);
}

export const describeStatus = (status: number | null, kind: WireError["kind"]) =>
  status === null ? kind : `HTTP ${status}`;

/** The distinct errors as report lines. */
export function renderErrorSummary(errors: readonly ProviderError[]): string[] {
  const groups = summariseErrors(errors);
  if (groups.length === 0) return ["No provider errors."];
  return groups.slice(0, 20).map((g) =>
    `- ${g.count}x ${g.source} \`${g.model}\`: ${describeStatus(g.status, g.kind)}${
      g.body ? `: ${g.body.replaceAll("|", "\\|")}` : ""
    }`
  );
}

type JsonSchema = Record<string, unknown>;

const isRecord = (value: unknown): value is Record<string, unknown> =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/**
 * Where a value first departs from a schema, as a path and a reason, or null when it matches. Used
 * to say why a router's JSON-mode reply would be rejected by the gateway, which only says
 * `invalid_output`.
 */
export function schemaProblem(value: unknown, schema: JsonSchema, path = "$"): string | null {
  if (matchesSchema(value, schema)) return null;
  if (schema.type === "object" && isRecord(value)) {
    const properties = isRecord(schema.properties) ? schema.properties : {};
    for (const key of Array.isArray(schema.required) ? schema.required : []) {
      if (!Object.hasOwn(value, String(key))) return `${path}.${key} is missing`;
    }
    if (schema.additionalProperties === false) {
      const extra = Object.keys(value).find((key) => !Object.hasOwn(properties, key));
      if (extra !== undefined) return `${path}.${extra} is not in the schema`;
    }
    for (const [key, sub] of Object.entries(properties)) {
      if (Object.hasOwn(value, key) && isRecord(sub)) {
        const found = schemaProblem(value[key], sub, `${path}.${key}`);
        if (found) return found;
      }
    }
  }
  if (schema.type === "array" && Array.isArray(value) && isRecord(schema.items)) {
    for (const [index, item] of value.entries()) {
      const found = schemaProblem(item, schema.items, `${path}[${index}]`);
      if (found) return found;
    }
  }
  const shown = typeof value === "string" ? JSON.stringify(value.slice(0, 40)) : typeof value;
  return `${path} does not match (${shown})`;
}

/**
 * Whether a failed call says the router account has no credit left (HTTP 402, or the router's
 * "Insufficient credits" in a 429): every later call would fail the same way and spend nothing, so
 * the run stops and says so instead of ending conversations one by one as athlete or Coach errors.
 */
export function isCreditsError(error: Pick<WireError, "status" | "body">): boolean {
  return error.status === 402 ||
    /insufficient credits|payment[_ ]required|top up/i.test(error.body);
}
