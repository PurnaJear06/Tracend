import { assertEquals } from "jsr:@std/assert@1.0.14";
import { type ScreeningOutcome, screeningOutcomes } from "./outcome.ts";
import {
  parseScreeningAnswers,
  type ScreeningAnswers,
  screeningOutcome,
  screeningOutcomeOf,
  screeningSnapshot,
} from "./screening.ts";

const answers = (overrides: Partial<ScreeningAnswers> = {}): ScreeningAnswers => ({
  exercisesRegularly: true,
  knownDisease: false,
  symptoms: false,
  clearedByProfessional: false,
  ...overrides,
});

// The same sixteen rows as supabase/tests/database/onboarding_screening_test.sql, in the same
// order: exercises regularly (yes first), known condition, symptoms, cleared (no first).
const table: ReadonlyArray<readonly [boolean, boolean, boolean, boolean, ScreeningOutcome]> = [
  [true, false, false, false, "cleared"],
  [true, false, false, true, "cleared"],
  [true, false, true, false, "see_professional"],
  [true, false, true, true, "see_professional"],
  [true, true, false, false, "moderate_until_cleared"],
  [true, true, false, true, "cleared"],
  [true, true, true, false, "see_professional"],
  [true, true, true, true, "see_professional"],
  [false, false, false, false, "cleared"],
  [false, false, false, true, "cleared"],
  [false, false, true, false, "see_professional"],
  [false, false, true, true, "see_professional"],
  [false, true, false, false, "see_professional"],
  [false, true, false, true, "cleared"],
  [false, true, true, false, "see_professional"],
  [false, true, true, true, "see_professional"],
];

Deno.test("the outcome maps all sixteen answer combinations", () => {
  assertEquals(table.length, 16);
  for (
    const [exercisesRegularly, knownDisease, symptoms, clearedByProfessional, expected] of table
  ) {
    assertEquals(
      screeningOutcome({ exercisesRegularly, knownDisease, symptoms, clearedByProfessional }),
      expected,
      `exercises ${exercisesRegularly}, condition ${knownDisease}, symptoms ${symptoms}, cleared ${clearedByProfessional}`,
    );
  }
});

Deno.test("every Contract 8 outcome is reachable and nothing else is returned", () => {
  const seen = new Set(table.map((row) =>
    screeningOutcome({
      exercisesRegularly: row[0],
      knownDisease: row[1],
      symptoms: row[2],
      clearedByProfessional: row[3],
    })
  ));
  assertEquals([...seen].sort(), [...screeningOutcomes].sort());
});

Deno.test("a current symptom stops the plan even after a clearance", () => {
  assertEquals(
    screeningOutcome(answers({ symptoms: true, knownDisease: true, clearedByProfessional: true })),
    "see_professional",
  );
});

Deno.test("an athlete never screened is unscreened, never cleared", () => {
  assertEquals(screeningOutcomeOf(undefined), "unscreened");
  assertEquals(screeningOutcomeOf(null), "unscreened");
  assertEquals(screeningOutcomeOf(answers({ knownDisease: true })), "moderate_until_cleared");
});

Deno.test("the draft payload's screening is read, with clearance defaulting to no", () => {
  assertEquals(parseScreeningAnswers(undefined), { kind: "absent" });
  assertEquals(parseScreeningAnswers(null), { kind: "absent" });
  assertEquals(
    parseScreeningAnswers({ exercises_regularly: false, known_disease: true, symptoms: false }),
    { kind: "answers", answers: answers({ exercisesRegularly: false, knownDisease: true }) },
  );
  assertEquals(
    parseScreeningAnswers({
      exercises_regularly: true,
      known_disease: true,
      symptoms: false,
      cleared_by_professional: true,
    }),
    { kind: "answers", answers: answers({ knownDisease: true, clearedByProfessional: true }) },
  );
});

Deno.test("a malformed screening is invalid, never cleared", () => {
  for (
    const value of [
      "yes",
      [],
      7,
      {},
      { exercises_regularly: true, known_disease: false },
      { exercises_regularly: "yes", known_disease: false, symptoms: false },
      { exercises_regularly: true, known_disease: false, symptoms: null },
      {
        exercises_regularly: true,
        known_disease: false,
        symptoms: false,
        cleared_by_professional: "no",
      },
    ]
  ) {
    assertEquals(parseScreeningAnswers(value), { kind: "invalid" }, JSON.stringify(value));
  }
});

Deno.test("the snapshot carries the answers and the outcome", () => {
  assertEquals(screeningSnapshot(answers({ knownDisease: true })), {
    exercises_regularly: true,
    known_disease: true,
    symptoms: false,
    cleared_by_professional: false,
    outcome: "moderate_until_cleared",
  });
});
