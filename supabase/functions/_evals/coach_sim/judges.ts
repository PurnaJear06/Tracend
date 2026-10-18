// The simulator's two model judges, run on a different model from the Coach (a model grading its
// own answers is not a check). Both are reported, never gated, until checked against human
// labels.
//
// - The expert-coach judge scores every Coach reply 1-5 on five items and writes what a coach of
//   twenty years would have said instead.
// - The claim-support judge (RAG audit P1-3) reads every reply that cites the research library:
//   for each sentence that states something from a cited source, is it supported, partly
//   supported or unsupported by the excerpt Coach was shown?
import { sentencesOf } from "../coach_bank/graders.ts";
import type { Turn } from "../coach_bank/types.ts";
import { normalizedModelId } from "../live_model.ts";
import { jsonObjectIn, type RouterChat } from "./router_client.ts";

export const expertRubric = [
  [
    "specific",
    "Uses this athlete's own numbers, dates and situation where they matter, not advice that would fit anyone.",
  ],
  [
    "correct",
    "Sound for an experienced lifter: nothing wrong, outdated or oversimplified; the figures and the reasoning hold up.",
  ],
  [
    "not_generic",
    "Adds something new this turn: no opening, check, caveat or question repeated from earlier in the conversation.",
  ],
  [
    "pushback",
    "Pushes back when the athlete is wrong and agrees when they are right, without caving or lecturing. Score 5 when no pushback was called for and none was given.",
  ],
  [
    "coach_like",
    "Reads like a strength coach of twenty years: decisive, prioritised, a practical next step, no filler.",
  ],
] as const;

export type ExpertItem = typeof expertRubric[number][0];

export type ExpertVerdict = Readonly<{
  scores: Readonly<Record<ExpertItem, number>>;
  mean: number;
  /** Every item scored 3 or more. */
  pass: boolean;
  problem: string;
  betterAnswer: string;
}>;

export type ClaimVerdict = "supported" | "partial" | "unsupported";

export type Claim = Readonly<{
  sentence: string;
  source: string;
  verdict: ClaimVerdict;
  reason: string;
}>;

/** Refuses a judge that is the Coach's own model. */
export function assertDistinctJudge(judgeModel: string, coachModel: string): void {
  if (normalizedModelId(judgeModel) === normalizedModelId(coachModel)) {
    throw new Error(`The judge must be a different model from the Coach (${coachModel}).`);
  }
}

const clip = (text: string, max: number) =>
  text.length <= max ? text : `${text.slice(0, max)} [cut]`;

export type ExpertInput = Readonly<{
  digest: string;
  coachBrief: string;
  /** The conversation before this turn. */
  earlier: readonly Turn[];
  question: string;
  reply: string;
  /** What Coach looked up this turn, as it read it. */
  lookedUp: string;
}>;

const expertSystem =
  "You are a strength and conditioning coach with twenty years of experience coaching lifters of every level. " +
  "You review replies an AI coach in a fitness app gave an athlete. Judge the reply as a demanding head coach would judge a junior coach. " +
  "Score each rubric item from 1 (bad) to 5 (excellent), using the athlete's data and the conversation. " +
  "The app's rules require the coach to keep replies short (about 120 words), to put any plan change forward as a proposal the athlete approves (never to say it changed anything), to stay out of diagnosis and rehab, and to take every target from the app's rules; do not mark a reply down for following those rules. " +
  'Return a JSON object: {"scores": {<item id>: <1-5>}, "problem": "<the biggest problem in one sentence, or empty>", "better_answer": "<what you would have said, at most three sentences>"}.\n' +
  expertRubric.map(([id, text]) => `- ${id}: ${text}`).join("\n");

export function expertPrompt(input: ExpertInput): { system: string; user: string } {
  const thread = input.earlier.slice(-8).map((turn) =>
    `${turn.role === "user" ? "Athlete" : "Coach"}: ${turn.content}`
  ).join("\n\n");
  return {
    system: expertSystem,
    user: [
      `What the athlete's records show:\n<data>\n${input.digest}\n</data>`,
      `What an experienced coach would do in this conversation: ${input.coachBrief}`,
      `The conversation before this turn:\n<conversation>\n${thread || "(none)"}\n</conversation>`,
      input.lookedUp
        ? `Rows the coach looked up this turn:\n<rows>\n${clip(input.lookedUp, 4000)}\n</rows>`
        : "",
      `The athlete's message:\n<message>${input.question}</message>`,
      `The coach's reply:\n<reply>${input.reply}</reply>`,
    ].filter(Boolean).join("\n\n"),
  };
}

