// Invariants of the plan contributor over many temporary-block scenarios, so a fix for one repro
// cannot break its neighbour: a block that starts on any weekday of the week and ends on any date,
// today anywhere from three days before the block to three days after its last day, the restored
// plan named like the block's sessions or not, and any subset of the week's sessions finished under
// the old plan or under the block. Every scenario is checked against:
//  (a) no session is both finished and undone, and one workout finishes at most one session;
//  (b) no make-up is offered for a workout finished this week, under any version (by id, or by name
//      across versions);
//  (c) nothing dated after the block's last day comes from the block;
//  (d) the contributor and the schedule lookup agree on done and planned for every date.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { renderLookup } from "../../coach_lookups/render.ts";
import { request } from "../../coach_lookups/lookup_fixtures.ts";
import { addDays } from "../../training/schedule/week_ahead.ts";
import { splitPlanPayload, splitWeekDate } from "./plan_fixtures.ts";
import {
  matchFinished,
  parsePlanState,
  pickFocusSession,
  type PlanSession,
  type PlanState,
  renderTrainingPlan,
  resolveSchedule,
  weekSessions,
} from "./training_plan.ts";

const monday = splitWeekDate(1);
const dateOf = (weekday: number) => addDays(monday, weekday - 1);
const planWeekdays = [1, 3, 5];
const dayNames = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"];
const shortDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];

type Names = Readonly<{ restored: (day: number) => string; block: (day: number) => string }>;

const nameSets: Readonly<Record<string, Names>> = {
  // Every session is called "Full body", block and restored alike.
  allSame: { restored: () => "Full body", block: () => "Full body" },
  // Distinct restored names; the block reuses them.
  reused: {
    restored: (day) => ["Upper", "Lower", "Pull"][planWeekdays.indexOf(day)],
    block: (day) => ["Upper", "Lower", "Pull"][planWeekdays.indexOf(day)],
  },
  // Distinct restored names; the block's own.
  apart: {
    restored: (day) => ["Upper", "Lower", "Pull"][planWeekdays.indexOf(day)],
    block: () => "Home block",
  },
  // Unique per version and day, for the lookup comparison.
  unique: { restored: (day) => `R${day}`, block: (day) => `B${day}` },
};

const exerciseOf = (id: string) => ({
  slug: id.startsWith("b-") ? "push-up" : "barbell-back-squat",
  sets: 3,
});

const sessionPayload = (id: string, name: string, day: number) => ({
  planned_workout_id: id,
  order: planWeekdays.indexOf(day) + 1,
  name,
  weekday: day,
  minutes: 60,
  exercises: [{
    planned_exercise_id: `e-${id}`,
    order: 1,
    name: id.startsWith("b-") ? "Push-up" : "Squat",
    ...exerciseOf(id),
    rep_min: 8,
    rep_max: 12,
  }],
});

type Scenario = Readonly<{
  /** The weekday the block starts, its last day (a date) and today's weekday. */
  start: number;
  endsOn: string;
  today: number;
  names: Names;
  /**
   * Per plan weekday up to today: nothing, finished under the old plan (r), under the block (b), or
   * logged under both (two workouts that day).
   */
  finished: readonly ("none" | "r" | "b" | "both")[];
}>;

const blockActive = (scenario: Scenario) => scenario.today >= scenario.start;

function payloadOf(scenario: Scenario): Record<string, unknown> {
  const { today, names, finished } = scenario;
  const payload = splitPlanPayload(today, []);
  const restored = planWeekdays.map((day) => sessionPayload(`r-${day}`, names.restored(day), day));
  const block = planWeekdays.map((day) => sessionPayload(`b-${day}`, names.block(day), day));
  payload.sessions = blockActive(scenario) ? block : restored;
  payload.after_block = blockActive(scenario)
    ? { ends_on: scenario.endsOn, version_number: 1, sessions: restored }
    : null;
  const rows = planWeekdays.flatMap((day, index) => {
    const choice = finished[index];
    if (day > today || choice === "none") return [];
    const row = (prefix: "r" | "b") => ({
      id: `${prefix}-${day}`,
      date: dateOf(day),
      name: prefix === "r" ? names.restored(day) : names.block(day),
      weekday: day,
      order: index + 1,
    });
    return choice === "both" ? [row("r"), row("b")] : [row(choice)];
  });
  payload.completed_this_week = rows.map((row) => ({
    planned_workout_id: row.id,
    local_date: row.date,
    name: row.name,
    weekday: row.weekday,
    order: row.order,
  }));
  payload.recent_completed = rows.filter((row) =>
    row.date === dateOf(today) || row.date === dateOf(today - 1)
  ).map((row) => ({
    planned_workout_id: row.id,
    local_date: row.date,
    name: row.name,
    exercises: [exerciseOf(row.id)],
  }));
  return payload;
}

