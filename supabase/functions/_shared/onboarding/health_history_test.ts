import { assertEquals } from "jsr:@std/assert@1.0.14";
import { stableJson } from "./snapshot.ts";
import {
  daysInMonth,
  type HealthMonth,
  historyWindow,
  monthStart,
  returningFromBreak,
  summarizeHealthHistory,
} from "./health_history.ts";
import type { HealthSummary } from "./health_summary.ts";

const today = "2026-10-03";

/** A month `back` months before today's, with the given values. */
const month = (back: number, values: Partial<HealthMonth> = {}): HealthMonth => ({
  month: monthStart(today, back),
  workouts: 0,
  strength_workouts: 0,
  workout_minutes: 0,
  sleep_nights: 0,
  sleep_minutes_avg: null,
  weight_days: 0,
  weight_kg_avg: null,
  data_days: 25,
  ...values,
});

const recent = (strength?: number): HealthSummary => ({
  window_days: 28,
  days_with_data: 26,
  ...(strength === undefined
    ? {}
    : { workouts_per_week: strength, strength_workouts_per_week: strength }),
});

Deno.test("the window is the 11 completed months; the month in progress never counts", () => {
  assertEquals(historyWindow(today), { from: "2025-11-01", through: "2026-09-01" });
  assertEquals(monthStart("2026-01-15", 1), "2025-12-01");
  assertEquals(daysInMonth("2026-02-01"), 28);
  assertEquals(daysInMonth("2024-02-01"), 29);
  const history = summarizeHealthHistory(
    [month(0, { strength_workouts: 30, workouts: 30 }), month(12), month(1)],
    today,
  )!;
  assertEquals(history.months, 1);
  assertEquals(history.first_month, "2026-09-01");
});

Deno.test("usual strength is the median from the first month with a workout", () => {
  const rows = [
    // Before the watch: no workouts, which proves nothing.
    month(11),
    month(10),
    month(9, { workouts: 16, strength_workouts: 16 }),
    month(8, { workouts: 17, strength_workouts: 13 }),
    // A real month off, after workouts were readable.
    month(7, { workouts: 0, strength_workouts: 0 }),
    month(6, { workouts: 15, strength_workouts: 15 }),
  ];
  const history = summarizeHealthHistory(rows, today)!;
  assertEquals(history.strength_months, 4);
  // Per week: January 16/4.43, February 13/4, March 0, April 15/4.29
  // -> median of 0, 3.25, 3.5, 3.61 = 3.4.
  assertEquals(history.usual_strength_per_week, 3.4);
  // Two months with workouts are not enough to call anything usual.
  const short = summarizeHealthHistory([
    month(2, { workouts: 12, strength_workouts: 12 }),
    month(1, { workouts: 12, strength_workouts: 12 }),
  ], today)!;
  assertEquals(short.usual_strength_per_week, undefined);
  // A year without workouts: none found, no usual value.
  assertEquals(
    summarizeHealthHistory([month(3), month(2), month(1)], today)!.strength_months,
    undefined,
  );
});

Deno.test("sleep and weight count only covered months", () => {
  const rows = [
    month(4, { sleep_nights: 28, sleep_minutes_avg: 420, weight_days: 5, weight_kg_avg: 82 }),
    month(3, { sleep_nights: 19, sleep_minutes_avg: 300, weight_days: 3, weight_kg_avg: 90 }),
    month(2, { sleep_nights: 25, sleep_minutes_avg: 400, weight_days: 4, weight_kg_avg: 81 }),
    month(1, { sleep_nights: 30, sleep_minutes_avg: 410, weight_days: 8, weight_kg_avg: 80.2 }),
  ];
  const history = summarizeHealthHistory(rows, today)!;
  assertEquals(history.usual_sleep_minutes, 410);
  assertEquals(history.sleep_months, 3);
  assertEquals(history.weight_change_kg, -1.8);
  assertEquals(history.weight_months, 3);
  assertEquals(summarizeHealthHistory([], today), null);
  assertEquals(summarizeHealthHistory([month(1, { data_days: 0 })], today), null);
});

Deno.test("returning from a break: far below a real usual, never from a low usual", () => {
  const usual = summarizeHealthHistory(
    [3, 2, 1].map((back) => month(back, { workouts: 17, strength_workouts: 17 })),
    today,
  )!;
  // July and August 17/4.43, September 17/4.29: median 3.84.
  assertEquals(usual.usual_strength_per_week, 3.8);
  assertEquals(returningFromBreak(usual, recent(1)), true);
  // No strength workout lately counts as none: the history proves access.
  assertEquals(returningFromBreak(usual, recent()), true);
  assertEquals(returningFromBreak(usual, null), true);
  assertEquals(returningFromBreak(usual, recent(2)), false);
  const light = summarizeHealthHistory(
    [3, 2, 1].map((back) => month(back, { workouts: 6, strength_workouts: 6 })),
    today,
  )!;
  assertEquals(returningFromBreak(light, recent(0)), false);
  assertEquals(returningFromBreak(null, recent(0)), false);
});

Deno.test("the history is rounded and order-free, so the same months hash the same", () => {
  const rows = [3, 2, 1].map((back) =>
    month(back, {
      workouts: 13,
      strength_workouts: 11,
      sleep_nights: 29,
      sleep_minutes_avg: 401.4,
      weight_days: 6,
      weight_kg_avg: 80.04 + back,
    })
  );
  assertEquals(
    stableJson(summarizeHealthHistory(rows, today)),
    stableJson(summarizeHealthHistory([...rows].reverse(), today)),
  );
});
