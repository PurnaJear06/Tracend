// Scoring for the library retrieval evaluation (library_eval.ts): recall of the sources a good
// answer needs among the sources in the top results, and the mean reciprocal rank of the first one.

/**
 * single: one topic's sources. multi_source: sources from two or three topics, so a good answer
 * needs chunks from each. follow_up: a question with no topic of its own that follows an earlier
 * question (`previous`); it is searched with that question's topic and expects that question's
 * sources. no_answer: outside the library (medication, rehabilitation, pregnancy, minors, medical
 * diets, eating disorders, medical reports, drugs); nothing is expected, and a good answer says
 * the library does not cover it.
 */
export type QuestionKind = "single" | "multi_source" | "follow_up" | "no_answer";

export const questionKinds: readonly QuestionKind[] = [
  "single",
  "multi_source",
  "follow_up",
  "no_answer",
];

export type LibraryQuestion = Readonly<{
  id: string;
  text: string;
  kind?: QuestionKind;
  /** Manifest keys of the sources a good answer needs; empty for a no_answer question. */
  expected: readonly string[];
  /** The athlete's earlier questions in the conversation, newest first (follow_up questions). */
  previous?: readonly string[];
  /** The regions of the athlete asking, for example ["global", "IN"]; default ["global"]. */
  region?: readonly string[];
}>;

export type QuestionScore = Readonly<{
  id: string;
  kind: QuestionKind;
  recall: number;
  /** 1 / (rank of the first expected source among the results), 0 when none was found. */
  reciprocalRank: number;
  found: readonly string[];
  missing: readonly string[];
  /** The result list as source keys, best first (a source appears once per chunk). */
  retrieved: readonly string[];
}>;

export type EvalSummary = Readonly<{
  /** Questions that expect sources (a no_answer question is not scored). */
  questions: number;
  meanRecall: number;
  /** Share of questions where every expected source was in the results. */
  fullRecall: number;
  /** Share of questions where at least one expected source was in the results. */
  anyRecall: number;
  /** Mean reciprocal rank of the first expected source. */
  mrr: number;
}>;

export const questionKind = (question: LibraryQuestion): QuestionKind => question.kind ?? "single";

/**
 * Recall of the expected sources among the retrieved source keys (duplicates ignored), and the
 * reciprocal rank of the first expected source in the ranked list.
 */
export function scoreQuestion(
  question: LibraryQuestion,
  retrievedKeys: readonly string[],
): QuestionScore {
  const retrieved = new Set(retrievedKeys);
  const found = question.expected.filter((key) => retrieved.has(key));
  const missing = question.expected.filter((key) => !retrieved.has(key));
  const firstRank = retrievedKeys.findIndex((key) => question.expected.includes(key)) + 1;
  return {
    id: question.id,
    kind: questionKind(question),
    recall: question.expected.length === 0 ? 1 : found.length / question.expected.length,
    reciprocalRank: firstRank === 0 ? 0 : 1 / firstRank,
    found,
    missing,
    retrieved: retrievedKeys,
  };
}

const answerable = (scores: readonly QuestionScore[]) =>
  scores.filter((score) => score.kind !== "no_answer");

export function summarise(scores: readonly QuestionScore[]): EvalSummary {
  const scored = answerable(scores);
  const count = scored.length;
  if (count === 0) return { questions: 0, meanRecall: 0, fullRecall: 0, anyRecall: 0, mrr: 0 };
  return {
    questions: count,
    meanRecall: scored.reduce((sum, score) => sum + score.recall, 0) / count,
    fullRecall: scored.filter((score) => score.missing.length === 0).length / count,
    anyRecall: scored.filter((score) => score.found.length > 0).length / count,
    mrr: scored.reduce((sum, score) => sum + score.reciprocalRank, 0) / count,
  };
}

/** The summary for the questions of one kind. */
export function summariseKind(scores: readonly QuestionScore[], kind: QuestionKind): EvalSummary {
  return summarise(scores.filter((score) => score.kind === kind));
}

const percent = (value: number) => `${(value * 100).toFixed(0)}%`.padStart(4);

/**
 * The results table: one row per search mode and question kind, recall in the top results, the
 * share with every source found, and MRR. A no_answer row only counts the questions.
 */
export function renderTable(modes: Readonly<Record<string, readonly QuestionScore[]>>): string {
  const lines = [
    "mode         questions        n  recall@8  all found  any found    MRR",
    "-----------  ---------  -------  --------  ---------  ---------  -----",
  ];
  for (const [mode, scores] of Object.entries(modes)) {
    const rows: [string, EvalSummary][] = [
      ["all scored", summarise(scores)],
      ["single", summariseKind(scores, "single")],
      ["multi_source", summariseKind(scores, "multi_source")],
      ["follow_up", summariseKind(scores, "follow_up")],
    ];
    for (const [label, summary] of rows) {
      if (summary.questions === 0) continue;
      lines.push(
        `${mode.padEnd(11)}  ${label.padEnd(9)}  ${String(summary.questions).padStart(7)}  ${
          summary.meanRecall.toFixed(3).padStart(8)
        }  ${percent(summary.fullRecall).padStart(9)}  ${percent(summary.anyRecall).padStart(9)}  ${
          summary.mrr.toFixed(3)
        }`,
      );
    }
    const none = scores.filter((score) => score.kind === "no_answer").length;
    if (none > 0) {
      lines.push(`${mode.padEnd(11)}  no_answer  ${String(none).padStart(7)}  (not scored)`);
    }
  }
  return lines.join("\n");
}

/** The distinct sources a result list names, best first, at most `limit`. */
export function topSources(retrieved: readonly string[], limit = 3): string[] {
  return [...new Set(retrieved)].slice(0, limit);
}
