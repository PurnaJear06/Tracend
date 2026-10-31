// Synthetic athlete records for the Coach simulator: months of logged sessions, body weight,
// meals with complete and partial days, check-ins and watch nights, generated deterministically
// from a persona's spec. From the one set of records come every view Coach reads, so a figure
// is the same wherever it shows: the athlete file (prepare_coach_chat_v8's shape), the
// contributor payloads (plan, nutrition, goal phase, data index) and the lookup RPC payloads
// (migration 20261018100020's shapes), which the production lookup runner renders. Nothing here
// is a real athlete.
import type { LookupRpc } from "../../_shared/coach_lookups/runner.ts";
import type { AthleteState, StatePlan } from "../../_shared/coach_proposals/types.ts";

// ---- dates ----------------------------------------------------------------------------------

const dayMs = 86_400_000;

export function addDays(date: string, days: number): string {
  return new Date(Date.parse(`${date}T00:00:00Z`) + days * dayMs).toISOString().slice(0, 10);
}

/** ISO weekday, Monday 1 to Sunday 7. */
export function weekdayOf(date: string): number {
  const day = new Date(`${date}T00:00:00Z`).getUTCDay();
  return day === 0 ? 7 : day;
}

export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / dayMs);
}

/** Every date from `from` to `to`, both included. */
export function datesFrom(from: string, to: string): string[] {
  return Array.from({ length: daysBetween(from, to) + 1 }, (_, index) => addDays(from, index));
}

