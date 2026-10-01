/// The athlete's AI coaching answer as the server sees it. `unavailable`
/// means the check itself failed; callers treat it as not granted.
export type AiCoachingConsent = "granted" | "not_granted" | "unavailable";

/// What the athlete agreed AI may do; each has its own current notice.
export type AiConsentPurpose = "coach_chat" | "daily_coaching" | "onboarding_plan";

export type ConsentRpc = (
  name: "has_ai_coaching_consent",
  params: { target_user_id: string; consent_purpose?: AiConsentPurpose },
) => PromiseLike<{ data: unknown; error: unknown }>;

/// Reads `has_ai_coaching_consent`: true only when the newest ai_coaching
/// record grants the notice that is current for the purpose (the Coach chat
/// when none is given).
export async function aiCoachingConsent(
  rpc: ConsentRpc,
  userId: string,
  purpose?: AiConsentPurpose,
): Promise<AiCoachingConsent> {
  try {
    const { data, error } = await rpc(
      "has_ai_coaching_consent",
      purpose ? { target_user_id: userId, consent_purpose: purpose } : { target_user_id: userId },
    );
    if (error || typeof data !== "boolean") return "unavailable";
    return data ? "granted" : "not_granted";
  } catch {
    return "unavailable";
  }
}

/// What coach-chat answers instead of calling the model, or null to go on.
export function coachChatConsentRefusal(
  consent: AiCoachingConsent,
): { status: 403 | 503; error: string } | null {
  if (consent === "granted") return null;
  return consent === "unavailable"
    ? { status: 503, error: "ai_consent_unavailable" }
    : { status: 403, error: "ai_consent_required" };
}
