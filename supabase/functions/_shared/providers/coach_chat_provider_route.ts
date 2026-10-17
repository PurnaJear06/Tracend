// Which Coach chat route answers a question (A9, finding 15 of the Coach audit). The default route
// (AI_COACH_CHAT_*) is the small, fast model that handles conversation. Questions that need
// analysis (progress, trends and pace, changes to the plan or a target, nutrition amounts) go to the
// second route (AI_COACH_CHAT_STRONG_*) when it is set and the athlete's accepted notice names its
// vendor; otherwise they take the default route. A plain rules classifier decides, so the choice
// is the same for the same question and costs nothing.
import type { AiRoute, AiVendor } from "../ai/types.ts";

// The question must ask for analysis. A domain noun alone ("sets", "plan", "weight", "protein")
// is not enough: "how many sets should I do today?" and "what's my plan today?" stay on the
// default route.

// Progress, trend, pace or review: how things are going over time.
const progressIntent =
  /\b(?:progress|trends?|plateau\w*|stall\w*|stagnat\w+|how am i doing|how'?s my|on track|results?|review|compar\w+|improv\w+|over the (?:last|past)|since i started|rate of|pace|(?:fast|slow|quick)\w* enough|too (?:fast|slow))\b/;
// Changing the plan or a target: a change word near what it changes.
const changeIntent =
  /\b(?:change|adjust|modify|update|rebuild|redesign|restructure|swap|switch|replace|raise|lower|increase|reduce|cut)\b.{0,30}\b(?:plan|program|programme|routine|split|block|calories|kcal|macros?|protein|carbs?|target|deficit|surplus|volume|frequency)\b|\b(?:new|different) (?:plan|program|routine|split)\b|\bdeload\b|\bperiodi[sz]ation\b/;
// Nutrition numbers: asking for an amount.
const numberIntent =
  /\bhow (?:many|much) (?:calories|kcal|protein|carbs?|fat|grams)\b|\b(?:am i|are we) (?:eating|getting) enough\b|\bmaintenance (?:calories|level)\b|\btdee\b/;

/** True for a question that asks for analysis: progress, a trend or pace, a change to the plan or a target, or a nutrition amount. */
export function needsStrongerCoachRoute(question: string): boolean {
  const q = question.toLowerCase();
  return [progressIntent, changeIntent, numberIntent].some((pattern) => pattern.test(q));
}

export type CoachRouteSelection =
  | Readonly<{ route: AiRoute; tier: "default" }>
  | Readonly<{ route: AiRoute; tier: "strong" }>
  | Readonly<{ route: AiRoute; tier: "default"; strongSkipped: "consent_vendor_differs" }>;

/**
 * The route for a turn. The stronger route answers a question that needs analysis when it is set
 * (`strong` returns it; it is only asked for then) and its vendor is the one the athlete's
 * accepted notice names: a notice names one vendor, so a stronger route at another company would
 * be refused for consent, and the default route answers instead.
 */
export function selectCoachChatRoute(
  question: string,
  defaultRoute: AiRoute,
  strong: () => AiRoute | null,
  consentVendor: AiVendor | null,
): CoachRouteSelection {
  if (!needsStrongerCoachRoute(question)) return { route: defaultRoute, tier: "default" };
  const stronger = strong();
  if (!stronger) return { route: defaultRoute, tier: "default" };
  if (stronger.vendor !== consentVendor) {
    return { route: defaultRoute, tier: "default", strongSkipped: "consent_vendor_differs" };
  }
  return { route: stronger, tier: "strong" };
}
