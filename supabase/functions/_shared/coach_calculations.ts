// Deterministic Coach calculators. They read only the prepared athlete file
// (prepare_coach_chat_v8) and return exact numbers, so the model quotes
// averages, changes, trends and projections instead of computing them. Every
// result names its window and how many days were measured; a metric that was
// not measured is left out, never counted as zero.

export type WindowAverage = Readonly<{ days: number; average: number | null }>;

export type WeightTrend = Readonly<{
  window_days: 28 | 56;
  readings: number;
  first_date: string;
  last_date: string;
  kg_per_week: number;
}>;

export type WeightProjectionRow = Readonly<{
  target_kg: number;
  weeks_low: number;
  weeks_high: number;
  goal: boolean;
}>;

export type WeightHorizonRow = Readonly<{ weeks: number; kg_low: number; kg_high: number }>;

export type WeightCalculation = Readonly<{
  latest_kg: number;
  latest_date: string;
  trends: readonly WeightTrend[];
  projection:
    | Readonly<{
      kg_per_week_low: number;
      kg_per_week_high: number;
      windows: readonly number[];
      targets: readonly WeightProjectionRow[];
      horizons: readonly WeightHorizonRow[];
    }>
    | null;
  projection_unavailable_reason: string | null;
}>;

export type TrainingWindow = Readonly<{
  sessions: number;
  minutes: number;
  completed_sets: number;
  volume_kg: number;
  avg_rpe: number | null;
  avg_session_minutes: number | null;
}>;

export type TrainingCalculation = Readonly<{
  last_7_days: TrainingWindow;
  previous_7_days: TrainingWindow;
  last_28_days: TrainingWindow;
  sessions_per_week_28d: number;
  planned_sessions_per_week: number | null;
  volume_change_pct: number | null;
}>;

export type MetricCalculation = Readonly<{
  key: string;
  label: string;
  last_7_days: WindowAverage;
  previous_7_days: WindowAverage;
  change: number | null;
  last_28_days: WindowAverage;
  min_28d: number;
  max_28d: number;
}>;

export type NutritionWindow = Readonly<{
  days_logged: number;
  calories: number | null;
  protein_g: number | null;
  carbohydrate_g: number | null;
  fat_g: number | null;
}>;

export type NutritionCalculation = Readonly<{
  last_7_days: NutritionWindow;
  last_28_days: NutritionWindow;
  targets: Readonly<Record<string, number>>;
}>;

export type CoachCalculations = Readonly<{
  coaching_date: string;
  weight: WeightCalculation | null;
  training: TrainingCalculation | null;
  metrics: readonly MetricCalculation[];
  nutrition: NutritionCalculation | null;
}>;

// A trend needs readings on at least 4 days spanning at least 14 days; fewer
// points let one water-weight swing decide the answer.
export const weightTrendMinimumDays = 4;
export const weightTrendMinimumSpanDays = 14;
// Below this pace the weight is treated as stable and no date is projected.
export const weightFlatKgPerWeek = 0.05;
const projectionTargetCount = 10;
const projectionMaxWeeks = 104;
const projectionHorizonsWeeks = [4, 8, 12, 26] as const;
// A week-over-week change needs at least this many measured days in each week.
const metricChangeMinimumDays = 3;

const metricDefinitions = [
  { key: "sleep_minutes", label: "Sleep (min)", decimals: 0 },
  { key: "resting_heart_rate_bpm", label: "Resting heart rate (bpm)", decimals: 1 },
  { key: "hrv_ms", label: "HRV (ms)", decimals: 1 },
  { key: "steps", label: "Steps", decimals: 0 },
  { key: "active_energy_kcal", label: "Active energy (kcal)", decimals: 0 },
  { key: "workout_minutes", label: "Workout minutes", decimals: 0 },
] as const;

