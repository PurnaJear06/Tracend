import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderCoachContext } from "../host.ts";
import {
  createTrainingPlanContributor,
  parsePlanState,
  pickFocusSession,
  renderTrainingPlan,
  trainingPlanContributorBudgetChars,
} from "./training_plan.ts";
import { ownersCaseDate, ownersPlanPayload, splitPlanPayload } from "./plan_fixtures.ts";

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

Deno.test("a workout finished earlier this week is not prescribed again in today's slot", () => {
  // Push day (Saturday's slot) was done on Thursday ahead of time.
  const payload = ownersPlanPayload();
  (payload.completed_this_week as unknown[]).push({
    planned_workout_id: "w-push",
    local_date: "2026-10-15",
  });
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(
    text,
    "Today's planned session, Push day, was already done this week (2026-10-15); it is not prescribed again.",
  );
  assertStringIncludes(text, "The next planned session: Upper day (Sunday");
  assert(!text.includes("Today's planned session: Push day"));
  assert(!text.includes("1. Barbell bench press"));
});

Deno.test("a workout finished under an earlier plan version is matched by name, or by day and order", () => {
  const withRow = (row: Record<string, unknown>) => {
    const payload = ownersPlanPayload();
    (payload.completed_this_week as unknown[]).push(row);
    return renderTrainingPlan(parsePlanState(payload))!;
  };
  // Another version's id, the same name: Saturday's push day was done on Thursday.
  const byName = withRow({
    planned_workout_id: "old-version-push",
    local_date: "2026-10-15",
    name: "Push day",
    weekday: 4,
    order: 1,
  });
  assertStringIncludes(byName, "was already done this week (2026-10-15)");
  assert(!byName.includes("1. Barbell bench press"));
  // Renamed in the new version, but the same day and place in the week.
  const byPlace = withRow({
    planned_workout_id: "old-version-chest",
    local_date: "2026-10-17",
    name: "Chest and arms",
    weekday: 6,
    order: 3,
  });
  assertStringIncludes(byPlace, "is already logged as done");
  // A workout with a different name, day and order does not hide today's.
  const unrelated = withRow({
    planned_workout_id: "old-version-core",
    local_date: "2026-10-15",
    name: "Core",
    weekday: 4,
    order: 9,
  });
  assertStringIncludes(unrelated, "Today's planned session: Push day");
  assertStringIncludes(unrelated, "Core (2026-10-15)");
});

