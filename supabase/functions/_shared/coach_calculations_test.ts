import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { calculateCoachNumbers, formatCoachCalculations, roundTo } from "./coach_calculations.ts";
import { formatContextAsMarkdown } from "./providers/coach_chat_provider.ts";
import { evalProfiles } from "../_evals/fixtures.ts";

const date = "2026-09-27";

function daysAgo(days: number): string {
  const d = new Date(`${date}T00:00:00Z`);
  d.setUTCDate(d.getUTCDate() - days);
  return d.toISOString().slice(0, 10);
}

function weights(entries: Array<[number, number]>) {
  return entries.map(([days, kg]) => ({ measured_on: daysAgo(days), weight_kg: kg }));
}

Deno.test("roundTo rounds half away from zero without binary artifacts", () => {
  assertEquals(roundTo(1.005, 2), 1.01);
  assertEquals(roundTo(2.5, 0), 3);
  assertEquals(roundTo(-2.5, 0), -3);
  assertEquals(roundTo(-0.004, 2), 0);
});

Deno.test("no coaching date means no calculations", () => {
  assertEquals(calculateCoachNumbers({ weight_series_8w: weights([[0, 80]]) }), null);
  assertEquals(formatCoachCalculations(null), "");
});

Deno.test("weight trend and projection match the rich eval athlete's reference range", () => {
  const rich = evalProfiles().find((p) => p.id === "rich")!;
  const calc = calculateCoachNumbers(rich.context)!;
  const weight = calc.weight!;
  assertEquals(weight.latest_kg, 78.4);
  assertEquals(weight.latest_date, date);
  // 0.2 kg every 3 days = 0.4667 kg a week, in both windows.
  assertEquals(weight.trends.map((t) => [t.window_days, t.readings, t.kg_per_week]), [
    [28, 10, -0.47],
    [56, 19, -0.47],
  ]);
  const projection = weight.projection!;
  assertEquals(projection.windows, [28, 56]);
  const goal = projection.targets.find((row) => row.target_kg === 72)!;
  // (78.4 - 72) / 0.4667 = 13.7 weeks; the eval accepts 9 to 18.
  assertEquals([goal.weeks_low, goal.weeks_high, goal.goal], [14, 14, true]);
  assertEquals(projection.targets.map((row) => row.target_kg), [
    78,
    77,
    76,
    75,
    74,
    73,
    72,
    71,
    70,
    69,
  ]);
  assertEquals(projection.targets[0].weeks_low, 1);
  assertEquals(projection.horizons[0], { weeks: 4, kg_low: 76.5, kg_high: 76.5 });
});

Deno.test("projection range spans the 4- and 8-week paces when both point the same way", () => {
  const calc = calculateCoachNumbers({
    coaching_date: date,
    // 4 weeks: -0.5 kg/week; the 8-week fit is gentler because of older readings.
    weight_series_8w: weights([
      [0, 80],
      [7, 80.5],
      [14, 81],
      [21, 81.5],
      [35, 81.6],
      [42, 81.6],
      [49, 81.7],
    ]),
  })!;
  const [four, eight] = calc.weight!.trends;
  assertEquals(four.kg_per_week, -0.5);
  assert(eight.kg_per_week > -0.5 && eight.kg_per_week < 0);
  const p = calc.weight!.projection!;
  assertEquals(p.kg_per_week_high, -0.5 < eight.kg_per_week ? eight.kg_per_week : -0.5);
  const row = p.targets.find((r) => r.target_kg === 78)!;
  assertEquals(row.weeks_low, 4);
  assert(row.weeks_high > row.weeks_low);
});

Deno.test("a weight trend needs 4 days of readings across 14 days", () => {
  const calc = calculateCoachNumbers({
    coaching_date: date,
    weight_series_8w: weights([[0, 80], [5, 80.4], [10, 80.9]]),
  })!;
  assertEquals(calc.weight!.trends, []);
  assertEquals(calc.weight!.projection, null);
  assertStringIncludes(calc.weight!.projection_unavailable_reason!, "fewer than 4 days");
  const text = formatCoachCalculations(calc);
  assertStringIncludes(text, "- Latest: 80 kg on 2026-09-27");
  assertStringIncludes(text, "- Trend: not calculated (fewer than 4 days");
});

