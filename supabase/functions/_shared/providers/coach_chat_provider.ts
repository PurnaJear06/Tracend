import {
  type CoachChatAnswerV1,
  type CoachChatAnswerV2,
  parseCoachChatAnswer,
} from "../contracts/coach_chat_v1.ts";

export type CoachChatGeneration = Readonly<{
  answer: CoachChatAnswerV2;
  provider: "mock" | "gemini" | "groq" | "deepseek";
  model: string;
  inputUnits: number;
  outputUnits: number;
  estimatedCostUsd: number;
}>;

const answerSchema = {
  type: "object",
  additionalProperties: false,
  properties: {
    answer: { type: "string" },
    evidence: {
      type: "array",
      maxItems: 12,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          code: { type: "string" },
          label: { type: "string" },
          source: {
            type: "string",
            enum: ["feature_snapshot", "policy_evaluation", "coach_context"],
          },
        },
        required: ["code", "label", "source"],
      },
    },
    missing_data: { type: "array", maxItems: 12, items: { type: "string" } },
    safety_state: { type: "string", enum: ["allowed", "limited", "refused", "unavailable"] },
    suggested_follow_ups: { type: "array", maxItems: 4, items: { type: "string" } },
    reasoning_chain: {
      type: "array",
      maxItems: 6,
      items: {
        type: "object",
        additionalProperties: false,
        properties: {
          step: { type: "string" },
          value: { type: "string" },
          evidence_id: { type: "string", nullable: true },
        },
        required: ["step", "value"],
      },
    },
  },
  required: ["answer", "evidence", "missing_data", "safety_state", "suggested_follow_ups"],
} as const;

export function deterministicBoundary(question: string): CoachChatAnswerV1 | null {
  const normalized = question.toLowerCase();
  const emergency = [
    "chest pain",
    "fainting",
    "can't breathe",
    "cannot breathe",
    "severe shortness of breath",
  ];
  if (emergency.some((term) => normalized.includes(term))) {
    return {
      answer:
        "Stop the activity. Tracend cannot safely assess these symptoms. Contact local emergency services or seek urgent medical care now.",
      evidence: [],
      missing_data: [],
      safety_state: "refused",
      suggested_follow_ups: [],
    };
  }
  const clinical = [
    "diagnose",
    "medication",
    "medical report",
    "rehab",
    "pregnant",
    "eating disorder",
  ];
  if (clinical.some((term) => normalized.includes(term))) {
    return {
      answer:
        "Tracend cannot provide diagnosis, treatment, rehabilitation, medication, pregnancy, or eating-disorder guidance. Use a qualified clinician for this request.",
      evidence: [],
      missing_data: [],
      safety_state: "refused",
      suggested_follow_ups: [
        "Ask about the approved training plan",
        "Review current fitness evidence",
      ],
    };
  }
  return null;
}

export class CoachChatUnavailableError extends Error {
  constructor(
    readonly provider: "mock" | "gemini" | "groq" | "deepseek",
    readonly model: string,
    readonly failureReason: string = "unknown",
    readonly retryAfterSeconds: number | null = null,
  ) {
    const retrySuffix = retryAfterSeconds != null ? ` (retry in ${retryAfterSeconds}s)` : "";
    super(`coach_chat_unavailable: ${failureReason}${retrySuffix}`);
  }
}

function collectEvidenceIds(value: unknown, target = new Set<string>()): Set<string> {
  if (Array.isArray(value)) {
    for (const item of value) collectEvidenceIds(item, target);
  } else if (value && typeof value === "object") {
    for (const [key, item] of Object.entries(value as Record<string, unknown>)) {
      if (key === "evidence_id" && typeof item === "string") target.add(item);
      else collectEvidenceIds(item, target);
    }
  }
  return target;
}

const keyAbbreviations: Record<string, string> = {
  session_id: "sid",
  prescribed_workout: "w",
  duration_seconds: "dur",
  logging_completeness: "lc",
  session_effort: "eff",
  session_energy: "en",
  correction_status: "cs",
  local_date: "d",
  prescribed_name: "n",
  performed_name: "pn",
  kind: "k",
  status: "s",
  pain_flag: "p",
  exercise_order: "o",
  sets: "ss",
  set_number: "s",
  repetitions: "r",
  load_kg: "kg",
  rpe: "rpe",
  completed: "c",
  weight_kg: "w",
  body_fat_pct: "bf",
  steps_count: "st",
  resting_heart_rate_bpm: "rhr",
  hrv_sdnn_ms: "hrv",
  sleep_duration_hours: "sl",
  food_name: "f",
  serving_label: "s",
  calories: "cal",
  protein_g: "p",
  carbohydrate_g: "c",
  fat_g: "f",
  nutrition_adherence: "na",
  nutrition_compliance_7day: "nc7",
  days_with_confirmed_meals_7d: "dwm",
  confirmed_meal_count_7d: "cm7",
  schedule_slot_compliance: "ssc",
  scheduled_slots: "ss",
  matched_slots_today: "mst",
  last_photo_set: "lps",
  photo_sets_completed: "psc",
  has_physique_analysis: "hpa",
  avg_daily_carbohydrate_g: "adc",
  avg_daily_fat_g: "adf",
  days_with_meals: "dwm",
  coaching_narrative: "cn",
  active_preferences: "ap",
  session_journal: "sj",
  fts_messages: "ftsm",
  phase: "ph",
  headline: "hl",
  provenance: "prv",
  since: "sin",
  step: "stp",
  evidence_id: "eid",
};

function compactValue(value: unknown): unknown {
  if (value === null) return undefined;
  if (Array.isArray(value)) {
    const compacted = value.map(compactValue).filter((v) => v !== undefined);
    return compacted.length === 0 ? undefined : compacted;
  }
  if (typeof value === "object") {
    const result: Record<string, unknown> = {};
    for (const [key, val] of Object.entries(value as Record<string, unknown>)) {
      const compressed = compactValue(val);
      if (compressed !== undefined) {
        const abbr = keyAbbreviations[key] ?? key;
        if (abbr === "rationale" && typeof compressed === "string" && compressed.length > 120) {
          result[abbr] = compressed.slice(0, 120);
        } else {
          result[abbr] = compressed;
        }
      }
    }
    return Object.keys(result).length === 0 ? undefined : result;
  }
  // Truncate long string values — they are the #1 cause of context bloat.
  // Full message content, narrative summaries, and rationales can each be
  // thousands of chars; the model only needs a short signal, not the full text.
  if (typeof value === "string" && value.length > 500) {
    return value.slice(0, 500) + "…";
  }
  return value;
}

