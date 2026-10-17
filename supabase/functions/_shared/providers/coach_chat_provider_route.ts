// Which Coach chat route answers a question (A9, finding 15 of the Coach audit). The default route
// (AI_COACH_CHAT_*) is the small, fast model that handles conversation. Questions that need
// analysis (progress, body weight and goals, nutrition numbers, the training plan) go to the
// second route (AI_COACH_CHAT_STRONG_*) when it is set and the athlete's accepted notice names its
// vendor; otherwise they take the default route. A plain rules classifier decides, so the choice
// is the same for the same question and costs nothing.
import type { AiRoute, AiVendor } from "../ai/types.ts";

const progress =
  /\b(?:progress|trend|trends|plateau|plateaued|stall|stalled|stalling|results?|on track|how am i doing|how'?s my|compare[sd]?|comparison|improv\w+|over the (?:last|past)|weekly review|stagnat\w+)\b/;
const bodyWeightAndGoal =
  /\b(?:weight|weigh|weighed|kg|kgs|kilos?|lbs?|pounds?|body ?fat|bmi|goal|goals|target|cut|cutting|bulk|bulking|lean|leaner|lose|losing|loss|gain|gaining|deficit|surplus|maintenance|physique|abs|recomp\w*|diet break)\b/;
const nutritionNumbers =
  /\b(?:calories?|kcal|protein|macros?|carbs?|carbohydrates?|fats?|grams?|tdee|intake|how much (?:should|do) i eat|eat(?:ing)? (?:enough|too much|too little))\b/;
const planQuestions =
  /\b(?:plan|plans|program|programme|routine|split|block|deload|periodi[sz]ation|progression|progressive overload|sets|reps|volume|frequency|swap|replace|substitute|exercise selection|schedule|rest days?)\b/;

/** True for a question that needs the stronger route: analysis of progress, weight, nutrition numbers or the plan. */
export function needsStrongerCoachRoute(question: string): boolean {
  const q = question.toLowerCase();
  return [progress, bodyWeightAndGoal, nutritionNumbers, planQuestions].some((pattern) =>
    pattern.test(q)
  );
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