function* scenarios(nameKeys: readonly string[]): Generator<Scenario> {
  for (const key of nameKeys) {
    for (let start = 1; start <= 7; start += 1) {
      for (const length of [0, 2, 8]) {
        const endsOn = addDays(dateOf(start), length);
        for (let today = Math.max(1, start - 3); today <= 7; today += 1) {
          if (dateOf(today) > addDays(endsOn, 3)) continue;
          const days = planWeekdays.filter((day) => day <= today);
          const options = ["none", "r", "b", "both"] as const;
          const combos = options.flatMap((a) =>
            options.flatMap((b) => options.map((c) => [a, b, c] as const))
          );
          for (const combo of combos) {
            // Only the days up to today can hold a finished workout.
            if (
              combo.some((choice, index) =>
                choice !== "none" && !days.includes(planWeekdays[index])
              )
            ) {
              continue;
            }
            yield { start, endsOn, today, names: nameSets[key], finished: combo };
          }
        }
      }
    }
  }
}

const describe = (scenario: Scenario) =>
  `start ${scenario.start}, ends ${scenario.endsOn}, today ${scenario.today}, finished ${
    scenario.finished.join("/")
  }`;

Deno.test("invariants (a) to (c): finished, undone and make-up never contradict each other; nothing after the block's last day is the block's", () => {
  let checked = 0;
  for (const scenario of scenarios(["allSame", "reused", "apart"])) {
    const label = describe(scenario);
    const payload = payloadOf(scenario);
    const state = parsePlanState(payload) as PlanState;
    const focus = pickFocusSession(state);
    const matches = matchFinished(state);
    const candidates = weekSessions(state);
    const inBlock = blockActive(scenario);
    const today = dateOf(scenario.today);
    const prefixOn = (date: string) => !inBlock || date > scenario.endsOn ? "r-" : "b-";
    checked += 1;

    // (a) a session is finished or undone, never both; a workout finishes one session at most.
    for (const session of focus.undone) {
      assert(!matches.has(session.id), `${label}: ${session.id} is finished and undone`);
    }
    // A session of a plan is finished by its own workout, or by one of another version: never by a
    // different workout of its own plan.
    for (const [id, row] of matches) {
      const session = candidates.find((item) => item.id === id) as PlanSession;
      const pool = state.afterBlock?.sessions.some((item) => item.id === id)
        ? state.afterBlock.sessions
        : state.sessions;
      assert(
        row.id === id || !pool.some((item) => item.id === row.id),
        `${label}: ${row.id} finished ${session.id} of its own plan`,
      );
    }
    const rowsUsed = [...matches.values()];
    assertEquals(new Set(rowsUsed).size, rowsUsed.length, `${label}: a workout finished two`);
    for (const id of matches.keys()) {
      assert(candidates.some((session) => session.id === id), `${label}: ${id} not in force`);
    }

    // (b) no make-up for a workout finished this week under any version.
    if (focus.missed) {
      const made = focus.session as PlanSession;
      assert(!matches.has(made.id), `${label}: make-up ${made.id} is finished`);
      assert(!state.completed.some((row) => row.id === made.id), `${label}: ${made.id} was logged`);
      const pool = state.afterBlock?.sessions.some((s) => s.id === made.id)
        ? state.afterBlock.sessions
        : state.sessions;
      for (const row of state.completed) {
        const sameName = row.name.toLowerCase() === made.name.toLowerCase();
        const foreign = !pool.some((session) => session.id === row.id);
        if (sameName && foreign) {
          assert(
            rowsUsed.includes(row),
            `${label}: ${row.id} (${row.name}) finished no session but ${made.id} is offered`,
          );
        }
      }
      // A make-up is in force today.
      assert(made.id.startsWith(prefixOn(today)), `${label}: make-up ${made.id} is not in force`);
    }

    // (c) what is undone or offered is in force; nothing after the last day is the block's.
    for (const session of focus.undone) {
      assert(session.id.startsWith(prefixOn(today)), `${label}: undone ${session.id} lapsed`);
    }
    const text = renderTrainingPlan(state) as string;
    if (inBlock) {
      for (const line of text.split("\n")) {
        const ahead = line.match(/^- (Mon|Tue|Wed|Thu|Fri|Sat|Sun) (\d{4}-\d{2}-\d{2})/);
        if (ahead) {
          if (ahead[2] > scenario.endsOn && !line.includes("done:")) {
            assert(!/chest|triceps/.test(line), `${label}: block muscles after the block: ${line}`);
          }
          if (ahead[2] <= scenario.endsOn && ahead[2] >= today && !line.includes("done:")) {
            assert(
              !/quads|glutes/.test(line.replace(/undone earlier.*$/, "")),
              `${label}: restored muscles in the block: ${line}`,
            );
          }
        }
        const other = line.match(/^- (Monday|Tuesday|Wednesday|Thursday|Friday|Saturday|Sunday), /);
        if (other) {
          const date = dateOf(dayNames.indexOf(other[1]) + 1);
          if (date > scenario.endsOn) assert(!line.includes("Push-up"), `${label}: ${line}`);
          else assert(!line.includes("Squat"), `${label}: ${line}`);
        }
      }
    }
  }
  assert(checked > 1_000, `${checked} scenarios`);
});

