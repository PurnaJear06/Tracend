// Test doubles for the waitlist functions' dependencies.
import type { Mail } from "./smtp.ts";
import type { WaitlistDeps, WaitlistSettings } from "./waitlist.ts";

export const SITE = "https://tracend.pages.dev";

export const settings: WaitlistSettings = {
  supabaseUrl: "https://ref.supabase.co",
  serviceRoleKey: "service",
  siteUrl: SITE,
  turnstileSecret: "secret",
  smtp: { host: "smtp.test", user: "team@tracend.test", password: "pass" },
  emailFrom: "Tracend <team@tracend.test>",
};

export function fakeDeps(options: {
  rpc?: Record<string, { data: unknown; error?: unknown }>;
  verify?: boolean;
  sendFails?: boolean;
  missing?: string[];
} = {}) {
  const calls: Array<{ name: string; args: Record<string, unknown> }> = [];
  const sent: Mail[] = [];
  const reports: string[] = [];
  const deps: WaitlistDeps = {
    settings: options.missing ? { missing: options.missing } : settings,
    rpc: (name, args) => {
      calls.push({ name, args });
      const answer = options.rpc?.[name] ?? { data: null, error: new Error("unexpected") };
      return Promise.resolve({ data: answer.data, error: answer.error ?? null });
    },
    verify: () => Promise.resolve(options.verify ?? true),
    send: (mail) => {
      sent.push(mail);
      return options.sendFails ? Promise.reject(new Error("smtp_auth_535")) : Promise.resolve();
    },
    report: (_error, code) => {
      reports.push(code);
    },
  };
  return { deps, calls, sent, reports };
}

export function post(path: string, body: unknown, headers: Record<string, string> = {}) {
  return new Request(`https://ref.supabase.co/functions/v1/${path}`, {
    method: "POST",
    headers: { "content-type": "application/json", ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body),
  });
}