Deno.test("with nothing later in the week, a session missed earlier is offered before next week's", () => {
  const payload = ownersPlanPayload();
  payload.weekday = 7;
  payload.local_date = "2026-10-18";
  // Pull (Monday) and Leg (Wednesday) are done; Push (Saturday) was missed; Upper is today's slot.
  (payload.completed_this_week as unknown[]).push({
    planned_workout_id: "w-upper",
    local_date: "2026-10-18",
  });
  const focus = pickFocusSession(parsePlanState(payload)!);
  assertEquals(focus.session?.name, "Push day");
  assertEquals(focus.missed, true);
  assertStringIncludes(
    renderTrainingPlan(parsePlanState(payload))!,
    "A session from earlier this week is still undone: Push day",
  );
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

// The 2026-10-18 report: a Sunday, a six-day split without a Sunday session, Thursday's chest and
// delts session undone, Monday's session (chest, side delts, triceps) tomorrow.
const sundayWithThursdayUndone = () =>
  splitPlanPayload(7, ["w-chest-a", "w-legs-a", "w-pull", "w-shoulders"]);

Deno.test("Sunday: Monday is tomorrow, and the undone chest session made up today overlaps it", () => {
  const text = renderTrainingPlan(parsePlanState(sundayWithThursdayUndone()))!;
  assertStringIncludes(text, "Next 7 days from today");
  assertStringIncludes(
    text,
    "- Sun 2026-10-18 (today): no session is planned today; make up the undone Thursday session Chest volume and delts (",
  );
  assertStringIncludes(text, "- Mon 2026-10-19 (tomorrow): Chest priority and side delts (");
  assertStringIncludes(text, "- Sat 2026-10-24: Shoulder width (");
  const fact = text.split("\n").find((line) =>
    line.startsWith("Same muscles on consecutive days")
  )!;
  assertStringIncludes(fact, "Sat 2026-10-17 then Sun 2026-10-18: triceps, shoulders");
  assertStringIncludes(fact, "Sun 2026-10-18 then Mon 2026-10-19: chest, shoulders, triceps");
  // Monday's session was logged on the 12th; that is last week's Monday, not tomorrow's.
  assertStringIncludes(text, "Chest priority and side delts: ");
  assert(text.includes("[done 2026-10-12]"));
  assert(!text.includes("done this week]"));
});

Deno.test("the schedule block and its overlap fact stay compact", () => {
  const text = renderTrainingPlan(parsePlanState(sundayWithThursdayUndone()))!;
  const start = text.indexOf("Next 7 days from today");
  const end = text.indexOf("\nA session from earlier this week", start);
  const block = text.slice(start, end);
  assert(block.length < 1_500, `${block.length} characters`);
  assert(text.length <= trainingPlanContributorBudgetChars, `${text.length} characters`);
});

Deno.test("mid-week: a leg day after chest and before shoulders shares nothing, so there is no fact", () => {
  // Friday: Monday to Thursday done. Legs B today, Shoulder width tomorrow, Sunday free.
  const text = renderTrainingPlan(
    parsePlanState(splitPlanPayload(5, ["w-chest-a", "w-legs-a", "w-pull", "w-chest-b"])),
  )!;
  assertStringIncludes(text, "- Fri 2026-10-16 (today): Legs B (");
  assertStringIncludes(text, "- Sat 2026-10-17 (tomorrow): Shoulder width (");
  assertStringIncludes(text, "- Sun 2026-10-18: no session");
  assertStringIncludes(text, "- Thu 2026-10-15: done: Chest volume and delts (");
  assert(!text.includes("Same muscles on consecutive days"));
});

Deno.test("mid-week: back-to-back sessions that share muscles are named", () => {
  const payload = splitPlanPayload(3, ["w-chest-a", "w-legs-a"]);
  // The athlete moved Pull day's slot onto Thursday's session: two chest days in a row ahead.
  const sessions = payload.sessions as { weekday: number; name: string }[];
  sessions[2].weekday = 3;
  sessions[5].weekday = 5;
  sessions[5].name = "Chest again";
  (sessions[5] as Record<string, unknown>).exercises = (sessions[3] as Record<string, unknown>)
    .exercises;
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(text, "Thu 2026-10-15 then Fri 2026-10-16: chest, triceps, shoulders");
});

Deno.test("a rest day on Sunday with the week finished: Monday is tomorrow, nothing overlaps", () => {
  const text = renderTrainingPlan(
    parsePlanState(
      splitPlanPayload(7, [
        "w-chest-a",
        "w-legs-a",
        "w-pull",
        "w-chest-b",
        "w-legs-b",
        "w-shoulders",
      ]),
    ),
  )!;
  assertStringIncludes(text, "- Sun 2026-10-18 (today): no session");
  assertStringIncludes(text, "- Mon 2026-10-19 (tomorrow): Chest priority and side delts (");
  assert(!text.includes("Same muscles on consecutive days"));
});

Deno.test("Monday after a Sunday make-up: yesterday's session, outside the calendar week, counts", () => {
  const payload = splitPlanPayload(1, [], {
    recent_completed: [{
      planned_workout_id: "w-chest-b",
      local_date: "2026-10-18",
      name: "Chest volume and delts",
      exercises: [
        { slug: "dumbbell-bench-press", sets: 4 },
        { slug: "dumbbell-lateral-raise", sets: 4 },
      ],
    }],
    local_date: "2026-10-19",
  });
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(text, "- Sun 2026-10-18: done: Chest volume and delts (");
  assertStringIncludes(text, "Sun 2026-10-18 then Mon 2026-10-19: ");
});

Deno.test("a plan whose sessions have no set weekday lists seven days without a session", () => {
  const payload = splitPlanPayload(7, []);
  for (const session of payload.sessions as { weekday: number | null }[]) session.weekday = null;
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertEquals(text.split("\n").filter((line) => line.endsWith(": no session")).length, 7);
  assert(!text.includes("Same muscles on consecutive days"));
});

Deno.test("an older payload without recent_completed still renders the schedule", () => {
  const payload = sundayWithThursdayUndone();
  delete payload.recent_completed;
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(text, "- Mon 2026-10-19 (tomorrow)");
  assertStringIncludes(text, "Sun 2026-10-18 then Mon 2026-10-19: chest, shoulders, triceps");
  // Without yesterday's session the Saturday pair is not known; nothing is invented.
  assert(!text.includes("Sat 2026-10-17 then"));
});
