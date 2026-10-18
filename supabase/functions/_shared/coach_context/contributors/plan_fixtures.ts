// Synthetic get_coach_plan_state_v1 payloads for tests. No real user data. The owner's case: it is
// Saturday 2026-10-17 and the plan's push day (chest, side delts, triceps) is today.
export const ownersCaseDate = "2026-10-17";

const exercise = (
  id: string,
  order: number,
  name: string,
  slug: string | null,
  sets: number,
  repMin: number,
  repMax: number,
  restSeconds: number,
  targetRpe: number | null,
  loadKg: number | null,
) => ({
  planned_exercise_id: id,
  order,
  name,
  slug,
  sets,
  rep_min: repMin,
  rep_max: repMax,
  rest_seconds: restSeconds,
  target_rpe: targetRpe,
  load_kg: loadKg,
});

const target = (
  id: string,
  name: string,
  key: string,
  action: string,
  reason: string,
  loadKg: number | null,
  reps: number,
  sets: number,
  last: { date: string; load: number | null; sets: number; minReps: number },
) => ({
  planned_exercise_id: id,
  exercise_key: key,
  name,
  action,
  reason,
  load_kg: loadKg,
  reps,
  sets,
  confidence: "high",
  basis: {
    last_date: last.date,
    recent: [{
      local_date: last.date,
      load_kg: last.load,
      sets: last.sets,
      min_reps: last.minReps,
      total_reps: last.minReps * last.sets,
      min_rir: 2,
      effort_known: true,
      pain: false,
    }],
  },
});

export function ownersPlanPayload(): Record<string, unknown> {
  return {
    schema_version: "1.0",
    local_date: ownersCaseDate,
    weekday: 6,
    equipment: ["dumbbells", "bench", "cables"],
    avoid_patterns: [],
    plan: { title: "Upper lower push pull", version_number: 2, sessions_per_week: 4 },
    sessions: [
      {
        planned_workout_id: "w-pull",
        order: 1,
        name: "Pull day",
        weekday: 1,
        minutes: 55,
        exercises: [
          exercise("e-row", 1, "Barbell row", "barbell-row", 4, 6, 8, 120, 8, 50),
          exercise("e-pulldown", 2, "Lat pulldown", "lat-pulldown", 3, 8, 12, 90, 8, null),
        ],
      },
      {
        planned_workout_id: "w-legs",
        order: 2,
        name: "Leg day",
        weekday: 3,
        minutes: 60,
        exercises: [
          exercise("e-squat", 1, "Barbell back squat", "barbell-back-squat", 4, 5, 8, 150, 8, 80),
        ],
      },
      {
        planned_workout_id: "w-push",
        order: 3,
        name: "Push day",
        weekday: 6,
        minutes: 60,
        exercises: [
          exercise("e-bench", 1, "Barbell bench press", "barbell-bench-press", 3, 6, 8, 120, 8, 60),
          exercise(
            "e-incline",
            2,
            "Incline dumbbell press",
            "incline-dumbbell-press",
            3,
            8,
            10,
            90,
            8,
            24,
          ),
          exercise(
            "e-lateral",
            3,
            "Cable lateral raise",
            "cable-lateral-raise",
            3,
            12,
            15,
            60,
            9,
            null,
          ),
          exercise(
            "e-pressdown",
            4,
            "Cable triceps pressdown",
            "cable-triceps-pressdown",
            3,
            10,
            12,
            60,
            9,
            null,
          ),
        ],
      },
      {
        planned_workout_id: "w-upper",
        order: 4,
        name: "Upper day",
        weekday: 7,
        minutes: 55,
        exercises: [
          exercise(
            "e-ohp",
            1,
            "Barbell overhead press",
            "barbell-overhead-press",
            3,
            6,
            8,
            120,
            8,
            40,
          ),
        ],
      },
    ],
    completed_this_week: [
      {
        planned_workout_id: "w-pull",
        local_date: "2026-10-12",
        name: "Pull day",
        weekday: 1,
        order: 1,
      },
      {
        planned_workout_id: "w-legs",
        local_date: "2026-10-14",
        name: "Leg day",
        weekday: 3,
        order: 2,
      },
    ],
    progression: {
      schema_version: "1.0",
      targets: [
        target(
          "e-bench",
          "Barbell bench press",
          "barbell-bench-press",
          "add_load",
          "top_of_range",
          62.5,
          6,
          3,
          { date: "2026-10-10", load: 60, sets: 3, minReps: 8 },
        ),
        target(
          "e-incline",
          "Incline dumbbell press",
          "incline-dumbbell-press",
          "add_reps",
          "within_range",
          24,
          9,
          3,
          { date: "2026-10-10", load: 24, sets: 3, minReps: 8 },
        ),
      ],
    },
  };
}

