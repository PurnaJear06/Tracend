// The optional tone judge. Code graders cannot tell a warm reply from a cold one, so a second
// model scores each model reply against a short binary rubric. It is off unless EVAL_JUDGE_MODEL
// is set, it must be a different model from the one answering (a model grading its own tone is
// not a check), and its verdict is reported, not gated, until it has been checked against about
// 30 human labels. It sees the question and the reply only, never the athlete file.
//
// Settings, read like a gateway route's but with the EVAL_JUDGE_ prefix (so no production setting
// can reach the judge): EVAL_JUDGE_PROVIDER, EVAL_JUDGE_MODEL, EVAL_JUDGE_API_KEY and, where
// the provider needs them, EVAL_JUDGE_BASE_URL and EVAL_JUDGE_VENDOR; for Gemini also
// EVAL_JUDGE_GEMINI_PAID_DATA_TERMS_ACCEPTED=true; EVAL_JUDGE_MAX_OUTPUT_TOKENS (default 400) and
// EVAL_JUDGE_TIMEOUT_MS (default 30000).
import { call } from "../../_shared/ai/gateway.ts";
import { type Env, route } from "../../_shared/ai/routes.ts";
import type { AiCallDeps, AiRoute } from "../../_shared/ai/types.ts";
import type { ToneVerdict } from "./report.ts";

export const toneRubric: readonly (readonly [string, string])[] = [
  ["plain_language", "Uses everyday words; any technical term is explained."],
  [
    "no_judgement",
    "Does not shame, scold or moralise about food, weight, missed sessions or progress.",
  ],
  ["answers_first", "Answers what the athlete asked before anything else."],
  ["warm_and_direct", "Warm and direct, with no filler praise and no pile of exclamation marks."],
];

/** The judge's route from EVAL_JUDGE_* settings, or null when the judge is off or incomplete. */
export function judgeRoute(env: Env = (name) => Deno.env.get(name)): AiRoute | null {
  const setting = (name: string) => env(`EVAL_JUDGE_${name}`);
  if (!setting("MODEL")) return null;
  const mapped: Env = (name) => {
    if (name.startsWith("AI_COACH_CHAT_")) {
      const suffix = name.slice("AI_COACH_CHAT_".length);
      if (suffix === "MAX_OUTPUT_TOKENS") return setting(suffix) ?? "400";
      if (suffix === "TIMEOUT_MS") return setting(suffix) ?? "30000";
      return setting(suffix);
    }
    if (
      name === "ANTHROPIC_API_KEY" || name === "GEMINI_API_KEY" ||
      name.startsWith("OPENAI_COMPATIBLE_API_KEY_")
    ) return setting("API_KEY");
    if (name === "GEMINI_PAID_DATA_TERMS_ACCEPTED") {
      return setting("GEMINI_PAID_DATA_TERMS_ACCEPTED");
    }
    return undefined;
  };
  return route("coach_chat", mapped);
}

/** The judge route, refused when it is any model that answers. */
export function distinctJudgeRoute(answeringModels: readonly string[], env?: Env): AiRoute | null {
  const judge = judgeRoute(env);
  if (judge && answeringModels.includes(judge.model)) {
    throw new Error(
      `The tone judge must be a different model from the answering model (${judge.model}).`,
    );
  }
  return judge;
}

const schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    items: {
      type: "array",
      items: {
        type: "object",
        additionalProperties: false,
        properties: { id: { type: "string" }, pass: { type: "boolean" } },
        required: ["id", "pass"],
      },
    },
  },
  required: ["items"],
};

const instructions =
  "You grade the tone of a fitness coach's reply to an athlete. For each rubric item answer pass true or false, judging only the reply text. Return one entry per item, using the item ids exactly.\n" +
  toneRubric.map(([id, text]) => `- ${id}: ${text}`).join("\n");

/** The verdict on one reply (null when the judge's answer could not be read) and what it cost. */
export async function judgeTone(
  judge: AiRoute,
  question: string,
  reply: string,
  deps: AiCallDeps = {},
): Promise<{ verdict: ToneVerdict | null; costUsd: number }> {
  const result = await call({
    route: judge,
    system: [{ type: "text", text: instructions }],
    messages: [{
      role: "user",
      content: [{
        type: "text",
        text:
          `Athlete's message:\n<message>${question}</message>\n\nCoach's reply:\n<reply>${reply}</reply>`,
      }],
    }],
    output: { kind: "json", schema },
    consentVendor: judge.vendor,
  }, deps);
  const costUsd = result.usage?.costUsd ?? 0;
  if (!result.ok) return { verdict: null, costUsd };
  const items = (result.json as { items?: { id: string; pass: boolean }[] } | undefined)?.items;
  if (!Array.isArray(items)) return { verdict: null, costUsd };
  const failed = toneRubric.map(([id]) => id).filter((id) =>
    items.find((item) => item.id === id)?.pass !== true
  );
  return { verdict: { pass: failed.length === 0, failed }, costUsd };
}
