// Contract 7 contributor: the athlete's pre-exercise screening outcome (Contract 8, chunk B6) and
// the rule it implies for Coach. The outcome caps what Coach may advise: under
// moderate_until_cleared no vigorous or maximal effort, under see_professional no training
// prescriptions at all. Coach explains and follows the rule; it never sets, changes or softens
// the outcome. A stable contributor: the outcome changes only when the athlete answers the
// health check again, so it joins the cached prompt prefix.
//
// The reply guard (coach_safety/reply_guard.ts) reads the same outcome from the rendered block
// (`screeningOutcomeIn`), so the model and the guard always work from one value.
import { type ScreeningOutcome, screeningOutcomes } from "../../training/screening/outcome.ts";
import type { CoachContextContributor } from "../host.ts";

export const screeningContributorId = "screening";
export const screeningBudgetChars = 900;

export type ScreeningRecord = Readonly<{ outcome: ScreeningOutcome; screenedAt: string }>;

/** The athlete's newest screening, or null when they were never screened (reads as cleared). */
export type ScreeningSource = (userId: string) => Promise<ScreeningRecord | null>;

/** The query the source makes, typed structurally so any Supabase client fits. */
export type ScreeningQuery = (userId: string) => PromiseLike<{
  data: Readonly<{ outcome: string; screened_at: string }> | null;
  error: unknown;
}>;

export function screeningSourceFromQuery(query: ScreeningQuery): ScreeningSource {
  return async (userId) => {
    const { data, error } = await query(userId);
    if (error) throw new Error("screening unavailable");
    const outcome = screeningOutcomes.find((candidate) => candidate === data?.outcome);
    return data && outcome ? { outcome, screenedAt: data.screened_at } : null;
  };
}

/**
 * The source for Edge Functions: a service-role client built on first use, so importing the
 * registry needs no environment (tests, type checks). A missing key fails the turn's contributor,
 * which the host leaves out.
 */
export function serviceRoleScreeningSource(): ScreeningSource {
  let source: ScreeningSource | undefined;
  return async (userId) => {
    if (!source) {
      const url = Deno.env.get("SUPABASE_URL");
      const key = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
      if (!url || !key) throw new Error("service role is not configured");
      const { createClient } = await import("npm:@supabase/supabase-js@2.49.8");
      const client = createClient(url, key, { auth: { persistSession: false } });
      source = screeningSourceFromQuery((id) =>
        client.from("onboarding_screenings").select("outcome,screened_at").eq("user_id", id)
          .order("screened_at", { ascending: false }).order("id", { ascending: false }).limit(1)
          .maybeSingle()
      );
    }
    return source(userId);
  };
}

const rules: Readonly<Record<ScreeningOutcome, string>> = {
  cleared:
    "Rule: the health check puts no cap on effort. Follow the Safe Ranges and the athlete's plan as usual.",
  moderate_until_cleared:
    "Rule: keep every suggestion at moderate effort until a professional clears the athlete: no maximal or near-failure sets (at least 3 reps in reserve), no vigorous conditioning (sprints, intervals, HIIT), no strength-emphasis advice. When the athlete asks to push harder, recommend getting clearance first. Never diagnose.",
  see_professional:
    "Rule: the athlete must see a doctor or qualified exercise professional before training. Give no training prescriptions of any kind (no workouts, sets, reps, loads, cardio targets or effort advice). Recommend getting clearance first. Recovery, sleep and food questions may be answered in general terms.",
};

/** The block's text for a screening, or null without one (never screened reads as cleared). */
export function renderScreening(record: ScreeningRecord | null): string | null {
  if (!record) return null;
  return [
    `Pre-exercise health check, answered on ${
      record.screenedAt.slice(0, 10)
    }. Tracend calculated the outcome from the athlete's answers; you never change it.`,
    `Outcome: ${record.outcome}`,
    rules[record.outcome],
  ].join("\n");
}

const outcomeLine = new RegExp(
  String.raw`<reference_data source="${screeningContributorId}">[\s\S]*?^Outcome: (${
    screeningOutcomes.join("|")
  })$`,
  "m",
);

/** The outcome in rendered contributor text; cleared when the block is absent. */
export function screeningOutcomeIn(contributorText: string): ScreeningOutcome {
  const found = outcomeLine.exec(contributorText)?.[1];
  return screeningOutcomes.find((outcome) => outcome === found) ?? "cleared";
}

export function createScreeningContributor(source: ScreeningSource): CoachContextContributor {
  return Object.freeze({
    id: screeningContributorId,
    slot: "stable",
    budgetChars: screeningBudgetChars,
    async render(input) {
      return renderScreening(await source(input.userId));
    },
  });
}

export const screeningContributor: CoachContextContributor = createScreeningContributor(
  serviceRoleScreeningSource(),
);