/** Deep-truncates every string in an object tree to maxLength chars.
 *  Used as a progressive fallback when the context is still too large after
 *  compacting and targeted trimming. */
function deepTruncateStrings(obj: unknown, maxLength: number): unknown {
  if (typeof obj === "string" && obj.length > maxLength) {
    return obj.slice(0, maxLength) + "…";
  }
  if (Array.isArray(obj)) return obj.map((v) => deepTruncateStrings(v, maxLength));
  if (obj && typeof obj === "object") {
    const result: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(obj as Record<string, unknown>)) {
      result[k] = deepTruncateStrings(v, maxLength);
    }
    return result;
  }
  return obj;
}

/**
 * Ensures the serialised context fits within maxLength chars by progressively
 * trimming the largest contributors.  Never throws — returns a safe fallback
 * on any failure so the chat pipeline stays available even under budget pressure.
 */
function fitContextToLimit(bounded: string, maxLength: number, question: string): string {
  if (bounded.length <= maxLength) return bounded;

  let parsed: Record<string, unknown>;
  try {
    parsed = JSON.parse(bounded);
  } catch {
    console.warn(
      `fitContextToLimit: bounded JSON parse failed (${bounded.length} chars), returning fallback`,
    );
    return JSON.stringify({ question, context: { warning: "context_parse_failed" } });
  }

  const ctx = (parsed.context ?? parsed) as Record<string, unknown> | undefined;
  if (!ctx || typeof ctx !== "object") {
    console.warn(
      "fitContextToLimit: resolved context is not an object, returning fallback",
    );
    return JSON.stringify({ question, context: { warning: "context_invalid_structure" } });
  }

  // --- Tier 1: trim known high-volume free-text fields ---
  const messageArrays = ["fts_messages", "ftsm", "recent_other_conversations"];
  for (const key of messageArrays) {
    const arr = (ctx as Record<string, unknown>)[key];
    if (Array.isArray(arr)) {
      (ctx as Record<string, unknown>)[key] = arr.map(
        (msg: Record<string, unknown>) => ({
          ...msg,
          content: typeof msg.content === "string" ? msg.content.slice(0, 200) : msg.content,
        }),
      );
    }
  }

  // Trim long narrative / journal summary strings.
  const longTextKeys = ["summary", "headline", "proposed_training", "proposed_nutrition"];
  for (const key of longTextKeys) {
    const val = (ctx as Record<string, unknown>)[key];
    if (typeof val === "string" && val.length > 300) {
      (ctx as Record<string, unknown>)[key] = val.slice(0, 300) + "…";
    }
  }

  // Re-wrap if we unwrapped the outer envelope.
  if (parsed.context !== undefined) {
    parsed.context = ctx;
  } else {
    parsed = ctx as Record<string, unknown>;
  }
  bounded = JSON.stringify(parsed);
  if (bounded.length <= maxLength) return bounded;

  // --- Tier 2: aggressive string truncation across the entire tree ---
  if (parsed.context !== undefined) {
    parsed.context = deepTruncateStrings(ctx, 150);
  } else {
    parsed = deepTruncateStrings(ctx, 150) as Record<string, unknown>;
  }
  bounded = JSON.stringify(parsed);
  if (bounded.length <= maxLength) return bounded;

  // --- Tier 3: last resort — hard truncate the raw JSON string ---
  // This produces invalid JSON but keeps the pipeline alive.  The model
  // receives a partial context; worst case it returns low-confidence output
  // which is safer than refusing to answer entirely.
  console.warn(
    `fitContextToLimit: hard-truncating context from ${bounded.length} to ${maxLength} chars`,
  );
  const chopped = bounded.slice(0, maxLength);
  try {
    JSON.parse(chopped);
  } catch {
    return JSON.stringify({ question, context: { warning: "context_hard_truncated" } });
  }
  return chopped;
}

export function compactContext(context: Record<string, unknown>): Record<string, unknown> {
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    const compressed = compactValue(value);
    if (compressed !== undefined) {
      const abbr = keyAbbreviations[key] ?? key;
      result[abbr] = compressed;
    }
  }
  return result;
}

export function selectRelevantContext(
  ctx: Record<string, unknown>,
  kind: string,
): Record<string, unknown> {
  const out = { ...ctx };
  if (kind === "recovery") {
    delete out["nutrition_targets"];
    delete out["nutrition_schedule"];
    delete out["today_confirmed_meals"];
    delete out["today_meal_schedule"];
  }
  if (kind === "nutrition_focus") {
    delete out["session_trends"];
    delete out["last_3_sessions_summary"];
    delete out["latest_healthkit"];
    delete out["today_healthkit"];
    delete out["seven_day_healthkit_trend"];
    delete out["training_week_structure"];
    delete out["schedule_slot_compliance"];
    delete out["eight_week_measurement_delta"];
  }
  if (kind === "daily_action") {
    delete out["meal_compliance"];
    delete out["eight_week_measurement_delta"];
    delete out["seven_day_healthkit_trend"];
  }
  if (kind === "explain_evidence") {
    delete out["today_confirmed_meals"];
    delete out["today_meal_schedule"];
    delete out["training_week_structure"];
  }
  return out;
}

const kindMaxBudget: Record<string, number> = {
  recovery: 64_000,
  nutrition_focus: 64_000,
  daily_action: 48_000,
  explain_evidence: 64_000,
  plan_change: 128_000,
  general: 48_000,
};

function str(v: unknown): string {
  if (v === null || v === undefined) return "—";
  if (typeof v === "boolean") return v ? "Yes" : "No";
  return String(v);
}

function obj(v: unknown): Record<string, unknown> {
  return v && typeof v === "object" && !Array.isArray(v) ? v as Record<string, unknown> : {};
}

function arr(v: unknown): unknown[] {
  return Array.isArray(v) ? v : [];
}

