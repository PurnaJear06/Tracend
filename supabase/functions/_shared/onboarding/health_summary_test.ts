import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { stableJson } from "./snapshot.ts";
import {
  activityFromSteps,
  type HealthDay,
  healthWindow,
  type HealthWorkout,
  localDate,
  shiftDate,
  startsLighter,
  summarizeHealth,
} from "./health_summary.ts";

const today = "2026-10-03";

/** Days before today (1 = yesterday), each with the given values. */
function days(count: number, values: Partial<HealthDay> = {}, firstBack = 1): HealthDay[] {
  return Array.from({ length: count }, (_, index) => ({
    local_date: shiftDate(today, firstBack + index),
    steps: null,
    active_energy_kcal: null,
    sleep_minutes: null,
    weight_kg: null,
    ...values,
  }));
}

const workout = (back: number, type: string, minutes: number): HealthWorkout => ({
  local_date: shiftDate(today, back),
  activity_type: type,
  duration_seconds: minutes * 60,
});

Deno.test("the window is the 28 dates before the athlete's today", () => {
  assertEquals(healthWindow(today), { from: "2026-09-05", through: "2026-10-02" });
});

Deno.test("today's date follows the athlete's time zone across the UTC date change", () => {
  // 20:00 UTC is already 01:30 the next day in India.
  const evening = new Date("2026-10-02T20:00:00Z");
  assertEquals(localDate(evening, "Asia/Kolkata"), "2026-10-03");
  assertEquals(localDate(evening, "UTC"), "2026-10-02");
  assertEquals(localDate(evening, "America/Los_Angeles"), "2026-10-02");
  // An unknown zone reads as UTC instead of failing the plan.
  assertEquals(localDate(evening, "Not/AZone"), "2026-10-02");
});

Deno.test("today's partial row is left out; yesterday's is kept", () => {
  const rows = [
    ...days(6, { steps: 8000 }),
    // Today: a partial day, never averaged.
    {
      local_date: today,
      steps: 500,
      active_energy_kcal: null,
      sleep_minutes: null,
      weight_kg: null,
    },
  ];
  // Six full days: one short of the minimum, so today's row must not count.
  assertEquals(summarizeHealth(rows, [], today)?.steps_per_day, undefined);
  const withYesterday = [...rows, ...days(1, { steps: 8000 }, 7)];
  const summary = summarizeHealth(withYesterday, [], today)!;
  assertEquals(summary.steps_per_day, 8000);
  assertEquals(summary.steps_days, 7);
  // The newest row in the window is yesterday's, and it is counted.
  assert(rows.some((row) => row.local_date === shiftDate(today, 1)));
});

Deno.test("each metric needs enough days behind it", () => {
  const six = summarizeHealth(
    days(6, { steps: 9000, active_energy_kcal: 400, sleep_minutes: 420 }),
    [],
    today,
  )!;
  assertEquals(six.days_with_data, 6);
  assertEquals(six.steps_per_day, undefined);
  assertEquals(six.active_energy_kcal_per_day, undefined);
  assertEquals(six.sleep_minutes_per_night, undefined);

  const seven = summarizeHealth(
    days(7, { steps: 9000, active_energy_kcal: 400, sleep_minutes: 420 }),
    [],
    today,
  )!;
  assertEquals(seven.steps_per_day, 9000);
  assertEquals(seven.active_energy_kcal_per_day, 400);
  assertEquals(seven.sleep_minutes_per_night, 420);
  assertEquals(seven.sleep_nights, 7);
});

Deno.test("rows outside the window and zero values are ignored", () => {
  const summary = summarizeHealth(
    [
      ...days(7, { steps: 6000 }),
      // Zero means not recorded on that day, not a day without steps.
      ...days(3, { steps: 0 }, 8),
      // Older than 28 days.
      ...days(5, { steps: 20000 }, 29),
    ],
    [],
    today,
  )!;
  assertEquals(summary.steps_per_day, 6000);
  assertEquals(summary.steps_days, 7);
});

