import { assertEquals } from "jsr:@std/assert@1.0.14";
import { supabasePublishableKey, supabaseSecretKey } from "./supabase_keys.ts";

const env = (values: Record<string, string>) => (name: string) => values[name];

Deno.test("with no Tracend secret set, the legacy keys are read", () => {
  const get = env({
    SUPABASE_SERVICE_ROLE_KEY: "legacy-service",
    SUPABASE_ANON_KEY: "legacy-anon",
  });
  assertEquals(supabaseSecretKey(get), "legacy-service");
  assertEquals(supabasePublishableKey(get), "legacy-anon");
});

Deno.test("a Tracend secret wins over the legacy key", () => {
  const get = env({
    SUPABASE_SERVICE_ROLE_KEY: "legacy-service",
    SUPABASE_ANON_KEY: "legacy-anon",
    TRACEND_SUPABASE_SECRET_KEY: "new-secret",
    TRACEND_SUPABASE_PUBLISHABLE_KEY: "new-publishable",
  });
  assertEquals(supabaseSecretKey(get), "new-secret");
  assertEquals(supabasePublishableKey(get), "new-publishable");
});

Deno.test("an empty or blank Tracend secret falls back to the legacy key", () => {
  const get = env({
    SUPABASE_SERVICE_ROLE_KEY: "legacy-service",
    SUPABASE_ANON_KEY: "legacy-anon",
    TRACEND_SUPABASE_SECRET_KEY: "",
    TRACEND_SUPABASE_PUBLISHABLE_KEY: "  ",
  });
  assertEquals(supabaseSecretKey(get), "legacy-service");
  assertEquals(supabasePublishableKey(get), "legacy-anon");
});

Deno.test("each key is switched on its own", () => {
  const get = env({
    SUPABASE_SERVICE_ROLE_KEY: "legacy-service",
    SUPABASE_ANON_KEY: "legacy-anon",
    TRACEND_SUPABASE_SECRET_KEY: "new-secret",
  });
  assertEquals(supabaseSecretKey(get), "new-secret");
  assertEquals(supabasePublishableKey(get), "legacy-anon");
});

Deno.test("nothing set reads as missing", () => {
  assertEquals(supabaseSecretKey(env({})), undefined);
  assertEquals(supabasePublishableKey(env({})), undefined);
});

Deno.test("the default reader uses the process environment", () => {
  Deno.env.set("TRACEND_SUPABASE_SECRET_KEY", "from-process-env");
  try {
    assertEquals(supabaseSecretKey(), "from-process-env");
  } finally {
    Deno.env.delete("TRACEND_SUPABASE_SECRET_KEY");
  }
});
