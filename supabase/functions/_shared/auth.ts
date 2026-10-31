import { createClient } from "npm:@supabase/supabase-js@2.49.8";
import { supabasePublishableKey, supabaseSecretKey } from "./supabase_keys.ts";

const jsonHeaders = { "Content-Type": "application/json" };

export function reply(status: number, body: Record<string, unknown>): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders });
}

export class AuthError extends Error {
  readonly status: number;

  constructor(message: string, status: number) {
    super(message);
    this.name = "AuthError";
    this.status = status;
  }
}

export async function requireAuth(request: Request) {
  const url = Deno.env.get("SUPABASE_URL");
  const anonKey = supabasePublishableKey();
  const serviceKey = supabaseSecretKey();
  const authorization = request.headers.get("Authorization");
  if (!url || !anonKey || !serviceKey || !authorization) {
    throw new AuthError("authentication_required", 401);
  }
  const userClient = createClient(url, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData.user) {
    throw new AuthError("invalid_session", 401);
  }
  const serviceClient = createClient(url, serviceKey, { auth: { persistSession: false } });
  return { userId: userData.user.id, userEmail: userData.user.email, userClient, serviceClient };
}
