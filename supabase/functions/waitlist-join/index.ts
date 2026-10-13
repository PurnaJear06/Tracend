// Website waitlist: join. Checks the address and the Turnstile token, records
// the signup through public.waitlist_join and emails a confirmation link. New
// and existing addresses get the same answer, so the form reveals nobody.
import {
  cleanUtm,
  clientIp,
  confirmationEmail,
  CONSENT_VERSION,
  EMAIL,
  hashToken,
  isDisposable,
  json,
  liveDeps,
  newToken,
  preflight,
  readJson,
  type WaitlistDeps,
} from "../_shared/waitlist.ts";

const REF = /^[0-9A-HJKMNP-TV-Z]{8}$/;

export async function handleJoin(request: Request, deps: WaitlistDeps): Promise<Response> {
  if ("missing" in deps.settings) {
    deps.report(new Error(`waitlist_missing_${deps.settings.missing.join("_")}`), "not_configured");
    return json(null, 503, { error: "unavailable" });
  }
  const settings = deps.settings;
  const site = settings.siteUrl;
  if (request.method === "OPTIONS") return preflight(site);
  if (request.method !== "POST") return json(site, 405, { error: "method_not_allowed" });

  const body = await readJson(request);
  if (!body) return json(site, 400, { error: "invalid_request" });
  const email = typeof body.email === "string" ? body.email.trim().toLowerCase() : "";
  if (body.consent_version !== CONSENT_VERSION) return json(site, 409, { error: "stale_page" });
  if (email.length < 6 || email.length > 254 || !EMAIL.test(email)) {
    return json(site, 422, { error: "invalid_email" });
  }
  if (isDisposable(email)) return json(site, 422, { error: "disposable_email" });

  const ip = clientIp(request);
  const token = typeof body.turnstile_token === "string" ? body.turnstile_token : "";
  if (!(await deps.verify(token, ip))) return json(site, 403, { error: "verification_failed" });

  const ref = typeof body.ref === "string" && REF.test(body.ref.toUpperCase())
    ? body.ref.toUpperCase()
    : null;
  const zone = typeof body.time_zone === "string" ? body.time_zone.slice(0, 64) : null;
  const confirmToken = newToken();
  const unsubToken = newToken();
  const confirmHash = await hashToken(confirmToken);

  const { data, error } = await deps.rpc("waitlist_join", {
    join_email: email,
    client_ip: ip,
    confirm_hash: confirmHash,
    unsub_hash: await hashToken(unsubToken),
    ref_code: ref,
    consent: CONSENT_VERSION,
    zone,
    utm: cleanUtm(body.utm),
  });
  const result = data as { outcome?: string; referral_code?: string } | null;
  if (error || !result?.outcome) {
    deps.report(error ?? new Error("waitlist_join_empty"), "join_failed");
    return json(site, 500, { error: "server_error" });
  }
  if (result.outcome === "rate_limited") return json(site, 429, { error: "rate_limited" });

  if (result.outcome === "send") {
    try {
      await deps.send(confirmationEmail({ settings, to: email, confirmToken, unsubToken }));
    } catch (sendError) {
      deps.report(sendError, "email_failed");
      const undo = await deps.rpc("waitlist_unsent", {
        join_email: email,
        confirm_hash: confirmHash,
      });
      if (undo.error) deps.report(undo.error, "unsent_failed");
      return json(site, 502, { error: "email_failed" });
    }
  }
  return json(site, 200, { referral_code: result.referral_code ?? null });
}

if (import.meta.main) {
  const deps = liveDeps("waitlist-join");
  Deno.serve((request) => handleJoin(request, deps));
}
