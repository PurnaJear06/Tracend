import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { answersSnapshot, parseOnboardingAnswers } from "./answers.ts";
import { screeningOutcomeOf } from "../training/screening/screening.ts";

const payload = {
  goal: "muscle_gain",
  sex: "female",
  birth_year: 1990,
  height_cm: 165,
  weight_kg: 65,
  daily_activity: "some_standing",
  training_weekdays: [1, 3, 5],
  session_minutes: 60,
  equipment_items: ["dumbbells"],
};

const parse = (extra: Record<string, unknown> = {}) =>
  parseOnboardingAnswers("beginner", { ...payload, ...extra }, 2026);

Deno.test("a draft without screening still parses and is unscreened", () => {
  const parsed = parse();
  assert(parsed.ok);
  assertEquals(parsed.answers.screening, undefined);
  assertEquals(screeningOutcomeOf(parsed.answers.screening), "unscreened");
});

Deno.test("an older draft's snapshot has no screening key, so its hash is unchanged", () => {
  const parsed = parse();
  assert(parsed.ok);
  assertEquals("screening" in answersSnapshot(parsed.answers), false);
});

Deno.test("screening answers are read from the draft and carried into the snapshot", () => {
  const parsed = parse({
    screening: { exercises_regularly: true, known_disease: true, symptoms: false },
  });
  assert(parsed.ok);
  assertEquals(parsed.answers.screening, {
    exercisesRegularly: true,
    knownDisease: true,
    symptoms: false,
    clearedByProfessional: false,
  });
  assertEquals(screeningOutcomeOf(parsed.answers.screening), "moderate_until_cleared");
  assertEquals(answersSnapshot(parsed.answers).screening, {
    exercises_regularly: true,
    known_disease: true,
    symptoms: false,
    cleared_by_professional: false,
    outcome: "moderate_until_cleared",
  });
});

Deno.test("a malformed screening asks again instead of reading as cleared", () => {
  const parsed = parse({ screening: { exercises_regularly: "yes" } });
  assertEquals(parsed.ok, false);
  assertEquals(!parsed.ok && parsed.missing, ["screening"]);
});

Deno.test("changing a screening answer changes the snapshot", () => {
  const first = parse({
    screening: { exercises_regularly: true, known_disease: false, symptoms: false },
  });
  const second = parse({
    screening: { exercises_regularly: true, known_disease: true, symptoms: false },
  });
  assert(first.ok && second.ok);
  assertEquals(
    JSON.stringify(answersSnapshot(first.answers)) ===
      JSON.stringify(answersSnapshot(second.answers)),
    false,
  );
});
