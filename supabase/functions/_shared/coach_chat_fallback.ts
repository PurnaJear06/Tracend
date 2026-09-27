import type { CoachChatAnswerV2 } from "./contracts/coach_chat_v1.ts";

// Served when the model cannot produce a valid answer, so the athlete is never
// left at a dead end. It is deterministic and explicitly labeled: every number
// is copied from the prepared context (nothing is estimated), safety_state is
// "unavailable", and the response carries answer_source "data_summary" so the
// app never presents it as the coach's own answer.

export const coachChatDataSummaryModel = "coach-data-summary-v1";

const evidenceLabels: Readonly<Record<string, string>> = {
  APPROVED_PLAN_ACTIVE: "Approved plan is active",
  HEALTH_CONTEXT_AVAILABLE: "Watch data synced for today",
  RECOVERY_BELOW_BASELINE: "Recovery is below your baseline",
  RECOVERY_WITHIN_BASELINE: "Recovery is within your baseline",
  CHECK_IN_RECOVERY_MIXED: "Recovery signals are mixed",
  CHECK_IN_SAFETY_ESCALATION: "Check-in reported high pain",
};

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

function arr(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}

function present(value: unknown): boolean {
  return value !== null && value !== undefined && value !== "";
}

function evidenceLabel(code: string): string {
  if (evidenceLabels[code]) return evidenceLabels[code];
  const words = code.toLowerCase().replace(/_/g, " ");
  return words.charAt(0).toUpperCase() + words.slice(1);
}

export function buildCoachChatDataSummary(context: Record<string, unknown>): CoachChatAnswerV2 {
  const lines: string[] = [
    "I couldn't put together a full coaching answer just now, so here is what your data shows. Ask again in a moment and I'll give you my full take.",
  ];

  const plan = obj(context.active_plan);
  const twoWeeks = obj(obj(context.training_totals).last_14_days);
  if (present(twoWeeks.sessions)) {
    let line =
      `Training, last 14 days: ${twoWeeks.sessions} completed sessions, ${twoWeeks.total_minutes} minutes, ${twoWeeks.completed_sets} completed sets (${twoWeeks.volume_kg} kg volume).`;
    if (present(plan.sessions_per_week)) {
      line += ` Your plan calls for ${plan.sessions_per_week} sessions a week.`;
    }
    const watchWorkouts = arr(context.watch_workouts_14d).length;
    if (watchWorkouts > 0) {
      line += ` Your watch also recorded ${watchWorkouts} workouts in that time.`;
    }
    lines.push(line);
  }

  const computed = obj(context.computed_metrics);
  if (!computed.unavailable) {
    const recovery = obj(computed.recovery).score;
    const sleepQuality = obj(computed.sleep).quality;
    let line = present(recovery)
      ? `Recovery today: ${recovery}/100.`
      : "Recovery wasn't measured today.";
    if (present(sleepQuality)) line += ` Sleep quality: ${sleepQuality}/100.`;
    lines.push(line);
  }
  const weekAverages = obj(obj(context.health_averages).last_7_days);
  if (present(weekAverages.avg_sleep_minutes)) {
    lines.push(
      `Average sleep over the last 7 days: ${weekAverages.avg_sleep_minutes} minutes (${weekAverages.days_synced} days synced).`,
    );
  }

  const latestWeight = obj(arr(context.weight_series_8w)[0]);
  if (present(latestWeight.weight_kg)) {
    let line = `Latest weight: ${latestWeight.weight_kg} kg on ${latestWeight.measured_on}.`;
    const trend = obj(computed.weight).trend_28d_kg_per_day;
    if (!computed.unavailable && present(trend)) line += ` 28-day trend: ${trend} kg/day.`;
    lines.push(line);
  }

  const targets = obj(context.nutrition_targets);
  if (present(targets.calories)) {
    let line = `Nutrition target: ${targets.calories} kcal`;
    if (present(targets.protein_g)) line += ` and ${targets.protein_g} g protein`;
    line += " a day.";
    const loggedDays = obj(context.nutrition_adherence).days_with_confirmed_meals_7d;
    if (present(loggedDays)) line += ` ${loggedDays} of the last 7 days have confirmed meals.`;
    lines.push(line);
  }

  const permitted = arr(context.permitted_evidence)
    .filter((code): code is string => typeof code === "string")
    .slice(0, 12);
  const missing = arr(context.missing_data)
    .filter((item): item is string => typeof item === "string" && item.length <= 300)
    .slice(0, 12);

  return {
    answer: lines.join("\n\n"),
    evidence: permitted.map((code) => ({
      code,
      label: evidenceLabel(code),
      source: "coach_context",
    })),
    missing_data: missing,
    safety_state: "unavailable",
    suggested_follow_ups: [],
  };
}
