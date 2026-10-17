// Every guard runs on everything the athlete can read, not only on `answer`: follow-up chips,
// the reasoning chain, evidence labels and missing-data notes are shown too.
import { assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { CoachChatAnswerValidationError, parseCoachChatAnswer } from "./coach_chat_v1.ts";
import { coachReplyCheck } from "../coach_safety/reply_guard.ts";
import { numberGroundOf } from "../coach_safety/numbers_check.ts";
import { ownerContext } from "../coach_safety/fixtures.ts";
import { safeRangesOf } from "../coach_safety/safe_ranges.ts";
import { weightClaimCheckFor } from "../training/goal_phase/guard.ts";
import { renderCoachContextParts } from "../providers/coach_chat_provider.ts";

const context = ownerContext();
const check = coachReplyCheck({
  ranges: safeRangesOf(context),
  screening: "cleared",
  ground: numberGroundOf([renderCoachContextParts(context, 96_000).file, "What now?"]),
  weightClaim: weightClaimCheckFor(context, "What now?"),
});

const permitted = ["APPROVED_PLAN_ACTIVE"];
const clean = {
  answer: "Your weight is 74.4 kg. Want to set a target?",
  evidence: [{ code: "APPROVED_PLAN_ACTIVE", label: "Plan is active", source: "coach_context" }],
  missing_data: ["No waist reading"],
  safety_state: "allowed",
  suggested_follow_ups: ["Set a target"],
  reasoning_chain: [{ step: "Weight", value: "74.4 kg", evidence_id: null }],
};

function rule(answer: Record<string, unknown>): string | null {
  try {
    parseCoachChatAnswer(answer, permitted, check);
    return null;
  } catch (error) {
    if (error instanceof CoachChatAnswerValidationError) return error.rule;
    throw error;
  }
}

Deno.test("a clean answer passes in every field", () => {
  assertEquals(rule(clean), null);
});

const faults: readonly (readonly [string, string])[] = [
  ["I've updated your plan.", "claimed_action"],
  ["Drop to 1,000 kcal a day.", "calories_below_floor"],
  ["Aim to lose 1.5 kg a week.", "loss_rate_above_ceiling"],
  ["Walk 45 minutes a day.", "numbers_not_grounded"],
  ["Your weight will be 66.5 kg in 12 weeks.", "projection_without_target"],
];

Deno.test("each guard fires on every athlete-visible field", () => {
  const places: readonly (readonly [string, (text: string) => Record<string, unknown>])[] = [
    ["answer", (text) => ({ ...clean, answer: text })],
    ["follow-up", (text) => ({ ...clean, suggested_follow_ups: [text] })],
    ["missing data", (text) => ({ ...clean, missing_data: [text] })],
    [
      "evidence label",
      (text) => ({
        ...clean,
        evidence: [{ code: "APPROVED_PLAN_ACTIVE", label: text, source: "coach_context" }],
      }),
    ],
    [
      "reasoning step",
      (text) => ({ ...clean, reasoning_chain: [{ step: text, value: "ok", evidence_id: null }] }),
    ],
    [
      "reasoning value",
      (text) => ({ ...clean, reasoning_chain: [{ step: "Step", value: text, evidence_id: null }] }),
    ],
  ];
  for (const [place, build] of places) {
    for (const [text, expected] of faults) {
      assertEquals(rule(build(text)), expected, `${place}: ${text}`);
    }
  }
});

Deno.test("the error names the rule and the answer path, never the text", () => {
  const error = assertThrows(
    () =>
      parseCoachChatAnswer(
        { ...clean, suggested_follow_ups: ["Walk 45 minutes a day."] },
        permitted,
        check,
      ),
    CoachChatAnswerValidationError,
  );
  assertEquals(error.rule, "numbers_not_grounded");
  assertEquals(error.path, "answer");
  assertEquals(error.actual, 1);
  assertEquals(error.message.includes("45"), false);
});