Deno.test("no workouts found is never reported as no training", () => {
  const summary = summarizeHealth(days(28, { steps: 9000 }), [], today)!;
  assertEquals(summary.workouts_per_week, undefined);
  assertEquals(summary.workout_types, undefined);
  // Steps are there but workouts are not: nothing about training is claimed,
  // so nothing makes the plan lighter.
  assertEquals(startsLighter(summary), false);
});

Deno.test("workouts give a weekly rate, minutes and the commonest types", () => {
  const summary = summarizeHealth(days(10, { steps: 9000 }), [
    workout(2, "TRADITIONAL_STRENGTH_TRAINING", 60),
    workout(5, "TRADITIONAL_STRENGTH_TRAINING", 50),
    workout(9, "RUNNING", 30),
    workout(12, "WALKING", 40),
    workout(15, "RUNNING", 30),
    workout(40, "SWIMMING", 30),
  ], today)!;
  assertEquals(summary.workouts_per_week, 1.3);
  assertEquals(summary.workout_minutes_per_week, 53);
  assertEquals(summary.workout_types, ["running", "traditional strength training", "walking"]);
});

Deno.test("weight: the latest reading, and a trend only with enough readings", () => {
  const few = summarizeHealth(
    [
      ...days(1, { weight_kg: 80.04 }, 1),
      ...days(1, { weight_kg: 80.6 }, 10),
    ],
    [],
    today,
  )!;
  assertEquals(few.weight_latest_kg, 80);
  assertEquals(few.weight_latest_date, "2026-10-02");
  assertEquals(few.weight_trend_kg_per_week, undefined);

  // Losing 0.5 kg a week, weighed every 4 days for 4 weeks.
  const readings = [1, 5, 9, 13, 17, 21, 25].map((back) => ({
    ...days(1, {}, back)[0],
    weight_kg: 80 + back * (0.5 / 7),
  }));
  const losing = summarizeHealth(readings, [], today)!;
  assertEquals(losing.weight_trend_kg_per_week, -0.5);
});

Deno.test("no Apple Health data at all gives no summary", () => {
  assertEquals(summarizeHealth([], [], today), null);
  assertEquals(summarizeHealth(days(5), [], today), null);
});

Deno.test("the summary is rounded and stable, so the same data gives the same hash", () => {
  const rows = days(9, { steps: 8123.6, active_energy_kcal: 411.4, sleep_minutes: 401.5 });
  const first = summarizeHealth(rows, [workout(3, "RUNNING", 31)], today);
  const second = summarizeHealth([...rows].reverse(), [workout(3, "RUNNING", 31)], today);
  assertEquals(stableJson(first), stableJson(second));
  assertEquals(first?.steps_per_day, 8124);
  assertEquals(first?.sleep_minutes_per_night, 402);
  // No key is present with an undefined value (stableJson would break).
  assert(Object.values(first!).every((value) => value !== undefined));
});

Deno.test("steps map to a daily-activity answer, never to physical labour", () => {
  assertEquals(activityFromSteps(4999), "mostly_sitting");
  assertEquals(activityFromSteps(5000), "some_standing");
  assertEquals(activityFromSteps(7499), "some_standing");
  assertEquals(activityFromSteps(7500), "mostly_standing");
  assertEquals(activityFromSteps(30000), "mostly_standing");
});

Deno.test("only short sleep starts the plan lighter", () => {
  const short = summarizeHealth(days(7, { sleep_minutes: 340 }), [], today);
  const enough = summarizeHealth(days(7, { sleep_minutes: 360 }), [], today);
  const tooFew = summarizeHealth(days(6, { sleep_minutes: 300 }), [], today);
  assertEquals(startsLighter(short), true);
  assertEquals(startsLighter(enough), false);
  assertEquals(startsLighter(tooFew), false);
  assertEquals(startsLighter(null), false);
});
