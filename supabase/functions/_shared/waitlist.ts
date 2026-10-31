// Shared by the website's waitlist functions: settings, CORS, tokens and the
// confirmation email. The website (site/) calls them without a session, so
// every response carries CORS headers for the site's own origin only.

import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { captureException } from "./sentry.ts";
import { type Mail, sendMail, type SmtpConfig } from "./smtp.ts";
import { supabaseSecretKey } from "./supabase_keys.ts";

/** Must match CONSENT_VERSION in site/src/config.ts (a test checks). */
export const CONSENT_VERSION = "waitlist-2026-10-13";

export interface WaitlistSettings {
  supabaseUrl: string;
  serviceRoleKey: string;
  siteUrl: string; // https://tracend.pages.dev, no trailing slash
  turnstileSecret: string;
  smtp: SmtpConfig;
  emailFrom: string;
}

/** Edge Function secrets. Returns the names that are missing instead of throwing. */
export function readSettings(
  get: (name: string) => string | undefined = (name) => Deno.env.get(name),
): WaitlistSettings | { missing: string[] } {
  const names = [
    "SUPABASE_URL",
    "WAITLIST_SITE_URL",
    "TURNSTILE_SECRET_KEY",
    "SMTP_HOST",
    "SMTP_USER",
    "SMTP_PASSWORD",
    "WAITLIST_EMAIL_FROM",
  ];
  const values = Object.fromEntries(names.map((name) => [name, get(name)?.trim() ?? ""]));
  const serviceRoleKey = supabaseSecretKey(get);
  const missing = names.filter((name) => !values[name]);
  if (!serviceRoleKey) missing.push("SUPABASE_SERVICE_ROLE_KEY");
  if (missing.length || !serviceRoleKey) return { missing };
  return {
    supabaseUrl: values.SUPABASE_URL.replace(/\/+$/, ""),
    serviceRoleKey,
    siteUrl: values.WAITLIST_SITE_URL.replace(/\/+$/, ""),
    turnstileSecret: values.TURNSTILE_SECRET_KEY,
    smtp: { host: values.SMTP_HOST, user: values.SMTP_USER, password: values.SMTP_PASSWORD },
    emailFrom: values.WAITLIST_EMAIL_FROM,
  };
}

export function corsHeaders(siteUrl: string | null): Record<string, string> {
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "Cache-Control": "no-store",
    "Vary": "Origin",
  };
  if (siteUrl) {
    headers["Access-Control-Allow-Origin"] = siteUrl;
    headers["Access-Control-Allow-Methods"] = "POST, OPTIONS";
    headers["Access-Control-Allow-Headers"] = "content-type";
    headers["Access-Control-Max-Age"] = "86400";
  }
  return headers;
}

export function json(
  siteUrl: string | null,
  status: number,
  body: Readonly<Record<string, unknown>>,
): Response {
  return new Response(JSON.stringify(body), { status, headers: corsHeaders(siteUrl) });
}

export function preflight(siteUrl: string | null): Response {
  return new Response(null, { status: 204, headers: corsHeaders(siteUrl) });
}

/** Reads a small JSON object body; null when it is missing, too big or not an object. */
export async function readJson(request: Request): Promise<Record<string, unknown> | null> {
  const text = await request.text().catch(() => "");
  if (!text || text.length > 4096) return null;
  try {
    const value = JSON.parse(text);
    return value && typeof value === "object" && !Array.isArray(value) ? value : null;
  } catch {
    return null;
  }
}

/** A link token: 32 random bytes as 43 base64url characters. */
export const TOKEN = /^[A-Za-z0-9_-]{43}$/;

export function newToken(): string {
  const bytes = crypto.getRandomValues(new Uint8Array(32));
  let binary = "";
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replaceAll("+", "-").replaceAll("/", "_").replace(/=+$/, "");
}

/** The database stores only this hash of each token. */
export async function hashToken(token: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(token));
  return Array.from(new Uint8Array(digest), (b) => b.toString(16).padStart(2, "0")).join("");
}

/** The visitor's address as Supabase's edge sees it; used only as a salted hash. */
export function clientIp(request: Request): string | null {
  const forwarded = request.headers.get("x-forwarded-for")?.split(",")[0];
  const ip = (request.headers.get("cf-connecting-ip") ?? request.headers.get("x-real-ip") ??
    forwarded ?? "").trim();
  return ip.length >= 2 && ip.length <= 64 ? ip : null;
}

export const EMAIL = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;

// Common throwaway-address services. Not exhaustive: Turnstile, the per-network
// limit and the confirmation email do the real work.
const DISPOSABLE = new Set([
  "10minutemail.com",
  "20minutemail.com",
  "discard.email",
  "dispostable.com",
  "emailondeck.com",
  "fakeinbox.com",
  "getnada.com",
  "guerrillamail.com",
  "guerrillamail.net",
  "guerrillamailblock.com",
  "maildrop.cc",
  "mailinator.com",
  "mailnesia.com",
  "mintemail.com",
  "mohmal.com",
  "moakt.com",
  "sharklasers.com",
  "spamgourmet.com",
  "temp-mail.org",
  "tempmail.com",
  "tempmail.dev",
  "tempmailo.com",
  "tempr.email",
  "throwawaymail.com",
  "trashmail.com",
  "yopmail.com",
]);