export function formatContextAsMarkdown(
  ctx: Record<string, unknown>,
  maxLength: number = 28_000,
): string {
  const out: string[] = [];
  let used = 0;

  const push = (s: string): boolean => {
    if (used + s.length > maxLength) return false;
    out.push(s);
    used += s.length;
    return true;
  };

  // 1. Active Training Plan
  const plan = obj(ctx.active_plan);
  if (Object.keys(plan).length) {
    let s = "## Active Training Plan\n";
    if (plan.title) s += `**${str(plan.title)}**`;
    if (plan.version_number != null) s += ` (v${str(plan.version_number)})`;
    if (plan.sessions_per_week != null) s += `, ${str(plan.sessions_per_week)} sessions/week`;
    s += "\n";
    if (plan.rationale) s += `${str(plan.rationale)}\n`;
    push(s);
  }

  // 2. Goal
  const goal = obj(ctx.active_goal);
  if (Object.keys(goal).length) {
    let s = "## Goal\n";
    const type = str(goal.type ?? goal.target_label ?? "Active Goal");
    s += `**${type}**`;
    if (goal.target_value != null) s += ` — target: ${str(goal.target_value)}`;
    if (goal.deadline) s += `, deadline: ${str(goal.deadline)}`;
    s += "\n";
    push(s);
  }

  // 3. Coaching Narrative
  const narrative = obj(ctx.coaching_narrative);
  if (Object.keys(narrative).length) {
    const active = obj(narrative.active);
    if (Object.keys(active).length) {
      let s = "## Coaching Narrative\n";
      s += `**${str(active.phase)}**: ${str(active.headline)}`;
      if (active.since) s += ` (since ${str(active.since)})`;
      s += "\n";
      push(s);
    }
  }

  // 4. Today's Check-In
  const checkIn = obj(ctx.latest_check_in) || obj(ctx.latest_check_in_detail);
  if (Object.keys(checkIn).length) {
    let s = "## Today's Check-In\n";
    const fields = [
      "local_date",
      "sleep_quality",
      "energy",
      "soreness",
      "hunger",
      "mood",
      "pain_severity",
      "available_to_train",
      "notes",
    ];
    for (const f of fields) {
      const v = checkIn[f];
      if (v != null) s += `- ${f.replace(/_/g, " ")}: ${str(v)}\n`;
    }
    push(s);
  }

  // 5. Recent Training
  const sessions = arr(
    ctx.session_trends ?? ctx.last_3_sessions_summary ?? ctx.focused_execution ??
      ctx.recent_execution ?? ctx.brief_sessions,
  );
  if (sessions.length) {
    let s = "## Recent Training\n";
    s += "| Date | Workout | Duration | Effort |\n";
    s += "|------|---------|----------|--------|\n";
    for (const ses of sessions.slice(0, 6)) {
      const o = obj(ses);
      s += `| ${str(o.local_date ?? o.d)} | ${str(o.prescribed_workout ?? o.workout ?? o.n)} | ${
        str(o.duration_seconds ?? o.dur)
      }s | ${str(o.effort ?? o.session_effort ?? o.eff)} |\n`;
    }
    push(s);
  }

  // 6. Health Metrics
  const health = obj(ctx.latest_healthkit ?? ctx.today_healthkit);
  const measurement = obj(ctx.latest_measurement);
  const weight = obj(ctx.latest_weight);
  const delta = obj(ctx.eight_week_measurement_delta);
  const trend = obj(ctx.seven_day_healthkit_trend);
  if (
    Object.keys(health).length || Object.keys(measurement).length || Object.keys(weight).length ||
    Object.keys(delta).length || Object.keys(trend).length
  ) {
    let s = "## Health Metrics\n";
    if (Object.keys(health).length) {
      const hkFields = [
        "resting_heart_rate_bpm",
        "hrv_sdnn_ms",
        "sleep_duration_hours",
        "sleep_minutes",
        "steps_count",
        "completeness",
      ];
      for (const f of hkFields) {
        const v = health[f];
        if (v != null) s += `- ${f.replace(/_/g, " ")}: ${str(v)}\n`;
      }
    }
    const meas = weight.weight_kg ?? measurement.weight_kg;
    if (meas != null) s += `- weight: ${str(meas)} kg\n`;
    if (measurement.body_fat_pct != null) s += `- body fat: ${str(measurement.body_fat_pct)}%\n`;
    if (weight.body_fat_pct != null) s += `- body fat: ${str(weight.body_fat_pct)}%\n`;
    const early = obj(delta.earliest);
    const late = obj(delta.latest);
    if (early.weight_kg != null && late.weight_kg != null) {
      s += `- 8-week change: ${str(early.weight_kg)} → ${str(late.weight_kg)} kg\n`;
    }
    if (trend.avg_resting_hr != null) s += `- avg RHR (7d): ${str(trend.avg_resting_hr)}\n`;
    if (trend.avg_hrv_sdnn != null) s += `- avg HRV (7d): ${str(trend.avg_hrv_sdnn)}\n`;
    if (trend.avg_sleep_minutes != null) {
      s += `- avg sleep (7d): ${str(trend.avg_sleep_minutes)} min\n`;
    }
    push(s);
  }

  // 7. Brief health (general kind fallback)
  const briefHealth = arr(ctx.brief_health);
  if (briefHealth.length) {
    const latest = obj(briefHealth[0]);
    if (latest.sleep_minutes != null || latest.resting_heart_rate_bpm != null) {
      let s = "## Health\n";
      if (latest.sleep_minutes != null) s += `- sleep: ${str(latest.sleep_minutes)} min\n`;
      if (latest.resting_heart_rate_bpm != null) {
        s += `- RHR: ${str(latest.resting_heart_rate_bpm)}\n`;
      }
      push(s);
    }
  }

  // 8. Nutrition Targets & Schedule
  const nutTargets = obj(ctx.nutrition_targets);
  const nutSchedule = arr(ctx.nutrition_schedule);
  if (Object.keys(nutTargets).length || nutSchedule.length) {
    let s = "## Nutrition\n";
    if (nutTargets.calories != null) {
      s += `Targets: ${str(nutTargets.calories)} kcal`;
      if (nutTargets.protein_g != null) s += `, ${str(nutTargets.protein_g)}g P`;
      if (nutTargets.carbohydrate_g != null) s += `, ${str(nutTargets.carbohydrate_g)}g C`;
      if (nutTargets.fat_g != null) s += `, ${str(nutTargets.fat_g)}g F`;
      s += "\n";
    }
    if (nutSchedule.length) {
      s += "Schedule: ";
      const slots = nutSchedule.map((sl) => {
        const sObj = obj(sl);
        const label = str(sObj.label ?? sObj.slot_key);
        const time = str(sObj.local_time);
        return `${label} (${time})`;
      });
      s += slots.join(", ") + "\n";
    }
    push(s);
  }

  // 9. Today's Meals (nutrition_focus kind)
  const meals = arr(ctx.today_confirmed_meals ?? ctx.today_meal_schedule);
  if (meals.length) {
    let s = "## Today's Meals\n";
    for (const meal of meals.slice(0, 3)) {
      const m = obj(meal);
      const foods = arr(m.foods);
      if (foods.length) {
        const items = foods.map((f) => {
          const fObj = obj(f);
          return str(fObj.food_name ?? fObj.food ?? fObj.f ?? fObj.name);
        }).join(", ");
        s += `- ${items}\n`;
      }
    }
    push(s);
  }

  // 10. Nutrition Compliance
  const compliance = obj(ctx.nutrition_compliance_7day);
  if (Object.keys(compliance).length) {
    let s = "## 7-Day Nutrition Compliance\n";
    if (compliance.avg_daily_calories != null) {
      s += `- avg calories: ${str(compliance.avg_daily_calories)}\n`;
    }
    if (compliance.avg_daily_protein_g != null) {
      s += `- avg protein: ${str(compliance.avg_daily_protein_g)}g\n`;
    }
    if (compliance.avg_daily_carbohydrate_g != null) {
      s += `- avg carbs: ${str(compliance.avg_daily_carbohydrate_g)}g\n`;
    }
    if (compliance.avg_daily_fat_g != null) s += `- avg fat: ${str(compliance.avg_daily_fat_g)}g\n`;
    if (compliance.days_with_meals != null) {
      s += `- days tracked: ${str(compliance.days_with_meals)}/7\n`;
    }
    push(s);
  }

  // 11. Training Week Structure (recovery kind)
  const tws = arr(ctx.training_week_structure);
  if (tws.length) {
    let s = "## Training Week Structure\n";
    for (const day of tws.slice(0, 7)) {
      const d = obj(day);
      s += `- ${str(d.preferred_weekday)} (week ${str(d.target_week)}): ${
        str(d.prescribed_workout ?? d.workout_name)
      }\n`;
    }
    push(s);
  }

  // 12. Session Journal (past coaching memory)
  const journal = arr(ctx.session_journal);
  if (journal.length) {
    let s = "## Session History\n";
    for (const entry of journal.slice(0, 5)) {
      const e = obj(entry);
      s += `- ${str(e.coaching_date)}: ${str(e.summary)}\n`;
    }
    push(s);
  }

  // 13. Recent Conversation
  const msgs = arr(ctx.recent_messages ?? ctx.recent_other_conversations);
  if (msgs.length) {
    let s = "## Recent Conversation\n";
    for (const msg of msgs.slice(0, 6)) {
      const m = obj(msg);
      const role = str(m.role).toUpperCase();
      const content = typeof m.content === "string" ? m.content : "";
      if (content) s += `**${role}:** ${content.slice(0, 300)}${content.length > 300 ? "…" : ""}\n`;
    }
    push(s);
  }

  // 14. Preferences
  const prefs = arr(ctx.active_preferences);
  if (prefs.length) {
    let s = "## Preferences\n";
    for (const pref of prefs.slice(0, 10)) {
      const p = obj(pref);
      s += `- ${str(p.category)}: ${str(p.key)} = ${str(p.value)} (${str(p.provenance)})\n`;
    }
    push(s);
  }

  // 15. Latest Decision
  const decision = obj(ctx.latest_decision);
  if (Object.keys(decision).length && decision.final_decision) {
    let s = "## Latest Decision\n";
    s += `**${str(decision.final_decision)}**`;
    if (decision.confidence != null) s += ` (confidence: ${str(decision.confidence)})`;
    if (decision.reason) s += `\n${str(decision.reason)}`;
    s += "\n";
    push(s);
  }

  // 16. Data Quality
  const quality = obj(ctx.data_quality);
  const coverage = obj(ctx.context_coverage);
  if (Object.keys(quality).length || Object.keys(coverage).length) {
    let s = "## Data Quality\n";
    if (quality.training_logging_coverage != null) {
      s += `- training coverage: ${str(quality.training_logging_coverage)}\n`;
    }
    if (quality.last_health_sync) s += `- last health sync: ${str(quality.last_health_sync)}\n`;
    if (quality.last_confirmed_meal) s += `- last meal: ${str(quality.last_confirmed_meal)}\n`;
    if (quality.conflict_count != null) s += `- conflicts: ${str(quality.conflict_count)}\n`;
    if (Object.keys(coverage).length) {
      const parts: string[] = [];
      for (const [k, v] of Object.entries(coverage)) {
        if (v) parts.push(k.replace(/_/g, " "));
      }
      if (parts.length) s += `- available: ${parts.join(", ")}\n`;
    }
    push(s);
  }

  // 17. Plan Proposals (plan_change kind)
  const proposals = arr(ctx.plan_proposals);
  if (proposals.length) {
    let s = "## Plan Proposals\n";
    for (const prop of proposals.slice(0, 3)) {
      const p = obj(prop);
      s += `- ${str(p.status)}: ${str(p.proposed_training ?? p.headline).slice(0, 200)}\n`;
    }
    push(s);
  }

  // 18. Nutrition Adherence
  const adherence = obj(ctx.nutrition_adherence);
  if (Object.keys(adherence).length) {
    let s = "## Nutrition Adherence\n";
    if (adherence.days_with_confirmed_meals_7d != null) {
      s += `- meal days: ${str(adherence.days_with_confirmed_meals_7d)}/7\n`;
    }
    if (adherence.confirmed_meal_count_7d != null) {
      s += `- meals confirmed: ${str(adherence.confirmed_meal_count_7d)}\n`;
    }
    push(s);
  }

  // 19. Permitted Evidence
  const evidence = arr(ctx.permitted_evidence);
  if (evidence.length) {
    push(`## Evidence Permitted\n${evidence.map((e) => `- ${str(e)}`).join("\n")}\n`);
  }

  return out.join("\n");
}

