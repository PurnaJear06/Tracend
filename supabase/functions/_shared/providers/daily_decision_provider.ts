import type { AiCoachingConsent } from "../ai_consent.ts";
import type { CoachModelProvider } from "./coach_model_provider.ts";
import { createCoachModelProvider } from "./create_coach_model_provider.ts";
import { MockCoachModelProvider } from "./mock_coach_model_provider.ts";

/// The provider for the daily decision: the configured AI model only with a
/// current grant, otherwise the deterministic one, so no data leaves.
export function dailyDecisionProvider(
  consent: AiCoachingConsent,
  configured: () => CoachModelProvider = createCoachModelProvider,
): CoachModelProvider {
  return consent === "granted" ? configured() : new MockCoachModelProvider();
}
