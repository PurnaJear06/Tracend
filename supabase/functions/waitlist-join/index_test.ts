import { assert, assertEquals, assertMatch } from "jsr:@std/assert@1.0.14";
import { CONSENT_VERSION } from "../_shared/waitlist.ts";
import { fakeDeps, post, SITE } from "../_shared/waitlist_fakes.ts";
import { handleJoin } from "./index.ts";

const join = (overrides: Record<string, unknown> = {}) =>
  post("waitlist-join", {
    email: " Runner@Example.test ",
    turnstile_token: "tok",
    consent_version: CONSENT_VERSION,
    ref: "abcd2345",
    time_zone: "Asia/Kolkata",
    utm: { source: "instagram" },
    ...overrides,
  }, { "cf-connecting-ip": "203.0.113.9" });

const sendOutcome = { waitlist_join: { data: { outcome: "send", referral_code: "7K3M9QXZ" } } };

Deno.test("a new signup is recorded with hashes only and gets one email", async () => {
  const { deps, calls, sent } = fakeDeps({ rpc: sendOutcome });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { referral_code: "7K3M9QXZ" });
  assertEquals(res.headers.get("access-control-allow-origin"), SITE);
  const args = calls[0].args;
  assertEquals(calls[0].name, "waitlist_join");
  assertEquals(args.join_email, "runner@example.test");
  assertEquals(args.client_ip, "203.0.113.9");
  assertEquals(args.ref_code, "ABCD2345");
  assertEquals(args.consent, CONSENT_VERSION);
  assertEquals(args.utm, { source: "instagram" });
  assertMatch(String(args.confirm_hash), /^[0-9a-f]{64}$/);
  assertMatch(String(args.unsub_hash), /^[0-9a-f]{64}$/);
  assertEquals(sent.length, 1);
  assertEquals(sent[0].to, "runner@example.test");
  const token = sent[0].text.match(/confirm\/#([A-Za-z0-9_-]{43})/)?.[1];
  assert(
    token && !JSON.stringify(args).includes(token),
    "the raw token never reaches the database",
  );
});

Deno.test("an address already emailed gets the same answer and no second email", async () => {
  const { deps, sent } = fakeDeps({
    rpc: { waitlist_join: { data: { outcome: "none", referral_code: "7K3M9QXZ" } } },
  });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { referral_code: "7K3M9QXZ" });
  assertEquals(sent.length, 0);
});

Deno.test("a failed email is undone so the next try sends at once", async () => {
  const { deps, calls, reports } = fakeDeps({
    rpc: { ...sendOutcome, waitlist_unsent: { data: null } },
    sendFails: true,
  });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 502);
  assertEquals(await res.json(), { error: "email_failed" });
  assertEquals(calls[1].name, "waitlist_unsent");
  assertEquals(calls[1].args.confirm_hash, calls[0].args.confirm_hash);
  assertEquals(reports, ["email_failed"]);
});

Deno.test("bad input is refused before Turnstile or the database", async () => {
  const cases: Array<[Request, number, string]> = [
    [join({ email: "not-an-email" }), 422, "invalid_email"],
    [join({ email: "a@mailinator.com" }), 422, "disposable_email"],
    [join({ consent_version: "waitlist-2020-01-01" }), 409, "stale_page"],
    [post("waitlist-join", "{not json"), 400, "invalid_request"],
    [post("waitlist-join", "[1,2]"), 400, "invalid_request"],
  ];
  for (const [request, status, error] of cases) {
    const { deps, calls } = fakeDeps({ rpc: sendOutcome });
    const res = await handleJoin(request, deps);
    assertEquals(res.status, status, error);
    assertEquals((await res.json()).error, error);
    assertEquals(calls.length, 0);
  }
});

Deno.test("a failed bot check stops the signup", async () => {
  const { deps, calls } = fakeDeps({ rpc: sendOutcome, verify: false });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 403);
  assertEquals((await res.json()).error, "verification_failed");
  assertEquals(calls.length, 0);
});

Deno.test("too many tries from one network are refused", async () => {
  const { deps, sent } = fakeDeps({
    rpc: { waitlist_join: { data: { outcome: "rate_limited" } } },
  });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 429);
  assertEquals((await res.json()).error, "rate_limited");
  assertEquals(sent.length, 0);
});

Deno.test("a database error is reported and answered generically", async () => {
  const { deps, reports } = fakeDeps({
    rpc: { waitlist_join: { data: null, error: { code: "XX" } } },
  });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 500);
  assertEquals((await res.json()).error, "server_error");
  assertEquals(reports, ["join_failed"]);
});

Deno.test("an invalid referral code is dropped, not refused", async () => {
  const { deps, calls } = fakeDeps({ rpc: sendOutcome });
  await handleJoin(join({ ref: "ILOU0000" }), deps);
  assertEquals(calls[0].args.ref_code, null);
});

Deno.test("preflight and methods follow CORS for the site only", async () => {
  const { deps } = fakeDeps();
  const pre = await handleJoin(
    new Request("https://ref.supabase.co/functions/v1/waitlist-join", { method: "OPTIONS" }),
    deps,
  );
  assertEquals(pre.status, 204);
  assertEquals(pre.headers.get("access-control-allow-origin"), SITE);
  assertEquals(pre.headers.get("access-control-allow-headers"), "content-type");
  const get = await handleJoin(
    new Request("https://ref.supabase.co/functions/v1/waitlist-join"),
    deps,
  );
  assertEquals(get.status, 405);
});

Deno.test("missing secrets answer 503 and are reported by name", async () => {
  const { deps, reports } = fakeDeps({ missing: ["SMTP_PASSWORD"] });
  const res = await handleJoin(join(), deps);
  assertEquals(res.status, 503);
  assertEquals(reports, ["not_configured"]);
});