Deno.test("a stable weight gets a trend but no projected date", () => {
  const calc = calculateCoachNumbers({
    coaching_date: date,
    weight_series_8w: weights([[0, 80], [7, 80], [14, 80], [21, 80]]),
  })!;
  assertEquals(calc.weight!.trends[0].kg_per_week, 0);
  assertEquals(calc.weight!.projection, null);
  assertStringIncludes(calc.weight!.projection_unavailable_reason!, "stable");
  assertStringIncludes(
    formatCoachCalculations(calc),
    "- Projection: not calculated (weight is stable",
  );
});

Deno.test("an 8-week trend in the other direction does not widen the current projection", () => {
  const calc = calculateCoachNumbers({
    coaching_date: date,
    weight_series_8w: weights([
      [0, 79],
      [7, 79.5],
      [14, 80],
      [21, 80.5],
      [35, 76],
      [42, 75],
      [49, 74],
      [55, 73],
    ]),
  })!;
  const [four, eight] = calc.weight!.trends;
  assert(four.kg_per_week < 0 && eight.kg_per_week > 0);
  assertEquals(calc.weight!.projection!.windows, [28]);
});

Deno.test("HealthKit weights join body measurements; identical same-day readings count once", () => {
  const calc = calculateCoachNumbers({
    coaching_date: date,
    weight_series_8w: weights([[0, 80], [7, 80.5]]),
    health_daily_28d: [
      { local_date: daysAgo(0), weight_kg: 80 },
      { local_date: daysAgo(14), weight_kg: 81 },
      { local_date: daysAgo(21), weight_kg: 81.5 },
      { local_date: daysAgo(-1), weight_kg: 60 },
    ],
  })!;
  assertEquals(calc.weight!.trends[0].readings, 4);
  assertEquals(calc.weight!.trends[0].kg_per_week, -0.5);
});

Deno.test("training windows, week-over-week change and plan pace", () => {
  const session = (days: number, minutes: number, volume: number, rpe: number | null) => ({
    local_date: daysAgo(days),
    duration_minutes: minutes,
    completed_sets: 10,
    volume_kg: volume,
    avg_rpe: rpe,
  });
  const calc = calculateCoachNumbers({
    coaching_date: date,
    active_plan: { sessions_per_week: 4 },
    training_log_28d: [
      session(0, 60, 3000, 8),
      session(6, 50, 2000, null),
      session(7, 45, 4000, 7),
      session(20, 30, 1000, 6),
    ],
  })!;
  const t = calc.training!;
  assertEquals(t.last_7_days, {
    sessions: 2,
    minutes: 110,
    completed_sets: 20,
    volume_kg: 5000,
    avg_rpe: 8,
    avg_session_minutes: 55,
  });
  assertEquals(t.previous_7_days.sessions, 1);
  assertEquals(t.volume_change_pct, 25);
  assertEquals(t.last_28_days.sessions, 4);
  assertEquals(t.sessions_per_week_28d, 1);
  assertEquals(t.planned_sessions_per_week, 4);
  const text = formatCoachCalculations(calc);
  assertStringIncludes(text, "- Change, last 7 vs previous 7 days: +1 session, volume +25%");
  assertStringIncludes(text, "- Pace over 28 days: 1 sessions a week (plan: 4 a week)");
});

Deno.test("an empty training log reports zero sessions and no volume change", () => {
  const calc = calculateCoachNumbers({ coaching_date: date, training_log_28d: [] })!;
  assertEquals(calc.training!.last_7_days.sessions, 0);
  assertEquals(calc.training!.volume_change_pct, null);
  assertStringIncludes(formatCoachCalculations(calc), "volume — (no volume the week before)");
});

