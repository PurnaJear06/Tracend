// The service-role RPC caller the Coach context contributors and lookups share. The client is
// built on first use, so importing the registry needs no environment (tests, type checks). A
// missing key fails the call, which the host leaves out of the turn, and the next call tries
// again.

/** An RPC call, typed structurally so any Supabase client fits. */
export type ServiceRpc = (
  name: string,
  params: Record<string, unknown>,
) => PromiseLike<{ data: unknown; error: unknown }>;

export function serviceRoleRpc(): ServiceRpc {
  let rpc: ServiceRpc | undefined;
  return async (name, params) => {
    if (!rpc) {
      const url = Deno.env.get("SUPABASE_URL");
      const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!url || !key) throw new Error("service role is not configured");
      const { createClient } = await import("npm:@supabase/supabase-js@2.49.8");
      const client = createClient(url, key, { auth: { persistSession: false } });
      rpc = (rpcName, rpcParams) => client.rpc(rpcName, rpcParams);
    }
    return rpc(name, params);
  };
}

/** The one caller the contributors and the lookup runner use. */
export const coachServiceRpc: ServiceRpc = serviceRoleRpc();

/** Reads a baseline payload for a user and coaching date (a service-role RPC). */
export type StateSource = (userId: string, localDate: string) => Promise<unknown>;

export function stateSourceFromRpc(rpc: ServiceRpc, name: string): StateSource {
  return async (userId, localDate) => {
    const { data, error } = await rpc(name, { p_user_id: userId, p_local_date: localDate });
    if (error) throw new Error(`${name} unavailable`);
    return data;
  };
}
