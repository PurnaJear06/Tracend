// When a simulation run is a harness failure rather than a finding. The simulator reports quality
// and never gates on it, but a run whose models did not answer measures nothing: the job fails when
// the Coach route errors on too many turns, the judges give no verdicts, or the athlete model cannot
// write. Pure functions over the finished run, so they are tested without a network.
import { isCreditsError, type ProviderError } from "./diagnostics.ts";
import type { ConversationRun } from "./simulate.ts";

/** The share of Coach turns that may end in a provider error before the run is a failure. */
export const providerErrorLimit = 0.2;
/** The share of judge calls that may fail (any way) before the judges are not trusted. */
export const judgeFailureLimit = 0.1;
/** The share of conversations the athlete model may fail to continue. */
export const athleteFailureLimit = 0.2;

/** Failure codes that mean the route did not answer (not a model that answered badly). */
export const providerErrorCodes: ReadonlySet<string> = new Set([
  "provider_http_error",
  "provider_timeout",
  "provider_rate_limited",
]);

export type HarnessStats = Readonly<{
  /** Coach turns that ran a model (red-flag referrals are answered by fixed text). */
  coachTurns: number;
  providerErrorTurns: number;
  modelAnswers: number;
  judgeCalls: number;
  expertVerdicts: number;
  claimCalls: number;
  claimVerdicts: number;
  conversations: number;
  athleteFailures: number;
}>;

export function harnessStats(runs: readonly ConversationRun[]): HarnessStats {
  const turns = runs.flatMap((run) => run.turns);
  const failed = (turn: (typeof turns)[number], prefix: string) =>
    turn.judgeFailures.some((failure) => failure.startsWith(prefix));
  const coach = turns.filter((turn) => turn.reply.outcome !== "boundary");
  return {
    coachTurns: coach.length,
    providerErrorTurns:
      coach.filter((turn) =>
        turn.reply.failureCode !== undefined && providerErrorCodes.has(turn.reply.failureCode)
      ).length,
    modelAnswers: turns.filter((turn) => turn.reply.outcome === "model").length,
    judgeCalls: turns.filter((turn) => turn.expert || failed(turn, "expert:")).length,
    expertVerdicts: turns.filter((turn) => turn.expert).length,
    claimCalls: turns.filter((turn) => turn.claims || failed(turn, "claims:")).length,
    claimVerdicts: turns.filter((turn) => turn.claims).length,
    conversations: runs.length,
    athleteFailures: runs.filter((run) => run.ended === "athlete_failed").length,
  };
}

/**
 * The reasons this run is a harness failure, empty when it is sound. `judgesEnabled` is whether a
 * judge model was chosen. Quality findings are never among them.
 */
export function harnessFailures(
  runs: readonly ConversationRun[],
  judgesEnabled: boolean,
  errors: readonly ProviderError[] = [],
): string[] {
  const stats = harnessStats(runs);
  const reasons: string[] = [];
  const noCredit = errors.filter(isCreditsError);
  if (noCredit.length > 0) {
    reasons.push(
      `The router account ran out of credit (${noCredit.length} calls answered "${
        noCredit[0].body.slice(0, 120)
      }"): ${
        runs.filter((r) => r.ended === "credits").length
      } conversations stopped early and the results are partial. Top up the router balance and run again.`,
    );
  }
  for (const run of runs.filter((r) => r.ended === "harness_error")) {
    reasons.push(`Harness error in ${run.id}: ${run.error}`);
  }
  if (stats.coachTurns === 0) reasons.push("No Coach turn ran.");
  if (stats.coachTurns > 0 && stats.providerErrorTurns / stats.coachTurns > providerErrorLimit) {
    reasons.push(
      `${stats.providerErrorTurns} of ${stats.coachTurns} Coach turns ended in a provider error (limit ${
        providerErrorLimit * 100
      }%).`,
    );
  }
  if (stats.coachTurns > 0 && stats.modelAnswers === 0) {
    reasons.push("No Coach turn got a model answer.");
  }
  if (judgesEnabled && stats.modelAnswers > 0 && stats.expertVerdicts === 0) {
    reasons.push(
      `The expert judge produced no verdicts (${stats.judgeCalls} judged turns of ${stats.modelAnswers} model answers).`,
    );
  }
  // A judge that ran out of output tokens gave no verdict; counting that as a pass or hiding it
  // behind the others would mislead, so any such call is a harness error.
  const truncated = errors.filter((e) => e.source === "judge" && e.kind === "truncated").length;
  if (judgesEnabled && truncated > 0) {
    reasons.push(
      `${truncated} judge calls ran into their output limit and gave no verdict; raise judgeMaxTokens.`,
    );
  }
  const judgeCalls = stats.judgeCalls + stats.claimCalls;
  const judgeVerdicts = stats.expertVerdicts + stats.claimVerdicts;
  if (
    judgesEnabled && judgeCalls > 0 && (judgeCalls - judgeVerdicts) / judgeCalls > judgeFailureLimit
  ) {
    reasons.push(
      `${judgeCalls - judgeVerdicts} of ${judgeCalls} judge calls gave no verdict (limit ${
        judgeFailureLimit * 100
      }%).`,
    );
  }
  if (judgesEnabled && stats.claimCalls > 0 && stats.claimVerdicts === 0) {
    reasons.push(`The claim-support judge produced no verdicts in ${stats.claimCalls} calls.`);
  }
  if (
    stats.conversations > 0 && stats.athleteFailures / stats.conversations > athleteFailureLimit
  ) {
    reasons.push(
      `The athlete model could not continue ${stats.athleteFailures} of ${stats.conversations} conversations (limit ${
        athleteFailureLimit * 100
      }%).`,
    );
  }
  return reasons;
}
