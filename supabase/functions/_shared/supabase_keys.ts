/**
 * The two Supabase API keys an Edge Function holds, read in one place so the legacy JWT keys
 * (anon, service_role), which Supabase retires, can be swapped for the new publishable and secret
 * keys without touching a call site.
 *
 * Each key is the Edge secret named here when it is set, else the legacy variable the platform
 * injects. The Tracend names carry no `SUPABASE_` prefix because `supabase secrets set` refuses
 * that prefix. Nothing sets them today, so every function keeps reading the legacy keys. The
 * steps to switch are in docs/handoff/supabase-key-migration.md.
 */
type Get = (name: string) => string | undefined;

const fromEnv: Get = (name) => Deno.env.get(name);

function firstSet(get: Get, names: readonly string[]): string | undefined {
  for (const name of names) {
    const value = get(name)?.trim();
    if (value) return value;
  }
  return undefined;
}

/** The key that bypasses row level security: TRACEND_SUPABASE_SECRET_KEY, else the service_role key. */
export function supabaseSecretKey(get: Get = fromEnv): string | undefined {
  return firstSet(get, ["TRACEND_SUPABASE_SECRET_KEY", "SUPABASE_SERVICE_ROLE_KEY"]);
}

/** The key that acts as the signed-in user: TRACEND_SUPABASE_PUBLISHABLE_KEY, else the anon key. */
export function supabasePublishableKey(get: Get = fromEnv): string | undefined {
  return firstSet(get, ["TRACEND_SUPABASE_PUBLISHABLE_KEY", "SUPABASE_ANON_KEY"]);
}
