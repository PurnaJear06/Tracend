// What in the athlete file may ground a figure in a reply's numbers check, key by key. The file
// holds the athlete's records and Tracend's calculations, and a few fields a model wrote: the
// reason on the active plan (the onboarding plan's), the latest daily decision, and the last
// proposals the athlete was shown (legacy ones were a model's, and none of them is a target while
// it is pending or declined). Those are shown to Coach and ground nothing, so that a figure that
// only they hold must come from a record. `contextForGrounds` is the file as it grounds; the file
// itself (`renderCoachContextParts`) is unchanged.
//
// Every key the file reads is declared here. `context_grounding_test.ts` records the keys the
// renderer reads, puts a marker in every field of a full context and checks that each field that
// is shown is declared and grounds exactly as declared; a new section or a new field fails it
// until its author states what it is.
//
//   records       the athlete's records, Tracend's calculations, what the athlete wrote or approved
//   modelText     a model wrote it (or it is a proposal, not a target): shown, grounds nothing
//   conversation  the conversation memory: it is not in the file and has its own rules
//                 (the athlete's words ground, Coach's never do, a data summary only on its day)
//   fields        the key mixes both: the fields listed in `records` ground, those in `modelText` do not
export type ContextKeyGrounding =
  | "records"
  | "modelText"
  | "conversation"
  | Readonly<{ records: readonly string[]; modelText: readonly string[] }>;

export const contextGrounding: Readonly<Record<string, ContextKeyGrounding>> = Object.freeze({
  coaching_date: "records",
  training_week_structure: "records",
  latest_check_in: "records",
  d: "records",
  permitted_evidence: "records",
  computed_metrics: "records",
  profile_context: "records",
  plan_status: "records",
  active_goal: "records",
  check_ins_14d: "records",
  training_totals: "records",
  training_log_28d: "records",
  watch_workouts_14d: "records",
  session_trends: "records",
  last_3_sessions_summary: "records",
  focused_execution: "records",
  recent_execution: "records",
  brief_sessions: "records",
  health_daily_28d: "records",
  health_averages: "records",
  weight_series_8w: "records",
  measurement_history: "records",
  latest_healthkit: "records",
  today_healthkit: "records",
  latest_measurement: "records",
  latest_weight: "records",
  eight_week_measurement_delta: "records",
  seven_day_healthkit_trend: "records",
  brief_health: "records",
  nutrition_targets: "records",
  data_quality: "records",
  context_coverage: "records",
  omitted_sections: "records",
  // The plan's sessions per week and version are the approved plan; its title and the reason for
  // it were written with the onboarding model.
  active_plan: {
    records: ["version_number", "sessions_per_week"],
    modelText: ["title", "rationale"],
  },
  // A model's words about an earlier day: their figures were true then.
  latest_decision: "modelText",
  // The last three proposals, any status and any schema: a pending or declined one is not a target,
  // and a legacy one is a model's. An applied one is in the plan and the targets above.
  plan_proposals: "modelText",
  recent_messages: "conversation",
  recent_other_conversations: "conversation",
});

/** The paths of a mixed key that a model wrote, or the whole key when it is all model text. */
const removed = (key: string, rule: ContextKeyGrounding): readonly string[] =>
  rule === "modelText"
    ? [key]
    : typeof rule === "object"
    ? rule.modelText.map((p) => `${key}.${p}`)
    : [];

function without(node: unknown, steps: string[]): unknown {
  if (steps.length === 0) return undefined;
  if (Array.isArray(node)) return node.map((item) => without(item, steps));
  if (node === null || typeof node !== "object") return node;
  const [step, ...rest] = steps;
  const copy = { ...(node as Record<string, unknown>) };
  if (rest.length === 0) delete copy[step];
  else if (step in copy) copy[step] = without(copy[step], rest);
  return copy;
}

/** The context with the fields a model wrote left out: what the numbers check may ground on. */
export function contextForGrounds(
  context: Record<string, unknown>,
  rules: Readonly<Record<string, ContextKeyGrounding>> = contextGrounding,
): Record<string, unknown> {
  let result: Record<string, unknown> = context;
  for (const [key, rule] of Object.entries(rules)) {
    if (!(key in context)) continue;
    for (const path of removed(key, rule)) {
      result = without(result, path.split(".")) as Record<string, unknown>;
    }
  }
  return result;
}
