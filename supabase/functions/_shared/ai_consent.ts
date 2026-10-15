/// The athlete's AI coaching answer as the server sees it. `unavailable`
/// means the check itself failed; callers treat it as not granted.
export type AiCoachingConsent = "granted" | "not_granted" | "unavailable";

/// What the athlete agreed AI may do; each has its own current notice.
export type AiConsentPurpose = "coach_chat" | "daily_coaching" | "onboarding_plan";

export type ConsentRpc = (
  name: "has_ai_coaching_consent",
  params: { target_user_id: string; consent_purpose: AiConsentPurpose },
) => PromiseLike<{ data: unknown; error: unknown }>;

/// Reads `has_ai_coaching_consent`: true only when the newest ai_coaching
/// record grants the notice that is current for the purpose. Every caller
/// names its purpose, so a notice published for one purpose never decides
/// another.
export async function aiCoachingConsent(
  rpc: ConsentRpc,
  userId: string,
  purpose: AiConsentPurpose,
): Promise<AiCoachingConsent> {
  try {
    const { data, error } = await rpc(
      "has_ai_coaching_consent",
      { target_user_id: userId, consent_purpose: purpose },
    );
    if (error || typeof data !== "boolean") return "unavailable";
    return data ? "granted" : "not_granted";
  } catch {
    return "unavailable";
  }
}

/// What the gateway asks consent for: its features (Contract 1) and today's
/// names. `get_ai_consent_v2` maps each to the notice that covers it.
export type AiConsentFeature =
  | AiConsentPurpose
  | "daily_decision"
  | "onboarding_questions"
  | "meal_vision"
  | "physique_vision"
  | "library_context";

/// The vendor that receives the athlete's data, as a notice names it. Never an
/// API shape: a notice naming DeepSeek must not cover a route to Groq, though
/// both are reached the same way.
export type AiVendor = "anthropic" | "deepseek" | "groq" | "gemini";

const vendors: ReadonlySet<string> = new Set<AiVendor>([
  "anthropic",
  "deepseek",
  "groq",
  "gemini",
]);

/// The grant, and the vendor and version of the notice current for the
/// purpose. `provider` (the vendor) is null when that notice names none (it
/// predates vendor names) or names one this code does not know: the gateway
/// then refuses to send.
export type AiConsentWithProvider = Readonly<{
  consent: AiCoachingConsent;
  provider: AiVendor | null;
  noticeVersion: string | null;
}>;

export type ConsentV2Rpc = (
  name: "get_ai_consent_v2",
  params: { target_user_id: string; consent_purpose: AiConsentFeature },
) => PromiseLike<{ data: unknown; error: unknown }>;

const consentUnavailable: AiConsentWithProvider = Object.freeze({
  consent: "unavailable",
  provider: null,
  noticeVersion: null,
});

/// Reads `get_ai_consent_v2`. Never throws: a failed or malformed answer is
/// `unavailable` with no provider, which callers treat as not granted.
export async function aiConsentWithProvider(
  rpc: ConsentV2Rpc,
  userId: string,
  purpose: AiConsentFeature,
): Promise<AiConsentWithProvider> {
  try {
    const { data, error } = await rpc(
      "get_ai_consent_v2",
      { target_user_id: userId, consent_purpose: purpose },
    );
    if (error || data === null || typeof data !== "object" || Array.isArray(data)) {
      return consentUnavailable;
    }
    const answer = data as Record<string, unknown>;
    const version = typeof answer.notice_version === "string"
      ? answer.notice_version
      : answer.notice_version === null
      ? null
      : undefined;
    if (typeof answer.granted !== "boolean" || version === undefined) {
      return consentUnavailable;
    }
    const provider = typeof answer.provider === "string" && vendors.has(answer.provider)
      ? answer.provider as AiVendor
      : null;
    return {
      consent: answer.granted ? "granted" : "not_granted",
      provider,
      noticeVersion: version,
    };
  } catch {
    return consentUnavailable;
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
