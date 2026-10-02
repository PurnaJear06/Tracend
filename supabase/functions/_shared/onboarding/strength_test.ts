import { assertEquals } from "jsr:@std/assert@1.0.14";
import { parseOnboardingAnswers } from "./answers.ts";
import { estimatedOneRepMax, liftEstimates, startingLoadKg, strengthRatios } from "./strength.ts";

Deno.test("Epley counts the reps left in reserve", () => {
  // 100 kg x 5 with 2 left = 7 reps to failure: 100 x (1 + 7/30) = 123.3.
  assertEquals(estimatedOneRepMax(100, 5, 2), 123.5);
  assertEquals(estimatedOneRepMax(100, 5, 0), 116.5);
  assertEquals(estimatedOneRepMax(60, 1, 0), 62);
});

Deno.test("a starting load is lighter than the estimate, on a plate step, and never below the bar", () => {
  // 120 kg estimate, 8 reps at RPE 8 (10 to failure): 120 / 1.333 x 0.95 = 85.5 -> 85.
  assertEquals(startingLoadKg(120, 8, 8), 85);
  // Higher effort allows more load.
  assertEquals(startingLoadKg(120, 8, 9), 87.5);
  // A light estimate gives no load rather than less than an empty bar.
  assertEquals(startingLoadKg(25, 10, 7), null);
  for (const [e1rm, reps, rpe] of [[150, 5, 8], [80, 12, 7.5], [200, 3, 9]]) {
    const load = startingLoadKg(e1rm, reps, rpe)!;
    assertEquals(load % 2.5, 0);
    assertEquals(load < e1rm, true);
  }
});

Deno.test("ratios only for pairs the athlete gave both of", () => {
  const estimates = liftEstimates([
    { slug: "barbell-bench-press", loadKg: 100, reps: 5, repsLeft: 1 },
    { slug: "barbell-row", loadKg: 80, reps: 8, repsLeft: 2 },
    { slug: "barbell-back-squat", loadKg: 140, reps: 5, repsLeft: 1 },
  ]);
  // Row 80 x (1 + 10/30) = 106.5; bench 100 x (1 + 6/30) = 120.
  assertEquals(strengthRatios(estimates), { row_to_bench: 0.89 });
  assertEquals(strengthRatios([]), {});
});

Deno.test("reported lifts: barbell only, one each, inside the bounds", () => {
  const payload = {
    goal: "strength",
    sex: "male",
    birth_year: 1990,
    height_cm: 180,
    weight_kg: 85,
    daily_activity: "mostly_sitting",
    training_weekdays: [1, 3, 5],
    session_minutes: 60,
    equipment_items: ["barbell", "bench"],
    current_plan: "5x5",
    training_years: "over_5",
    current_lifts: [
      { slug: "barbell-bench-press", load_kg: 100.3, reps: 5, reps_left: 1 },
      { slug: "barbell-bench-press", load_kg: 200, reps: 1, reps_left: 0 },
      { slug: "pull-up", load_kg: 10, reps: 8, reps_left: 1 },
      { slug: "barbell-deadlift", load_kg: 180, reps: 20, reps_left: 1 },
      { slug: "barbell-row", load_kg: 70, reps: 8, reps_left: 7 },
    ],
    priority_muscles: ["chest", "glutes", "calves"],
    strong_muscles: ["quads", "nonsense"],
  };
  const parsed = parseOnboardingAnswers("experienced", payload, 2026);
  if (!parsed.ok) throw new Error("expected answers");
  // The first bench entry counts, rounded to 0.5 kg; out-of-bounds sets and
  // non-barbell lifts are dropped.
  assertEquals(parsed.answers.currentLifts, [
    { slug: "barbell-bench-press", loadKg: 100.5, reps: 5, repsLeft: 1 },
  ]);
  assertEquals(parsed.answers.priorityMuscles, ["glutes", "chest"]);
  assertEquals(parsed.answers.strongMuscles, ["quads"]);
  assertEquals(parsed.answers.experience, "intermediate");
  // Under a year keeps the beginner limits; a beginner never reports lifts.
  const fresh = parseOnboardingAnswers(
    "experienced",
    { ...payload, training_years: "under_1" },
    2026,
  );
  assertEquals(fresh.ok && fresh.answers.experience, "beginner");
  const beginner = parseOnboardingAnswers("beginner", payload, 2026);
  assertEquals(beginner.ok && beginner.answers.currentLifts, []);
  assertEquals(beginner.ok && beginner.answers.trainingYears, null);
  // An experienced draft from before the question stays intermediate.
  const { training_years: _years, ...older } = payload;
  const old = parseOnboardingAnswers("experienced", older, 2026);
  assertEquals(old.ok && old.answers.experience, "intermediate");
});

Deno.test("follow-up answers count only with the hash they were asked for", () => {
  const payload = {
    goal: "fat_loss",
    sex: "female",
    birth_year: 1990,
    height_cm: 165,
    weight_kg: 65,
    daily_activity: "some_standing",
    training_weekdays: [1, 4],
    session_minutes: 45,
    equipment_items: [],
    follow_ups_hash: "hash-a",
    follow_ups: [
      { category: "split_history", question: "What split did you run?", answer: "Full body" },
      { category: "injury_history", question: "Any injuries?", answer: "Knee" },
      { category: "recovery_between_sessions", question: "Sore after?", answer: "" },
    ],
  };
  const current = parseOnboardingAnswers("beginner", payload, 2026, "hash-a");
  assertEquals(current.ok && current.answers.followUps, [
    { category: "split_history", question: "What split did you run?", answer: "Full body" },
  ]);
  const edited = parseOnboardingAnswers("beginner", payload, 2026, "hash-b");
  assertEquals(edited.ok && edited.answers.followUps, []);
  assertEquals(parseOnboardingAnswers("beginner", payload, 2026).ok, true);
});
