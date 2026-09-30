import { assertEquals } from "jsr:@std/assert@1.0.14";
import { aiCoachingConsent, coachChatConsentRefusal, type ConsentRpc } from "./ai_consent.ts";
import { dailyDecisionProvider } from "./providers/daily_decision_provider.ts";
import type { CoachModelProvider } from "./providers/coach_model_provider.ts";
import { MockCoachModelProvider } from "./providers/mock_coach_model_provider.ts";

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

Deno.test("coach-chat refuses without a grant and when the check fails", () => {
  assertEquals(coachChatConsentRefusal("granted"), null);
  assertEquals(coachChatConsentRefusal("not_granted"), {
    status: 403,
    error: "ai_consent_required",
  });
  assertEquals(coachChatConsentRefusal("unavailable"), {
    status: 503,
    error: "ai_consent_unavailable",
  });
});

Deno.test("the daily decision uses the AI model only with a grant", () => {
  let built = 0;
  const configured = () => {
    built++;
    return { generateDecision: () => Promise.reject(new Error("unused")) } as CoachModelProvider;
  };
  dailyDecisionProvider("granted", configured);
  assertEquals(built, 1);
  for (const consent of ["not_granted", "unavailable"] as const) {
    const provider = dailyDecisionProvider(consent, configured);
    assertEquals(provider instanceof MockCoachModelProvider, true);
  }
  assertEquals(built, 1);
});
