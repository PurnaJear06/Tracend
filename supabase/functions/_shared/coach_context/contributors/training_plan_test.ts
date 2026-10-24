import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { coachContextContributorTimeoutMs, cutNote, renderCoachContext } from "../host.ts";
import type { LoadSignals } from "../../training/heart_rate/load_signals.ts";
import type { HeartRateInputs } from "../../training/heart_rate/profile.ts";
import { createHeartRateContributor } from "./heart_rate.ts";
import {
  createTrainingPlanContributor,
  finishedOn,
  incompleteRecoverySentence,
  loadSignalsDeadlineMs,
  type LoadSignalsSource,
  longerRestSentence,
  parsePlanState,
  pickFocusSession,
  renderTrainingPlan,
  slowerRecoverySentence,
  trainingPlanContributorBudgetChars,
  weekAheadOf,
} from "./training_plan.ts";
import { overlapFactLine } from "../../training/schedule/week_ahead.ts";
import {
  ownersCaseDate,
  ownersPlanPayload,
  splitPlanPayload,
  splitWeekDate,
} from "./plan_fixtures.ts";

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

const lineOf = (text: string, start: string) => text.split("\n").find((l) => l.startsWith(start))!;

Deno.test("Sunday: Monday is tomorrow, and the undone chest session is not set for today because it repeats Monday's muscles", () => {
  const text = renderTrainingPlan(parsePlanState(sundayWithThursdayUndone()))!;
  assertStringIncludes(text, "Next 7 days from today");
  const today = lineOf(text, "- Sun 2026-10-18 (today)");
  assertStringIncludes(
    today,
    "undone earlier this week: Chest volume and delts (Thursday), Legs B (Friday)",
  );
  assertStringIncludes(
    today,
    "Chest volume and delts is not set for today: it would train chest, triceps, front and side delts on consecutive days with tomorrow's session",
  );
  assertStringIncludes(
    lineOf(text, "- Mon 2026-10-19 (tomorrow)"),
    "Chest priority and side delts (chest, front and side delts, triceps)",
  );
  assertStringIncludes(text, "- Sat 2026-10-24: Shoulder width (");
  assertStringIncludes(
    text,
    "No session is set for the rest of this week; the next one is next week's first: Chest priority and side delts (Monday",
  );
  // Monday's session was logged on the 12th; that is last week's Monday, not tomorrow's, so it is
  // not tagged done.
  assert(!text.includes("done this week]"));
});

Deno.test("a make-up is set for today when it shares nothing with tomorrow, and states the fact, not an order", () => {
  // Only Friday's legs are undone: Sunday could make them up, and Monday trains chest.
  const text = renderTrainingPlan(
    parsePlanState(
      splitPlanPayload(7, ["w-chest-a", "w-legs-a", "w-pull", "w-chest-b", "w-shoulders"]),
    ),
  )!;
  const today = lineOf(text, "- Sun 2026-10-18 (today)");
  assertStringIncludes(
    today,
    "no session is planned today; undone earlier this week: Friday session Legs B",
  );
  assert(!today.includes("make up"));
  assertStringIncludes(text, "A session from earlier this week is still undone: Legs B");
});

Deno.test("an undone session that is tomorrow's own is not made up today; tomorrow covers it", () => {
  // Sunday, and Monday's session (the week's first) was missed: tomorrow's Monday is that session.
  const monday = renderTrainingPlan(
    parsePlanState(
      splitPlanPayload(7, ["w-legs-a", "w-pull", "w-chest-b", "w-legs-b", "w-shoulders"]),
    ),
  )!;
  const today = lineOf(monday, "- Sun 2026-10-18 (today)");
  assert(!today.includes("no session is planned today"));
  assertStringIncludes(today, "undone earlier this week: Chest priority and side delts (Monday)");
  assertStringIncludes(
    lineOf(monday, "- Mon 2026-10-19 (tomorrow)"),
    "Chest priority and side delts",
  );
  assert(!monday.includes("A session from earlier this week is still undone"));
  // Monday and Friday undone: Monday is tomorrow's, so Friday is the candidate and it shares
  // nothing with Monday's chest day, so it is made up today.
  const both = renderTrainingPlan(
    parsePlanState(splitPlanPayload(7, ["w-legs-a", "w-pull", "w-chest-b", "w-shoulders"])),
  )!;
  assertStringIncludes(both, "A session from earlier this week is still undone: Legs B");
  // Monday and Thursday undone: the candidate is Thursday, which repeats Monday's muscles, so
  // nothing is made up and the choice is not pushed on to Friday.
  const repeats = renderTrainingPlan(
    parsePlanState(splitPlanPayload(7, ["w-legs-a", "w-pull", "w-legs-b", "w-shoulders"])),
  )!;
  assertStringIncludes(
    lineOf(repeats, "- Sun 2026-10-18 (today)"),
    "Chest volume and delts is not set for today",
  );
  assert(!repeats.includes("A session from earlier this week is still undone"));
});

// The 2026-10-23 incident: Friday's Legs B was logged (23 sets) and never finished, the hourly job
// closed it, and Coach read it as "not done". It is the athlete's to save or discard.
const legsBUnfinished = (patch: Record<string, unknown> = {}) => ({
  planned_workout_id: "w-legs-b",
  local_date: splitWeekDate(5),
  name: "Legs B",
  logged_sets: 23,
  ...patch,
});
const sundayWithLegsBLogged = (unfinished: Record<string, unknown>[]) =>
  splitPlanPayload(7, ["w-chest-a", "w-legs-a", "w-pull", "w-chest-b", "w-shoulders"], {
    unfinished,
  });

