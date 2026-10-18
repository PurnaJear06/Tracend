// Scoring for E3's head-to-head check (library_head_to_head.ts): the same questions answered end to
// end with retrieval and with the whole library in the cached prefix. Pure, so it is tested.

export type ArmAnswer = Readonly<{
  /** The model answered (not the labelled data summary, not a failure). */
  answered: boolean;
  /** Library source ids the reply's evidence cited. */
  cited: readonly string[];
  /** The sources a good answer needs (library_questions.json). */
  expected: readonly string[];
  /** Tokens read from the cache, written to it and sent uncached, all attempts of the turn. */
  cacheReadTokens: number;
  cacheWriteTokens: number;
  inputTokens: number;
  outputTokens: number;
  costUsd: number;
  latencyMs: number;
  /** The reply was repaired: the first attempt broke a guard rule. */
  repaired: boolean;
}>;

export type ArmSummary = Readonly<{
  questions: number;
  answeredRate: number;
  /** Share of answered replies that cite at least one expected source. */
  citesExpected: number;
  /** Mean share of the expected sources an answered reply cites. */
  meanExpectedCited: number;
  /** Share of cited ids that are expected sources (precision). */
  citationPrecision: number;
  repairRate: number;
  meanCostUsd: number;
  meanLatencyMs: number;
  meanCacheReadTokens: number;
  meanCacheWriteTokens: number;
  meanUncachedInputTokens: number;
}>;

const mean = (values: readonly number[]) =>
  values.length === 0 ? 0 : values.reduce((sum, value) => sum + value, 0) / values.length;

export function summariseArm(answers: readonly ArmAnswer[]): ArmSummary {
  const answered = answers.filter((answer) => answer.answered);
  const withExpected = answered.filter((answer) => answer.expected.length > 0);
  const cited = answered.flatMap((answer) =>
    answer.cited.map((key) => answer.expected.includes(key))
  );
  return {
    questions: answers.length,
    answeredRate: answers.length === 0 ? 0 : answered.length / answers.length,
    citesExpected: withExpected.length === 0
      ? 0
      : withExpected.filter((answer) => answer.cited.some((key) => answer.expected.includes(key)))
        .length / withExpected.length,
    meanExpectedCited: mean(
      withExpected.map((answer) =>
        answer.expected.filter((key) => answer.cited.includes(key)).length / answer.expected.length
      ),
    ),
    citationPrecision: cited.length === 0 ? 0 : cited.filter(Boolean).length / cited.length,
    repairRate: answers.length === 0
      ? 0
      : answers.filter((answer) => answer.repaired).length / answers.length,
    meanCostUsd: mean(answers.map((answer) => answer.costUsd)),
    meanLatencyMs: mean(answers.map((answer) => answer.latencyMs)),
    meanCacheReadTokens: mean(answers.map((answer) => answer.cacheReadTokens)),
    meanCacheWriteTokens: mean(answers.map((answer) => answer.cacheWriteTokens)),
    meanUncachedInputTokens: mean(answers.map((answer) => answer.inputTokens)),
  };
}

const pct = (value: number) => `${(value * 100).toFixed(0)}%`;

/** One table, a column per arm. */
export function renderHeadToHead(arms: Readonly<Record<string, ArmSummary>>): string {
  const names = Object.keys(arms);
  const rows: [string, (summary: ArmSummary) => string][] = [
    ["questions", (s) => String(s.questions)],
    ["answered by the model", (s) => pct(s.answeredRate)],
    ["cites an expected source", (s) => pct(s.citesExpected)],
    ["expected sources cited (mean)", (s) => pct(s.meanExpectedCited)],
    ["citation precision", (s) => pct(s.citationPrecision)],
    ["needed a repair", (s) => pct(s.repairRate)],
    ["cost per turn (USD)", (s) => s.meanCostUsd.toFixed(5)],
    ["latency per turn (ms)", (s) => String(Math.round(s.meanLatencyMs))],
    ["cache read tokens per turn", (s) => String(Math.round(s.meanCacheReadTokens))],
    ["cache write tokens per turn", (s) => String(Math.round(s.meanCacheWriteTokens))],
    ["uncached input tokens per turn", (s) => String(Math.round(s.meanUncachedInputTokens))],
  ];
  const header = `| measure | ${names.join(" | ")} |`;
  const rule = `|---|${names.map(() => "---").join("|")}|`;
  return [
    header,
    rule,
    ...rows.map(([label, read]) => `| ${label} | ${names.map((n) => read(arms[n])).join(" | ")} |`),
  ].join("\n");
}
