import { assertEquals } from "jsr:@std/assert@1.0.14";
import { handleMealMediaRetention } from "./index.ts";

function withEnv<T>(values: Record<string, string>, run: () => Promise<T>): Promise<T> {
  const before = Object.keys(values).map((key) => [key, Deno.env.get(key)] as const);
  for (const [key, value] of Object.entries(values)) Deno.env.set(key, value);
  return run().finally(() => {
    for (const [key, value] of before) {
      if (value === undefined) Deno.env.delete(key);
      else Deno.env.set(key, value);
    }
  });
}

const env = {
  SUPABASE_URL: "http://127.0.0.1:1",
  SUPABASE_SERVICE_ROLE_KEY: "service-role-test-value",
  RETENTION_WORKER_SECRET: "worker-secret-test-value",
};

const post = (authorization?: string) =>
  new Request("http://localhost/", {
    method: "POST",
    headers: authorization ? { Authorization: authorization } : {},
  });

Deno.test("the worker refuses anything but its own bearer secret", async () => {
  await withEnv(env, async () => {
    for (
      const header of [
        undefined,
        "Bearer wrong",
        "Bearer worker-secret-test-valu",
        "worker-secret-test-value",
      ]
    ) {
      const result = await handleMealMediaRetention(post(header));
      assertEquals(result.status, 401);
      assertEquals(await result.json(), { error: "authentication_required" });
    }
  });
});

Deno.test("the worker refuses to run without its secret configured", async () => {
  await withEnv({ ...env, RETENTION_WORKER_SECRET: "" }, async () => {
    assertEquals((await handleMealMediaRetention(post("Bearer "))).status, 401);
  });
});

Deno.test("the worker answers only POST", async () => {
  assertEquals((await handleMealMediaRetention(new Request("http://localhost/"))).status, 405);
});