Deno.test("a session logged but not finished reads as logged sets, never as not done", () => {
  const state = parsePlanState(sundayWithLegsBLogged([legsBUnfinished()]))!;
  const text = renderTrainingPlan(state)!;
  assertStringIncludes(
    text,
    "Logged but not finished (the athlete has not saved or discarded them yet): Legs B on 2026-10-16 (23 sets logged).",
  );
  assertStringIncludes(text, "never that it was not done, skipped or missed");
  assertStringIncludes(text, "the athlete can save or discard it on Today");
  assertStringIncludes(text, "[logged 23 sets on 2026-10-16, not finished]");
  // It is not undone, so it is not made up and no line calls it undone.
  assertEquals(pickFocusSession(state).undone, []);
  assert(!text.includes("undone earlier this week"));
  assert(!text.includes("A session from earlier this week is still undone"));
  assert(!text.includes("no session is planned today"));
});

Deno.test("the same week without the unfinished list still calls Legs B undone", () => {
  const text = renderTrainingPlan(parsePlanState(sundayWithLegsBLogged([]))!)!;
  assert(!text.includes("Logged but not finished"));
  assertStringIncludes(text, "A session from earlier this week is still undone: Legs B");
  const older = parsePlanState(
    splitPlanPayload(7, ["w-chest-a", "w-legs-a", "w-pull", "w-chest-b", "w-shoulders"]),
  )!;
  assertEquals(older.unfinished, []);
});

Deno.test("one set reads as one set, and every unfinished session is listed", () => {
  const text = renderTrainingPlan(
    parsePlanState(sundayWithLegsBLogged([
      legsBUnfinished({ logged_sets: 1 }),
      legsBUnfinished({
        planned_workout_id: "w-shoulders",
        name: "Shoulder width",
        local_date: splitWeekDate(6),
        logged_sets: 8,
      }),
    ]))!,
  )!;
  assertStringIncludes(
    text,
    "Legs B on 2026-10-16 (1 set logged), Shoulder width on 2026-10-17 (8 sets logged).",
  );
  assertStringIncludes(text, "[logged 1 set on 2026-10-16, not finished]");
});

Deno.test("a workout left unfinished last week does not stand for this week's session", () => {
  const state = parsePlanState(
    sundayWithLegsBLogged([legsBUnfinished({ local_date: "2026-10-09" })]),
  )!;
  const text = renderTrainingPlan(state)!;
  assertStringIncludes(text, "Legs B on 2026-10-09 (23 sets logged)");
  assertStringIncludes(text, "A session from earlier this week is still undone: Legs B");
  assert(!text.includes("not finished]"));
});

Deno.test("a workout left unfinished under an earlier plan version is matched by name", () => {
  const renamed = parsePlanState(
    sundayWithLegsBLogged([legsBUnfinished({ planned_workout_id: "w-old-legs" })]),
  )!;
  assertEquals(pickFocusSession(renamed).undone, []);
  const other = parsePlanState(
    sundayWithLegsBLogged([legsBUnfinished({ planned_workout_id: "w-old-legs", name: "Arms" })]),
  )!;
  assertEquals(pickFocusSession(other).undone.map((session) => session.name), ["Legs B"]);
});

Deno.test("a row without sets or a day is not an unfinished workout", () => {
  const state = parsePlanState(
    sundayWithLegsBLogged([
      legsBUnfinished({ logged_sets: 0 }),
      legsBUnfinished({ local_date: undefined }),
    ]),
  )!;
  assertEquals(state.unfinished, []);
});

Deno.test("the schedule block and its overlap fact stay compact", () => {
  const text = renderTrainingPlan(parsePlanState(sundayWithThursdayUndone()))!;
  const start = text.indexOf("Next 7 days from today");
  const end = text.indexOf("\nNo session is set for the rest of this week", start);
  const block = text.slice(start, end);
  assert(block.length < 1_800, `${block.length} characters`);
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
  // Thursday and Friday both train chest, triceps and front and side delts.
  const sessions = payload.sessions as { weekday: number; name: string }[];
  sessions[5].weekday = 5;
  sessions[5].name = "Chest again";
  (sessions[5] as Record<string, unknown>).exercises = (sessions[3] as Record<string, unknown>)
    .exercises;
  sessions[4].weekday = 6;
  const state = parsePlanState(payload)!;
  assertStringIncludes(
    overlapFactLine(weekAheadOf(state).overlaps)!,
    "Thu 2026-10-15 then Fri 2026-10-16: chest, triceps, front and side delts",
  );
  // The fact is stated by the watch-outs block, not repeated in the plan block.
  assert(!renderTrainingPlan(state)!.includes("Same muscles on consecutive days"));
});

// Wednesday, with Thursday's slot filled by a second pull session that the athlete did early, on
// Tuesday (a swap). Without the early finish, Wednesday's pull and Thursday's would be back to back.
const wednesdayWithThursdayDoneOnTuesday = () => {
  const payload = splitPlanPayload(3, ["w-chest-a", "w-legs-a"]);
  const sessions = payload.sessions as Record<string, unknown>[];
  sessions[3].exercises = sessions[2].exercises;
  (payload.completed_this_week as unknown[]).push({
    planned_workout_id: "w-chest-b",
    local_date: "2026-10-13",
    name: "Chest volume and delts",
    weekday: 4,
    order: 4,
  });
  return payload;
};

