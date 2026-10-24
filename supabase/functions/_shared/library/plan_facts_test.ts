import { assertEquals } from "jsr:@std/assert@1.0.14";
import { parsePlanState } from "../coach_context/contributors/training_plan.ts";
import { sharedRead } from "../coach_context/host.ts";
import { goalPhaseInputsReadKey } from "../coach_context/contributors/goal_phase.ts";
import { planStateReadKey } from "../coach_context/contributors/training_plan.ts";
import { planFactsFrom, planFactsFromService } from "./plan_facts.ts";

const planPayload = {
  schema_version: "1.2",
  local_date: "2026-10-24",
  weekday: 6,
  experience: "advanced",
  plan: { title: "Upper lower", version_number: 3, sessions_per_week: 4 },
  sessions: [
    {
      planned_workout_id: "w1",
      order: 1,
      name: "Upper A",
      weekday: 1,
      minutes: 60,
      exercises: [
        {
          planned_exercise_id: "e1",
          name: "Bench",
          sets: 3,
          rep_min: 6,
          rep_max: 8,
          target_rpe: 8,
        },
        {
          planned_exercise_id: "e2",
          name: "Curl",
          sets: 3,
          rep_min: 10,
          rep_max: 15,
          target_rpe: null,
        },
      ],
    },
  ],
};
const goalPayload = {
  schema_version: "1.0",
  goal: { goal_type: "recomposition" },
  readings: [],
};

Deno.test("the facts are counts and enumerated values from the plan and the goal", () => {
  const plan = parsePlanState(planPayload);
  assertEquals(planFactsFrom(plan, "recomposition"), {
    sessionsPerWeek: 4,
    experience: "advanced",
    repMin: 6,
    repMax: 15,
    hasEffortTarget: true,
    goal: "recomposition",
    temporaryBlock: false,
  });
});

Deno.test("with no plan the goal alone gives facts, and with neither there are none", () => {
  assertEquals(planFactsFrom(null, "strength")?.goal, "strength");
  assertEquals(planFactsFrom(null, "strength")?.sessionsPerWeek, null);
  assertEquals(planFactsFrom(null, null), null);
});

Deno.test("an exercise name, a load or a date never reaches the facts", () => {
  const facts = JSON.stringify(planFactsFrom(parsePlanState(planPayload), "recomposition"));
  for (const word of ["Bench", "Curl", "2026", "Upper"]) {
    assertEquals(facts.includes(word), false, word);
  }
});

Deno.test("each source of facts counts when read and one failing leaves the other", async () => {
  const input = (plan: Promise<unknown>, goal: Promise<unknown>) => {
    const shared = new Map<string, Promise<unknown>>([
      [planStateReadKey, plan],
      [goalPhaseInputsReadKey, goal],
    ]);
    plan.catch(() => {});
    goal.catch(() => {});
    return { userId: "u", question: "q", localDate: "2026-10-24", shared };
  };
  const both = await planFactsFromService(
    input(Promise.resolve(planPayload), Promise.resolve(goalPayload)),
  );
  assertEquals(both?.sessionsPerWeek, 4);
  assertEquals(both?.goal, "recomposition");
  const goalFails = await planFactsFromService(
    input(Promise.resolve(planPayload), Promise.reject(new Error("down"))),
  );
  assertEquals(goalFails?.sessionsPerWeek, 4);
  assertEquals(goalFails?.goal, null);
  const planFails = await planFactsFromService(
    input(Promise.reject(new Error("down")), Promise.resolve(goalPayload)),
  );
  assertEquals(planFails?.goal, "recomposition");
  assertEquals(planFails?.sessionsPerWeek, null);
  const neither = await planFactsFromService(
    input(Promise.reject(new Error("down")), Promise.reject(new Error("down"))),
  );
  assertEquals(neither, null);
  // The reads are shared with the plan and goal phase sections, not repeated.
  const shared = new Map<string, Promise<unknown>>();
  let reads = 0;
  const read = () => {
    reads++;
    return Promise.resolve(planPayload);
  };
  await sharedRead({ shared }, planStateReadKey, read);
  await sharedRead({ shared }, planStateReadKey, read);
  assertEquals(reads, 1);
});
