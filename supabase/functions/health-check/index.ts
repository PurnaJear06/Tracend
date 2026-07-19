import { createClient } from "npm:@supabase/supabase-js@2.49.8";

const headers = { "Content-Type": "application/json" };
const reply = (status: number, body: Record<string, unknown>) =>
  new Response(JSON.stringify(body), { status, headers });

Deno.serve(async (request) => {
  if (request.method !== "GET" && request.method !== "HEAD") {
    return reply(405, { error: "method_not_allowed", allowed_methods: ["GET", "HEAD"] });
  }

  const url = Deno.env.get("SUPABASE_URL");
  const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  const version = Deno.env.get("FUNCTION_BUILD_VERSION") ?? "0.0.0";

  if (!url || !key) {
    return reply(500, { status: "error", detail: "missing_environment", version });
  }

  let dbStatus = "unknown";
  let dbLatencyMs = 0;
  const dbStart = performance.now();
  try {
    const client = createClient(url, key, { auth: { persistSession: false } });
    const { error } = await client.from("user_accounts").select("id", {
      head: true,
      count: "exact",
    });
    dbLatencyMs = Math.round(performance.now() - dbStart);
    dbStatus = error ? `error: ${error.message}` : "connected";
  } catch (err) {
    dbLatencyMs = Math.round(performance.now() - dbStart);
    dbStatus = `unreachable: ${err instanceof Error ? err.message : String(err)}`;
  }

  const healthy = dbStatus === "connected";
  return reply(healthy ? 200 : 503, {
    status: healthy ? "ok" : "degraded",
    database: dbStatus,
    database_latency_ms: dbLatencyMs,
    version,
    timestamp: new Date().toISOString(),
  });
});