export function isDisposable(email: string): boolean {
  const domain = email.slice(email.lastIndexOf("@") + 1).toLowerCase();
  return DISPOSABLE.has(domain);
}

/** Keeps known utm_* keys as short strings; anything else is dropped. */
export function cleanUtm(value: unknown): Record<string, string> {
  const out: Record<string, string> = {};
  if (!value || typeof value !== "object" || Array.isArray(value)) return out;
  for (const key of ["source", "medium", "campaign", "content"]) {
    const v = (value as Record<string, unknown>)[key];
    if (typeof v === "string" && v.trim()) out[key] = v.trim().slice(0, 100);
  }
  return out;
}

function escapeHtml(text: string): string {
  return text.replaceAll("&", "&amp;").replaceAll("<", "&lt;").replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

export function confirmationEmail(input: {
  settings: Pick<WaitlistSettings, "siteUrl" | "supabaseUrl" | "emailFrom">;
  to: string;
  confirmToken: string;
  unsubToken: string;
}): Mail {
  const { siteUrl, supabaseUrl, emailFrom } = input.settings;
  const confirm = `${siteUrl}/confirm/#${input.confirmToken}`;
  const unsubscribe = `${siteUrl}/unsubscribe/#${input.unsubToken}`;
  const oneClick = `${supabaseUrl}/functions/v1/waitlist-unsubscribe?token=${input.unsubToken}`;
  const text = [
    "Confirm your place on the Tracend beta waitlist:",
    confirm,
    "",
    "The link works for 7 days. If you didn't ask to join, ignore this email and we won't write again.",
    "",
    "Tracend, an AI personal trainer for iPhone and Apple Watch.",
    `Unsubscribe: ${unsubscribe}`,
  ].join("\n");
  const html = `<!doctype html><html><body style="margin:0;padding:0;background:#f4f4f1">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f1"><tr><td align="center" style="padding:32px 16px">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:480px;background:#ffffff;border-radius:16px">
<tr><td style="padding:32px 28px;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#141516">
<p style="margin:0 0 20px;font-size:13px;font-weight:700;letter-spacing:.08em;text-transform:uppercase">Tracend</p>
<h1 style="margin:0 0 12px;font-size:24px;line-height:1.25">Confirm your place on the beta</h1>
<p style="margin:0 0 24px;font-size:16px;line-height:1.5;color:#3b3d40">Tap the button to confirm your email. The link works for 7 days.</p>
<p style="margin:0 0 28px"><a href="${
    escapeHtml(confirm)
  }" style="display:inline-block;background:#c8f05a;color:#141a05;font-size:16px;font-weight:700;text-decoration:none;padding:14px 22px;border-radius:999px">Confirm my email</a></p>
<p style="margin:0 0 8px;font-size:14px;line-height:1.5;color:#5c5e61">If you didn&rsquo;t ask to join, ignore this email and we won&rsquo;t write again.</p>
<p style="margin:0;font-size:13px;line-height:1.5;color:#7a7c7f">Tracend, an AI personal trainer for iPhone and Apple Watch. <a href="${
    escapeHtml(unsubscribe)
  }" style="color:#7a7c7f">Unsubscribe</a></p>
</td></tr></table></td></tr></table></body></html>`;
  return {
    from: emailFrom,
    to: input.to,
    subject: "Confirm your place on the Tracend beta",
    text,
    html,
    headers: {
      "List-Unsubscribe": `<${oneClick}>`,
      "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    },
  };
}

/** Cloudflare Turnstile server-side check. */
export async function verifyTurnstile(
  secret: string,
  token: string,
  ip: string | null,
  fetcher: typeof fetch = fetch,
): Promise<boolean> {
  if (!token || token.length > 2048) return false;
  const form = new URLSearchParams({ secret, response: token });
  if (ip) form.set("remoteip", ip);
  try {
    const res = await fetcher("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body: form,
      signal: AbortSignal.timeout(8000),
    });
    const data = await res.json();
    return data?.success === true;
  } catch {
    return false;
  }
}

export type Rpc = (
  name: string,
  args: Record<string, unknown>,
) => Promise<{ data: unknown; error: unknown }>;

export interface WaitlistDeps {
  settings: WaitlistSettings | { missing: string[] };
  rpc: Rpc;
  verify: (token: string, ip: string | null) => Promise<boolean>;
  send: (mail: Mail) => Promise<void>;
  report: (error: unknown, failureCode: string) => void;
}

/** Production wiring: the service-role client, Turnstile, SMTP and Sentry. */
export function liveDeps(functionName: string): WaitlistDeps {
  const settings = readSettings();
  const ready = "missing" in settings ? null : settings;
  const client = ready
    ? createClient(ready.supabaseUrl, ready.serviceRoleKey, { auth: { persistSession: false } })
    : null;
  return {
    settings,
    rpc: async (name, args) => {
      if (!client) return { data: null, error: new Error("not_configured") };
      const { data, error } = await client.rpc(name, args);
      return { data, error };
    },
    verify: (token, ip) => verifyTurnstile(ready?.turnstileSecret ?? "", token, ip),
    send: (mail) => sendMail(ready!.smtp, mail),
    report: (error, failureCode) => captureException(error, { functionName, failureCode }),
  };
}