export function classifyQuestion(question: string): string {
  const q = question.toLowerCase();
  if (
    /weekly|new plan|change.{1,20}plan|plateau|progression|next block|program|routine|split|deload|periodiz/
      .test(q)
  ) return "plan_change";
  if (
    /recovery|rest|sleep|sore|fatigue|injur|hurt|pain|sick|fever|cold|ill|stress|energy/.test(q)
  ) return "recovery";
  if (
    /evidence|data|missing|gap|what's|explain|why|health|summary|trend|progress|tracking|logged|physique|visual progress|photo comparison|body composition/
      .test(q)
  ) return "explain_evidence";
  if (
    /nutrition|food|eat|diet|calories|protein|macro|meal|carb|fat|fiber|sodium|sugar|adherence|compliance|sticking to|diet plan/
      .test(q)
  ) return "nutrition_focus";
  if (/next|today|train|workout|schedule/.test(q)) {
    return "daily_action";
  }
  return "general";
}

export function isCoachChatLiveProviderConfigured(
  environment: Pick<typeof Deno.env, "get">,
): boolean {
  const enabled = environment.get("COACH_AI_ENABLED") === "true";
  const provider = environment.get("COACH_MODEL_PROVIDER") ?? "mock";
  if (provider === "groq") {
    return enabled && Boolean(environment.get("GROQ_API_KEY")) &&
      environment.get("GROQ_MODEL") === "qwen/qwen3.6-27b";
  }
  if (provider === "deepseek") {
    return enabled && Boolean(environment.get("DEEPSEEK_API_KEY")) &&
      environment.get("DEEPSEEK_MODEL") === "deepseek-v4-flash";
  }
  return provider === "gemini" && enabled &&
    environment.get("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true" &&
    Boolean(environment.get("GEMINI_API_KEY")) &&
    environment.get("GEMINI_MODEL") === "gemini-3.5-flash";
}

export async function generateCoachChat(
  question: string,
  context: Record<string, unknown>,
  contextKind: string = "general",
  fetcher: typeof fetch = fetch,
): Promise<CoachChatGeneration> {
  const boundary = deterministicBoundary(question);
  if (boundary) {
    return {
      answer: boundary,
      provider: "mock",
      model: "deterministic-safety-v1",
      inputUnits: 0,
      outputUnits: 0,
      estimatedCostUsd: 0,
    };
  }

  const enabled = Deno.env.get("COACH_AI_ENABLED") === "true";
  const provider = Deno.env.get("COACH_MODEL_PROVIDER") ?? "mock";
  const paid = Deno.env.get("GEMINI_PAID_DATA_TERMS_ACCEPTED") === "true";
  const key = Deno.env.get("GEMINI_API_KEY") ?? "";
  const model = Deno.env.get("GEMINI_MODEL") ?? "";
  const policyEvidence = Array.isArray(context.permitted_evidence)
    ? context.permitted_evidence.filter((item): item is string => typeof item === "string")
    : [];
  const permitted = [...new Set([...policyEvidence, ...collectEvidenceIds(context)])];
  const groqKey = Deno.env.get("GROQ_API_KEY") ?? "";
  const groqModel = Deno.env.get("GROQ_MODEL") ?? "";
  const groqEnabled = provider === "groq" && enabled && groqKey && groqModel === "qwen/qwen3.6-27b";
  const deepseekKey = Deno.env.get("DEEPSEEK_API_KEY") ?? "";
  const deepseekModel = Deno.env.get("DEEPSEEK_MODEL") ?? "";
  const deepseekEnabled = provider === "deepseek" && enabled && deepseekKey &&
    deepseekModel === "deepseek-v4-flash";
  const geminiEnabled = provider === "gemini" && enabled && paid && key &&
    model === "gemini-3.5-flash";
  if (
    !isCoachChatLiveProviderConfigured(Deno.env) ||
    (!groqEnabled && !deepseekEnabled && !geminiEnabled)
  ) {
    throw new CoachChatUnavailableError(
      "mock",
      "provider_not_configured",
      "ai_disabled_or_unconfigured",
    );
  }
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 25_000);
  try {
    const ctx = context as Record<string, unknown>;
    if (deepseekEnabled) {
      const kindBudget = kindMaxBudget[contextKind] ?? 64_000;
      const focused = selectRelevantContext(ctx, contextKind);
      const contextMarkdownDs = formatContextAsMarkdown(focused, kindBudget);
      const dsUserMessage = question + "\n\n---\n\n<coaching_context>\n" +
        contextMarkdownDs + "\n</coaching_context>";
      console.log(
        `coach-chat deepseek: kind=${contextKind} budget=${kindBudget} original=${
          JSON.stringify(ctx).length
        } filtered=${contextMarkdownDs.length}`,
      );
      const bounded = dsUserMessage.length > kindBudget
        ? dsUserMessage.slice(0, kindBudget)
        : dsUserMessage;
      const useThinking = contextKind === "plan_change";
      const request = async (repair: boolean) => {
        const response = await fetcher("https://api.deepseek.com/v1/chat/completions", {
          method: "POST",
          signal: controller.signal,
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${deepseekKey}`,
          },
          body: JSON.stringify({
            model: deepseekModel,
            ...(useThinking ? {} : { temperature: 0.2 }),
            max_tokens: 2000,
            response_format: { type: "json_object" },
            ...(useThinking
              ? { reasoning_effort: "high", thinking: { type: "enabled" } }
              : { thinking: { type: "disabled" } }),
            messages: [
              {
                role: "system",
                content:
                  "You are Tracend, an experienced personal fitness coach who has been working with this athlete through their journey. You know their training history, preferences, setbacks, and wins. Your coaching balances evidence with empathy — you use data to inform, never to judge.\n" +
                  "\n" +
                  "# Coaching approach\n" +
                  "1. Start with the person, not the data. Acknowledge their question, feelings, or situation before referencing metrics.\n" +
                  "2. Build a mental timeline. Connect what they are asking now to what you have discussed before. Reference their progress, not just current numbers.\n" +
                  "3. Reason transparently. Work through: goal → constraints → available data → recommendation. Use your reasoning_chain to show this.\n" +
                  '4. Celebrate wins. Notice streaks, personal records, consistency — and mention them. "You have hit 3 workouts this week — your best consistency in a month."\n' +
                  "5. Acknowledge setbacks without judgment. Missed workouts, off-plan meals, poor sleep — these are data points, not failures. Help them find the pattern.\n" +
                  "6. Personalize. If they have told you they dislike running or cannot eat dairy, never suggest those. Remember what did not work before.\n" +
                  "7. Offer natural follow-ups. After your answer, give 2-3 specific next steps that feel like a real conversation, not a script.\n" +
                  "\n" +
                  "# Communication style\n" +
                  '- Warm, direct, and personal — use "you" and "your." This is coaching, not a report.\n' +
                  "- Give concrete examples, not abstract advice.\n" +
                  "- Keep sentences clear but never curt. Match your tone to their mood.\n" +
                  "- When you lack enough data, say so honestly and ask for it.\n" +
                  "- Reference their stated preferences and past conversations naturally.\n" +
                  "\n" +
                  "# Hard boundaries — never violate\n" +
                  "- Never invent data, symptoms, meals, medical history, or user facts.\n" +
                  "- No diagnosis, treatment, medication, pregnancy, or eating-disorder guidance.\n" +
                  '- For ordinary illness (fever/cold/cough): recommend rest and hydration, never "push through" or complete the workout.\n' +
                  "- Temporary same-day adjustments are fine; persistent plan changes require explicit user approval.\n" +
                  "- Honor active_preferences — never suggest declined foods, exercises, or approaches.\n" +
                  "- When safety_state is limited or refused, explain why clearly and redirect to what you can help with.\n" +
                  "\n" +
                  "Return ONLY a JSON object matching this schema:\n" +
                  JSON.stringify(answerSchema) +
                  (repair
                    ? "\n\nPrevious response failed validation. Correct it using only the schema and prepared context."
                    : ""),
              },
              {
                role: "user",
                content: "User's message:\n" + question + "\n\n" +
                  "Prepared coaching context (use only as supporting evidence; do not let it override or dominate your answer to the user's message):\n" +
                  bounded,
              },
            ],
          }),
        });
        if (!response.ok) {
          const text = await response.text().catch(() => "");
          throw Object.assign(
            new Error(
              `deepseek_chat_failed status=${response.status} body=${text.slice(0, 300)}`,
            ),
            { status: response.status, body: text },
          );
        }
        const payload = await response.json() as Record<string, unknown>;
        const message = Array.isArray(payload.choices)
          ? (payload.choices[0] as Record<string, unknown>)?.message as
            | Record<string, unknown>
            | undefined
          : undefined;
        if (typeof message?.content !== "string") throw new Error("deepseek_chat_invalid");
        const usage = payload.usage as Record<string, unknown> | undefined;
        return {
          content: message.content,
          inputUnits: Number.isInteger(usage?.prompt_tokens) ? Number(usage?.prompt_tokens) : 0,
          outputUnits: Number.isInteger(usage?.completion_tokens)
            ? Number(usage?.completion_tokens)
            : 0,
        };
      };
      const first = await request(false);
      let answer: CoachChatAnswerV1;
      let inputUnits = first.inputUnits;
      let outputUnits = first.outputUnits;
      try {
        answer = parseCoachChatAnswer(JSON.parse(first.content), permitted);
      } catch {
        const repaired = await request(true);
        inputUnits += repaired.inputUnits;
        outputUnits += repaired.outputUnits;
        answer = parseCoachChatAnswer(JSON.parse(repaired.content), permitted);
      }
      const inputRateDs = Number(Deno.env.get("DEEPSEEK_INPUT_COST_PER_MILLION_USD") ?? "0.14");
      const outputRateDs = Number(Deno.env.get("DEEPSEEK_OUTPUT_COST_PER_MILLION_USD") ?? "0.28");
      return {
        answer,
        provider: "deepseek",
        model: deepseekModel,
        inputUnits,
        outputUnits,
        estimatedCostUsd: (inputUnits * inputRateDs + outputUnits * outputRateDs) / 1_000_000,
      };
    }
    if (groqEnabled) {
      const compacted = compactContext(ctx);
      let bounded = JSON.stringify({ question, context: compacted });
      console.log(
        `coach-chat context: original=${JSON.stringify(ctx).length} compacted=${bounded.length}`,
      );
      bounded = fitContextToLimit(bounded, 4_000, question);
      let reasoningInputUnits = 0;
      let reasoningOutputUnits = 0;
      const planningQuestion = /weekly|new plan|change (my )?plan|plateau|progression|next block/i
        .test(question);
      if (planningQuestion) {
        const reasoningResponse = await fetcher(
          "https://api.groq.com/openai/v1/chat/completions",
          {
            method: "POST",
            signal: controller.signal,
            headers: {
              "Content-Type": "application/json",
              Authorization: `Bearer ${groqKey}`,
            },
            body: JSON.stringify({
              model: groqModel,
              temperature: 0.1,
              max_completion_tokens: 1200,
              reasoning_effort: "high",
              reasoning_format: "hidden",
              response_format: { type: "json_object" },
              messages: [{
                role: "user",
                content:
                  "Analyze this personal training question using only the supplied context. Separate adherence, incomplete logging, recovery constraints, and ineffective programming. Return JSON with exactly analysis (string), evidence_ids (array using supplied evidence_id values), and recommendation (maintain, gather_data, or propose_change). Do not claim a persistent change.\n\n" +
                  bounded,
              }],
            }),
          },
        );
        if (!reasoningResponse.ok) {
          const text = await reasoningResponse.text().catch(() => "");
          throw Object.assign(
            new Error(
              `groq_chat_reasoning_failed status=${reasoningResponse.status} body=${
                text.slice(0, 300)
              }`,
            ),
            { status: reasoningResponse.status, body: text },
          );
        }
        const reasoningPayload = await reasoningResponse.json() as Record<string, unknown>;
        const reasoningMessage = Array.isArray(reasoningPayload.choices)
          ? (reasoningPayload.choices[0] as Record<string, unknown>)?.message as
            | Record<string, unknown>
            | undefined
          : undefined;
        if (typeof reasoningMessage?.content !== "string") {
          throw new Error("groq_chat_reasoning_invalid");
        }
        const analysis = JSON.parse(reasoningMessage.content) as Record<string, unknown>;
        if (
          Object.keys(analysis).sort().join(",") !== "analysis,evidence_ids,recommendation" ||
          typeof analysis.analysis !== "string" || analysis.analysis.length > 6000 ||
          !Array.isArray(analysis.evidence_ids) ||
          !analysis.evidence_ids.every((id) => typeof id === "string" && permitted.includes(id)) ||
          !["maintain", "gather_data", "propose_change"].includes(String(analysis.recommendation))
        ) throw new Error("groq_chat_reasoning_invalid");
        const usage = reasoningPayload.usage as Record<string, unknown> | undefined;
        reasoningInputUnits = Number.isInteger(usage?.prompt_tokens)
          ? Number(usage?.prompt_tokens)
          : 0;
        reasoningOutputUnits = Number.isInteger(usage?.completion_tokens)
          ? Number(usage?.completion_tokens)
          : 0;
        bounded = JSON.stringify({ question, context: ctx, validated_analysis: analysis });
      }
      const request = async (repair: boolean) => {
        const response = await fetcher("https://api.groq.com/openai/v1/chat/completions", {
          method: "POST",
          signal: controller.signal,
          headers: { "Content-Type": "application/json", Authorization: `Bearer ${groqKey}` },
          body: JSON.stringify({
            model: groqModel,
            temperature: 0.2,
            max_completion_tokens: 2000,
            reasoning_effort: "none",
            reasoning_format: "hidden",
            response_format: { type: "json_object" },
            messages: [
              {
                role: "system",
                content:
                  "You are Tracend, an experienced personal fitness coach who has been working with this athlete through their journey. You know their training history, preferences, setbacks, and wins. Your coaching balances evidence with empathy — you use data to inform, never to judge.\n" +
                  "\n" +
                  "# Coaching approach\n" +
                  "1. Start with the person, not the data. Acknowledge their question, feelings, or situation before referencing metrics.\n" +
                  "2. Build a mental timeline. Connect what they are asking now to what you have discussed before. Reference their progress, not just current numbers.\n" +
                  "3. Reason transparently. Work through: goal → constraints → available data → recommendation. Use your reasoning_chain to show this.\n" +
                  '4. Celebrate wins. Notice streaks, personal records, consistency — and mention them. "You have hit 3 workouts this week — your best consistency in a month."\n' +
                  "5. Acknowledge setbacks without judgment. Missed workouts, off-plan meals, poor sleep — these are data points, not failures. Help them find the pattern.\n" +
                  "6. Personalize. If they have told you they dislike running or cannot eat dairy, never suggest those. Remember what did not work before.\n" +
                  "7. Offer natural follow-ups. After your answer, give 2-3 specific next steps that feel like a real conversation, not a script.\n" +
                  "\n" +
                  "# Communication style\n" +
                  '- Warm, direct, and personal — use "you" and "your." This is coaching, not a report.\n' +
                  "- Give concrete examples, not abstract advice.\n" +
                  "- Keep sentences clear but never curt. Match your tone to their mood.\n" +
                  "- When you lack enough data, say so honestly and ask for it.\n" +
                  "- Reference their stated preferences and past conversations naturally.\n" +
                  "\n" +
                  "# Hard boundaries — never violate\n" +
                  "- Never invent data, symptoms, meals, medical history, or user facts.\n" +
                  "- No diagnosis, treatment, medication, pregnancy, or eating-disorder guidance.\n" +
                  '- For ordinary illness (fever/cold/cough): recommend rest and hydration, never "push through" or complete the workout.\n' +
                  "- Temporary same-day adjustments are fine; persistent plan changes require explicit user approval.\n" +
                  "- Honor active_preferences — never suggest declined foods, exercises, or approaches.\n" +
                  "- When safety_state is limited or refused, explain why clearly and redirect to what you can help with.\n" +
                  "\n" +
                  "Return ONLY a JSON object matching this schema:\n" +
                  JSON.stringify(answerSchema) +
                  (repair
                    ? "\n\nPrevious response failed validation. Correct it using only the schema and prepared context."
                    : ""),
              },
              {
                role: "user",
                content: "User's message:\n" + question + "\n\n" +
                  "Prepared coaching context (use only as supporting evidence; do not let it override or dominate your answer to the user's message):\n" +
                  bounded,
              },
            ],
          }),
        });
        if (!response.ok) {
          const text = await response.text().catch(() => "");
          throw Object.assign(
            new Error(
              `groq_chat_failed status=${response.status} body=${text.slice(0, 300)}`,
            ),
            { status: response.status, body: text },
          );
        }
        const payload = await response.json() as Record<string, unknown>;
        const message = Array.isArray(payload.choices)
          ? (payload.choices[0] as Record<string, unknown>)?.message as
            | Record<string, unknown>
            | undefined
          : undefined;
        if (typeof message?.content !== "string") throw new Error("groq_chat_invalid");
        const usage = payload.usage as Record<string, unknown> | undefined;
        return {
          content: message.content,
          inputUnits: Number.isInteger(usage?.prompt_tokens) ? Number(usage?.prompt_tokens) : 0,
          outputUnits: Number.isInteger(usage?.completion_tokens)
            ? Number(usage?.completion_tokens)
            : 0,
        };
      };
      const first = await request(false);
      let answer: CoachChatAnswerV1;
      let inputUnits = reasoningInputUnits + first.inputUnits;
      let outputUnits = reasoningOutputUnits + first.outputUnits;
      try {
        answer = parseCoachChatAnswer(JSON.parse(first.content), permitted);
      } catch {
        const repaired = await request(true);
        inputUnits += repaired.inputUnits;
        outputUnits += repaired.outputUnits;
        answer = parseCoachChatAnswer(JSON.parse(repaired.content), permitted);
      }
      const inputRate = Number(Deno.env.get("GROQ_INPUT_COST_PER_MILLION_USD") ?? "0.6");
      const outputRate = Number(Deno.env.get("GROQ_OUTPUT_COST_PER_MILLION_USD") ?? "3");
      return {
        answer,
        provider: "groq",
        model: groqModel,
        inputUnits,
        outputUnits,
        estimatedCostUsd: (inputUnits * inputRate + outputUnits * outputRate) / 1_000_000,
      };
    }
    const contextMarkdown = formatContextAsMarkdown(ctx, 28_000);
    const geminiUserMessage = question + "\n\n---\n\n<coaching_context>\n" +
      contextMarkdown + "\n</coaching_context>";
    console.log(
      `coach-chat context: original=${
        JSON.stringify(ctx).length
      } markdown=${geminiUserMessage.length}`,
    );
    const userMessage = geminiUserMessage.length > 32_000
      ? geminiUserMessage.slice(0, 32_000)
      : geminiUserMessage;
    if (geminiUserMessage.length > 32_000) {
      console.warn(
        `coach-chat: userMessage exceeded 32K (${geminiUserMessage.length}), hard-truncated`,
      );
    }
    const response = await fetcher(
      `https://generativelanguage.googleapis.com/v1beta/models/${
        encodeURIComponent(model)
      }:generateContent`,
      {
        method: "POST",
        signal: controller.signal,
        headers: { "Content-Type": "application/json", "x-goog-api-key": key },
        body: JSON.stringify({
          systemInstruction: {
            parts: [{
              text:
                "You are Tracend, an experienced personal fitness coach who has been working with this athlete through their journey. You know their training history, preferences, setbacks, and wins. Your coaching balances evidence with empathy — you use data to inform, never to judge.\n" +
                "\n" +
                "# Coaching approach\n" +
                "1. Start with the person, not the data. Acknowledge their question, feelings, or situation before referencing metrics.\n" +
                "2. Build a mental timeline. Connect what they are asking now to what you have discussed before. Reference their progress, not just current numbers.\n" +
                "3. Reason transparently. Work through: goal → constraints → available data → recommendation. Use your reasoning_chain to show this.\n" +
                '4. Celebrate wins. Notice streaks, personal records, consistency — and mention them. "You have hit 3 workouts this week — your best consistency in a month."\n' +
                "5. Acknowledge setbacks without judgment. Missed workouts, off-plan meals, poor sleep — these are data points, not failures. Help them find the pattern.\n" +
                "6. Personalize. If they have told you they dislike running or cannot eat dairy, never suggest those. Remember what did not work before.\n" +
                "7. Offer natural follow-ups. After your answer, give 2-3 specific next steps that feel like a real conversation, not a script.\n" +
                "\n" +
                "# Communication style\n" +
                '- Warm, direct, and personal — use "you" and "your." This is coaching, not a report.\n' +
                "- Give concrete examples, not abstract advice.\n" +
                "- Keep sentences clear but never curt. Match your tone to their mood.\n" +
                "- When you lack enough data, say so honestly and ask for it.\n" +
                "- Reference their stated preferences and past conversations naturally.\n" +
                "\n" +
                "# Hard boundaries — never violate\n" +
                "- Never invent data, symptoms, meals, medical history, or user facts.\n" +
                "- No diagnosis, treatment, medication, pregnancy, or eating-disorder guidance.\n" +
                '- For ordinary illness (fever/cold/cough): recommend rest and hydration, never "push through" or complete the workout.\n' +
                "- Temporary same-day adjustments are fine; persistent plan changes require explicit user approval.\n" +
                "- Honor active_preferences — never suggest declined foods, exercises, or approaches.\n" +
                "- When safety_state is limited or refused, explain why clearly and redirect to what you can help with.\n" +
                "\n" +
                "Return ONLY a JSON object matching this schema:\n" +
                JSON.stringify(answerSchema),
            }],
          },
          contents: [{
            role: "user",
            parts: [{
              text: userMessage,
            }],
          }],
          generationConfig: {
            temperature: 0.15,
            maxOutputTokens: 2200,
            responseMimeType: "application/json",
            responseJsonSchema: answerSchema,
            thinkingConfig: { thinkingLevel: "medium" },
          },
        }),
      },
    );
    if (!response.ok) {
      const geminiBody = await response.text().catch(() => "");
      throw Object.assign(
        new Error(
          `gemini_chat_failed status=${response.status} body=${geminiBody.slice(0, 300)}`,
        ),
        { status: response.status, body: geminiBody },
      );
    }
    const payload = await response.json() as Record<string, unknown>;
    const candidates = payload.candidates;
    const parts = Array.isArray(candidates)
      ? ((candidates[0] as Record<string, unknown>)?.content as Record<string, unknown> | undefined)
        ?.parts
      : undefined;
    if (!Array.isArray(parts) || typeof (parts[0] as Record<string, unknown>)?.text !== "string") {
      throw new Error("gemini_chat_invalid");
    }
    const parsed = parseCoachChatAnswer(
      JSON.parse((parts[0] as Record<string, string>).text),
      permitted,
    );
    const usage = payload.usageMetadata as Record<string, unknown> | undefined;
    const inputUnits = Number.isInteger(usage?.promptTokenCount)
      ? Number(usage?.promptTokenCount)
      : 0;
    const outputUnits = Number.isInteger(usage?.candidatesTokenCount)
      ? Number(usage?.candidatesTokenCount)
      : 0;
    const inputRate = Number(Deno.env.get("GEMINI_INPUT_COST_PER_MILLION_USD") ?? "1.5");
    const outputRate = Number(Deno.env.get("GEMINI_OUTPUT_COST_PER_MILLION_USD") ?? "9");
    return {
      answer: parsed,
      provider: "gemini",
      model,
      inputUnits,
      outputUnits,
      estimatedCostUsd: (inputUnits * inputRate + outputUnits * outputRate) / 1_000_000,
    };
  } catch (inner) {
    const cause = inner instanceof Error ? inner.message : String(inner);
    let retryAfter: number | null = null;
    if (inner instanceof Error && "status" in inner) {
      const err = inner as Error & { status: number; body?: string };
      if (err.status === 429) {
        const body = err.body ?? cause;
        const groqMatch = body.match(/try again in ([\d.]+)s/i);
        if (groqMatch) {
          retryAfter = Math.ceil(parseFloat(groqMatch[1]));
        } else if (body.includes("RESOURCE_EXHAUSTED") || body.includes("429")) {
          retryAfter = 60;
        }
      }
    }
    throw new CoachChatUnavailableError(
      provider === "groq"
        ? "groq"
        : provider === "deepseek"
        ? "deepseek"
        : provider === "gemini"
        ? "gemini"
        : "mock",
      provider === "groq"
        ? groqModel || "unconfigured"
        : provider === "deepseek"
        ? deepseekModel || "unconfigured"
        : model || "unconfigured",
      cause,
      retryAfter,
    );
  } finally {
    clearTimeout(timeout);
  }
}