/** A repeatable sequence of numbers in [0, 1) for one persona (mulberry32). */
export function seeded(seed: string): () => number {
  let state = [...seed].reduce((hash, ch) => Math.imul(hash ^ ch.charCodeAt(0), 2654435761), 7);
  return () => {
    state = (state + 0x6d2b79f5) | 0;
    let t = Math.imul(state ^ (state >>> 15), 1 | state);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

const round = (value: number, step: number) => Math.round(value / step) * step;
const tenth = (value: number) => Math.round(value * 10) / 10;

// ---- the spec -------------------------------------------------------------------------------

export type LiftSpec = Readonly<{
  name: string;
  slug: string;
  sets: number;
  repMin: number;
  repMax: number;
  restSeconds: number;
  targetRpe: number;
  /** The working load at the start of the history (null for an unloaded movement). */
  startKg: number | null;
  /** Added per week while the lift progresses. */
  gainPerWeek: number;
  /** From this date the load stays at `kg`, reps fall to the bottom of the range and effort rises. */
  plateau?: Readonly<{ from: string; kg: number }>;
}>;

export type SessionSpec = Readonly<{
  id: string;
  name: string;
  weekday: number;
  minutes: number;
  lifts: readonly LiftSpec[];
}>;

export type Food = Readonly<{ name: string; calories: number; protein: number }>;

export type MealType = "breakfast" | "lunch" | "dinner" | "snack";

export type TargetVersion = Readonly<{
  from: string;
  calories: number;
  protein: number;
  carbs: number;
  fat: number;
  rationale: string;
}>;

export type PlanVersion = Readonly<{
  from: string;
  /** The date its lifts' starting loads refer to; the history's start when omitted. */
  progressFrom?: string;
  title: string;
  rationale: string;
  blockWeeks: number;
  week: readonly SessionSpec[];
}>;

/** A day that differs from the pattern: a bad night, a hard session, a note, a missed log. */
export type DayEvent = Readonly<{
  date: string;
  sleepMinutes?: number;
  hrvMs?: number;
  checkIn?: Readonly<Partial<Omit<CheckIn, "local_date">>>;
  /** The session that day: its effort and minutes, and lifts that went differently. */
  session?: Readonly<{
    effort?: number;
    energy?: number;
    minutes?: number;
    /** Per lift slug: the sets logged instead of the pattern's. */
    sets?: Readonly<Record<string, readonly SetLog[]>>;
    /** Lift slugs logged with pain flagged. */
    pain?: readonly string[];
  }>;
  /** No session that day although the plan has one. */
  skipSession?: boolean;
  meals?: "partial" | "none";
}>;

export type RecordsSpec = Readonly<{
  /** The coaching date (today). Nothing is logged after it; today has no session yet. */
  today: string;
  /** The first day of the history. */
  start: string;
  /** Plan versions, oldest first; the newest is active. */
  plans: readonly PlanVersion[];
  /** Spans with no training at all (a break, a trip). */
  away?: readonly Readonly<{ from: string; to: string }>[];
  /** One planned session in this many is missed (0: none). */
  missEvery: number;
  /** Body weight knots [date, kg], oldest first; weigh-ins between them are interpolated. */
  weight: readonly (readonly [string, number])[];
  /** ISO weekdays the athlete weighs in. */
  weighInDays: readonly number[];
  /** Waist at the start and at today (cm), measured on the first of each month. */
  waist: readonly [number, number];
  /** The day meal logging started, the targets, and the foods eaten by meal type. */
  nutrition: Readonly<{
    since: string;
    targets: readonly TargetVersion[];
    menu: Readonly<Record<MealType, readonly (readonly Food[])[]>>;
    /** Share of days fully logged, partly logged and not logged (the rest). */
    complete: number;
    partial: number;
  }>;
  sleep: Readonly<{ minutes: number; spread: number; hrvMs: number; restingHr: number }>;
  steps: number;
  /** Days with a check-in, from this date. */
  checkInsSince: string;
  events: readonly DayEvent[];
}>;

// ---- the records ----------------------------------------------------------------------------

export type SetLog = Readonly<{ reps: number; load_kg: number | null; rir: number | null }>;

export type ExerciseLog = Readonly<{
  name: string;
  slug: string;
  planned: Readonly<{ sets: number; rep_min: number; rep_max: number }>;
  sets: readonly SetLog[];
  pain: boolean;
}>;

export type SessionLog = Readonly<{
  local_date: string;
  planned_workout_id: string;
  workout: string;
  minutes: number;
  effort: number;
  energy: number;
  exercises: readonly ExerciseLog[];
}>;

export type MealLog = Readonly<{
  local_date: string;
  meal_type: MealType;
  source: "photo_analysis" | "typed";
  foods: readonly Food[];
}>;

export type MealDay = Readonly<{
  local_date: string;
  meals: number;
  calories: number;
  protein_g: number;
  carbohydrate_g: number;
  fat_g: number;
  complete: boolean;
}>;

export type CheckIn = Readonly<{
  local_date: string;
  sleep_quality: number;
  energy: number;
  soreness: number;
  hunger: number;
  mood: number;
  pain_severity: number;
  available_to_train: boolean;
  note: string | null;
}>;

export type RecoveryDay = Readonly<{
  local_date: string;
  sleep_minutes: number | null;
  resting_heart_rate_bpm: number;
  hrv_ms: number | null;
  steps: number;
  recovery_score: number | null;
  sleep_quality: number | null;
}>;

export type Weighing = Readonly<{ date: string; kg: number; source: "manual" | "healthkit" }>;

export type Records = Readonly<{
  spec: RecordsSpec;
  sessions: readonly SessionLog[];
  meals: readonly MealLog[];
  mealDays: readonly MealDay[];
  checkIns: readonly CheckIn[];
  recovery: readonly RecoveryDay[];
  weights: readonly Weighing[];
  waist: readonly Readonly<{ date: string; waist_cm: number }>[];
}>;

/** The plan version in force on a date (the first one before the history starts). */
export function planOn(spec: RecordsSpec, date: string): PlanVersion {
  return [...spec.plans].reverse().find((plan) => plan.from <= date) ?? spec.plans[0];
}

export function targetOn(spec: RecordsSpec, date: string): TargetVersion {
  const { targets } = spec.nutrition;
  return [...targets].reverse().find((target) => target.from <= date) ?? targets[0];
}

const isAway = (spec: RecordsSpec, date: string) =>
  (spec.away ?? []).some((span) => date >= span.from && date <= span.to);

const eventOn = (spec: RecordsSpec, date: string) => spec.events.find((e) => e.date === date);

/** The working load of a lift on a date, and whether it is on its plateau. */
function loadOn(
  lift: LiftSpec,
  start: string,
  date: string,
): { kg: number | null; stuck: boolean } {
  if (lift.startKg === null) return { kg: null, stuck: false };
  if (lift.plateau && date >= lift.plateau.from) return { kg: lift.plateau.kg, stuck: true };
  const weeks = Math.max(0, daysBetween(start, date)) / 7;
  return { kg: round(lift.startKg + lift.gainPerWeek * weeks, 2.5), stuck: false };
}

function patternSets(lift: LiftSpec, kg: number | null, stuck: boolean, index: number): SetLog[] {
  const span = lift.repMax - lift.repMin + 1;
  const top = stuck ? lift.repMin - (index % 2) : lift.repMin + (index % span);
  return Array.from({ length: lift.sets }, (_, set) => ({
    reps: Math.max(1, top - (set === 0 ? 0 : Math.min(set, 2))),
    load_kg: kg,
    rir: stuck ? (set === lift.sets - 1 ? 0 : 1) : index % 3 === 2 ? 1 : 2,
  }));
}

/** Every record the spec describes, from its start to the day before today (today's check-in too). */
export function buildRecords(spec: RecordsSpec, seed: string): Records {
  const random = seeded(seed);
  const days = datesFrom(spec.start, spec.today);
  const sessions: SessionLog[] = [];
  const meals: MealLog[] = [];
  const mealDays: MealDay[] = [];
  const checkIns: CheckIn[] = [];
  const recovery: RecoveryDay[] = [];
  let planned = 0;
  const liftIndex = new Map<string, number>();

  for (const date of days) {
    const event = eventOn(spec, date);
    const jitter = random();
    // Watch nights: a few nights without the watch, the rest around the athlete's usual sleep.
    const watchOff = jitter < 0.05;
    const sleepMinutes = event?.sleepMinutes ??
      (watchOff ? null : Math.round(spec.sleep.minutes + (random() - 0.5) * 2 * spec.sleep.spread));
    const hrv = event?.hrvMs ??
      (sleepMinutes === null ? null : Math.round(
        spec.sleep.hrvMs + (sleepMinutes - spec.sleep.minutes) / 6 + (random() - 0.5) * 8,
      ));
    const restingHr = Math.round(
      spec.sleep.restingHr + (random() - 0.5) * 4 +
        (sleepMinutes !== null && sleepMinutes < spec.sleep.minutes - 60 ? 4 : 0),
    );
    const score = hrv === null || sleepMinutes === null ? null : Math.max(
      5,
      Math.min(
        95,
        Math.round(55 + (hrv - spec.sleep.hrvMs) * 2 + (sleepMinutes - spec.sleep.minutes) / 4),
      ),
    );
    const quality = sleepMinutes === null ? null : Math.max(
      10,
      Math.min(95, Math.round(70 + (sleepMinutes - spec.sleep.minutes) / 3)),
    );
    recovery.push({
      local_date: date,
      sleep_minutes: sleepMinutes,
      resting_heart_rate_bpm: restingHr,
      hrv_ms: hrv,
      steps: Math.round(spec.steps + (random() - 0.5) * 4000),
      recovery_score: score,
      sleep_quality: quality,
    });

    if (date >= spec.checkInsSince && (random() < 0.88 || event?.checkIn)) {
      const sleepScore = sleepMinutes === null
        ? 3
        : sleepMinutes < spec.sleep.minutes - 70
        ? 2
        : sleepMinutes > spec.sleep.minutes + 30
        ? 4
        : 3;
      checkIns.push({
        local_date: date,
        sleep_quality: sleepScore,
        energy: sleepScore === 2 ? 2 : 3 + (random() < 0.4 ? 1 : 0),
        soreness: 2 + Math.floor(random() * 2),
        hunger: 3,
        mood: 3 + (random() < 0.5 ? 1 : 0),
        pain_severity: 0,
        available_to_train: true,
        note: null,
        ...event?.checkIn,
      });
    }

    if (date < spec.today && !isAway(spec, date)) {
      const plan = planOn(spec, date);
      const session = plan.week.find((item) => item.weekday === weekdayOf(date));
      if (session) {
        planned++;
        const missed = event?.skipSession === true ||
          (spec.missEvery > 0 && planned % spec.missEvery === 0 && !event?.session);
        if (!missed) {
          const exercises = session.lifts.map((lift): ExerciseLog => {
            const index = liftIndex.get(lift.slug) ?? 0;
            liftIndex.set(lift.slug, index + 1);
            const { kg, stuck } = loadOn(lift, plan.progressFrom ?? spec.start, date);
            return {
              name: lift.name,
              slug: lift.slug,
              planned: { sets: lift.sets, rep_min: lift.repMin, rep_max: lift.repMax },
              sets: event?.session?.sets?.[lift.slug] ?? patternSets(lift, kg, stuck, index),
              pain: event?.session?.pain?.includes(lift.slug) ?? false,
            };
          });
          sessions.push({
            local_date: date,
            planned_workout_id: session.id,
            workout: session.name,
            minutes: event?.session?.minutes ?? session.minutes + Math.round((random() - 0.5) * 10),
            effort: event?.session?.effort ?? 7 + (random() < 0.3 ? 1 : 0),
            energy: event?.session?.energy ?? 3 + (random() < 0.5 ? 1 : 0),
            exercises,
          });
        }
      }
    }

    if (date >= spec.nutrition.since && date < spec.today) {
      const roll = random();
      const logged = event?.meals ??
        (roll < spec.nutrition.complete
          ? "complete"
          : roll < spec.nutrition.complete + spec.nutrition.partial
          ? "partial"
          : "none");
      if (logged !== "none") {
        const types: MealType[] = logged === "complete"
          ? ["breakfast", "lunch", "dinner", ...(random() < 0.6 ? ["snack" as const] : [])]
          : [random() < 0.5 ? "breakfast" : "lunch"];
        const dayMeals = types.map((type): MealLog => {
          const options = spec.nutrition.menu[type];
          return {
            local_date: date,
            meal_type: type,
            source: random() < 0.6 ? "photo_analysis" : "typed",
            foods: options[Math.floor(random() * options.length)],
          };
        });
        meals.push(...dayMeals);
        const calories = dayMeals.flatMap((m) => m.foods).reduce((sum, f) => sum + f.calories, 0);
        const protein = dayMeals.flatMap((m) => m.foods).reduce((sum, f) => sum + f.protein, 0);
        const target = targetOn(spec, date);
        mealDays.push({
          local_date: date,
          meals: dayMeals.length,
          calories,
          protein_g: protein,
          // Carbohydrate and fat follow the target's split of the energy left after protein.
          carbohydrate_g: Math.round(
            ((calories - protein * 4) * (target.carbs * 4)) / (target.carbs * 4 + target.fat * 9) /
              4,
          ),
          fat_g: Math.round(
            ((calories - protein * 4) * (target.fat * 9)) / (target.carbs * 4 + target.fat * 9) / 9,
          ),
          complete: dayMeals.length >= 3 || calories >= target.calories * 0.7,
        });
      }
    }
  }

  const knots = spec.weight;
  const weightOn = (date: string): number => {
    const after = knots.findIndex(([day]) => day >= date);
    if (after <= 0) return after === 0 ? knots[0][1] : knots[knots.length - 1][1];
    const [d0, k0] = knots[after - 1];
    const [d1, k1] = knots[after];
    return k0 + (k1 - k0) * (daysBetween(d0, date) / daysBetween(d0, d1));
  };
  const weights: Weighing[] = days.filter((date) => spec.weighInDays.includes(weekdayOf(date)))
    .map((date) => ({
      date,
      kg: tenth(weightOn(date) + (random() - 0.5) * 0.8),
      source: random() < 0.7 ? "manual" : "healthkit",
    }));
  const months = days.filter((date) => date.endsWith("-01"));
  const waist = months.map((date) => ({
    date,
    waist_cm: tenth(
      spec.waist[0] +
        (spec.waist[1] - spec.waist[0]) * (daysBetween(spec.start, date) /
            daysBetween(spec.start, spec.today)),
    ),
  }));
  return { spec, sessions, meals, mealDays, checkIns, recovery, weights, waist };
}

// ---- figures --------------------------------------------------------------------------------

export const e1rm = (kg: number, reps: number) => tenth(kg * (1 + reps / 30));

const sessionSets = (session: SessionLog) =>
  session.exercises.reduce((sum, exercise) => sum + exercise.sets.length, 0);

const sessionVolume = (session: SessionLog) =>
  Math.round(
    session.exercises.flatMap((e) => e.sets).reduce(
      (sum, set) => sum + set.reps * (set.load_kg ?? 0),
      0,
    ),
  );

const avgRir = (session: SessionLog) => {
  const rirs = session.exercises.flatMap((e) => e.sets).map((s) => s.rir).filter((r) =>
    r !== null
  ) as number[];
  return rirs.length ? rirs.reduce((a, b) => a + b, 0) / rirs.length : 2;
};

const within = <T extends { local_date: string }>(rows: readonly T[], from: string, to: string) =>
  rows.filter((row) => row.local_date >= from && row.local_date <= to);

const newestFirst = <T extends { local_date: string }>(rows: readonly T[]) =>
  [...rows].sort((a, b) => b.local_date.localeCompare(a.local_date));

const mean = (values: readonly number[]) =>
  values.length === 0 ? null : tenth(values.reduce((a, b) => a + b, 0) / values.length);

// ---- lookup payloads ------------------------------------------------------------------------

const payload = (lookup: string, from: string, to: string, truncated: boolean) => ({
  schema_version: "1.0",
  lookup,
  from,
  to,
  truncated,
});

const matches = (filter: string | null, ...names: string[]) =>
  filter === null ||
  names.some((name) =>
    name.toLowerCase().includes(filter.toLowerCase().replace(/-/g, " ")) ||
    name.toLowerCase().includes(filter.toLowerCase())
  );

/** The progression target Tracend's rules would give a lift after its newest session. */
export function nextTarget(records: Records, slug: string): Record<string, unknown> | null {
  const plan = planOn(records.spec, records.spec.today);
  const lift = plan.week.flatMap((s) => s.lifts).find((item) => item.slug === slug);
  const done = records.sessions.filter((s) => s.exercises.some((e) => e.slug === slug));
  const last = done.at(-1)?.exercises.find((e) => e.slug === slug);
  if (!lift || !last || last.sets.length === 0) return null;
  const top = last.sets[0];
  const minReps = Math.min(...last.sets.map((s) => s.reps));
  const stalled = lift.plateau !== undefined && records.spec.today >= lift.plateau.from;
  const atTop = minReps >= lift.repMax;
  const action = stalled ? "hold" : atTop ? "add_load" : "add_reps";
  return {
    planned_exercise_id: `pe-${slug}`,
    exercise_key: slug,
    name: lift.name,
    action,
    reason: stalled ? "stall" : atTop ? "top_of_range" : "within_range",
    load_kg: top.load_kg === null ? null : atTop && !stalled ? top.load_kg + 2.5 : top.load_kg,
    reps: atTop || stalled ? lift.repMin : minReps + 1,
    sets: lift.sets,
    confidence: "high",
    basis: {
      last_date: done.at(-1)!.local_date,
      // Newest first, as the progression summary lists them.
      recent: done.slice(-3).reverse().map((session) => {
        const exercise = session.exercises.find((e) => e.slug === slug)!;
        return {
          local_date: session.local_date,
          load_kg: exercise.sets[0].load_kg,
          sets: exercise.sets.length,
          min_reps: Math.min(...exercise.sets.map((s) => s.reps)),
          total_reps: exercise.sets.reduce((sum, s) => sum + s.reps, 0),
          min_rir: Math.min(...exercise.sets.map((s) => s.rir ?? 2)),
          effort_known: true,
          pain: exercise.pain,
        };
      }),
    },
  };
}

function workoutsPayload(records: Records, from: string, to: string, filter: string | null) {
  const inRange = newestFirst(within(records.sessions, from, to)).map((session) => ({
    session,
    exercises: session.exercises.filter((e) => matches(filter, e.name, e.slug)),
  })).filter((item) => filter === null || item.exercises.length > 0);
  return {
    ...payload("workouts", from, to, inRange.length > 15),
    sessions: inRange.slice(0, 15).map(({ session, exercises }) => ({
      local_date: session.local_date,
      workout: session.workout,
      minutes: session.minutes,
      effort: session.effort,
      energy: session.energy,
      exercises: exercises.map((exercise) => ({
        name: exercise.name,
        status: "performed",
        pain: exercise.pain,
        planned: exercise.planned,
        sets: exercise.sets.map((set) => ({ ...set, rpe: null, done: true })),
      })),
    })),
  };
}

function exerciseHistoryPayload(records: Records, from: string, to: string, filter: string) {
  const rows = within(records.sessions, from, to).flatMap((session) =>
    session.exercises.filter((e) => matches(filter, e.name, e.slug)).map((exercise) => {
      const top = [...exercise.sets].sort((a, b) =>
        (b.load_kg ?? 0) - (a.load_kg ?? 0) || b.reps - a.reps
      )[0];
      return {
        local_date: session.local_date,
        name: exercise.name,
        slug: exercise.slug,
        top_load_kg: top?.load_kg ?? null,
        top_reps: top?.reps ?? null,
        sets: exercise.sets.length,
        e1rm_kg: top?.load_kg ? e1rm(top.load_kg, top.reps) : null,
        min_rir: Math.min(...exercise.sets.map((s) =>
          s.rir ?? 2
        )),
      };
    })
  );
  const plan = planOn(records.spec, records.spec.today);
  const lifts = plan.week.flatMap((s) => s.lifts).filter((l) => matches(filter, l.name, l.slug));
  const slugs = [...new Set(rows.map((row) => row.slug))];
  return {
    ...payload("exercise_history", from, to, rows.length > 40),
    sessions: rows.slice(-40).map(({ slug: _slug, ...row }) => row),
    planned: lifts.map((lift) => ({
      name: lift.name,
      sets: lift.sets,
      rep_min: lift.repMin,
      rep_max: lift.repMax,
      rest_seconds: lift.restSeconds,
    })),
    next_targets: slugs.map((slug) => nextTarget(records, slug)).filter(Boolean),
  };
}

function mealsPayload(records: Records, from: string, to: string, filter: string | null) {
  const days = newestFirst(within(records.mealDays, from, to));
  const meals = newestFirst(within(records.meals, from, to)).filter((meal) =>
    matches(filter, meal.meal_type, ...meal.foods.map((f) => f.name))
  );
  const target = targetOn(records.spec, to);
  return {
    ...payload("meals", from, to, days.length > 60 || meals.length > 30),
    target_kcal: target.calories,
    rules: { min_meals: 3, min_target_share: 0.7 },
    days: days.slice(0, 60),
    meals: meals.slice(0, 30).map((meal) => ({
      local_date: meal.local_date,
      meal_type: meal.meal_type,
      source: meal.source,
      from_schedule: false,
      foods: meal.foods.map((food) => ({
        name: food.name,
        calories: food.calories,
        protein_g: food.protein,
      })),
    })),
  };
}

function bodyPayload(records: Records, from: string, to: string) {
  const weights = records.weights.filter((w) => w.date >= from && w.date <= to).reverse();
  const tape = records.waist.filter((w) => w.date >= from && w.date <= to).reverse();
  return {
    ...payload("body", from, to, weights.length > 90),
    weights: weights.slice(0, 90),
    measurements: tape.slice(0, 30).map((row) => ({
      date: row.date,
      waist_cm: row.waist_cm,
      chest_cm: null,
      hip_cm: null,
      arm_cm: null,
      thigh_cm: null,
    })),
  };
}

function weeklyReviewsPayload(records: Records, from: string, to: string) {
  const mondays = datesFrom(from, to).filter((date) =>
    weekdayOf(date) === 1 && addDays(date, 6) < records.spec.today
  );
  const reviews = mondays.reverse().slice(0, 12).map((monday) => {
    const sunday = addDays(monday, 6);
    const done = within(records.sessions, monday, sunday);
    const plannedCount = isAway(records.spec, monday)
      ? 0
      : planOn(records.spec, monday).week.length;
    const adherence = plannedCount === 0 ? 0 : Math.round((done.length / plannedCount) * 100);
    return {
      review_week: monday,
      outcome_code: adherence >= 75 ? "on_track" : "missed_sessions",
      training: {
        completed_workouts: done.length,
        planned_sessions: plannedCount,
        adherence_percent: adherence,
        completed_sets: done.reduce((sum, s) => sum + sessionSets(s), 0),
      },
      recovery: { check_in_days: within(records.checkIns, monday, sunday).length },
      nutrition: {
        confirmed_days: within(records.mealDays, monday, sunday).filter((d) => d.complete).length,
      },
      next_focus_code: adherence >= 75 ? "progression" : "consistency",
    };
  });
  return { ...payload("weekly_reviews", from, to, false), reviews };
}

function planHistoryPayload(records: Records, from: string, to: string) {
  const { spec } = records;
  const training = [...spec.plans].map((plan, index) => ({ plan, version: index + 1 }))
    .filter(({ plan }) => plan.from <= to).reverse().slice(0, 6).map(({ plan, version }) => ({
      version,
      status: plan === planOn(spec, spec.today) ? "active" : "superseded",
      created_on: addDays(plan.from, -1),
      effective_date: plan.from,
      title: plan.title,
      sessions_per_week: plan.week.length,
      block_weeks: plan.blockWeeks,
      rationale: plan.rationale,
      sessions: plan.week.map((session) => ({
        weekday: session.weekday,
        name: session.name,
        exercises: session.lifts.map((lift) => ({
          name: lift.name,
          sets: lift.sets,
          rep_min: lift.repMin,
          rep_max: lift.repMax,
        })),
      })),
    }));
  const nutrition = spec.nutrition.targets.map((target, index) => ({ target, version: index + 1 }))
    .filter(({ target }) => target.from <= to).reverse().slice(0, 12).map((
      { target, version },
    ) => ({
      version,
      status: target === targetOn(spec, spec.today) ? "active" : "superseded",
      created_on: addDays(target.from, -1),
      effective_date: target.from,
      calories: target.calories,
      protein_g: target.protein,
      carbohydrate_g: target.carbs,
      fat_g: target.fat,
      rationale: target.rationale,
    }));
  return { ...payload("plan_history", from, to, false), training, nutrition };
}

/** What the persona adds beyond its records: goals, health checks, months imported at onboarding. */
export type RecordsExtras = Readonly<{
  goals: readonly Readonly<Record<string, unknown>>[];
  screenings: readonly Readonly<{ screened_on: string; outcome: string }>[];
  healthHistory: readonly Readonly<Record<string, unknown>>[];
}>;

/**
 * A stand-in for the lookup RPCs over the records, answering in their payload shapes: the
 * production runner (createLookupRunner) calls it and renders the rows as it does in coach-chat.
 */
export function recordsRpc(records: Records, extras: RecordsExtras): LookupRpc {
  return (name, params) => {
    const { p_from: from, p_to: to, p_filter: filter } = params;
    const data = (() => {
      switch (name) {
        case "coach_lookup_workouts_v1":
          return workoutsPayload(records, from, to, filter);
        case "coach_lookup_exercise_history_v1":
          return exerciseHistoryPayload(records, from, to, filter ?? "");
        case "coach_lookup_meals_v1":
          return mealsPayload(records, from, to, filter);
        case "coach_lookup_body_v1":
          return bodyPayload(records, from, to);
        case "coach_lookup_check_ins_v1":
          return {
            ...payload("check_ins", from, to, false),
            check_ins: newestFirst(within(records.checkIns, from, to)).slice(0, 60),
          };
        case "coach_lookup_recovery_v1":
          return {
            ...payload("recovery", from, to, false),
            days: newestFirst(within(records.recovery, from, to)).slice(0, 60).map((day) => ({
              ...day,
              acwr: null,
            })),
          };
        case "coach_lookup_plan_history_v1":
          return planHistoryPayload(records, from, to);
        case "coach_lookup_goals_v1":
          return {
            ...payload("goals", from, to, false),
            goals: extras.goals,
            screenings: extras.screenings.filter((s) => s.screened_on <= to),
          };
        case "coach_lookup_weekly_reviews_v1":
          return weeklyReviewsPayload(records, from, to);
        case "coach_lookup_health_history_v1":
          return {
            ...payload("health_history", from, to, false),
            months: extras.healthHistory.filter((m) =>
              String(m.month) >= from.slice(0, 7) && String(m.month) <= to
            ),
          };
        case "coach_lookup_past_messages_v1":
          return { ...payload("past_messages", from, to, false), messages: [] };
        default:
          return null;
      }
    })();
    return Promise.resolve(
      data === null ? { data: null, error: { message: "unknown lookup" } } : { data, error: null },
    );
  };
}

// ---- contributor payloads -------------------------------------------------------------------

/** get_coach_plan_state_v1: the active plan, this week's finished sessions and the next targets. */
export function planStatePayload(
  records: Records,
  equipment: readonly string[],
): Record<string, unknown> {
  const { spec } = records;
  const plan = planOn(spec, spec.today);
  const version = spec.plans.indexOf(plan) + 1;
  const monday = addDays(spec.today, 1 - weekdayOf(spec.today));
  return {
    schema_version: "1.0",
    local_date: spec.today,
    weekday: weekdayOf(spec.today),
    equipment,
    avoid_patterns: [],
    plan: { title: plan.title, version_number: version, sessions_per_week: plan.week.length },
    sessions: plan.week.map((session, index) => ({
      planned_workout_id: session.id,
      order: index + 1,
      name: session.name,
      weekday: session.weekday,
      minutes: session.minutes,
      exercises: session.lifts.map((lift, order) => ({
        planned_exercise_id: `pe-${lift.slug}`,
        order: order + 1,
        name: lift.name,
        slug: lift.slug,
        sets: lift.sets,
        rep_min: lift.repMin,
        rep_max: lift.repMax,
        rest_seconds: lift.restSeconds,
        target_rpe: lift.targetRpe,
        load_kg: loadOn(lift, plan.progressFrom ?? spec.start, spec.today).kg,
      })),
    })),
    completed_this_week: within(records.sessions, monday, spec.today).map((session) => {
      const planned = plan.week.find((item) => item.id === session.planned_workout_id);
      return {
        planned_workout_id: session.planned_workout_id,
        local_date: session.local_date,
        name: session.workout,
        weekday: weekdayOf(session.local_date),
        order: planned ? plan.week.indexOf(planned) + 1 : null,
      };
    }),
    progression: {
      schema_version: "1.0",
      targets: plan.week.flatMap((s) => s.lifts).map((lift) => nextTarget(records, lift.slug))
        .filter(Boolean),
    },
  };
}

/**
 * get_coach_nutrition_state_v1: the last 7 days with complete-day flags and partial days kept
 * apart (`nutrition_day_totals(today - 6, today)`), and the 14 days of meals the sources count.
 */
export function nutritionStatePayload(records: Records): Record<string, unknown> {
  const { spec } = records;
  const target = targetOn(spec, spec.today);
  const from = addDays(spec.today, -13);
  const days = newestFirst(within(records.mealDays, addDays(spec.today, -6), spec.today));
  const meals = within(records.meals, from, spec.today);
  return {
    schema_version: "1.0",
    local_date: spec.today,
    target: {
      calories: target.calories,
      protein_g: target.protein,
      carbohydrate_g: target.carbs,
      fat_g: target.fat,
    },
    rules: { min_meals: 3, min_target_share: 0.7 },
    days,
    schedule: [],
    eaten_today: [],
    sources: {
      window_days: 14,
      meals: meals.length,
      photo_estimate: meals.filter((m) => m.source === "photo_analysis").length,
      from_schedule: 0,
      typed_in: meals.filter((m) => m.source === "typed").length,
    },
  };
}

/** get_goal_phase_inputs_v1 over the whole weight history. */
export function goalPhasePayload(
  records: Records,
  goal: Readonly<{ goalType: string; activatedOn: string; heightCm: number }>,
  target: Readonly<Record<string, unknown>> = {},
): Record<string, unknown> {
  return {
    schema_version: "1.0",
    height_cm: goal.heightCm,
    goal: {
      goal_type: goal.goalType,
      activated_on: goal.activatedOn,
      target: {
        weight_kg: null,
        body_fat_pct_min: null,
        body_fat_pct_max: null,
        physique: null,
        physique_note: null,
        date: null,
        ...target,
      },
    },
    readings: records.weights.map((w) => ({ date: w.date, kg: w.kg })),
  };
}

/**
 * get_coach_data_index_v1 (1.2): per kind of record, the first and last date and a count, and the
 * active plan's repeating weekdays. The personas keep no watch workouts, proposals, decisions or
 * earlier threads.
 */
export function dataIndexPayload(records: Records, extras: RecordsExtras): Record<string, unknown> {
  const span = (dates: readonly string[]) =>
    dates.length === 0
      ? { count: 0, first: null, last: null }
      : { count: dates.length, first: dates[0], last: dates[dates.length - 1] };
  const sorted = (dates: string[]) => [...dates].sort();
  const plan = planOn(records.spec, records.spec.today);
  const none = span([]);
  return {
    schema_version: "1.2",
    local_date: records.spec.today,
    domains: {
      workouts: span(records.sessions.map((s) => s.local_date)),
      meals: span(records.mealDays.map((d) => d.local_date)),
      body: span(
        sorted([...records.weights.map((w) => w.date), ...records.waist.map((w) => w.date)]),
      ),
      check_ins: span(records.checkIns.map((c) => c.local_date)),
      recovery: span(records.recovery.map((r) => r.local_date)),
      plan_history: span(records.spec.plans.map((p) => p.from)),
      goals: span(sorted(extras.goals.map((g) => String(g.created_on)))),
      weekly_reviews: span(
        datesFrom(records.spec.start, addDays(records.spec.today, -7)).filter((d) =>
          weekdayOf(d) === 1
        ),
      ),
      health_history: span(extras.healthHistory.map((m) => `${String(m.month)}-01`)),
      watch_workouts: none,
      proposals: none,
      daily_decisions: none,
      past_messages: none,
    },
    schedule: {
      version: records.spec.plans.indexOf(plan) + 1,
      starts_on: plan.from,
      weekdays: [...new Set(plan.week.map((session) => session.weekday))].sort(),
    },
  };
}

// ---- the athlete file -----------------------------------------------------------------------

export type ProfileFacts = Readonly<{
  sex: "male" | "female";
  age: number;
  heightCm: number;
  experience: "beginner" | "intermediate" | "advanced";
  trainingYears: "under_1" | "1_2" | "3_5" | "over_5";
  sessionMinutes: number;
  equipment: readonly string[];
  nutritionNotes: string;
  limitations: string | null;
  goal: Readonly<{ goalType: string; description: string; activatedOn: string }>;
}>;

/**
 * The athlete file in prepare_coach_chat_v8's shape, every figure taken from the records: the
 * last 28 days of sessions and watch data, eight weeks of weigh-ins, two weeks of check-ins. Every
 * window is the SQL's: `coaching_date - (days - 1)` through the coaching date, today included
 * (build_coach_athlete_context, migration 20260927230000).
 */
export function athleteFile(records: Records, profile: ProfileFacts): Record<string, unknown> {
  const { spec } = records;
  const today = spec.today;
  const plan = planOn(spec, today);
  const target = targetOn(spec, today);
  const since = (days: number) => addDays(today, -(days - 1));
  const last28 = newestFirst(within(records.sessions, since(28), today));
  const health = newestFirst(within(records.recovery, since(28), today));
  const weights = records.weights.filter((w) => w.date >= since(56) && w.date <= today).reverse();
  const checkIns = newestFirst(within(records.checkIns, since(14), today));
  const latestCheckIn = checkIns.find((c) => c.local_date === today) ?? null;
  const window = (days: number) => {
    const inside = last28.filter((s) => s.local_date >= since(days));
    return {
      days,
      sessions: inside.length,
      total_minutes: inside.reduce((sum, s) => sum + s.minutes, 0),
      completed_sets: inside.reduce((sum, s) => sum + sessionSets(s), 0),
      volume_kg: inside.reduce((sum, s) => sum + sessionVolume(s), 0),
    };
  };
  const measured = (
    days: number,
    key: "sleep_minutes" | "resting_heart_rate_bpm" | "hrv_ms" | "steps",
  ) =>
    health.filter((d) => d.local_date >= since(days)).map((d) => d[key]).filter((v): v is number =>
      v !== null
    );
  const averages = (days: number) => ({
    days_synced: health.filter((d) => d.local_date >= since(days)).length,
    days_with_sleep: measured(days, "sleep_minutes").length,
    avg_sleep_minutes: mean(measured(days, "sleep_minutes")),
    days_with_resting_heart_rate: measured(days, "resting_heart_rate_bpm").length,
    avg_resting_heart_rate_bpm: mean(measured(days, "resting_heart_rate_bpm")),
    days_with_hrv: measured(days, "hrv_ms").length,
    avg_hrv_ms: mean(measured(days, "hrv_ms")),
    days_with_steps: measured(days, "steps").length,
    avg_steps: mean(measured(days, "steps")),
  });
  const trend = (days: number) => {
    const recent = records.weights.filter((w) => w.date >= addDays(today, -days));
    if (recent.length < 2) return null;
    const first = recent[0];
    const last = recent[recent.length - 1];
    return Math.round(
      ((last.kg - first.kg) / Math.max(1, daysBetween(first.date, last.date))) * 100,
    ) /
      100;
  };
  const acute = window(7).volume_kg;
  const chronic = window(28).volume_kg / 4;
  const todayHealth = health.find((d) => d.local_date === today);
  const mealDays7 = within(records.mealDays, since(7), today);
  const permitted = ["APPROVED_PLAN_ACTIVE", "HEALTH_CONTEXT_AVAILABLE"];
  if ((todayHealth?.recovery_score ?? 60) < 45) permitted.push("RECOVERY_BELOW_BASELINE");
  if ((todayHealth?.sleep_quality ?? 70) < 55) permitted.push("SLEEP_QUALITY_LOW");
  if (chronic > 0 && acute / chronic > 1.3) permitted.push("TRAINING_LOAD_ELEVATED");
  return {
    schema_version: "8.1",
    coaching_date: today,
    context_kind: "general",
    active_plan: {
      title: plan.title,
      version_number: spec.plans.indexOf(plan) + 1,
      sessions_per_week: plan.week.length,
      rationale: plan.rationale,
    },
    active_goal: {
      goal_type: profile.goal.goalType,
      priority: 1,
      details: { description: profile.goal.description },
    },
    profile_context: {
      experience_level: profile.experience,
      training_years: profile.trainingYears,
      height_cm: profile.heightCm,
      training_days: plan.week.length,
      session_minutes: profile.sessionMinutes,
      sex: profile.sex,
      age: profile.age,
      equipment: profile.equipment,
      nutrition_notes: profile.nutritionNotes,
      ...(profile.limitations ? { limitations: profile.limitations } : {}),
    },
    nutrition_targets: {
      calories: target.calories,
      protein_g: target.protein,
      carbohydrate_g: target.carbs,
      fat_g: target.fat,
    },
    nutrition_schedule: [
      { slot_key: "breakfast", label: "Breakfast", local_time: "08:00" },
      { slot_key: "lunch", label: "Lunch", local_time: "13:30" },
      { slot_key: "dinner", label: "Dinner", local_time: "20:30" },
    ],
    training_week_structure: {
      sessions_per_week: plan.week.length,
      block_weeks: plan.blockWeeks,
      planned_workouts: plan.week.map((s) => ({ name: s.name, target_day: s.weekday })),
    },
    permitted_evidence: permitted,
    missing_data: [],
    computed_metrics: {
      local_date: today,
      recovery: { score: todayHealth?.recovery_score ?? null },
      sleep: {
        quality: todayHealth?.sleep_quality ?? null,
        debt_minutes: Math.max(
          0,
          Math.round(
            measured(7, "sleep_minutes").reduce((sum, m) => sum + (spec.sleep.minutes - m), 0),
          ),
        ),
      },
      training_load: {
        acwr: chronic > 0 ? Math.round((acute / chronic) * 100) / 100 : null,
        monotony: null,
      },
      weight: { trend_7d_kg_per_day: trend(7), trend_28d_kg_per_day: trend(28) },
      nutrition: { adherence_pct: null },
      data_confidence: "high",
    },
    latest_check_in: latestCheckIn,
    check_ins_14d: checkIns,
    training_totals: {
      last_7_days: window(7),
      last_14_days: window(14),
      last_28_days: window(28),
    },
    training_log_28d: last28.map((session) => ({
      local_date: session.local_date,
      workout: session.workout,
      duration_minutes: session.minutes,
      effort: session.effort,
      energy: session.energy,
      completed_sets: sessionSets(session),
      volume_kg: sessionVolume(session),
      avg_rpe: tenth(10 - avgRir(session)),
      logging_completeness: 1,
    })),
    watch_workouts_14d: [],
    health_daily_28d: health.map((day) => ({
      local_date: day.local_date,
      sleep_minutes: day.sleep_minutes,
      resting_heart_rate_bpm: day.resting_heart_rate_bpm,
      hrv_ms: day.hrv_ms,
      steps: day.steps,
      active_energy_kcal: Math.round(day.steps * 0.045),
      workout_minutes: last28.find((s) => s.local_date === day.local_date)?.minutes ?? 0,
      weight_kg: null,
      completeness: "complete",
    })),
    health_averages: { last_7_days: averages(7), last_28_days: averages(28) },
    weight_series_8w: weights.map((w) => ({
      measured_on: w.date,
      weight_kg: w.kg,
      waist_cm: records.waist.find((row) => row.date === w.date)?.waist_cm ?? null,
      source: w.source,
    })),
    nutrition_daily_28d: [],
    nutrition_adherence: {
      days_with_confirmed_meals_7d: mealDays7.length,
      confirmed_meal_count_7d: mealDays7.reduce((sum, d) => sum + d.meals, 0),
    },
    today_confirmed_meals: [],
    latest_weekly_review: null,
    latest_decision: null,
    active_preferences: [],
    plan_proposals: [],
    workout_reconciliations: [],
    data_quality: {
      training_logging_coverage: 1,
      last_health_sync: `${today}T06:30:00Z`,
      last_check_in: latestCheckIn?.local_date ?? checkIns[0]?.local_date ?? null,
      last_measurement: records.weights.at(-1)?.date ?? null,
      last_completed_workout: records.sessions.at(-1)?.local_date ?? null,
      conflict_count: 0,
    },
    recent_messages: [],
    recent_other_conversations: [],
    session_journal: [],
    omitted_sections: [],
  };
}

/**
 * The active plan as the proposal builder reads it (`AthleteState.plan`), from the same weeks and
 * loads the plan-state payload shows the Coach. Grading a proposal against the persona's own plan
 * (and not the fixture athlete's) is what the service does with the athlete's.
 */
export function statePlanOf(records: Records): StatePlan {
  const { spec } = records;
  const plan = planOn(spec, spec.today);
  return {
    versionId: "11111111-1111-4111-8111-111111111111",
    planId: "22222222-2222-4222-8222-222222222222",
    versionNumber: spec.plans.indexOf(plan) + 1,
    title: plan.title,
    blockWeeks: plan.blockWeeks,
    workouts: plan.week.map((session) => ({
      name: session.name,
      objective: "",
      weekday: session.weekday,
      estimatedMinutes: session.minutes,
      warmUp: "",
      coolDown: "",
      exercises: session.lifts.map((lift) => ({
        plannedExerciseId: `pe-${lift.slug}`,
        slug: lift.slug,
        name: lift.name,
        sets: lift.sets,
        repMin: lift.repMin,
        repMax: lift.repMax,
        targetRpe: lift.targetRpe,
        restSeconds: lift.restSeconds,
        notes: "",
        targetLoadKg: loadOn(lift, plan.progressFrom ?? spec.start, spec.today).kg,
      })),
    })),
    blockEndsOn: null,
    blockKind: null,
  };
}

/** The proposal fixture athlete with this persona's plan, weekdays and session length. */
export function proposalStateOf(
  records: Records,
  base: AthleteState,
  profile: Readonly<{ sessionMinutes: number }>,
): AthleteState {
  const plan = statePlanOf(records);
  return {
    ...base,
    plan,
    profile: {
      ...base.profile,
      trainingWeekdays: plan.workouts.flatMap((w) => w.weekday === null ? [] : [w.weekday]),
      sessionMinutes: profile.sessionMinutes,
    },
  };
}
