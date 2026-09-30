import { assertEquals } from "jsr:@std/assert@1.0.14";
import { aiCoachingConsent, type ConsentRpc } from "./ai_consent.ts";

const answering = (data: unknown, error: unknown = null): ConsentRpc => () =>
  Promise.resolve({ data, error });

Deno.test("a current grant allows AI coaching", async () => {
  assertEquals(await aiCoachingConsent(answering(true), "u"), "granted");
});

Deno.test("no grant, or a withdrawal, is not granted", async () => {
  assertEquals(await aiCoachingConsent(answering(false), "u"), "not_granted");
});

Deno.test("a failed or malformed check is unavailable, never granted", async () => {
  assertEquals(
    await aiCoachingConsent(answering(null, { code: "PGRST202" }), "u"),
    "unavailable",
  );
  assertEquals(await aiCoachingConsent(answering("yes"), "u"), "unavailable");
  assertEquals(
    await aiCoachingConsent(() => Promise.reject(new Error("offline")), "u"),
    "unavailable",
  );
});

Deno.test("the check asks about the signed-in athlete", async () => {
  let asked = "";
  await aiCoachingConsent((_name, params) => {
    asked = params.target_user_id;
    return Promise.resolve({ data: true, error: null });
  }, "athlete-1");
  assertEquals(asked, "athlete-1");
});
