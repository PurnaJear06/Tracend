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
//   - pain is on record (today's check-in, or an exercise flagged for pain in the last 14 days);
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
import type { AiRoute, AiVendor } from "../ai/types.ts";

/** Two watch-outs about training decisions are "several": one alone is a note, two are a judgement. */
export const strongWatchOutDecisions = 2;

export type RouteSignals = Readonly<{
  /** The health check outcome; anything but "cleared" counts. */
  screening: "cleared" | "moderate_until_cleared" | "see_professional" | "unknown";
  /** Pain is on record (today's check-in or a pain-flagged exercise in the last 14 days). */
  pain: boolean;
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
  return {
    screening: screeningStateOf(contributions),
    pain: watch?.pain === true,
    proposalsWaiting: count(proposals?.waiting),
    watchOutDecisions: count(watch?.decisions),
  };
}

/** The signals that ask for the stronger route, by name; empty when the default route suffices. */
export function strongRouteReasons(signals: RouteSignals): string[] {
  return [
    ...(signals.screening !== "cleared" ? ["screening_not_cleared"] : []),
    ...(signals.pain ? ["pain_on_record"] : []),
    ...(signals.proposalsWaiting > 0 ? ["proposal_waiting"] : []),
    ...(signals.watchOutDecisions >= strongWatchOutDecisions ? ["several_watch_outs"] : []),
  ];
}

export type CoachRouteSelection =
  | Readonly<{ route: AiRoute; tier: "default"; reasons: readonly string[] }>
  | Readonly<{ route: AiRoute; tier: "strong"; reasons: readonly string[] }>
  | Readonly<{
    route: AiRoute;
    tier: "default";
    reasons: readonly string[];
    strongSkipped: "consent_vendor_differs";
  }>;

/**
 * The route for a turn. The stronger route answers a turn with a signal when it is set and its
 * vendor is the one the athlete's accepted notice names: a notice names one vendor, so a stronger
 * route at another company would be refused for consent, and the default route answers instead.
 */
export function selectCoachChatRoute(
  signals: RouteSignals,
  defaultRoute: AiRoute,
  strong: AiRoute | null,
  consentVendor: AiVendor | null,
): CoachRouteSelection {
  const reasons = strongRouteReasons(signals);
  if (reasons.length === 0 || !strong) return { route: defaultRoute, tier: "default", reasons };
  if (strong.vendor !== consentVendor) {
    return {
      route: defaultRoute,
      tier: "default",
      reasons,
      strongSkipped: "consent_vendor_differs",
    };
  }
  return { route: strong, tier: "strong", reasons };
}
