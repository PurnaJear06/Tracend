// Which Coach chat route answers a turn (A9, finding 15 of the Coach audit). The default route
// (AI_COACH_CHAT_*) is the small, fast model that handles conversation. A turn whose records call
// for care or for weighing several kinds of record against each other goes to the second route
// (AI_COACH_CHAT_STRONG_*) when it is set and the athlete's accepted notice names its vendor;
// otherwise it takes the default route.
//
// The choice reads the state of the athlete's records, never the words of the question: a keyword
// list picks the tier by how a question is phrased ("check my training" matched none and stayed on
// the small model), and the same question is a different job for a cleared, pain-free athlete and
// for one whose health check is open or whose session is due on a poor-recovery day. The signals
// are deterministic, cost nothing and are the same for the same records:
//   - the health check is not cleared (or could not be read): effort is capped and referral wording
//     applies, which is the part of a reply most worth getting right;
//   - pain is on record (today's check-in, or an exercise flagged for pain in the last 14 days), or
//     could not be read (an unknown is treated as pain, as an unreadable health check is);
//   - a Coach proposal is waiting for the athlete's answer: what Coach says now bears on it;
//   - two or more watch-outs about training decisions at once (back-to-back muscles, a session due
//     on a bad recovery day, a pain flag planned again, behind plan, repeated skips, recovery
//     drift): that is a multi-domain judgement.
// A follow-up turn is not a signal: it is not a harder question, and most turns of a conversation
// are follow-ups.
import { screeningStateOf } from "../coach_context/contributors/screening.ts";
import { proposalsContributorId } from "../coach_context/contributors/proposals.ts";
import { watchOutsContributorId } from "../coach_context/contributors/watch_outs.ts";
import type { CoachContributions } from "../coach_context/host.ts";
import type { AiRoute } from "../ai/types.ts";

/** Two watch-outs about training decisions are "several": one alone is a note, two are a judgement. */
export const strongWatchOutDecisions = 2;

export type RouteSignals = Readonly<{
  /** The health check outcome; anything but "cleared" counts. */
  screening: "cleared" | "moderate_until_cleared" | "see_professional" | "unknown";
  /**
   * Pain on record (today's or yesterday's check-in, or a pain-flagged exercise in the last 14
   * days). "unknown" when the contributor that reads it failed or timed out or could not read its
   * facts: an unknown is treated as pain, as an unreadable health check is.
   */
  pain: "none" | "on_record" | "unknown";
  /** Coach proposals waiting for the athlete's answer. */
  proposalsWaiting: number;
  /** Watch-outs about training decisions this turn (not stale inputs or plan age). */
  watchOutDecisions: number;
}>;

const count = (value: unknown): number =>
  typeof value === "number" && Number.isFinite(value) ? value : 0;

/** The signals of a turn from what its contributors reported (their numeric traces). */
export function routeSignalsOf(contributions: CoachContributions | null): RouteSignals {
  const traces = contributions?.traces ?? {};
  const watch = traces[watchOutsContributorId];
  const proposals = traces[proposalsContributorId];
  const watchOutcome = contributions?.outcomes.find((entry) => entry.id === watchOutsContributorId);
  // The watch-outs report on pain whether or not they rendered text. A contributor that failed or
  // timed out, or whose facts could not be read (pain: null), leaves it unknown; no contributor at
  // all (a rollback path, a test) leaves nothing to know.
  const pain = !watchOutcome
    ? "none"
    : watchOutcome.outcome === "failed" || watchOutcome.outcome === "timeout" ||
        (watch ?? {}).pain === undefined || (watch ?? {}).pain === null
    ? "unknown"
    : watch?.pain === true
    ? "on_record"
    : "none";
  return {
    screening: screeningStateOf(contributions),
    pain,
    proposalsWaiting: count(proposals?.waiting),
    watchOutDecisions: count(watch?.decisions),
  };
}

/** The signals that ask for the stronger route, by name; empty when the default route suffices. */
export function strongRouteReasons(signals: RouteSignals): string[] {
  return [
    ...(signals.screening !== "cleared" ? ["screening_not_cleared"] : []),
    ...(signals.pain === "on_record" ? ["pain_on_record"] : []),
    ...(signals.pain === "unknown" ? ["pain_unknown"] : []),
    ...(signals.proposalsWaiting > 0 ? ["proposal_waiting"] : []),
    ...(signals.watchOutDecisions >= strongWatchOutDecisions ? ["several_watch_outs"] : []),
  ];
}

export type CoachRouteSelection =
  | Readonly<{ route: AiRoute; tier: "default"; reasons: readonly string[] }>
  | Readonly<{ route: AiRoute; tier: "strong"; reasons: readonly string[] }>;

/**
 * The route for a turn: the stronger route when a signal asks for it and it is set. The caller
 * passes it only when its vendor is the one the athlete's accepted notice names (a notice names
 * one vendor, so a stronger route at another company would be refused for consent); coach-chat
 * filters by vendor before it reserves the budget.
 */
export function selectCoachChatRoute(
  signals: RouteSignals,
  defaultRoute: AiRoute,
  strong: AiRoute | null,
): CoachRouteSelection {
  const reasons = strongRouteReasons(signals);
  return reasons.length === 0 || !strong
    ? { route: defaultRoute, tier: "default", reasons }
    : { route: strong, tier: "strong", reasons };
}
