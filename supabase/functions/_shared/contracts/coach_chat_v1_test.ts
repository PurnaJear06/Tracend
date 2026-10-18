import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.13";
import {
  coachChatAnswerLimits,
  CoachChatAnswerValidationError,
  parseCoachChatAnswer,
  parseCoachChatRequest,
} from "./coach_chat_v1.ts";
import appRequestFixture from "../../../../test/contract/fixtures/coach_chat_request_v1_1.json" with {
  type: "json",
};

Deno.test("chat request rejects ownership and accepts bounded input", () => {
  const request = parseCoachChatRequest({
    schema_version: "1.0",
    thread_id: "11111111-1111-4111-8111-111111111111",
    question: "What should I focus on in today's workout?",
    timezone: "Asia/Kolkata",
    idempotency_key: "22222222-2222-4222-8222-222222222222",
  });
  assertEquals(request.question.startsWith("What"), true);
  assertThrows(() => parseCoachChatRequest({ ...request, user_id: "unsafe" }));
});

Deno.test("chat request accepts app schema 1.0 and 1.1 only", () => {
  const request = {
    schema_version: "1.1",
    thread_id: "11111111-1111-4111-8111-111111111111",
    question: "How long until 72 kg?",
    timezone: "Asia/Kolkata",
    idempotency_key: "22222222-2222-4222-8222-222222222222",
  };
  assertEquals(parseCoachChatRequest(request).schema_version, "1.1");
  assertThrows(() => parseCoachChatRequest({ ...request, schema_version: "2.0" }));
});

Deno.test("the request the app builds (shared contract fixture) parses unchanged", () => {
  assertEquals(parseCoachChatRequest(appRequestFixture), appRequestFixture);
});

Deno.test("formatting a little over the preferred length no longer rejects an accurate answer", () => {
  const answer = {
    answer: "Grounded answer",
    evidence: [],
    missing_data: ["Maintenance calories — you haven't logged meals, so intake isn't measured"],
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [{
      step: "Compare the 14-day training load against the plan's weekly session target",
      value: "7 sessions in 14 days against a plan of 5 per week, so slightly under plan",
      evidence_id: null,
    }],
  };
  assertEquals(parseCoachChatAnswer(answer, []).answer, "Grounded answer");
  const error = assertThrows(
    () =>
      parseCoachChatAnswer({
        ...answer,
        reasoning_chain: [{
          step: "x".repeat(coachChatAnswerLimits.reasoningStepMaxLength + 1),
          value: "v",
          evidence_id: null,
        }],
      }, []),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "reasoning_step_too_long");
});

Deno.test("chat answer rejects unsupported evidence", () => {
  const answer = {
    answer: "Keep the approved plan.",
    evidence: [{
      code: "APPROVED_PLAN_ACTIVE",
      label: "Approved plan",
      source: "feature_snapshot",
    }],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: ["Show today's workout"],
  };
  assertEquals(parseCoachChatAnswer(answer, ["APPROVED_PLAN_ACTIVE"]).safety_state, "allowed");
  assertThrows(() => parseCoachChatAnswer(answer, []));
});

Deno.test("chat answer exposes only a finite validation rule and JSON path", () => {
  const error = assertThrows(
    () =>
      parseCoachChatAnswer({
        answer: "Grounded answer",
        evidence: [{ code: "INVENTED", label: "No", source: "feature_snapshot" }],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [],
      }, ["APPROVED_PLAN_ACTIVE"]),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "evidence_code_not_permitted");
  assertEquals(error.path, "evidence[0].code");
  assertEquals(error.message.includes("Grounded answer"), false);
});

Deno.test("chat answer reports reasoning limits from shared constants", () => {
  const error = assertThrows(
    () =>
      parseCoachChatAnswer({
        answer: "Grounded answer",
        evidence: [],
        missing_data: [],
        safety_state: "allowed",
        suggested_follow_ups: [],
        reasoning_chain: [{
          step: "Recovery",
          value: "x".repeat(coachChatAnswerLimits.reasoningValueMaxLength + 1),
          evidence_id: null,
        }],
      }, []),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "reasoning_value_too_long");
  assertEquals(error.path, "reasoning_chain[0].value");
  assertEquals(error.limit, coachChatAnswerLimits.reasoningValueMaxLength);
});

const libraryAnswer = (code: string, source = "library", label = "A label the model wrote") => ({
  answer: "Ten or more weekly sets is where the research points.",
  evidence: [{ code, label, source }],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
});

const shownVolume = {
  schoenfeld_2017_weekly_volume: { label: "Resistance training volume and growth (2017)" },
};

Deno.test("library evidence cites a source id that was shown this turn, and only one", () => {
  const parsed = parseCoachChatAnswer(
    libraryAnswer("schoenfeld_2017_weekly_volume"),
    ["APPROVED_PLAN_ACTIVE"],
    undefined,
    shownVolume,
  );
  assertEquals(parsed.evidence[0].source, "library");
  for (
    const [code, sources] of [
      ["made_up_2019_claim", shownVolume],
      ["APPROVED_PLAN_ACTIVE", shownVolume],
      ["toString", shownVolume],
      ["schoenfeld_2017_weekly_volume", {}],
    ] as const
  ) {
    const error = assertThrows(
      () => parseCoachChatAnswer(libraryAnswer(code), ["APPROVED_PLAN_ACTIVE"], undefined, sources),
      CoachChatAnswerValidationError,
    );
    assertEquals(error.rule, "citation_not_retrieved");
    assertEquals(error.path, "evidence[0].code");
  }
});

Deno.test("the server writes a library citation's label from the retrieved source, not the model", () => {
  const answer = libraryAnswer("schoenfeld_2017_weekly_volume");
  const parsed = parseCoachChatAnswer(answer, ["APPROVED_PLAN_ACTIVE"], undefined, shownVolume);
  assertEquals(parsed.evidence, [{
    code: "schoenfeld_2017_weekly_volume",
    label: "Resistance training volume and growth (2017)",
    source: "library",
  }]);
  // The model's own object is not changed, and other evidence keeps the model's label.
  assertEquals(answer.evidence[0].label, "A label the model wrote");
  const mixed = parseCoachChatAnswer(
    {
      ...answer,
      evidence: [
        { code: "APPROVED_PLAN_ACTIVE", label: "Plan is active", source: "coach_context" },
        ...answer.evidence,
      ],
    },
    ["APPROVED_PLAN_ACTIVE"],
    undefined,
    shownVolume,
  );
  assertEquals(mixed.evidence.map((item) => item.label), [
    "Plan is active",
    "Resistance training volume and growth (2017)",
  ]);
});

Deno.test("the answer check is told which library sources the reply cites", () => {
  const seen: (readonly string[] | undefined)[] = [];
  parseCoachChatAnswer(
    libraryAnswer("schoenfeld_2017_weekly_volume"),
    ["APPROVED_PLAN_ACTIVE"],
    (_, cited) => {
      seen.push(cited);
      return null;
    },
    shownVolume,
  );
  assertEquals(seen, [["schoenfeld_2017_weekly_volume"]]);
});

Deno.test("a shown library id is not a permitted code for data evidence", () => {
  const error = assertThrows(
    () =>
      parseCoachChatAnswer(
        libraryAnswer("schoenfeld_2017_weekly_volume", "coach_context"),
        ["APPROVED_PLAN_ACTIVE"],
        undefined,
        shownVolume,
      ),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "evidence_code_not_permitted");
});
