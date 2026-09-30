/// The athlete's AI coaching answer as the server sees it. `unavailable`
/// means the check itself failed; callers treat it as not granted.
export type AiCoachingConsent = "granted" | "not_granted" | "unavailable";

export type ConsentRpc = (
  name: "has_ai_coaching_consent",
  params: { target_user_id: string },
) => PromiseLike<{ data: unknown; error: unknown }>;

/// Reads `has_ai_coaching_consent`: true only when the newest ai_coaching
/// record grants the current notice version.
export async function aiCoachingConsent(
  rpc: ConsentRpc,
  userId: string,
): Promise<AiCoachingConsent> {
  try {
    const { data, error } = await rpc("has_ai_coaching_consent", { target_user_id: userId });
    if (error || typeof data !== "boolean") return "unavailable";
    return data ? "granted" : "not_granted";
  } catch {
    return "unavailable";
  }
}
