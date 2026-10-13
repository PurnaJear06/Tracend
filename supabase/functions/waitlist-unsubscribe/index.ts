// Website waitlist: unsubscribe. Two callers: the unsubscribe page (JSON body
// with the token) and mail apps' one-tap unsubscribe (RFC 8058: a form POST to
// the List-Unsubscribe address, token in the query string).
import {
  hashToken,
  json,
  liveDeps,
  preflight,
  readJson,
  TOKEN,
  type WaitlistDeps,
} from "../_shared/waitlist.ts";

export async function handleUnsubscribe(
  request: Request,
  deps: WaitlistDeps,
): Promise<Response> {
  if ("missing" in deps.settings) {
    deps.report(new Error(`waitlist_missing_${deps.settings.missing.join("_")}`), "not_configured");
    return json(null, 503, { error: "unavailable" });
  }
  const site = deps.settings.siteUrl;
  if (request.method === "OPTIONS") return preflight(site);
  if (request.method !== "POST") return json(site, 405, { error: "method_not_allowed" });

  let token = new URL(request.url).searchParams.get("token");
  if (token === null) {
    const body = await readJson(request);
    token = typeof body?.token === "string" ? String(body.token) : "";
  }
  if (!TOKEN.test(token)) return json(site, 200, { status: "invalid" });

  const { data, error } = await deps.rpc("waitlist_unsubscribe", {
    token_hash: await hashToken(token),
  });
  const result = data as { status?: string } | null;
  if (error || !result?.status) {
    deps.report(error ?? new Error("waitlist_unsubscribe_empty"), "unsubscribe_failed");
    return json(site, 500, { error: "server_error" });
  }
  return json(site, 200, { status: result.status });
}

if (import.meta.main) {
  const deps = liveDeps("waitlist-unsubscribe");
  Deno.serve((request) => handleUnsubscribe(request, deps));
}