Deno.test("a session already done this week is not planned again, and no overlap comes from it", () => {
  const text = renderTrainingPlan(parsePlanState(wednesdayWithThursdayDoneOnTuesday()))!;
  const thursday = lineOf(text, "- Thu 2026-10-15");
  assertStringIncludes(thursday, "no session");
  assertStringIncludes(
    thursday,
    "Chest volume and delts was already done this week, on 2026-10-13",
  );
  assert(!text.includes("Same muscles on consecutive days"));
  // The same plan with Thursday's session not done does overlap Wednesday's.
  const open = wednesdayWithThursdayDoneOnTuesday();
  open.completed_this_week = (open.completed_this_week as { planned_workout_id: string }[]).filter(
    (row) => row.planned_workout_id !== "w-chest-b",
  );
  assertStringIncludes(
    overlapFactLine(weekAheadOf(parsePlanState(open)!).overlaps)!,
    "Wed 2026-10-14 then Thu 2026-10-15: biceps, back, rear delts",
  );
  assertEquals(weekAheadOf(parsePlanState(wednesdayWithThursdayDoneOnTuesday())!).overlaps, []);
});

Deno.test("from the next ISO week on, every session is planned again", () => {
  // Wednesday: Monday's session is done this week, and next Monday it is planned again.
  const text = renderTrainingPlan(
    parsePlanState(splitPlanPayload(3, ["w-chest-a", "w-legs-a"])),
  )!;
  assertStringIncludes(text, "- Mon 2026-10-19: Chest priority and side delts (");
  assertStringIncludes(text, "- Tue 2026-10-20: Legs A (");
  assert(!text.includes("was already done this week, on 2026-10-19"));
});