const nutritionKeys = ["calories", "protein_g", "carbohydrate_g", "fat_g"] as const;

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function arr(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function num(value: unknown): number | null {
  if (typeof value === "number") return Number.isFinite(value) ? value : null;
  if (typeof value === "string" && value.trim() !== "") {
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
  }
  return null;
}

// Decimal rounding without binary artifacts (1.005 -> 1.01), half away from
// zero like Postgres round(numeric, n), so numbers match the SQL averages.
export function roundTo(value: number, decimals: number): number {
  const sign = value < 0 ? -1 : 1;
  const rounded = Number(Math.round(Number(`${Math.abs(value)}e${decimals}`)) + `e-${decimals}`);
  return rounded === 0 ? 0 : sign * rounded;
}

function dayIndex(date: unknown): number | null {
  if (typeof date !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(date)) return null;
  const [year, month, day] = date.split("-").map(Number);
  const time = Date.UTC(year, month - 1, day);
  const parsed = new Date(time);
  if (parsed.getUTCMonth() !== month - 1 || parsed.getUTCDate() !== day) return null;
  return time / 86_400_000;
}

function mean(values: readonly number[]): number | null {
  return values.length ? values.reduce((sum, v) => sum + v, 0) / values.length : null;
}

type WeightPoint = Readonly<{ day: number; date: string; kg: number }>;

function weightPoints(ctx: Record<string, unknown>, today: number): WeightPoint[] {
  // Same sources as the feature engine's weight trend: body measurements plus
  // HealthKit daily weights, with identical same-day readings counted once.
  const seen = new Set<string>();
  const points: WeightPoint[] = [];
  const add = (date: unknown, weight: unknown) => {
    const day = dayIndex(date);
    const kg = num(weight);
    if (day === null || kg === null || kg <= 0 || day > today) return;
    const key = `${date}|${kg}`;
    if (seen.has(key)) return;
    seen.add(key);
    points.push({ day, date: date as string, kg });
  };
  for (const point of arr(ctx.weight_series_8w)) {
    add(obj(point).measured_on, obj(point).weight_kg);
  }
  for (const row of arr(ctx.health_daily_28d)) add(obj(row).local_date, obj(row).weight_kg);
  return points;
}

function weightTrend(points: readonly WeightPoint[], today: number, window: 28 | 56) {
  const inside = points.filter((p) => p.day >= today - (window - 1));
  const days = [...new Set(inside.map((p) => p.day))].sort((a, b) => a - b);
  if (
    days.length < weightTrendMinimumDays ||
    days[days.length - 1] - days[0] < weightTrendMinimumSpanDays
  ) {
    return null;
  }
  const meanX = mean(inside.map((p) => p.day))!;
  const meanY = mean(inside.map((p) => p.kg))!;
  let covariance = 0;
  let variance = 0;
  for (const p of inside) {
    covariance += (p.day - meanX) * (p.kg - meanY);
    variance += (p.day - meanX) ** 2;
  }
  const byDay = [...inside].sort((a, b) => a.day - b.day);
  return {
    window_days: window,
    readings: inside.length,
    first_date: byDay[0].date,
    last_date: byDay[byDay.length - 1].date,
    kgPerWeek: (covariance / variance) * 7,
  };
}

function calculateWeight(ctx: Record<string, unknown>, today: number): WeightCalculation | null {
  const points = weightPoints(ctx, today);
  if (!points.length) return null;
  const latestDay = Math.max(...points.map((p) => p.day));
  // weight_series_8w lists the newest entry first within a day.
  const latest = points.find((p) => p.day === latestDay)!;
  const raw = [weightTrend(points, today, 28), weightTrend(points, today, 56)]
    .filter((t): t is NonNullable<typeof t> => t !== null);
  const trends: WeightTrend[] = raw.map((t) => ({
    window_days: t.window_days as 28 | 56,
    readings: t.readings,
    first_date: t.first_date,
    last_date: t.last_date,
    kg_per_week: roundTo(t.kgPerWeek, 2),
  }));

  // The current pace is the most recent valid trend (4 weeks, else 8 weeks).
  // The other window widens the range only when it points the same way.
  const current = raw[0];
  let reason: string | null = null;
  let rates: { window: number; rate: number }[] = [];
  if (!current) {
    reason =
      `fewer than ${weightTrendMinimumDays} days with a weight reading across at least ${weightTrendMinimumSpanDays} days`;
  } else if (Math.abs(current.kgPerWeek) < weightFlatKgPerWeek) {
    reason =
      `weight is stable (under ${weightFlatKgPerWeek} kg a week), so no date can be projected`;
  } else {
    rates = raw
      .filter((t) =>
        Math.sign(t.kgPerWeek) === Math.sign(current.kgPerWeek) &&
        Math.abs(t.kgPerWeek) >= weightFlatKgPerWeek
      )
      .map((t) => ({ window: t.window_days, rate: t.kgPerWeek }));
  }
  if (!rates.length) {
    return {
      latest_kg: latest.kg,
      latest_date: latest.date,
      trends,
      projection: null,
      projection_unavailable_reason: reason,
    };
  }

  const direction = Math.sign(rates[0].rate);
  const weeksTo = (target: number) => rates.map((r) => (target - latest.kg) / r.rate);
  const first = direction < 0 ? Math.ceil(latest.kg - 1) : Math.floor(latest.kg + 1);
  const targetValues = Array.from(
    { length: projectionTargetCount },
    (_, index) => first + direction * index,
  );
  const goal = num(obj(obj(ctx.active_goal).details).target_weight_kg);
  const goalAhead = goal !== null && Math.sign(goal - latest.kg) === direction;
  if (goalAhead && !targetValues.includes(goal)) targetValues.push(goal);
  const targets: WeightProjectionRow[] = targetValues
    .sort((a, b) => direction < 0 ? b - a : a - b)
    .map((target) => {
      const weeks = weeksTo(target);
      return {
        target_kg: target,
        weeks_low: Math.max(1, Math.round(Math.min(...weeks))),
        weeks_high: Math.max(1, Math.round(Math.max(...weeks))),
        goal: goalAhead && target === goal,
      };
    })
    .filter((row) => row.weeks_low <= projectionMaxWeeks);
  const horizons: WeightHorizonRow[] = projectionHorizonsWeeks.map((weeks) => {
    const values = rates.map((r) => latest.kg + r.rate * weeks);
    return {
      weeks,
      kg_low: roundTo(Math.min(...values), 1),
      kg_high: roundTo(Math.max(...values), 1),
    };
  });
  const rounded = rates.map((r) => roundTo(r.rate, 2));
  return {
    latest_kg: latest.kg,
    latest_date: latest.date,
    trends,
    projection: {
      kg_per_week_low: Math.min(...rounded),
      kg_per_week_high: Math.max(...rounded),
      windows: rates.map((r) => r.window),
      targets,
      horizons,
    },
    projection_unavailable_reason: null,
  };
}

function trainingWindow(rows: readonly Record<string, unknown>[]): TrainingWindow {
  const sum = (key: string) => rows.reduce((total, row) => total + (num(row[key]) ?? 0), 0);
  const rpe = rows.map((row) => num(row.avg_rpe)).filter((v): v is number => v !== null);
  const durations = rows.map((row) => num(row.duration_minutes)).filter((v): v is number =>
    v !== null
  );
  const averageRpe = mean(rpe);
  const averageMinutes = mean(durations);
  return {
    sessions: rows.length,
    minutes: roundTo(sum("duration_minutes"), 0),
    completed_sets: roundTo(sum("completed_sets"), 0),
    volume_kg: roundTo(sum("volume_kg"), 1),
    avg_rpe: averageRpe === null ? null : roundTo(averageRpe, 1),
    avg_session_minutes: averageMinutes === null ? null : roundTo(averageMinutes, 0),
  };
}

function calculateTraining(
  ctx: Record<string, unknown>,
  today: number,
): TrainingCalculation | null {
  if (!Array.isArray(ctx.training_log_28d)) return null;
  const rows = ctx.training_log_28d.map(obj).filter((row) => {
    const day = dayIndex(row.local_date);
    return day !== null && day <= today && day >= today - 27;
  });
  const between = (from: number, to: number) =>
    rows.filter((row) => {
      const day = dayIndex(row.local_date)!;
      return day >= today - from && day <= today - to;
    });
  const last7 = trainingWindow(between(6, 0));
  const previous7 = trainingWindow(between(13, 7));
  const last28 = trainingWindow(rows);
  const planned = num(obj(ctx.training_week_structure).sessions_per_week) ??
    num(obj(ctx.active_plan).sessions_per_week);
  return {
    last_7_days: last7,
    previous_7_days: previous7,
    last_28_days: last28,
    sessions_per_week_28d: roundTo(last28.sessions / 4, 1),
    planned_sessions_per_week: planned,
    volume_change_pct: previous7.volume_kg > 0
      ? roundTo(((last7.volume_kg - previous7.volume_kg) / previous7.volume_kg) * 100, 0)
      : null,
  };
}

function calculateMetrics(ctx: Record<string, unknown>, today: number): MetricCalculation[] {
  const days = arr(ctx.health_daily_28d).map(obj).map((row) => ({
    row,
    day: dayIndex(row.local_date),
  })).filter((d): d is { row: Record<string, unknown>; day: number } =>
    d.day !== null && d.day <= today && d.day >= today - 27
  );
  const results: MetricCalculation[] = [];
  for (const definition of metricDefinitions) {
    const values = (from: number, to: number) =>
      days
        .filter((d) => d.day >= today - from && d.day <= today - to)
        .map((d) => num(d.row[definition.key]))
        .filter((v): v is number => v !== null);
    const average = (list: number[]): WindowAverage => {
      const value = mean(list);
      return {
        days: list.length,
        average: value === null ? null : roundTo(value, definition.decimals),
      };
    };
    const all = values(27, 0);
    if (!all.length) continue;
    const last7 = average(values(6, 0));
    const previous7 = average(values(13, 7));
    const change = last7.days >= metricChangeMinimumDays &&
        previous7.days >= metricChangeMinimumDays
      ? roundTo(last7.average! - previous7.average!, definition.decimals)
      : null;
    results.push({
      key: definition.key,
      label: definition.label,
      last_7_days: last7,
      previous_7_days: previous7,
      change,
      last_28_days: average(all),
      min_28d: Math.min(...all),
      max_28d: Math.max(...all),
    });
  }
  return results;
}

function nutritionWindow(rows: readonly Record<string, unknown>[]): NutritionWindow {
  const average = (key: string) => {
    const value = mean(rows.map((row) => num(row[key])).filter((v): v is number => v !== null));
    return value === null ? null : roundTo(value, 0);
  };
  return {
    days_logged: rows.length,
    calories: average("calories"),
    protein_g: average("protein_g"),
    carbohydrate_g: average("carbohydrate_g"),
    fat_g: average("fat_g"),
  };
}

function calculateNutrition(
  ctx: Record<string, unknown>,
  today: number,
): NutritionCalculation | null {
  if (!Array.isArray(ctx.nutrition_daily_28d)) return null;
  const rows = ctx.nutrition_daily_28d.map(obj).filter((row) => {
    const day = dayIndex(row.local_date);
    return day !== null && day <= today && day >= today - 27;
  });
  const targetSource = obj(ctx.nutrition_targets);
  const targets: Record<string, number> = {};
  for (const key of nutritionKeys) {
    const value = num(targetSource[key]);
    if (value !== null) targets[key] = value;
  }
  return {
    last_7_days: nutritionWindow(rows.filter((row) => dayIndex(row.local_date)! >= today - 6)),
    last_28_days: nutritionWindow(rows),
    targets,
  };
}

export function calculateCoachNumbers(ctx: Record<string, unknown>): CoachCalculations | null {
  const today = dayIndex(ctx.coaching_date);
  if (today === null) return null;
  return {
    coaching_date: ctx.coaching_date as string,
    weight: calculateWeight(ctx, today),
    training: calculateTraining(ctx, today),
    metrics: calculateMetrics(ctx, today),
    nutrition: calculateNutrition(ctx, today),
  };
}

function signed(value: number): string {
  return value > 0 ? `+${value}` : String(value);
}

function range(low: number, high: number, unit: string): string {
  return low === high ? `${low} ${unit}` : `${low} to ${high} ${unit}`;
}

function formatTraining(label: string, t: TrainingWindow): string {
  let line = `- ${label}: ${t.sessions} ${t.sessions === 1 ? "session" : "sessions"}`;
  if (t.sessions > 0) {
    line += `, ${t.minutes} min, ${t.completed_sets} completed sets, ${t.volume_kg} kg volume`;
    line += `, avg RPE ${t.avg_rpe ?? "—"}, avg session ${t.avg_session_minutes ?? "—"} min`;
  }
  return line + "\n";
}

function formatNutrition(
  label: string,
  n: NutritionWindow,
  targets: Readonly<Record<string, number>>,
): string {
  if (n.days_logged === 0) return `- ${label}: no days with confirmed meals\n`;
  const part = (key: (typeof nutritionKeys)[number], unit: string, name: string) => {
    const value = n[key];
    if (value === null) return `${name} —`;
    const target = targets[key];
    return target === undefined
      ? `${value} ${unit} ${name}`
      : `${value} ${unit} ${name} (target ${target}, ${signed(roundTo(value - target, 0))})`;
  };
  return `- ${label}: ${n.days_logged} ${
    n.days_logged === 1 ? "day" : "days"
  } logged; per logged day ${part("calories", "kcal", "energy")}, ${
    part("protein_g", "g", "protein")
  }, ${part("carbohydrate_g", "g", "carbohydrate")}, ${part("fat_g", "g", "fat")}\n`;
}

// The "Calculated by Tracend" context section, or "" when nothing applies.
export function formatCoachCalculations(calc: CoachCalculations | null): string {
  if (!calc) return "";
  const parts: string[] = [];
  const w = calc.weight;
  if (w) {
    let s = "### Weight\n";
    s += `- Latest: ${w.latest_kg} kg on ${w.latest_date}\n`;
    for (const t of w.trends) {
      s += `- ${t.window_days / 7}-week trend: ${signed(t.kg_per_week)} kg/week (${t.readings} ${
        t.readings === 1 ? "reading" : "readings"
      }, ${t.first_date} to ${t.last_date}; least-squares fit)\n`;
    }
    if (!w.trends.length) {
      s += `- Trend: not calculated (${w.projection_unavailable_reason})\n`;
    }
    if (w.projection) {
      const p = w.projection;
      s += `- Projection (estimate; assumes the pace of ${
        range(p.kg_per_week_low, p.kg_per_week_high, "kg/week")
      } from the ${p.windows.map((d) => `${d / 7}-week`).join(" and ")} trend continues):\n`;
      for (const row of p.targets) {
        s += `  - reach ${row.target_kg} kg${row.goal ? " (goal)" : ""}: about ${
          range(row.weeks_low, row.weeks_high, row.weeks_high === 1 ? "week" : "weeks")
        }\n`;
      }
      for (const row of p.horizons) {
        s += `  - in ${row.weeks} weeks: about ${range(row.kg_low, row.kg_high, "kg")}\n`;
      }
    } else if (w.trends.length) {
      s += `- Projection: not calculated (${w.projection_unavailable_reason})\n`;
    }
    parts.push(s);
  }
  const t = calc.training;
  if (t) {
    let s = "### Training (completed sessions)\n";
    s += formatTraining("Last 7 days", t.last_7_days);
    s += formatTraining("Previous 7 days", t.previous_7_days);
    const sessionChange = t.last_7_days.sessions - t.previous_7_days.sessions;
    s += `- Change, last 7 vs previous 7 days: ${signed(sessionChange)} ${
      Math.abs(sessionChange) === 1 ? "session" : "sessions"
    }, volume ${
      t.volume_change_pct === null
        ? "— (no volume the week before)"
        : `${signed(t.volume_change_pct)}%`
    }\n`;
    s += formatTraining("Last 28 days", t.last_28_days);
    s += `- Pace over 28 days: ${t.sessions_per_week_28d} sessions a week${
      t.planned_sessions_per_week === null ? "" : ` (plan: ${t.planned_sessions_per_week} a week)`
    }\n`;
    parts.push(s);
  }
  if (calc.metrics.length) {
    let s = "### Watch metrics (averages over measured days only)\n";
    s += "| Metric | Last 7 days | Previous 7 days | Change | Last 28 days | 28-day range |\n";
    s += "|--------|-------------|-----------------|--------|--------------|--------------|\n";
    const cell = (a: WindowAverage) =>
      a.average === null ? "— (0 days)" : `${a.average} (${a.days} d)`;
    for (const m of calc.metrics) {
      s += `| ${m.label} | ${cell(m.last_7_days)} | ${cell(m.previous_7_days)} | ${
        m.change === null ? "—" : signed(m.change)
      } | ${cell(m.last_28_days)} | ${m.min_28d} to ${m.max_28d} |\n`;
    }
    s +=
      `Change is shown only when both weeks have at least ${metricChangeMinimumDays} measured days.\n`;
    parts.push(s);
  }
  const n = calc.nutrition;
  if (n) {
    let s = "### Nutrition (confirmed meals; unlogged days are unknown, not zero)\n";
    s += formatNutrition("Last 7 days", n.last_7_days, n.targets);
    s += formatNutrition("Last 28 days", n.last_28_days, n.targets);
    parts.push(s);
  }
  if (!parts.length) return "";
  return `## Calculated by Tracend (exact; quote these instead of computing)\n` +
    `Windows end on ${calc.coaching_date}: last 7 days = that day and the 6 before it; previous 7 days = the 7 days before those.\n` +
    parts.join("");
}
