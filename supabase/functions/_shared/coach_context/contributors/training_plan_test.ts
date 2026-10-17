import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderCoachContext } from "../host.ts";
import {
  createTrainingPlanContributor,
  parsePlanState,
  pickFocusSession,
  renderTrainingPlan,
  trainingPlanContributorBudgetChars,
} from "./training_plan.ts";
import { ownersCaseDate, ownersPlanPayload } from "./plan_fixtures.ts";

const render = (mutate?: (payload: Record<string, unknown>) => void) => {
  const payload = ownersPlanPayload();
  mutate?.(payload);
  return renderTrainingPlan(parsePlanState(payload));
};

Deno.test("the owner's case: today's push day names every exercise with sets, reps, rest, load and target", () => {
  const text = render()!;
  assertStringIncludes(text, "Today's planned session: Push day (Saturday, about 60 min).");
  assertStringIncludes(
    text,
    "1. Barbell bench press: 3 x 6-8, rest 120 s, RPE 8, plan load 60 kg. Next target (Tracend, from the logged sets): 62.5 kg x 6 reps, 3 sets; add load,",
  );
  assertStringIncludes(text, "Last logged 2026-10-10: 60 kg, 3 sets, fewest reps 8.");
  assertStringIncludes(
    text,
    "2. Incline dumbbell press: 3 x 8-10, rest 90 s, RPE 8, plan load 24 kg.",
  );
  assertStringIncludes(text, "24 kg x 9 reps, 3 sets; add reps");
  assertStringIncludes(text, "3. Cable lateral raise: 3 x 12-15, rest 60 s, RPE 9.");
  assertStringIncludes(text, "No sets logged for it yet; the plan's prescription stands.");
  assertStringIncludes(text, "4. Cable triceps pressdown: 3 x 10-12");
});

Deno.test("each of today's exercises carries catalog home alternatives, never an invented one", () => {
  const text = render()!;
  // Bench press: push-ups are the bodyweight form, a home-size kit form is a dumbbell press.
  const bench = text.split("\n").find((line) => line.includes("1. Barbell bench press"))!;
  assertStringIncludes(bench, "Home: bodyweight");
  assertStringIncludes(bench, "Push-up");
  assertStringIncludes(bench, "minimal kit");
  const pressdown = text.split("\n").find((line) => line.includes("4. Cable triceps pressdown"))!;
  assertStringIncludes(pressdown, "Home:");
  assertStringIncludes(text, "Home options are catalog exercises that need no equipment");
  assertStringIncludes(text, "name only exercises listed here");
});

Deno.test("the week: what is finished, what is left by day, and the plan's sets a week by muscle", () => {
  const text = render()!;
  assertStringIncludes(
    text,
    "Finished this week (Monday to today): Pull day (2026-10-12), Leg day (2026-10-14).",
  );
  assertStringIncludes(text, "- Sunday, Upper day: Barbell overhead press 3 x 6-8");
  assertStringIncludes(text, "Sets a week by main muscle in the plan:");
  assertStringIncludes(text, "Equipment profile (from onboarding): dumbbells, bench, cables.");
  assertStringIncludes(text, "Today is Saturday 2026-10-17.");
});

Deno.test("a session already logged today is not offered again: the next one is", () => {
  const text = render((payload) => {
    (payload.completed_this_week as unknown[]).push({
      planned_workout_id: "w-push",
      local_date: ownersCaseDate,
    });
  })!;
  assertStringIncludes(text, "Today's planned session, Push day, is already logged as done.");
  assertStringIncludes(text, "The next planned session: Upper day (Sunday");
});

Deno.test("a rest day points at the next session, and the end of the week at next week's first", () => {
  const rest = parsePlanState({ ...ownersPlanPayload(), weekday: 2 })!;
  // Leg day (Wednesday) is already done this week, so the next one is Saturday's.
  assertEquals(pickFocusSession(rest).session?.name, "Push day");
  assertEquals(pickFocusSession(rest).isToday, false);
  const late = parsePlanState({
    ...ownersPlanPayload(),
    weekday: 7,
    local_date: "2026-10-18",
    completed_this_week: [
      ...(ownersPlanPayload().completed_this_week as unknown[]),
      { planned_workout_id: "w-push", local_date: "2026-10-17" },
      { planned_workout_id: "w-upper", local_date: "2026-10-18" },
    ],
  })!;
  const focus = pickFocusSession(late);
  assertEquals(focus.nextWeek, true);
  assertEquals(focus.session?.name, "Pull day");
});

Deno.test("an unreadable payload, no plan or no sessions renders nothing", () => {
  assertEquals(render((p) => (p.schema_version = "2.0")), null);
  assertEquals(render((p) => (p.plan = null)), null);
  assertEquals(render((p) => (p.sessions = [])), null);
  assertEquals(parsePlanState("nonsense"), null);
});

Deno.test("an athlete without an equipment answer is told so; movements to avoid drop out of home options", () => {
  const text = render((payload) => {
    payload.equipment = null;
    payload.avoid_patterns = ["horizontal_push"];
  })!;
  assertStringIncludes(text, "Equipment profile: not on file.");
  const bench = text.split("\n").find((line) => line.includes("1. Barbell bench press"))!;
  assert(!bench.includes("Push-up"), bench);
});

Deno.test("the text fits its budget and the host labels it as reference data", async () => {
  const text = render()!;
  assert(text.length <= trainingPlanContributorBudgetChars, `${text.length} characters`);
  const contributor = createTrainingPlanContributor(() => Promise.resolve(ownersPlanPayload()));
  const rendered = await renderCoachContext([contributor], {
    userId: "user-1",
    question: "What should I do today?",
    localDate: ownersCaseDate,
  });
  assertStringIncludes(rendered.volatile, '<reference_data source="training_plan">');
  assertEquals(rendered.outcomes[0].outcome, "rendered");
  const failing = createTrainingPlanContributor(() => Promise.reject(new Error("down")));
  const failed = await renderCoachContext([failing], {
    userId: "user-1",
    question: "q",
    localDate: ownersCaseDate,
  });
  assertEquals(failed.outcomes[0].outcome, "failed");
});