Deno.test("a session logged today and another still planned today are both on today's line", () => {
  // Friday's slot is still planned, and Thursday's session was done today instead of yesterday.
  const payload = splitPlanPayload(5, ["w-chest-a", "w-legs-a", "w-pull"], {
    recent_completed: [{
      planned_workout_id: "w-chest-b",
      local_date: "2026-10-16",
      name: "Chest volume and delts",
      exercises: [{ slug: "dumbbell-bench-press", sets: 4 }],
    }],
  });
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(text, "Today's planned session: Legs B");
  assertStringIncludes(
    lineOf(text, "- Fri 2026-10-16 (today)"),
    "done: Chest volume and delts + Legs B",
  );
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

Deno.test("Monday after a Sunday session: yesterday's session, outside the calendar week, counts", () => {
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
  assertStringIncludes(
    overlapFactLine(weekAheadOf(parsePlanState(payload)!).overlaps)!,
    "Sun 2026-10-18 then Mon 2026-10-19: ",
  );
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
  assert(!text.includes("Sat 2026-10-17 then"));
});

// A plan at the largest size the app allows: seven sessions of nine exercises with long names.
const bigPlan = () => {
  const payload = splitPlanPayload(3, ["w-chest-a"]);
  const base = (payload.sessions as Record<string, unknown>[])[0];
  const pool = [
    "barbell-bench-press",
    "incline-dumbbell-press",
    "cable-lateral-raise",
    "cable-triceps-pressdown",
    "dumbbell-bench-press",
    "pec-deck",
    "dumbbell-lateral-raise",
    "dumbbell-overhead-triceps-extension",
    "dumbbell-shoulder-press",
  ];
  payload.sessions = Array.from({ length: 7 }, (_, day) => ({
    ...base,
    planned_workout_id: `w-big-${day}`,
    order: day + 1,
    name: `Session ${day + 1} with a rather long descriptive name for the day`,
    weekday: day + 1,
    exercises: pool.map((slug, index) => ({
      ...(base.exercises as Record<string, unknown>[])[0],
      planned_exercise_id: `e-big-${day}-${index}`,
      order: index + 1,
      name: `Long exercise name number ${index + 1} with extra words for the day`,
      slug,
      sets: 3,
    })),
  }));
  payload.completed_this_week = [];
  payload.recent_completed = [];
  return payload;
};

Deno.test("a plan of 9 exercises in 7 sessions with long names fits the budget whole", () => {
  const text = renderTrainingPlan(parsePlanState(bigPlan()))!;
  assert(text.length <= trainingPlanContributorBudgetChars, `${text.length} characters`);
});

Deno.test("when a block is cut for size the rules and the week stay: only the trailing lists shrink", async () => {
  const contributor = createTrainingPlanContributor(() => Promise.resolve(bigPlan()));
  const full = renderTrainingPlan(parsePlanState(bigPlan()))!;
  // A budget that cannot hold the whole text: the host drops whole trailing lines.
  const squeezed = await renderCoachContext([{
    ...contributor,
    budgetChars: Math.floor(full.length * 0.7),
  }], { userId: "user-1", question: "q", localDate: "2026-10-14" });
  const body = squeezed.texts.training_plan;
  assertStringIncludes(body, "name only exercises listed here");
  assertStringIncludes(body, "Next 7 days from today");
  assertStringIncludes(body, "Sets a week by main muscle in the plan");
  assert(body.endsWith(cutNote));
  assertEquals(squeezed.outcomes[0].clipped, true);
});

Deno.test("two sessions with one name are told apart by id: finishing one does not finish the other", () => {
  // Two sessions called "Upper" on Monday and Thursday; Monday's was done.
  const payload = splitPlanPayload(3, []);
  const sessions = payload.sessions as Record<string, unknown>[];
  sessions[0].name = "Upper";
  sessions[3].name = "Upper";
  payload.completed_this_week = [{
    planned_workout_id: "w-chest-a",
    local_date: "2026-10-12",
    name: "Upper",
    weekday: 1,
    order: 1,
  }];
  const state = parsePlanState(payload)!;
  assertEquals(finishedOn(state, state.sessions[0]), "2026-10-12");
  assertEquals(finishedOn(state, state.sessions[3]), null);
  const text = renderTrainingPlan(state)!;
  assertStringIncludes(lineOf(text, "- Thu 2026-10-15"), "Upper (");
  assert(!lineOf(text, "- Thu 2026-10-15").includes("already done"));
});

Deno.test("a temporary block ending this week: the days after it show the plan it hands back to", () => {
  // Wednesday 2026-10-14; the block's sessions are bodyweight push-ups on every weekday and the
  // block ends on Friday. Saturday and Sunday are the restored plan's: Shoulder width on Saturday.
  const payload = splitPlanPayload(3, ["w-chest-a", "w-legs-a"]);
  const restored = (payload.sessions as Record<string, unknown>[]).map((session) => ({
    ...session,
  }));
  const base = (payload.sessions as Record<string, unknown>[])[0];
  payload.sessions = [1, 2, 3, 4, 5, 6, 7].map((weekday) => ({
    ...base,
    planned_workout_id: `w-block-${weekday}`,
    name: "Home block",
    weekday,
    order: weekday,
    exercises: [{
      planned_exercise_id: `e-block-${weekday}`,
      order: 1,
      name: "Push-up",
      slug: "push-up",
      sets: 3,
      rep_min: 8,
      rep_max: 12,
    }],
  }));
  payload.after_block = { ends_on: "2026-10-16", version_number: 2, sessions: restored };
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(lineOf(text, "- Thu 2026-10-15"), "Home block");
  assertStringIncludes(lineOf(text, "- Fri 2026-10-16"), "Home block");
  assertStringIncludes(lineOf(text, "- Sat 2026-10-17"), "Shoulder width");
  assertStringIncludes(lineOf(text, "- Mon 2026-10-19"), "Chest priority and side delts");
  assert(!lineOf(text, "- Sun 2026-10-18").includes("Home block"));
});

// A plan state whose active version is a "Home block" with a session every weekday, ending on
// `endsOn`, and which hands back to the six-day split.
const blockPayload = (weekday: number, endsOn: string, done: readonly string[] = []) => {
  const payload = splitPlanPayload(weekday, done);
  const restored = payload.sessions as Record<string, unknown>[];
  const base = restored[0];
  payload.sessions = [1, 2, 3, 4, 5, 6, 7].map((day) => ({
    ...base,
    planned_workout_id: `w-block-${day}`,
    name: "Home block",
    weekday: day,
    order: day,
    exercises: [{
      planned_exercise_id: `e-block-${day}`,
      order: 1,
      name: "Push-up",
      slug: "push-up",
      sets: 3,
      rep_min: 8,
      rep_max: 12,
    }],
  }));
  payload.after_block = { ends_on: endsOn, version_number: 2, sessions: restored };
  return payload;
};

Deno.test("a block ending this week: today's prescription and the lists never read the block after its last day", () => {
  // Saturday, the day after the block's last day (the hourly job has not swapped the version yet).
  const text = renderTrainingPlan(parsePlanState(blockPayload(6, "2026-10-16")))!;
  assertStringIncludes(text, "Today's planned session: Shoulder width");
  assertStringIncludes(lineOf(text, "- Sat 2026-10-17 (today)"), "Shoulder width");
  assert(
    !text.split("\n").slice(text.split("\n").findIndex((l) => l.startsWith("Today's planned")))
      .some((l) => /^- (Saturday|Sunday), Home block/.test(l)),
  );
});

Deno.test("a block ending this week: the other sessions mix the block's days and the restored plan's, and the way back is named", () => {
  const text = renderTrainingPlan(parsePlanState(blockPayload(3, "2026-10-15")))!;
  // Wednesday: Mon to Thu are the block's, Fri to Sun the restored plan's.
  assertStringIncludes(text, "- Thursday, Home block: Push-up");
  assertStringIncludes(text, "- Friday, Legs B: ");
  assertStringIncludes(text, "- Saturday, Shoulder width: ");
  assert(!text.includes("- Friday, Home block"));
  assertStringIncludes(
    text,
    "After the temporary block (last day 2026-10-15) the plan returns to: Monday Chest priority and side delts; Tuesday Legs A;",
  );
});

Deno.test("a block that ended before this week: the next-week fallback is the restored plan's first session", () => {
  const text = renderTrainingPlan(
    parsePlanState(
      blockPayload(7, "2026-10-11", [
        "w-chest-a",
        "w-legs-a",
        "w-pull",
        "w-chest-b",
        "w-legs-b",
        "w-shoulders",
      ]),
    ),
  )!;
  assertStringIncludes(
    text,
    "No session is set for the rest of this week; the next one is next week's first: Chest priority and side delts (Monday",
  );
  assert(!text.includes("Home block"));
});

// A block of "Home block" sessions on the given weekdays that ends on `endsOn`, handing back to
// "Full body" on Thursday, Friday and Saturday. Each restored session has its own id.
const blockToFullBody = (
  weekday: number,
  blockDays: readonly number[],
  endsOn: string,
  done: readonly Readonly<{ id: string; date: string; weekday: number }>[] = [],
) => {
  const payload = splitPlanPayload(weekday, []);
  const base = (payload.sessions as Record<string, unknown>[])[0];
  // The block's sessions are push-ups and the restored plan's are squats, so a session read from
  // the wrong pool shows in its muscles.
  const session = (id: string, name: string, day: number) => ({
    ...base,
    planned_workout_id: id,
    name,
    weekday: day,
    order: day,
    exercises: [{
      planned_exercise_id: `e-${id}`,
      order: 1,
      name: id.startsWith("b-") ? "Push-up" : "Squat",
      slug: id.startsWith("b-") ? "push-up" : "barbell-back-squat",
      sets: 3,
      rep_min: 8,
      rep_max: 12,
    }],
  });
  payload.sessions = blockDays.map((day) => session(`b-${day}`, "Home block", day));
  payload.after_block = {
    ends_on: endsOn,
    version_number: 2,
    sessions: [4, 5, 6].map((day) => session(`r-${day}`, "Full body", day)),
  };
  payload.completed_this_week = done.map((row) => ({
    planned_workout_id: row.id,
    local_date: row.date,
    name: row.id.startsWith("r-") ? "Full body" : "Home block",
    weekday: row.weekday,
    order: row.weekday,
  }));
  payload.recent_completed = [];
  return payload;
};

Deno.test("restored sessions with one name are told apart by id: Thursday's does not finish Friday's or Saturday's", () => {
  // The block ended Wednesday 2026-10-14; Thursday's Full body was logged. On Friday, Friday's is
  // today's and Saturday's is still to do.
  const payload = blockToFullBody(5, [1, 2, 3], "2026-10-14", [
    { id: "r-4", date: "2026-10-15", weekday: 4 },
  ]);
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(text, "Today's planned session: Full body (Friday");
  assert(!text.includes("was already done this week"), "no restored session is done early");
  assertStringIncludes(lineOf(text, "- Sat 2026-10-17"), "Full body (");
  assert(!lineOf(text, "- Sat 2026-10-17").includes("already done"));
});

Deno.test("a block session left undone is not made up after the block's last day", () => {
  // The block (Monday to Wednesday) ended on Wednesday 2026-10-14; the restored Thursday, Friday and
  // Saturday sessions are done, today is Saturday. Monday's Home block lapsed: nothing is undone.
  const payload = blockToFullBody(6, [1, 2, 3], "2026-10-14", [
    { id: "r-4", date: "2026-10-15", weekday: 4 },
    { id: "r-5", date: "2026-10-16", weekday: 5 },
    { id: "r-6", date: "2026-10-17", weekday: 6 },
  ]);
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assert(!text.includes("A session from earlier this week is still undone"));
  assert(!lineOf(text, "- Sat 2026-10-17 (today)").includes("Home block"));
  assert(!text.includes("undone earlier this week"));
  // The same plan during the block (Wednesday, its last day) does count Monday's as undone.
  const during = blockToFullBody(3, [1, 2, 3], "2026-10-14");
  assertStringIncludes(
    renderTrainingPlan(parsePlanState(during))!,
    "undone earlier this week: Home block (Monday), Home block (Tuesday)",
  );
});

// The five points of a temporary block as the contributor sees them: before it (an ordinary plan),
// during it, its last day, the day after it (the hourly job has not swapped the version yet) and
// after the job's clone (an ordinary plan again). Each row is [what the state holds, the weekday
// and date of today, today's session, tomorrow's session].
Deno.test("a temporary block, five points: today's and tomorrow's sessions come from the plan in force", () => {
  const regular = (weekday: number) => {
    const payload = blockToFullBody(weekday, [], "2026-10-14");
    payload.sessions = (payload.after_block as { sessions: unknown[] }).sessions;
    payload.after_block = null;
    return payload;
  };
  const rows: readonly (readonly [string, Record<string, unknown>, string, string])[] = [
    [
      "before the block",
      regular(4),
      "- Thu 2026-10-15 (today): Full body",
      "- Fri 2026-10-16 (tomorrow): Full body",
    ],
    [
      "during the block",
      blockToFullBody(2, [1, 2, 3], "2026-10-14"),
      "- Tue 2026-10-13 (today): Home block",
      "- Wed 2026-10-14 (tomorrow): Home block",
    ],
    [
      "its last day",
      blockToFullBody(3, [1, 2, 3], "2026-10-14"),
      "- Wed 2026-10-14 (today): Home block",
      "- Thu 2026-10-15 (tomorrow): Full body",
    ],
    [
      "the day after",
      blockToFullBody(4, [1, 2, 3, 4, 5, 6], "2026-10-14"),
      "- Thu 2026-10-15 (today): Full body",
      "- Fri 2026-10-16 (tomorrow): Full body",
    ],
    [
      "after the clone",
      regular(5),
      "- Fri 2026-10-16 (today): Full body",
      "- Sat 2026-10-17 (tomorrow): Full body",
    ],
  ];
  for (const [point, payload, today, tomorrow] of rows) {
    const text = renderTrainingPlan(parsePlanState(payload))!;
    assertStringIncludes(text, today, point);
    assertStringIncludes(text, tomorrow, point);
    // Nothing dated after the block's last day is read from the block.
    if (point === "the day after") {
      assert(!/^- (Thu|Fri|Sat|Sun) 2026-10-\d\d[^\n]*Home block/m.test(text), point);
      assertStringIncludes(text, "Today's planned session: Full body (Thursday", point);
      // The sets a week are those of the plan in force (3 restored sessions of 3 squat sets).
      assertStringIncludes(text, "Sets a week by main muscle in the plan: quads 9", point);
    }
  }
});

Deno.test("a restored session finished yesterday with no logged exercises falls back to the restored plan's sets", () => {
  const payload = blockToFullBody(5, [1, 2, 3], "2026-10-14");
  payload.recent_completed = [{
    planned_workout_id: "r-4",
    local_date: "2026-10-15",
    name: "Full body",
    exercises: [],
  }];
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(lineOf(text, "- Thu 2026-10-15"), "done: Full body (glutes, quads)");
});

Deno.test("a block approved mid-week: Monday's workout finished under the old plan counts for the block's Monday slot", () => {
  // Wednesday: the block (Full body on Monday, Wednesday, Friday) was approved today and runs to the
  // 25th; Monday's Full body (r-1) was finished under the plan it replaced.
  const payload = splitPlanPayload(3, []);
  const base = (payload.sessions as Record<string, unknown>[])[0];
  const session = (id: string, day: number) => ({
    ...base,
    planned_workout_id: id,
    name: "Full body",
    weekday: day,
    order: day,
    exercises: [{
      planned_exercise_id: `e-${id}`,
      order: 1,
      name: "Squat",
      slug: "barbell-back-squat",
      sets: 3,
      rep_min: 8,
      rep_max: 12,
    }],
  });
  payload.sessions = [1, 3, 5].map((day) => session(`b-${day}`, day));
  payload.after_block = {
    ends_on: "2026-10-25",
    version_number: 1,
    sessions: [1, 3, 5].map((day) => session(`r-${day}`, day)),
  };
  payload.completed_this_week = [{
    planned_workout_id: "r-1",
    local_date: "2026-10-12",
    name: "Full body",
    weekday: 1,
    order: 1,
  }];
  payload.recent_completed = [];
  const state = parsePlanState(payload)!;
  assertEquals(pickFocusSession(state).undone, []);
  const text = renderTrainingPlan(state)!;
  assert(!text.includes("undone earlier this week"));
  assert(!text.includes("A session from earlier this week is still undone"));
  assertStringIncludes(text, "[done 2026-10-12]");
});

Deno.test("weekday-less sessions follow the plan in force too: after the block's last day, the restored plan's", () => {
  const payload = blockToFullBody(5, [1, 2, 3], "2026-10-14");
  (payload.sessions as Record<string, unknown>[]).push({
    ...(payload.sessions as Record<string, unknown>[])[0],
    planned_workout_id: "b-float",
    name: "Block extra",
    weekday: null,
    order: 9,
  });
  (payload.after_block as { sessions: Record<string, unknown>[] }).sessions.push({
    ...(payload.sessions as Record<string, unknown>[])[0],
    planned_workout_id: "r-float",
    name: "Restored extra",
    weekday: null,
    order: 9,
  });
  const text = renderTrainingPlan(parsePlanState(payload))!;
  assertStringIncludes(text, "no set day, Restored extra");
  assert(!text.includes("Block extra"));
});

// An ordinary plan change in the middle of a week: the new plan's sessions and the workouts
// finished this week, some of them under the old plan. Today is Saturday 2026-10-17.
type Slot = readonly [id: string, name: string, weekday: number, order: number];
type Done = readonly [id: string, name: string, weekday: number, order: number, date: string];
const reshuffled = (slots: readonly Slot[], done: readonly Done[]) => {
  const payload = splitPlanPayload(6, []);
  const base = (payload.sessions as Record<string, unknown>[])[0];
  payload.sessions = slots.map(([id, name, weekday, order]) => ({
    ...base,
    planned_workout_id: id,
    name,
    weekday,
    order,
  }));
  payload.after_block = null;
  payload.completed_this_week = done.map(([id, name, weekday, order, date]) => ({
    planned_workout_id: id,
    local_date: date,
    name,
    weekday,
    order,
  }));
  payload.recent_completed = [];
  return parsePlanState(payload)!;
};
const finishedNames = (state: ReturnType<typeof reshuffled>) =>
  state.sessions.filter((session) => finishedOn(state, session) !== null).map((session) =>
    session.name
  );
const mon = "2026-10-12";
const tue = "2026-10-13";
const wed = "2026-10-14";
const thu = "2026-10-15";
const fri = "2026-10-16";

Deno.test("plan change (a): old Push done Monday and Wednesday, new Monday Pull and Wednesday Push: Pull stays undone", () => {
  const state = reshuffled([["n-1", "Pull", 1, 1], ["n-3", "Push", 3, 2]], [
    ["o-1", "Push", 1, 1, mon],
    ["o-3", "Push", 3, 2, wed],
  ]);
  assertEquals(finishedNames(state), ["Push"]);
  assertEquals(pickFocusSession(state).undone.map((session) => session.name), ["Pull"]);
});

Deno.test("plan change (b): old Push done Monday plus the new Push done Wednesday: Pull stays undone", () => {
  const state = reshuffled([["n-1", "Pull", 1, 1], ["n-3", "Push", 3, 2]], [
    ["o-1", "Push", 1, 1, mon],
    ["n-3", "Push", 3, 2, wed],
  ]);
  assertEquals(finishedNames(state), ["Push"]);
  assertEquals(finishedOn(state, state.sessions[1]), wed);
  assertEquals(pickFocusSession(state).undone.map((session) => session.name), ["Pull"]);
});

Deno.test("plan change (c): a renamed workout takes its slot only after names are matched: Pull stays undone", () => {
  // Old "Squat day" (Monday, slot 1) and old Push (Tuesday, slot 2); the new plan has Push on
  // Monday and Pull on Tuesday. Push is finished by the old Push; the old Squat day, whose name no
  // session has, finds its slot (Monday) taken and finishes nothing.
  const state = reshuffled([["n-1", "Push", 1, 1], ["n-2", "Pull", 2, 2]], [
    ["o-1", "Squat day", 1, 1, mon],
    ["o-2", "Push", 2, 2, tue],
  ]);
  assertEquals(finishedNames(state), ["Push"]);
  assertEquals(finishedOn(state, state.sessions[0]), tue);
  assertEquals(pickFocusSession(state).undone.map((session) => session.name), ["Pull"]);
});

Deno.test("a renamed workout still finds its slot when no name competes", () => {
  const state = reshuffled([["n-1", "Push", 1, 1], ["n-2", "Pull", 2, 2]], [
    ["o-1", "Squat day", 1, 1, mon],
  ]);
  assertEquals(finishedNames(state), ["Push"]);
});

Deno.test("a workout done off its own weekday counts for the same-name session nearest to the day it was done", () => {
  const upper = (done: Done) =>
    reshuffled([["n-1", "Upper", 1, 1], ["n-5", "Upper", 5, 2]], [done]);
  // Done on a Thursday: Friday's Upper is nearer than Monday's.
  const thursday = upper(["o-9", "Upper", 4, 1, thu]);
  assertEquals(finishedOn(thursday, thursday.sessions[1]), thu);
  assertEquals(finishedOn(thursday, thursday.sessions[0]), null);
  // Done on a Tuesday: Monday's is nearer.
  const tuesday = upper(["o-9", "Upper", 2, 1, tue]);
  assertEquals(finishedOn(tuesday, tuesday.sessions[0]), tue);
  assertEquals(finishedOn(tuesday, tuesday.sessions[1]), null);
});

Deno.test("workouts are matched in the order they were done, whatever order they arrive in", () => {
  // One session called Upper, and two old Upper workouts (Monday, Friday) listed newest first: the
  // first to be done counts, the second finishes nothing.
  const state = reshuffled([["n-3", "Upper", 3, 1]], [
    ["o-5", "Upper", 5, 1, fri],
    ["o-1", "Upper", 1, 1, mon],
  ]);
  assertEquals(finishedOn(state, state.sessions[0]), mon);
});

Deno.test("a workout logged twice finishes its session once, on its first date", () => {
  const state = reshuffled([["n-1", "Upper", 1, 1]], [
    ["n-1", "Upper", 1, 1, mon],
    ["n-1", "Upper", 1, 1, wed],
  ]);
  assertEquals(finishedOn(state, state.sessions[0]), mon);
});

Deno.test("the athlete's level reaches the home alternatives: an advanced lifter's pull-up has a weighted form", () => {
  const withLevel = (experience: unknown) =>
    render((payload) => {
      payload.experience = experience;
      const today = (payload.sessions as { weekday: number; exercises: { slug: string }[] }[])
        .find((session) => session.weekday === 6)!;
      today.exercises[0].slug = "pull-up";
    })!;
  assertStringIncludes(withLevel("advanced"), "Weighted pull-up");
  assert(!withLevel("intermediate").includes("Weighted pull-up"));
  // An older payload without the level reads as intermediate, as before.
  assert(!withLevel(undefined).includes("Weighted pull-up"));
  assertEquals(
    parsePlanState({ ...ownersPlanPayload(), experience: "advanced" })?.experience,
    "advanced",
  );
  assertEquals(
    parsePlanState({ ...ownersPlanPayload(), experience: "expert" })?.experience,
    "intermediate",
  );
  assertEquals(parsePlanState(ownersPlanPayload())?.experience, "intermediate");
});

// Heart-rate load signals (C4): fixed sentences, never a changed target (D9).
const signalsWith = (engine: Partial<LoadSignals["engine"]>): LoadSignals => ({
  engine: { confidence: "none", rest: "none", reasons: [], ...engine },
});

const slowerRecovery = signalsWith({ confidence: "lower", reasons: ["recovery_slower"] });
const slowSettling = signalsWith({ confidence: "lower", reasons: ["slow_settling"] });

const renderWith = (
  signals: LoadSignals | null,
  mutate?: (payload: Record<string, unknown>) => void,
) => {
  const payload = ownersPlanPayload();
  mutate?.(payload);
  return renderTrainingPlan(parsePlanState(payload), signals);
};

const bench = (text: string) => lineOf(text, "  1. Barbell bench press");
const incline = (text: string) => lineOf(text, "  2. Incline dumbbell press");

Deno.test("slower recovery marks a step up as less certain and changes nothing else", () => {
  const plain = renderWith(null)!;
  const text = renderWith(slowerRecovery)!;
  assertStringIncludes(bench(text), "add load");
  assertStringIncludes(bench(text), slowerRecoverySentence);
  assertStringIncludes(incline(text), slowerRecoverySentence);
  assert(!lineOf(text, "  3. Cable lateral raise").includes(slowerRecoverySentence));
  assertEquals(text.split(slowerRecoverySentence).length - 1, 2);
  // Only the sentence differs: the target, the loads and the reps are the same text.
  assertEquals(text.replaceAll(` ${slowerRecoverySentence}`, ""), plain);
});

Deno.test("each reason gets its own sentence, and only a comparison says 'than usual'", () => {
  const settling = renderWith(slowSettling)!;
  assertStringIncludes(bench(settling), incompleteRecoverySentence);
  assert(!settling.includes(slowerRecoverySentence));
  assert(!settling.includes("than usual"), "a fixed line is not a comparison");
  const slower = renderWith(slowerRecovery)!;
  assertStringIncludes(slower, "than usual");
  assert(!slower.includes(incompleteRecoverySentence));
  // Both reasons: the comparison is true, so it is the one said.
  const both = renderWith(
    signalsWith({ confidence: "lower", reasons: ["slow_settling", "recovery_slower"] }),
  )!;
  assertStringIncludes(bench(both), slowerRecoverySentence);
  assert(!both.includes(incompleteRecoverySentence));
  // The rest sentence is no comparison either.
  const rest = renderWith(signalsWith({ rest: "allow_longer", reasons: ["rest_short"] }))!;
  assert(!rest.includes("than usual"));
  assert(!incompleteRecoverySentence.includes("than usual"));
  assert(!longerRestSentence.includes("than usual"));
});

Deno.test("confidence none adds nothing", () => {
  assertEquals(renderWith(signalsWith({})), renderWith(null));
});

Deno.test("a hold or a cut is never called less certain", () => {
  for (const action of ["hold", "lower"]) {
    for (const signals of [slowerRecovery, slowSettling]) {
      const text = renderWith(signals, (payload) => {
        const targets = (payload.progression as { targets: Record<string, unknown>[] }).targets;
        for (const target of targets) target.action = action;
      })!;
      assert(!text.includes("less certain"), action);
    }
  }
});

Deno.test("the sentence needs a target: an exercise with no logged sets has none", () => {
  const text = renderWith(slowerRecovery, (payload) => {
    (payload.progression as { targets: unknown[] }).targets = [];
  })!;
  assert(!text.includes("less certain"));
});

Deno.test("a longer rest is suggested once, before the exercises, when heart rate asks for it", () => {
  const text = renderWith(signalsWith({ rest: "allow_longer", reasons: ["rest_short"] }))!;
  assertEquals(text.split(longerRestSentence).length - 1, 1);
  assert(text.indexOf(longerRestSentence) < text.indexOf("  1. Barbell bench press"));
  assert(!text.includes("less certain"), "rest alone does not lower confidence");
  assert(!renderWith(signalsWith({}))!.includes(longerRestSentence));
});

Deno.test("the sentences carry no figure, so a reply can quote nothing from them", () => {
  for (const sentence of [slowerRecoverySentence, incompleteRecoverySentence, longerRestSentence]) {
    assert(!/\d/.test(sentence), sentence);
  }
});

const turn = { userId: "user-1", question: "q", localDate: ownersCaseDate };
const planSource = () => Promise.resolve(ownersPlanPayload());

async function plan(
  signals?: LoadSignalsSource,
  deadlineMs?: number,
  source: () => Promise<unknown> = planSource,
) {
  const rendered = await renderCoachContext(
    [createTrainingPlanContributor(source, signals, deadlineMs)],
    turn,
  );
  return {
    text: rendered.texts.training_plan,
    outcome: rendered.outcomes[0],
    trace: rendered.traces?.training_plan,
  };
}

Deno.test("the registered contributor reads the signals and traces how the read went", async () => {
  const without = await plan();
  assert(!without.text.includes("less certain"));
  assertEquals(without.trace, undefined);

  const ok = await plan(() => Promise.resolve(slowerRecovery));
  assertStringIncludes(ok.text, slowerRecoverySentence);
  assertEquals(ok.trace, { load_signals: "ok" });

  for (
    const [reader, status] of [
      [() => Promise.resolve(null), "unavailable"],
      [() => Promise.reject(new Error("down")), "failed"],
      [() => {
        throw new Error("sync");
      }, "failed"],
    ] as const
  ) {
    const result = await plan(reader);
    assertEquals(result.text, without.text, status);
    assertEquals(result.outcome.outcome, "rendered");
    assertEquals(result.trace, { load_signals: status });
  }
});

Deno.test("a signals read that never answers cannot hold the plan: it renders as before, in time", async () => {
  const without = await plan();
  const started = performance.now();
  const hung = await plan(() => new Promise(() => {}), 50);
  assert(performance.now() - started < 1_000, "the deadline is the signals' own");
  assertEquals(hung.text, without.text);
  assertEquals(hung.outcome.outcome, "rendered");
  assertEquals(hung.trace, { load_signals: "timeout" });
});

Deno.test("with the real deadline the plan still renders well inside the host's budget", async () => {
  const started = performance.now();
  const hung = await plan(() => new Promise(() => {}));
  const elapsed = performance.now() - started;
  assertEquals(hung.outcome.outcome, "rendered");
  assert(elapsed >= loadSignalsDeadlineMs - 50 && elapsed < 2_000, `${elapsed} ms`);
  assert(loadSignalsDeadlineMs < coachContextContributorTimeoutMs);
});

Deno.test("the signals read starts with the plan read, not after it", async () => {
  const events: string[] = [];
  await plan(
    () => {
      events.push("signals asked");
      return Promise.resolve(null);
    },
    undefined,
    async () => {
      events.push("plan asked");
      await new Promise((resolve) => setTimeout(resolve, 30));
      events.push("plan answered");
      return ownersPlanPayload();
    },
  );
  assertEquals(events, ["plan asked", "signals asked", "plan answered"]);
});

Deno.test("the profile's inputs are read once for the heart-rate block and the signals", async () => {
  const inputs = { schema_version: "1.0", as_of: ownersCaseDate } as HeartRateInputs;
  for (const planFirst of [true, false]) {
    let reads = 0;
    let seen: HeartRateInputs | null = null;
    const load = () => {
      reads += 1;
      return Promise.resolve(inputs);
    };
    const heart = createHeartRateContributor(load);
    const planWith = createTrainingPlanContributor(planSource, async (_user, _date, read) => {
      seen = await read();
      return null;
    });
    await renderCoachContext(planFirst ? [planWith, heart] : [heart, planWith], turn);
    assertEquals(reads, 1, `plan first: ${planFirst}`);
    assert(seen === inputs, "the signals got the turn's shared read");
  }
});

Deno.test("the largest plan fits its budget with the longest sentence on every step and the rest line", () => {
  const full = renderTrainingPlan(parsePlanState(bigPlan()))!;
  const longest = Math.max(slowerRecoverySentence.length, incompleteRecoverySentence.length);
  const room = 9 * (longest + 1) + longerRestSentence.length + 1;
  assert(
    full.length + room <= trainingPlanContributorBudgetChars,
    `${full.length} + ${room} characters`,
  );
});