/** The names (unique per version and day) a lookup or contributor line holds in a segment. */
const tokens = (text: string) => new Set(text.match(/\b[RB][1-7]\b/g) ?? []);

Deno.test("invariant (d): the contributor and the schedule lookup agree on done and planned for every date", () => {
  let checked = 0;
  for (const scenario of scenarios(["unique"])) {
    const label = describe(scenario);
    const payload = payloadOf(scenario);
    const state = parsePlanState(payload) as PlanState;
    const focus = pickFocusSession(state);
    const { points, notes } = resolveSchedule(state, focus);
    const inBlock = blockActive(scenario);
    const todayDate = dateOf(scenario.today);
    const names = scenario.names;
    const restored = planWeekdays.map((day) => ({
      id: `r-${day}`,
      day,
      name: names.restored(day),
    }));
    const block = planWeekdays.map((day) => ({ id: `b-${day}`, day, name: names.block(day) }));
    const versionOn = (date: string) =>
      inBlock && date <= scenario.endsOn && date >= dateOf(scenario.start)
        ? { id: "v-b", number: 2, workouts: block, block: true }
        : { id: "v-r", number: 1, workouts: restored, block: false };
    const weekdayOf = (date: string) =>
      (((Date.parse(`${date}T00:00:00Z`) / 86_400_000) + 3) % 7) + 1;
    const first = addDays(todayDate, -1);
    const last = addDays(todayDate, 6);
    const days = [];
    for (let at = first; at <= last; at = addDays(at, 1)) {
      const version = versionOn(at);
      const weekday = weekdayOf(at);
      const done = (payload.recent_completed as {
        planned_workout_id: string;
        local_date: string;
        name: string;
        exercises: unknown[];
      }[])
        .filter((row) => row.local_date === at).map((row) => ({
          planned_workout_id: row.planned_workout_id,
          name: row.name,
          exercises: row.exercises,
        }));
      days.push({
        date: at,
        weekday,
        version_id: version.id,
        version: version.number,
        block: version.block,
        planned: version.workouts.filter((w) => w.day === weekday).map((w) => ({
          id: w.id,
          name: w.name,
          minutes: 60,
        })),
        done,
      });
    }
    const sessions = [
      ...restored.map((w) => ({ ...w, version_id: "v-r" })),
      ...(inBlock ? block.map((w) => ({ ...w, version_id: "v-b" })) : []),
    ].map((w) => ({
      id: w.id,
      version_id: w.version_id,
      name: w.name,
      weekday: w.day,
      exercises: [exerciseOf(w.id)],
    }));
    const rendered = renderLookup(request("plan_history", first, last, "schedule"), {
      schema_version: "1.1",
      lookup: "plan_history",
      filter: "schedule",
      from: first,
      to: last,
      today: todayDate,
      truncated: false,
      plan: {
        id: versionOn(todayDate).id,
        version: versionOn(todayDate).number,
        starts_on: monday,
      },
      sessions,
      days,
    }).text.split("\n");
    checked += 1;

    for (let at = first; at <= last; at = addDays(at, 1)) {
      const line = rendered.find((l) => l.startsWith(`- ${shortDays[weekdayOf(at) - 1]} ${at}`)) ??
        "";
      const segments = line.replace(/^[^:]*: /, "").split("; ");
      const lookupDone = tokens(segments.filter((s) => s.startsWith("done ")).join(" "));
      const lookupPlanned = tokens(
        segments.filter((s) => s.startsWith("planned ") && !s.includes("not logged")).join(" "),
      );
      const contributorDone = new Set(
        points.filter((p) => p.date === at && p.kind === "done").flatMap((
          p,
        ) => [...tokens(p.name)]),
      );
      const contributorPlanned = new Set([
        ...points.filter((p) => p.date === at && p.kind === "planned").flatMap((
          p,
        ) => [...tokens(p.name)]),
        ...notes.filter((n) => n.date === at && n.text.includes("already done this week")).flatMap((
          n,
        ) => [...tokens(n.text.split(" was ")[0])]),
      ]);
      if (at <= todayDate) {
        assertEquals(contributorDone, lookupDone, `${label}: done on ${at}`);
      }
      if (at > todayDate) {
        assertEquals(contributorPlanned, lookupPlanned, `${label}: planned on ${at}`);
      } else if (at === todayDate) {
        for (const name of contributorPlanned) {
          assert(
            lookupPlanned.has(name) || lookupDone.has(name),
            `${label}: ${name} planned today`,
          );
        }
      }
    }
  }
  assert(checked > 300, `${checked} scenarios`);
});