Deno.test("watch metrics average measured days only and need 3 days a week for a change", () => {
  const day = (days: number, sleep: number | null, hrv: number | null) => ({
    local_date: daysAgo(days),
    sleep_minutes: sleep,
    hrv_ms: hrv,
    steps: null,
  });
  const calc = calculateCoachNumbers({
    coaching_date: date,
    health_daily_28d: [
      day(0, 400, 40),
      day(1, null, 41),
      day(2, 420, 42.5),
      day(3, 380, null),
      day(7, 360, 50),
      day(8, 370, null),
      day(9, 350, null),
    ],
  })!;
  assertEquals(calc.metrics.map((m) => m.key), ["sleep_minutes", "hrv_ms"]);
  const sleep = calc.metrics[0];
  assertEquals(sleep.last_7_days, { days: 3, average: 400 });
  assertEquals(sleep.previous_7_days, { days: 3, average: 360 });
  assertEquals(sleep.change, 40);
  assertEquals([sleep.min_28d, sleep.max_28d], [350, 420]);
  const hrv = calc.metrics[1];
  assertEquals(hrv.last_7_days, { days: 3, average: 41.2 });
  assertEquals(hrv.previous_7_days.days, 1);
  assertEquals(hrv.change, null);
  const text = formatCoachCalculations(calc);
  assertStringIncludes(
    text,
    "| Sleep (min) | 400 (3 d) | 360 (3 d) | +40 | 380 (6 d) | 350 to 420 |",
  );
  assertStringIncludes(text, "| HRV (ms) | 41.2 (3 d) | 50 (1 d) | — |");
});

Deno.test("nutrition averages cover logged days and compare with targets", () => {
  const calc = calculateCoachNumbers({
    coaching_date: date,
    nutrition_targets: { calories: 1900, protein_g: 150 },
    nutrition_daily_28d: [
      { local_date: daysAgo(1), calories: 1800, protein_g: 140, carbohydrate_g: 200, fat_g: 60 },
      { local_date: daysAgo(3), calories: 2001, protein_g: 151, carbohydrate_g: 210, fat_g: 70 },
      { local_date: daysAgo(20), calories: 1500, protein_g: 100, carbohydrate_g: 150, fat_g: 50 },
    ],
  })!;
  assertEquals(calc.nutrition!.last_7_days, {
    days_logged: 2,
    calories: 1901,
    protein_g: 146,
    carbohydrate_g: 205,
    fat_g: 65,
  });
  assertEquals(calc.nutrition!.last_28_days.days_logged, 3);
  const text = formatCoachCalculations(calc);
  assertStringIncludes(
    text,
    "- Last 7 days: 2 days logged; per logged day 1901 kcal energy (target 1900, +1), 146 g protein (target 150, -4), 205 g carbohydrate, 65 g fat",
  );
  assertStringIncludes(
    formatCoachCalculations(
      calculateCoachNumbers({ coaching_date: date, nutrition_daily_28d: [] }),
    ),
    "- Last 7 days: no days with confirmed meals",
  );
});

Deno.test("the Coach context carries the calculated section instead of a second weight slope", () => {
  const rich = evalProfiles().find((p) => p.id === "rich")!;
  const markdown = formatContextAsMarkdown(rich.context, 96_000);
  assertStringIncludes(
    markdown,
    "## Calculated by Tracend (exact; quote these instead of computing)",
  );
  assertStringIncludes(markdown, "  - reach 72 kg (goal): about 14 weeks");
  assert(!markdown.includes("weight trend: 7d"));
  assert(
    markdown.indexOf("## Calculated by Tracend") < markdown.indexOf("## Training Log"),
    "calculations come before the rows they summarize",
  );

  const noWeight = { ...rich.context, weight_series_8w: [], health_daily_28d: [] };
  assertStringIncludes(formatContextAsMarkdown(noWeight, 96_000), "weight trend: 7d");
});
