import { assert, assertEquals } from "jsr:@std/assert@1";
import {
  intentFromModel,
  parseCoachProposalIntent,
  proposalIntentJsonSchema,
  proposalParamNames,
} from "./intent.ts";
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

// ---- the model's list form -----------------------------------------------------------------
// The gateway schema has no optional field, so the model writes `proposal_intent` as a list of one
// item with `params` name/value pairs (every value text). intentFromModel turns it into the object
// parseCoachProposalIntent has always read.

const one = (
  kind: string,
  reason: string,
  params: Record<string, string>,
  note = "",
) => [{
  kind,
  reason,
  note,
  params: Object.entries(params).map(([name, value]) => ({ name, value })),
}];

Deno.test("every kind round-trips: the model's list form gives the same intent as the object form", () => {
  const pairs: [unknown, Record<string, unknown>][] = [
    [
      one("temporary_block", "travel", {
        setting: "bodyweight",
        start_date: "2026-10-18",
        end_date: "2026-10-30",
      }),
      {
        kind: "temporary_block",
        reason: "travel",
        setting: "bodyweight",
        start_date: "2026-10-18",
        end_date: "2026-10-30",
      },
    ],
    [
      one("training_schedule", "time", { days_per_week: "4", weeks: "8" }),
      { kind: "training_schedule", reason: "time", days_per_week: 4, weeks: 8 },
    ],
    [
      one("training_schedule", "time", { weekdays: "5, 1,3", session_minutes: "45", weeks: "4" }),
      {
        kind: "training_schedule",
        reason: "time",
        weekdays: [5, 1, 3],
        session_minutes: 45,
        weeks: 4,
      },
    ],
    [
      one("exercise_swap", "preference", {
        from_exercise: "Barbell back squat",
        to_exercise: "Goblet squat",
      }),
      {
        kind: "exercise_swap",
        reason: "preference",
        from_exercise: "Barbell back squat",
        to_exercise: "Goblet squat",
      },
    ],
    [
      one("exercise_swap", "preference", { from_exercise: "Barbell back squat" }),
      { kind: "exercise_swap", reason: "preference", from_exercise: "Barbell back squat" },
    ],
    [
      one("intensity_or_phase", "fatigue", { level: "deload", weeks: "1" }),
      { kind: "intensity_or_phase", reason: "fatigue", level: "deload", weeks: 1 },
    ],
    [
      one("intensity_or_phase", "plateau", { focus: "strength", weeks: "6" }),
      { kind: "intensity_or_phase", reason: "plateau", focus: "strength", weeks: 6 },
    ],
    [
      one("goal_or_phase", "diet_fatigue", { phase: "diet_break" }),
      { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    ],
    [
      one("goal_or_phase", "athlete_request", {
        phase: "cut",
        target_weight_kg: "74.5",
        target_date: "2027-03-01",
      }),
      {
        kind: "goal_or_phase",
        reason: "athlete_request",
        phase: "cut",
        target_weight_kg: 74.5,
        target_date: "2027-03-01",
      },
    ],
    [
      one("nutrition_targets", "plateau", { direction: "lower", requested_calories: "2100" }),
      {
        kind: "nutrition_targets",
        reason: "plateau",
        direction: "lower",
        requested_calories: 2100,
      },
    ],
    [
      one("next_session_adjustment", "fatigue", { direction: "lighter", session: "next" }),
      {
        kind: "next_session_adjustment",
        reason: "fatigue",
        direction: "lighter",
        session: "next",
      },
    ],
  ];
  const kinds = new Set<string>();
  for (const [modelForm, objectForm] of pairs) {
    kinds.add(String(objectForm.kind));
    assertEquals(intentFromModel(modelForm), objectForm);
    // The strict parser reads both to the same intent.
    assertEquals(
      parseCoachProposalIntent(intentFromModel(modelForm)),
      parseCoachProposalIntent(objectForm),
    );
    assert(parseCoachProposalIntent(intentFromModel(modelForm)).ok);
  }
  assertEquals(kinds.size, proposalKinds.length);
});

Deno.test("an empty or missing list is no intent; an empty note and an empty value are left out", () => {
  assertEquals(intentFromModel([]), undefined);
  assertEquals(intentFromModel(undefined), undefined);
  assertEquals(
    intentFromModel(
      one("nutrition_targets", "plateau", { direction: "lower", requested_calories: "" }),
    ),
    { kind: "nutrition_targets", reason: "plateau", direction: "lower" },
  );
  assertEquals(
    intentFromModel(one("goal_or_phase", "plateau", { phase: "cut" }, "after the holiday")),
    { kind: "goal_or_phase", reason: "plateau", phase: "cut", note: "after the holiday" },
  );
});

Deno.test("a malformed list becomes null, which the parser refuses", () => {
  const item = one("goal_or_phase", "plateau", { phase: "cut" })[0];
  for (
    const bad of [
      null,
      "text",
      {},
      [item, item],
      [null],
      [{ ...item, params: "phase" }],
      [{ ...item, params: [{ name: "phase", value: "cut" }, { name: "phase", value: "gain" }] }],
      [{ ...item, params: [{ name: "__proto__", value: "x" }] }],
      [{ ...item, params: [{ name: "kind", value: "exercise_swap" }] }],
      [{ ...item, params: [{ name: "phase", value: 3 }] }],
      // A name written twice is refused whatever its values, an empty one included.
      [{ ...item, params: [{ name: "phase", value: "" }, { name: "phase", value: "cut" }] }],
      [{ ...item, params: [{ name: "phase", value: "cut" }, { name: "phase", value: "" }] }],
      [{ ...item, params: [{ name: "weeks", value: "" }, { name: "weeks", value: "" }] }],
    ]
  ) {
    assertEquals(intentFromModel(bad), null, JSON.stringify(bad));
    assertEquals(parseCoachProposalIntent(intentFromModel(bad)).ok, false);
  }
});

Deno.test("a figure that is not a plain number reaches the parser as text and is refused there", () => {
  for (
    const [name, value] of [
      ["requested_calories", "about 2100"],
      ["requested_calories", "2,100"],
      ["requested_calories", "2100 kcal"],
    ]
  ) {
    const intent = intentFromModel(
      one("nutrition_targets", "plateau", { direction: "lower", [name]: value }),
    );
    assertEquals((intent as Record<string, unknown>)[name], value);
    assertEquals(parseCoachProposalIntent(intent).ok, false, value);
  }
  const days = intentFromModel(one("training_schedule", "time", { weekdays: "1,mon", weeks: "4" }));
  assertEquals(parseCoachProposalIntent(days).ok, false);
  const wrongField = intentFromModel(
    one("temporary_block", "travel", { setting: "bodyweight", weeks: "2" }),
  );
  assertEquals(parseCoachProposalIntent(wrongField).ok, false);
});

Deno.test("the intent schema has every property required and no union", () => {
  const text = JSON.stringify(proposalIntentJsonSchema);
  assert(!text.includes("anyOf") && !text.includes("null"));
  const item = proposalIntentJsonSchema.items;
  assertEquals(item.required, ["kind", "reason", "note", "params"]);
  assertEquals(Object.keys(item.properties), [...item.required]);
  assertEquals(item.properties.params.items.properties.name.enum, [...proposalParamNames]);
});
