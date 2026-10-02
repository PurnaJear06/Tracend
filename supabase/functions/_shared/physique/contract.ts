import { type Muscle, muscles } from "../onboarding/catalog.ts";

// What a physique check may say (AI_SAFETY_SPEC §9). The model suggests up to
// three muscles to develop, relative to the athlete's own build, with a short
// reason each; up to three neutral observations; photo issues from a fixed
// list; and its limitations. It never gives a body-fat figure, a score, a
// judgement of looks, or anything medical. Any broken rule rejects the whole
// reply; nothing is trimmed or rewritten. The database checks the same shape
// (private.is_valid_physique_result).

export const photoIssues = ["lighting", "pose", "clothing", "framing", "blur", "mismatch"] as const;
export type PhotoIssue = typeof photoIssues[number];
export type Confidence = "low" | "medium" | "high";

export type DevelopmentPriority = Readonly<{
  muscle: Muscle;
  confidence: Confidence;
  reason: string;
}>;

export type PhysiqueResult = Readonly<{
  schema_version: "1.0";
  development_priorities: readonly DevelopmentPriority[];
  observations: readonly string[];
  photo_issues: readonly PhotoIssue[];
  limitations: string;
}>;

export type PhysiqueParse =
  | Readonly<{ ok: true; result: PhysiqueResult }>
  | Readonly<{ ok: false; rule: string }>;

export const reasonMaxLength = 120;
export const observationMaxLength = 160;
export const limitationsMaxLength = 240;

/** Words the reply must never contain, by why they are refused. */
const forbidden: readonly (readonly [string, RegExp])[] = [
  ["body_composition_figure", /\d\s*%|percent|body\s*-?\s*fat|\bbmi\b|lean mass|\bfat\b/],
  ["score", /\bscores?\b|\bratings?\b|\brated\b|\d+(?:\.\d+)?\s*\/\s*10\b|out of (?:10|ten)\b/],
  [
    "appearance_judgement",
    /attractive|\bugly\b|\bsexy\b|\bhot\b|beautiful|handsome|\bgross\b|disgusting|flabby|chubby|skinny|scrawny|obese|overweight|underweight|pathetic|embarrass|\bperfect\b|\bideal body\b/,
  ],
  ["sexual", /sexual|\bnude\b|naked|genital|\bbreasts?\b|\bbutt\b/],
  [
    "medical",
    /diagnos|disease|disorder|syndrome|medical|gyn(?:a|e)?comastia|\bgyno\b|hernia|scoliosis|injur|surgery|\blipo|steroid|hormone|testosterone|doctor/,
  ],
  [
    "sensitive_trait",
    /\brace\b|ethnic|skin (?:tone|colou?r)|tattoo|religio|\bgender\b|\bage\b|years? old|pregnan/,
  ],
  ["eating", /calorie|\bdiet\b|starv|purg|laxative|eat less|stop eating/],
];

function forbiddenRule(text: string): string | null {
  const lower = text.toLowerCase();
  for (const [rule, pattern] of forbidden) if (pattern.test(lower)) return rule;
  return null;
}

const isText = (value: unknown, max: number): value is string =>
  typeof value === "string" && value.trim().length >= 1 && value.length <= max;

/**
 * Photo issues lower what the model may claim: one issue caps confidence at
 * medium, two or more at low.
 */
export function capConfidence(confidence: Confidence, issues: number): Confidence {
  if (issues >= 2) return "low";
  if (issues === 1 && confidence === "high") return "medium";
  return confidence;
}

/** Parses the model's reply; the rule it broke when it is unusable. */
export function parsePhysiqueResult(content: string): PhysiqueParse {
  let value: unknown;
  try {
    value = JSON.parse(content.trim());
  } catch {
    return { ok: false, rule: "not_json" };
  }
  if (!value || typeof value !== "object" || Array.isArray(value)) {
    return { ok: false, rule: "not_object" };
  }
  const reply = value as Record<string, unknown>;
  const keys = Object.keys(reply).sort();
  if (keys.join(",") !== "development_priorities,limitations,observations,photo_issues") {
    return { ok: false, rule: "unexpected_keys" };
  }
  const issues = reply.photo_issues;
  if (
    !Array.isArray(issues) || issues.length > 3 || new Set(issues).size !== issues.length ||
    !issues.every((issue) => photoIssues.includes(issue as PhotoIssue))
  ) {
    return { ok: false, rule: "photo_issues" };
  }
  const priorities = reply.development_priorities;
  if (!Array.isArray(priorities) || priorities.length < 1 || priorities.length > 3) {
    return { ok: false, rule: "priority_count" };
  }
  const parsed: DevelopmentPriority[] = [];
  for (const item of priorities) {
    if (!item || typeof item !== "object" || Array.isArray(item)) {
      return { ok: false, rule: "priority_shape" };
    }
    const priority = item as Record<string, unknown>;
    if (Object.keys(priority).sort().join(",") !== "confidence,muscle,reason") {
      return { ok: false, rule: "priority_shape" };
    }
    if (!muscles.includes(priority.muscle as Muscle)) return { ok: false, rule: "unknown_muscle" };
    if (!["low", "medium", "high"].includes(priority.confidence as string)) {
      return { ok: false, rule: "confidence" };
    }
    if (!isText(priority.reason, reasonMaxLength)) return { ok: false, rule: "reason_length" };
    parsed.push({
      muscle: priority.muscle as Muscle,
      confidence: capConfidence(priority.confidence as Confidence, issues.length),
      reason: priority.reason.trim(),
    });
  }
  if (new Set(parsed.map((priority) => priority.muscle)).size !== parsed.length) {
    return { ok: false, rule: "duplicate_muscle" };
  }
  const observations = reply.observations;
  if (
    !Array.isArray(observations) || observations.length > 3 ||
    !observations.every((observation) => isText(observation, observationMaxLength))
  ) {
    return { ok: false, rule: "observations" };
  }
  if (!isText(reply.limitations, limitationsMaxLength)) return { ok: false, rule: "limitations" };
  for (
    const text of [
      ...parsed.map((priority) => priority.reason),
      ...observations as string[],
      reply.limitations,
    ]
  ) {
    const rule = forbiddenRule(text);
    if (rule) return { ok: false, rule };
  }
  return {
    ok: true,
    result: {
      schema_version: "1.0",
      development_priorities: parsed,
      observations: (observations as string[]).map((observation) => observation.trim()),
      photo_issues: issues as PhotoIssue[],
      limitations: reply.limitations.trim(),
    },
  };
}
