import { assert, assertEquals } from "jsr:@std/assert@1";
import { parseCoachProposalIntent } from "./intent.ts";
import { nextDateOnWeekdays, spreadWeekdays } from "./plan_rules.ts";
import { proposalKinds } from "./types.ts";

Deno.test("every kind has a valid intent and the parser reads it into camel case", () => {
  const valid: Record<string, unknown>[] = [
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      start_date: "2026-10-18",
      end_date: "2026-10-30",
    },
    { kind: "training_schedule", reason: "time", days_per_week: 4, weeks: 8 },
    {
      kind: "training_schedule",
      reason: "time",
      weekdays: [5, 1, 3],
      session_minutes: 45,
      weeks: 4,
    },
    {
      kind: "exercise_swap",
      reason: "preference",
      from_exercise: "Barbell back squat",
      to_exercise: "Goblet squat",
    },
    { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    { kind: "intensity_or_phase", reason: "plateau", focus: "strength", weeks: 6 },
    { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    {
      kind: "goal_or_phase",
      reason: "athlete_request",
      phase: "cut",
      target_weight_kg: 74.5,
      target_date: "2027-03-01",
    },
    { kind: "nutrition_targets", reason: "plateau", direction: "lower", requested_calories: 2100 },
    { kind: "next_session_adjustment", reason: "fatigue", direction: "lighter", session: "next" },
  ];
  assertEquals(new Set(valid.map((item) => item.kind)).size, proposalKinds.length);
  for (const raw of valid) {
    const parsed = parseCoachProposalIntent(raw);
    assert(parsed.ok, JSON.stringify(raw));
    assertEquals(parsed.intent.kind, raw.kind);
  }
  const schedule = parseCoachProposalIntent(valid[2]);
  assert(schedule.ok && schedule.intent.kind === "training_schedule");
  assertEquals(schedule.intent.weekdays, [1, 3, 5]);
  assertEquals(schedule.intent.sessionMinutes, 45);
});

Deno.test("spread weekdays keep the athlete's days and place new ones apart", () => {
  assertEquals(spreadWeekdays([1, 3, 5], 3), [1, 3, 5]);
  const four = spreadWeekdays([1, 3, 5], 4);
  assertEquals(four.length, 4);
  assert([1, 3, 5].every((day) => four.includes(day)));
  assertEquals(spreadWeekdays([1, 2, 4, 5], 2).length, 2);
  assertEquals(spreadWeekdays([], 3).length, 3);
  assertEquals(new Set(spreadWeekdays([2, 5], 6)).size, 6);
});

Deno.test("the next date on a weekday is after today and within a week", () => {
  assertEquals(nextDateOnWeekdays("2026-10-18", [1]), "2026-10-19");
  assertEquals(nextDateOnWeekdays("2026-10-19", [1]), "2026-10-26");
  assertEquals(nextDateOnWeekdays("2026-10-18", []), null);
});
