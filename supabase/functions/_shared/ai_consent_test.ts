import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  aiCoachingConsent,
  aiConsentWithProvider,
  coachChatConsentRefusal,
  type ConsentRpc,
  type ConsentV2Rpc,
} from "./ai_consent.ts";
import { dailyDecisionProvider } from "./providers/daily_decision_provider.ts";
import type { CoachModelProvider } from "./providers/coach_model_provider.ts";
import { MockCoachModelProvider } from "./providers/mock_coach_model_provider.ts";

const answering = (data: unknown, error: unknown = null): ConsentRpc => () =>
  Promise.resolve({ data, error });

Deno.test("a current grant allows AI coaching", async () => {
  assertEquals(await aiCoachingConsent(answering(true), "u", "coach_chat"), "granted");
});

Deno.test("no grant, or a withdrawal, is not granted", async () => {
  assertEquals(await aiCoachingConsent(answering(false), "u", "coach_chat"), "not_granted");
});

Deno.test("a failed or malformed check is unavailable, never granted", async () => {
  assertEquals(
    await aiCoachingConsent(answering(null, { code: "PGRST202" }), "u", "coach_chat"),
    "unavailable",
  );
  assertEquals(await aiCoachingConsent(answering("yes"), "u", "coach_chat"), "unavailable");
  assertEquals(
    await aiCoachingConsent(() => Promise.reject(new Error("offline")), "u", "coach_chat"),
    "unavailable",
  );
});

Deno.test("the check asks about the signed-in athlete", async () => {
  let asked = "";
  await aiCoachingConsent(
    (_name, params) => {
      asked = params.target_user_id;
      return Promise.resolve({ data: true, error: null });
    },
    "athlete-1",
    "coach_chat",
  );
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

Deno.test("a purpose asks about that purpose's current notice", async () => {
  let asked: Record<string, unknown> = {};
  await aiCoachingConsent(
    (_name, params) => {
      asked = params;
      return Promise.resolve({ data: true, error: null });
    },
    "athlete-1",
    "onboarding_plan",
  );
  assertEquals(asked, { target_user_id: "athlete-1", consent_purpose: "onboarding_plan" });
});

Deno.test("each caller's purpose reaches the check unchanged", async () => {
  for (const purpose of ["coach_chat", "daily_coaching", "onboarding_plan"] as const) {
    let asked: Record<string, unknown> = {};
    await aiCoachingConsent(
      (_name, params) => {
        asked = params;
        return Promise.resolve({ data: true, error: null });
      },
      "athlete-1",
      purpose,
    );
    assertEquals(asked, { target_user_id: "athlete-1", consent_purpose: purpose });
  }
});

const answeringV2 = (data: unknown, error: unknown = null): ConsentV2Rpc => () =>
  Promise.resolve({ data, error });

Deno.test("v2 returns the grant with the notice's provider and version", async () => {
  assertEquals(
    await aiConsentWithProvider(
      answeringV2({
        schema_version: "1.0",
        granted: true,
        provider: "anthropic",
        notice_version: "ai-coaching-v6",
      }),
      "u",
      "coach_chat",
    ),
    { consent: "granted", provider: "anthropic", noticeVersion: "ai-coaching-v6" },
  );
  assertEquals(
    await aiConsentWithProvider(
      answeringV2({
        schema_version: "1.0",
        granted: false,
        provider: "deepseek",
        notice_version: "meal-photo-ai-v2",
      }),
      "u",
      "meal_vision",
    ),
    { consent: "not_granted", provider: "deepseek", noticeVersion: "meal-photo-ai-v2" },
  );
});

Deno.test("v2: a notice without a known vendor gives no provider", async () => {
  for (const provider of [null, "openai_compatible", "router", "someone_else", 7]) {
    assertEquals(
      await aiConsentWithProvider(
        answeringV2({
          schema_version: "1.0",
          granted: true,
          provider,
          notice_version: "ai-coaching-v5",
        }),
        "u",
        "daily_decision",
      ),
      { consent: "granted", provider: null, noticeVersion: "ai-coaching-v5" },
    );
  }
  assertEquals(
    await aiConsentWithProvider(
      answeringV2({ schema_version: "1.0", granted: false, provider: null, notice_version: null }),
      "u",
      "physique_vision",
    ),
    { consent: "not_granted", provider: null, noticeVersion: null },
  );
});

Deno.test("v2: a failed or malformed check is unavailable, never granted", async () => {
  const unavailable = { consent: "unavailable", provider: null, noticeVersion: null } as const;
  for (
    const rpc of [
      answeringV2(null, { code: "22023" }),
      answeringV2(null),
      answeringV2(true),
      answeringV2([]),
      answeringV2({ granted: "yes", provider: "anthropic", notice_version: "v" }),
      answeringV2({ granted: true, provider: "anthropic", notice_version: 3 }),
      answeringV2({ granted: true, provider: "anthropic" }),
      (() => Promise.reject(new Error("offline"))) as ConsentV2Rpc,
      (() => {
        throw new Error("sync");
      }) as ConsentV2Rpc,
    ]
  ) {
    assertEquals(await aiConsentWithProvider(rpc, "u", "coach_chat"), unavailable);
  }
});

Deno.test("v2 asks about the athlete and the purpose unchanged", async () => {
  for (
    const purpose of [
      "coach_chat",
      "daily_coaching",
      "daily_decision",
      "onboarding_plan",
      "onboarding_questions",
      "meal_vision",
      "physique_vision",
      "library_context",
    ] as const
  ) {
    let asked: [string, Record<string, unknown>] = ["", {}];
    await aiConsentWithProvider(
      (name, params) => {
        asked = [name, params];
        return Promise.resolve({
          data: { granted: true, provider: "anthropic", notice_version: "v" },
          error: null,
        });
      },
      "athlete-1",
      purpose,
    );
    assertEquals(asked, [
      "get_ai_consent_v2",
      { target_user_id: "athlete-1", consent_purpose: purpose },
    ]);
  }
});