/** The expert verdict from the judge's answer, or null when an item is missing or out of range. */
export function parseExpertVerdict(text: string): ExpertVerdict | null {
  const json = jsonObjectIn(text);
  const scores = json?.scores as Record<string, unknown> | undefined;
  if (!scores || typeof scores !== "object") return null;
  const read: Partial<Record<ExpertItem, number>> = {};
  for (const [id] of expertRubric) {
    const value = Number(scores[id]);
    if (!Number.isInteger(value) || value < 1 || value > 5) return null;
    read[id] = value;
  }
  const values = Object.values(read) as number[];
  return {
    scores: read as Record<ExpertItem, number>,
    mean: Math.round((values.reduce((a, b) => a + b, 0) / values.length) * 100) / 100,
    pass: values.every((value) => value >= 3),
    problem: typeof json?.problem === "string" ? json.problem.trim() : "",
    betterAnswer: typeof json?.better_answer === "string" ? json.better_answer.trim() : "",
  };
}

export type JudgeCall<T> = Readonly<{ verdict: T | null; costUsd: number; failure?: string }>;

export async function judgeExpert(
  chat: RouterChat,
  model: string,
  input: ExpertInput,
): Promise<JudgeCall<ExpertVerdict>> {
  const result = await chat({ model, ...expertPrompt(input), maxTokens: 700, json: true });
  if (!result.ok) return { verdict: null, costUsd: result.costUsd, failure: result.reason };
  const verdict = parseExpertVerdict(result.text);
  return verdict
    ? { verdict, costUsd: result.costUsd }
    : { verdict: null, costUsd: result.costUsd, failure: "unreadable verdict" };
}

// ---- claim support (P1-3) -------------------------------------------------------------------

const claimSystem =
  "You check whether an AI coach's research claims are faithful to the excerpts it was shown. " +
  "You get the reply as numbered sentences and, for each research source the reply cites, the exact excerpt the coach saw. " +
  "List every sentence that states a research finding, a guideline or a figure that comes from, or is presented as coming from, research or a cited source. " +
  "Leave out sentences that only talk about the athlete's own data, plan or next session, and general coaching talk. " +
  "For each listed sentence, judge it against the excerpts only (not your own knowledge): supported (the excerpt says it), partial (the excerpt says part of it, or says it with conditions the sentence drops), or unsupported (the excerpt does not say it, or says something else). " +
  'Return a JSON object: {"claims": [{"sentence": <number>, "source": "<source id it relies on>", "verdict": "supported" | "partial" | "unsupported", "reason": "<one short sentence>"}]}. An empty list is a valid answer.';

export type ClaimInput = Readonly<{
  reply: string;
  /** The text Coach was shown for each cited source, by source id. */
  excerpts: Readonly<Record<string, string>>;
}>;

export function claimPrompt(input: ClaimInput): { system: string; user: string } {
  const sentences = sentencesOf(input.reply);
  return {
    system: claimSystem,
    user: [
      "The reply, sentence by sentence:",
      ...sentences.map((sentence, index) => `${index + 1}. ${sentence}`),
      "",
      "The excerpts the coach was shown, by source id:",
      ...Object.entries(input.excerpts).map(([id, text]) =>
        `<excerpt source="${id}">\n${clip(text, 3500)}\n</excerpt>`
      ),
    ].join("\n"),
  };
}

const claimVerdicts: readonly ClaimVerdict[] = ["supported", "partial", "unsupported"];

/**
 * The claims from the judge's answer, or null when it is unreadable. An entry naming a sentence
 * that does not exist is dropped; one naming a source the reply did not cite is unsupported (the
 * shown excerpts are the only support a claim may have).
 */
export function parseClaims(text: string, input: ClaimInput): Claim[] | null {
  const json = jsonObjectIn(text);
  if (!json || !Array.isArray(json.claims)) return null;
  const sentences = sentencesOf(input.reply);
  const claims: Claim[] = [];
  for (const raw of json.claims) {
    const entry = raw as Record<string, unknown>;
    const index = Number(entry?.sentence);
    if (!Number.isInteger(index) || index < 1 || index > sentences.length) continue;
    const verdict = claimVerdicts.find((v) => v === entry.verdict);
    if (!verdict) continue;
    const source = typeof entry.source === "string" ? entry.source : "";
    const cited = Object.hasOwn(input.excerpts, source);
    claims.push({
      sentence: sentences[index - 1],
      source,
      verdict: cited ? verdict : "unsupported",
      reason: cited
        ? (typeof entry.reason === "string" ? entry.reason.trim() : "")
        : `relies on ${source || "a source"} the reply did not cite`,
    });
  }
  return claims;
}

export async function judgeClaims(
  chat: RouterChat,
  model: string,
  input: ClaimInput,
): Promise<JudgeCall<Claim[]>> {
  const result = await chat({ model, ...claimPrompt(input), maxTokens: 900, json: true });
  if (!result.ok) return { verdict: null, costUsd: result.costUsd, failure: result.reason };
  const claims = parseClaims(result.text, input);
  return claims
    ? { verdict: claims, costUsd: result.costUsd }
    : { verdict: null, costUsd: result.costUsd, failure: "unreadable verdict" };
}
