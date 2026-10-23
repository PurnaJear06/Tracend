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
import { blockOf, type CoachContextContributor, type CoachContributions } from "../host.ts";
import { plain, record as recorded } from "../../recorded_text.ts";

export const screeningContributorId = "screening";
export const screeningBudgetChars = 900;

/**
 * What Coach and the reply guard act on: the outcome, or "unknown" when the lookup failed. An
 * unreadable health check is never read as cleared: it carries the restrictions of
 * moderate_until_cleared.
 */
export type ScreeningState = ScreeningOutcome | "unknown";

/** How long the lookup may take before the contributor reports the health check unknown. */
export const screeningLookupTimeoutMs = 3_000;

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
    if (!data) return null;
    const outcome = screeningOutcomes.find((candidate) => candidate === data.outcome);
    // A row with a value this code does not know is not "no row".
    if (!outcome) throw new Error("screening outcome unreadable");
    return { outcome, screenedAt: data.screened_at };
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

/**
 * The block's text for a screening with its values marked (`../../recorded_text.ts`): the day it
 * was answered is a record; the rules, and the figures in them, are Tracend's fixed wording.
 */
function screeningMarked(record: ScreeningRecord | null): string | null {
  if (!record) return null;
  return [
    `Pre-exercise health check, answered on ${
      recorded(record.screenedAt.slice(0, 10))
    }. Tracend calculated the outcome from the athlete's answers; you never change it.`,
    `Outcome: ${record.outcome}`,
    rules[record.outcome],
  ].join("\n");
}

/** The block's text for a screening, or null without one (never screened reads as cleared). */
export function renderScreening(record: ScreeningRecord | null): string | null {
  const marked = screeningMarked(record);
  return marked === null ? null : plain(marked);
}

/** The block when the lookup failed or timed out: restricted, never cleared. */
export function renderScreeningUnknown(): string {
  return [
    "The athlete's pre-exercise health check could not be read just now, so its outcome is unknown. Tracend treats an unknown outcome as moderate_until_cleared.",
    "Outcome: unknown",
    `${rules.moderate_until_cleared} If the athlete asks, say the health check could not be read this time.`,
  ].join("\n");
}

const outcomeLine = new RegExp(
  String.raw`<reference_data source="${screeningContributorId}">[\s\S]*?^Outcome: (${
    [...screeningOutcomes, "unknown"].join("|")
  })$`,
  "m",
);

/** The outcome in rendered contributor text; cleared when the block is absent. */
export function screeningOutcomeIn(contributorText: string): ScreeningState {
  const found = outcomeLine.exec(contributorText)?.[1];
  if (found === "unknown") return "unknown";
  return screeningOutcomes.find((outcome) => outcome === found) ?? "cleared";
}

/**
 * The screening state a turn runs under. The rendered block decides. Without a block, a
 * contributor that failed or timed out means unknown (restricted); one that rendered nothing
 * means the athlete was never screened (cleared); no contributors at all (a rollback path or a
 * test) means there is nothing to apply.
 */
export function screeningStateOf(contributions: CoachContributions | null): ScreeningState {
  if (!contributions) return "cleared";
  const blockState = screeningOutcomeIn(contributions.stable);
  if (blockState !== "cleared") return blockState;
  const reported = contributions.outcomes.find((entry) => entry.id === screeningContributorId);
  return reported && (reported.outcome === "failed" || reported.outcome === "timeout")
    ? "unknown"
    : "cleared";
}

export function createScreeningContributor(
  source: ScreeningSource,
  timeoutMs: number = screeningLookupTimeoutMs,
): CoachContextContributor {
  return Object.freeze({
    id: screeningContributorId,
    slot: "stable",
    budgetChars: screeningBudgetChars,
    async render(input) {
      let timer: ReturnType<typeof setTimeout> | undefined;
      try {
        const record = await Promise.race([
          source(input.userId),
          new Promise<never>((_, reject) => {
            timer = setTimeout(() => reject(new Error("screening lookup timed out")), timeoutMs);
          }),
        ]);
        const marked = screeningMarked(record);
        return marked === null ? null : blockOf(marked);
      } catch {
        // Fail closed: "could not read" is not "no row".
        return renderScreeningUnknown();
      } finally {
        clearTimeout(timer);
      }
    },
  });
}

export const screeningContributor: CoachContextContributor = createScreeningContributor(
  serviceRoleScreeningSource(),
);
