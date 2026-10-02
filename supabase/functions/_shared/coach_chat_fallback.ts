import type { CoachChatAnswerV2 } from "./contracts/coach_chat_v1.ts";

// Served when the model cannot produce a valid answer, so the athlete is never
// left at a dead end. It is deterministic and explicitly labeled: every number
// is copied from the prepared context (nothing is estimated), and the response
// carries answer_source "data_summary" so the app never presents it as the
// coach's own answer.
//
// The summary does not answer the question, so it must be safe for any
// question:
// - A message that may be about a health risk gets a safety referral instead
//   of numbers. Training and calorie figures sent in reply to an injury or a
//   purging disclosure would read as advice about it. The screen is
//   deliberately broad: a false alarm only replaces the numbers with the
//   referral, while a miss would answer a red flag with numbers.
// - No word list catches every phrasing, so every data summary also ends with
//   the referral in one line.

export const coachChatDataSummaryModel = "coach-data-summary-v1";

/** Eating disorders and unsafe weight control (also hides the physique check). */
export const eatingConcernPattern =
  /purg(?:e|ed|es|ing)\b|laxative|diuretic|\bbinge|bulimi|anorexi|starv(?:e|ing) myself|starvation|stop(?:ped)? eating|not eating (?:at all|anything)|eating disorder|dehydrat/;

// Grouped by the red flags and unsupported populations in AI_SAFETY_SPEC.md.
const healthRiskPatterns: readonly RegExp[] = [
  // Red-flag symptoms and emergencies
  /chest (?:pain|tight|pressure)|heart (?:attack|racing|pounding)|palpitation|\bfaint|passed out|passing out|black(?:ed)? ?out|dizz|light-?headed|short(?:ness)? of breath|can'?t breathe|cannot breathe|\bnumb(?:ness)?\b|tingling|seizure|\bstroke\b|collaps|unconscious/,
  // Injury and pain
  /\bpain(?:ful|s)?\b|painkiller|\bhurt(?:s|ing)?\b|injur|sprain|fractur|\btorn\b|\btore\b|\btear\b|swollen|swelling|dislocat|\brehab|physio|surgery|\bdard\b|\bchot\b/,
  // Illness
  /fever|\bflu\b|covid|infection|\bsick\b|unwell|nause|vomit|throw(?:ing)? up|threw up|\bpuk(?:e|ed|ing)\b|diarrh|bukhar|\bulti\b|chakkar/,
  // Medical care, medication and drugs
  /\bmedic|\bmeds\b|doctor|diagnos|prescription|\bpills?\b|insulin|diabet|\bblood\b|hypertension|asthma|thyroid|steroid|testosterone|\btrt\b|\bsarms?\b|ozempic|semaglutide|wegovy|mounjaro|tirzepatide|fat burner|ibuprofen|paracetamol|antidepressant/,
  // Pregnancy
  /pregnan|postpartum|post-partum|breastfeed|trimester/,
  // Eating disorders and unsafe weight control
  eatingConcernPattern,
  // Self-harm and crisis
  /suicid|kill myself|self[- ]?harm|end my life|want to die/,
];

export function mayConcernHealthRisk(question: string): boolean {
  const normalized = question.toLowerCase();
  return healthRiskPatterns.some((pattern) => pattern.test(normalized));
}

const safetyReferral =
  "I couldn't answer just now, and your message may be about your health, so I won't reply with numbers from your data. Tracend can't safely advise on pain, injuries, dizziness or fainting, illness, medication, pregnancy or eating concerns: please talk to a doctor, physiotherapist or dietitian. Stop training if something feels wrong, and contact local emergency services if it's urgent.";

const closingReferral =
  "If your question is about pain, an injury, dizziness or fainting, illness, medication, pregnancy or eating, please don't wait for me: talk to a doctor or another qualified professional.";

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

export function buildCoachChatDataSummary(
  context: Record<string, unknown>,
  question: string,
): CoachChatAnswerV2 {
  if (mayConcernHealthRisk(question)) {
    return {
      answer: safetyReferral,
      evidence: [],
      missing_data: [],
      safety_state: "limited",
      suggested_follow_ups: [],
    };
  }

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
  // The average covers only the nights the watch measured, so the count
  // travels with it.
  const weekAverages = obj(obj(context.health_averages).last_7_days);
  if (present(weekAverages.avg_sleep_minutes)) {
    const nights = weekAverages.days_with_sleep;
    lines.push(
      `Average sleep over the last 7 days: ${weekAverages.avg_sleep_minutes} minutes` +
        (present(nights) ? `, from ${nights} ${nights === 1 ? "night" : "nights"} measured.` : "."),
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
    if (present(loggedDays)) {
      line += ` ${loggedDays} of the last 7 days ${
        loggedDays === 1 ? "has" : "have"
      } confirmed meals.`;
    }
    lines.push(line);
  }

  lines.push(closingReferral);

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
