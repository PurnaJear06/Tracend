import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.14";
import {
  cleanUtm,
  clientIp,
  confirmationEmail,
  CONSENT_VERSION,
  hashToken,
  isDisposable,
  newToken,
  readSettings,
  TOKEN,
  verifyTurnstile,
} from "./waitlist.ts";

Deno.test("the consent version matches the website's", async () => {
  const site = await Deno.readTextFile(new URL("../../../site/src/config.ts", import.meta.url));
  assert(site.includes(`CONSENT_VERSION = '${CONSENT_VERSION}'`));
});

Deno.test("tokens are 43 base64url characters and hash to 64 hex", async () => {
  const token = newToken();
  assertMatch(token, TOKEN);
  assert(newToken() !== token);
  assertMatch(await hashToken(token), /^[0-9a-f]{64}$/);
  assertEquals(await hashToken("abc"), await hashToken("abc"));
});

Deno.test("settings list every missing secret and trim trailing slashes", () => {
  const empty = readSettings(() => undefined);
  assert("missing" in empty && empty.missing.length === 8);
  const env: Record<string, string> = {
    SUPABASE_URL: "https://ref.supabase.co/",
    SUPABASE_SERVICE_ROLE_KEY: "service",
    WAITLIST_SITE_URL: "https://tracend.pages.dev/",
    TURNSTILE_SECRET_KEY: "secret",
    SMTP_HOST: "smtp.gmail.com",
    SMTP_USER: "team@tracend.test",
    SMTP_PASSWORD: "pass",
    WAITLIST_EMAIL_FROM: "Tracend <team@tracend.test>",
  };
  const settings = readSettings((name) => env[name]);
  assert(!("missing" in settings));
  assertEquals(settings.siteUrl, "https://tracend.pages.dev");
  assertEquals(settings.supabaseUrl, "https://ref.supabase.co");
  assertEquals(settings.serviceRoleKey, "service");
  const { SUPABASE_SERVICE_ROLE_KEY: _legacy, ...rest } = env;
  const switched = readSettings((name) => ({ ...rest, TRACEND_SUPABASE_SECRET_KEY: "new" })[name]);
  assert(!("missing" in switched));
  assertEquals(switched.serviceRoleKey, "new");
  const noKey = readSettings((name) => rest[name]);
  assert("missing" in noKey && noKey.missing.join() === "SUPABASE_SERVICE_ROLE_KEY");
});

Deno.test("the client address prefers Cloudflare's header, then the first forwarded hop", () => {
  const ip = (headers: Record<string, string>) =>
    clientIp(new Request("https://x.test", { headers }));
  assertEquals(
    ip({ "cf-connecting-ip": "203.0.113.9", "x-forwarded-for": "1.1.1.1" }),
    "203.0.113.9",
  );
  assertEquals(ip({ "x-forwarded-for": "198.51.100.4, 10.0.0.1" }), "198.51.100.4");
  assertEquals(ip({}), null);
});

Deno.test("throwaway domains are refused, real ones are not", () => {
  assert(isDisposable("a@mailinator.com"));
  assert(isDisposable("a@YOPMAIL.com"));
  assert(!isDisposable("a@gmail.com"));
});

Deno.test("only short utm strings survive", () => {
  assertEquals(cleanUtm({ source: "instagram", medium: 3, campaign: "x".repeat(300), evil: "y" }), {
    source: "instagram",
    campaign: "x".repeat(100),
  });
  assertEquals(cleanUtm("nope"), {});
  assertEquals(cleanUtm(["a"]), {});
});

Deno.test("the confirmation email links to the site and offers one-tap unsubscribe", () => {
  const mail = confirmationEmail({
    settings: {
      siteUrl: "https://tracend.pages.dev",
      supabaseUrl: "https://ref.supabase.co",
      emailFrom: "Tracend <team@tracend.test>",
    },
    to: "runner@example.test",
    confirmToken: "C".repeat(43),
    unsubToken: "U".repeat(43),
  });
  assert(mail.text.includes(`https://tracend.pages.dev/confirm/#${"C".repeat(43)}`));
  assert(mail.html.includes(`https://tracend.pages.dev/confirm/#${"C".repeat(43)}`));
  assert(mail.text.includes(`https://tracend.pages.dev/unsubscribe/#${"U".repeat(43)}`));
  assertEquals(
    mail.headers?.["List-Unsubscribe"],
    `<https://ref.supabase.co/functions/v1/waitlist-unsubscribe?token=${"U".repeat(43)}>`,
  );
  assertEquals(mail.headers?.["List-Unsubscribe-Post"], "List-Unsubscribe=One-Click");
  assert(!/[–—]/.test(mail.text + mail.html + mail.subject));
});

Deno.test("Turnstile passes only on success and fails closed on errors", async () => {
  const answer = (body: unknown): typeof fetch => () =>
    Promise.resolve(new Response(JSON.stringify(body)));
  assert(await verifyTurnstile("s", "token", "1.2.3.4", answer({ success: true })));
  assert(!(await verifyTurnstile("s", "token", null, answer({ success: false }))));
  assert(!(await verifyTurnstile("s", "", null, answer({ success: true }))));
  assert(!(await verifyTurnstile("s", "token", null, () => Promise.reject(new Error("down")))));
});
