// Website waitlist: confirm. The confirm page posts the token from the email
// link; the answer is a status the page shows (confirmed, expired,
// unsubscribed or invalid) and, once confirmed, the invite code.
import {
  hashToken,
  json,
  liveDeps,
  preflight,
  readJson,
  TOKEN,
  type WaitlistDeps,
} from "../_shared/waitlist.ts";

export async function handleConfirm(request: Request, deps: WaitlistDeps): Promise<Response> {
  if ("missing" in deps.settings) {
    deps.report(new Error(`waitlist_missing_${deps.settings.missing.join("_")}`), "not_configured");
    return json(null, 503, { error: "unavailable" });
  }
  const site = deps.settings.siteUrl;
  if (request.method === "OPTIONS") return preflight(site);
  if (request.method !== "POST") return json(site, 405, { error: "method_not_allowed" });

  const body = await readJson(request);
  const token = typeof body?.token === "string" ? body.token : "";
  if (!TOKEN.test(token)) return json(site, 200, { status: "invalid" });

  const { data, error } = await deps.rpc("waitlist_confirm", {
    token_hash: await hashToken(token),
  });
  const result = data as { status?: string; referral_code?: string } | null;
  if (error || !result?.status) {
    deps.report(error ?? new Error("waitlist_confirm_empty"), "confirm_failed");
    return json(site, 500, { error: "server_error" });
  }
  return json(site, 200, {
    status: result.status,
    ...(result.referral_code ? { referral_code: result.referral_code } : {}),
  });
}

if (import.meta.main) {
  const deps = liveDeps("waitlist-confirm");
  Deno.serve((request) => handleConfirm(request, deps));
}