// A synthetic six-day split, Monday to Saturday, with Sunday free. Two sessions train chest, side
// delts and triceps (Monday and Thursday) and Saturday trains shoulders: the shape behind the
// 2026-10-18 report, where Coach prescribed the undone Thursday session on Sunday and never said
// that Monday trains the same muscles.
type Slot = readonly [slug: string, name: string, sets: number];

const split: readonly Readonly<{ id: string; name: string; weekday: number; slots: Slot[] }>[] = [
  {
    id: "w-chest-a",
    name: "Chest priority and side delts",
    weekday: 1,
    slots: [
      ["barbell-bench-press", "Barbell bench press", 4],
      ["incline-dumbbell-press", "Incline dumbbell press", 3],
      ["cable-lateral-raise", "Cable lateral raise", 4],
      ["cable-triceps-pressdown", "Cable triceps pressdown", 3],
    ],
  },
  {
    id: "w-legs-a",
    name: "Legs A",
    weekday: 2,
    slots: [
      ["barbell-back-squat", "Barbell back squat", 4],
      ["leg-press", "Leg press", 3],
      ["leg-extension", "Leg extension", 3],
      ["standing-calf-raise", "Standing calf raise", 3],
    ],
  },
  {
    id: "w-pull",
    name: "Pull and rear delts",
    weekday: 3,
    slots: [
      ["lat-pulldown", "Lat pulldown", 4],
      ["barbell-row", "Barbell row", 3],
      ["face-pull", "Face pull", 3],
      ["cable-curl", "Cable curl", 3],
    ],
  },
  {
    id: "w-chest-b",
    name: "Chest volume and delts",
    weekday: 4,
    slots: [
      ["dumbbell-bench-press", "Dumbbell bench press", 4],
      ["pec-deck", "Pec deck", 3],
      ["dumbbell-lateral-raise", "Dumbbell lateral raise", 4],
      ["dumbbell-overhead-triceps-extension", "Overhead triceps extension", 3],
    ],
  },
  {
    id: "w-legs-b",
    name: "Legs B",
    weekday: 5,
    slots: [
      ["barbell-romanian-deadlift", "Romanian deadlift", 4],
      ["lying-leg-curl", "Lying leg curl", 3],
      ["barbell-hip-thrust", "Hip thrust", 3],
      ["seated-calf-raise", "Seated calf raise", 3],
    ],
  },
  {
    id: "w-shoulders",
    name: "Shoulder width",
    weekday: 6,
    slots: [
      ["dumbbell-shoulder-press", "Dumbbell shoulder press", 3],
      ["cable-lateral-raise", "Cable lateral raise", 4],
      ["dumbbell-rear-delt-fly", "Rear delt fly", 3],
      ["band-pull-apart", "Band pull-apart", 3],
    ],
  },
];

const sessionOf = (item: typeof split[number], order: number) => ({
  planned_workout_id: item.id,
  order,
  name: item.name,
  weekday: item.weekday,
  minutes: 90,
  exercises: item.slots.map(([slug, name, sets], index) =>
    exercise(`${item.id}-${index + 1}`, index + 1, name, slug, sets, 8, 12, 90, 8, null)
  ),
});

/** The date of an ISO weekday in the week of Monday 2026-10-12 (1 is Monday). */
export const splitWeekDate = (weekday: number): string =>
  new Date(Date.UTC(2026, 9, 11 + weekday)).toISOString().slice(0, 10);

/**
 * The split's plan state for a coaching date in the week of Monday 2026-10-12. `done` lists the
 * workout ids finished this week, each on its own weekday's date; `yesterdayDone` and `todayDone`
 * fill recent_completed, which the SQL gives whatever the calendar week.
 */
export function splitPlanPayload(
  weekday: number,
  done: readonly string[],
  extra: Record<string, unknown> = {},
): Record<string, unknown> {
  const finished = (id: string) => split.find((item) => item.id === id)!;
  const row = (id: string, date: string) => ({
    planned_workout_id: id,
    local_date: date,
    name: finished(id).name,
    weekday: finished(id).weekday,
    order: split.indexOf(finished(id)) + 1,
  });
  const completed = done.map((id) => row(id, splitWeekDate(finished(id).weekday)));
  const today = splitWeekDate(weekday);
  const recent = completed.filter((item) =>
    item.local_date === today || item.local_date === splitWeekDate(weekday - 1)
  ).map((item) => ({
    planned_workout_id: item.planned_workout_id,
    local_date: item.local_date,
    name: item.name,
    exercises: finished(item.planned_workout_id).slots.map(([slug, , sets]) => ({ slug, sets })),
  }));
  return {
    schema_version: "1.1",
    local_date: today,
    weekday,
    equipment: ["dumbbells", "bench", "cables"],
    avoid_patterns: [],
    plan: { title: "Six day split", version_number: 3, sessions_per_week: 6 },
    sessions: split.map((item, index) => sessionOf(item, index + 1)),
    completed_this_week: completed,
    recent_completed: recent,
    progression: { schema_version: "1.0", targets: [] },
    ...extra,
  };
}