Deno.test("an ordinary plan change mid-week, no block: each leftover workout finishes the right session, or none", () => {
  const oldNames = ["Push", "Pull", "Legs"];
  const newPlans: readonly (readonly string[])[] = [
    ["Push", "Pull", "Legs"],
    ["Push", "Legs", "Pull"],
    ["Pull", "Push", "Legs"],
    ["Pull", "Legs", "Push"],
    ["Legs", "Push", "Pull"],
    ["Legs", "Pull", "Push"],
    ["Push", "Push", "Legs"],
    ["Upper", "Upper", "Upper"],
    ["Push", "Pull", "Core"],
  ];
  const options = ["none", "old", "new", "both"] as const;
  let checked = 0;
  for (const names of newPlans) {
    for (let today = 1; today <= 7; today += 1) {
      for (const a of options) {
        for (const b of options) {
          for (const c of options) {
            const choices = [a, b, c];
            const label = `new ${names.join("/")}, today ${today}, ${choices.join("/")}`;
            const payload = splitPlanPayload(today, []);
            const base = (payload.sessions as Record<string, unknown>[])[0];
            payload.sessions = planWeekdays.map((day, index) => ({
              ...base,
              planned_workout_id: `n-${day}`,
              name: names[index],
              weekday: day,
              order: index + 1,
            }));
            payload.after_block = null;
            const rows = planWeekdays.flatMap((day, index) => {
              if (day > today || choices[index] === "none") return [];
              const old = { id: `o-${day}`, name: oldNames[index] };
              const current = { id: `n-${day}`, name: names[index] };
              const made = (who: { id: string; name: string }) => ({
                planned_workout_id: who.id,
                local_date: dateOf(day),
                name: who.name,
                weekday: day,
                order: index + 1,
              });
              return choices[index] === "both"
                ? [made(old), made(current)]
                : [made(choices[index] === "old" ? old : current)];
            });
            payload.completed_this_week = rows;
            payload.recent_completed = [];
            const state = parsePlanState(payload) as PlanState;
            const matches = matchFinished(state);
            const sessions = weekSessions(state);
            const used = [...matches.values()];
            checked += 1;

            assertEquals(new Set(used).size, used.length, `${label}: a workout finished two`);
            for (const session of pickFocusSession(state).undone) {
              assert(!matches.has(session.id), `${label}: ${session.id} finished and undone`);
            }
            const nameExists = (name: string) =>
              sessions.some((session) => session.name.toLowerCase() === name.toLowerCase());
            // WHICH session each leftover finishes: the same name when the plan has the name, the
            // same day and place only when it does not.
            for (const [id, row] of matches) {
              if (row.id === id) continue;
              const session = sessions.find((item) => item.id === id) as PlanSession;
              if (nameExists(row.name)) {
                assertEquals(
                  session.name.toLowerCase(),
                  row.name.toLowerCase(),
                  `${label}: ${row.id} -> ${id}`,
                );
              } else {
                assert(
                  session.weekday === row.weekday && session.order === row.order,
                  `${label}: ${row.id} -> ${id} by place`,
                );
              }
            }
            // A leftover that finished nothing found no free session of its name (or, without
            // that name, of its place): it never leaves a free session it could have taken.
            for (const row of state.completed.filter((item) => !used.includes(item))) {
              const ownPlan = state.sessions.some((session) => session.id === row.id);
              if (ownPlan) continue;
              const free = sessions.filter((session) => !matches.has(session.id));
              if (nameExists(row.name)) {
                assert(
                  !free.some((session) => session.name.toLowerCase() === row.name.toLowerCase()),
                  `${label}: ${row.id} left a free session of its name`,
                );
              } else {
                assert(
                  !free.some((session) =>
                    session.weekday === row.weekday && session.order === row.order
                  ),
                  `${label}: ${row.id} left its free slot`,
                );
              }
            }
          }
        }
      }
    }
  }
  assert(checked > 3_000, `${checked} scenarios`);
});
