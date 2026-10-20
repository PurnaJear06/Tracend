// What in the athlete file may ground a figure in a reply's numbers check, key by key, in the
// three words of `../grounding.ts`. The file holds the athlete's records and Tracend's calculations,
// and a few fields a model wrote: the reason on the active plan (the onboarding model's), the latest
// daily decision, and the last proposals the athlete was shown (a pending or declined one is not a
// target, and a legacy one was a model's). Those are shown to Coach and ground nothing, so a figure
// that only they hold must come from a record. A pending proposal Tracend built grounds a figure
// through the `coach_proposals` contributor (`coach_context/contributors/proposals.ts`), which
// states its figures as proposal figures. `contextForGrounds` is the file as it grounds; the file
// itself (`renderCoachContextParts`) is unchanged.
//
// A key that is not declared grounds nothing, and so does a field of a mixed key that is not
// declared. `context_grounding_test.ts` records the keys and fields the renderer reads, changes
// every field of a full context and checks that each one that is shown is declared and grounds
// exactly as declared; a new section or a new field fails it until its author states what it is.
//
//   records       the athlete's records, Tracend's calculations, what the athlete wrote or approved
//   modelText     a model wrote it (or it is a proposal, not a target): shown, grounds nothing
//   notInFile     read into the part of the context that is not the file: the conversation memory,
//                 which has its own rules (the athlete's words ground, Coach's never do, a data
//                 summary only on its day), and the notice of what was left out for size
//   a declaration the key mixes kinds: the paths listed ground as declared, the rest nothing
import { type Declaration, pruneTo, resolve } from "../grounding.ts";

export type ContextKeyGrounding = "records" | "modelText" | "notInFile" | Declaration;

export const contextGrounding: Readonly<Record<string, ContextKeyGrounding>> = Object.freeze<
  Record<string, ContextKeyGrounding>
>({
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
  // The plan's version and sessions per week are the approved plan, and so is its title (the app
  // shows it); the reason for it was written with the onboarding model.
  active_plan: {
    records: ["active_plan.version_number", "active_plan.sessions_per_week"],
    columns: {
      "active_plan.title": "training_plans.title",
      "active_plan.rationale": "training_plan_versions.rationale",
    },
  },
  // A model's words about an earlier day: their figures were true then.
  latest_decision: "modelText",
  // The last three proposals, any status and any schema: a pending or declined one is not a target,
  // and a legacy one is a model's. An applied one is in the plan and the targets above.
  plan_proposals: "modelText",
  omitted_sections: "notInFile",
  recent_messages: "notInFile",
  recent_other_conversations: "notInFile",
});

/**
 * The context as it grounds: whole for a key of records, cut down to the declared fields for a
 * mixed key, and without the key for model text, the conversation and any key not declared.
 */
export function contextForGrounds(
  context: Record<string, unknown>,
  rules: Readonly<Record<string, ContextKeyGrounding>> = contextGrounding,
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(context)) {
    const rule = rules[key];
    if (rule === "records") out[key] = value;
    else if (typeof rule === "object") {
      const kept = resolve(rule);
      out[key] = pruneTo(value, new Set([...kept.records, ...kept.controls]), key);
    }
  }
  return out;
}
