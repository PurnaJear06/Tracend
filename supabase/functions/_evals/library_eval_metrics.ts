// Scoring for the library retrieval evaluation (library_eval.ts): recall of the sources a good
// answer needs among the sources in the top results.

export type LibraryQuestion = Readonly<{
  id: string;
  text: string;
  /** Manifest keys of the sources a good answer needs. */
  expected: readonly string[];
}>;

export type QuestionScore = Readonly<{
  id: string;
  recall: number;
  found: readonly string[];
  missing: readonly string[];
}>;

export type EvalSummary = Readonly<{
  questions: number;
  meanRecall: number;
  /** Share of questions where every expected source was in the results. */
  fullRecall: number;
  /** Share of questions where at least one expected source was in the results. */
  anyRecall: number;
}>;

/** Recall of the expected sources among the retrieved source keys (duplicates ignored). */
export function scoreQuestion(
  question: LibraryQuestion,
  retrievedKeys: readonly string[],
): QuestionScore {
  const retrieved = new Set(retrievedKeys);
  const found = question.expected.filter((key) => retrieved.has(key));
  const missing = question.expected.filter((key) => !retrieved.has(key));
  return {
    id: question.id,
    recall: question.expected.length === 0 ? 1 : found.length / question.expected.length,
    found,
    missing,
  };
}

export function summarise(scores: readonly QuestionScore[]): EvalSummary {
  const count = scores.length;
  if (count === 0) return { questions: 0, meanRecall: 0, fullRecall: 0, anyRecall: 0 };
  return {
    questions: count,
    meanRecall: scores.reduce((sum, score) => sum + score.recall, 0) / count,
    fullRecall: scores.filter((score) => score.missing.length === 0).length / count,
    anyRecall: scores.filter((score) => score.found.length > 0 || score.recall === 1).length /
      count,
  };
}
