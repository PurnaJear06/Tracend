// Retrieval evaluation for the research library: for each question in library_questions.json,
// build the query Coach chat builds (a follow-up borrows the topic of the earlier question), embed
// it with the real gte-small model, run the real hybrid search (search_library_v3, top 8, with the
// region of the athlete asking) and score recall of the sources a good answer needs, before and
// after the relevance floor Coach chat applies (retrieval.ts). Also scores full-text-only and
// vector-only searches, to show what the hybrid adds, checks that a source for another country
// never reaches an athlete outside it, and prints the sweep that calibrates the floor. Synthetic
// questions, no athlete data.
//
// It needs a database whose chunks are all embedded and an Edge runtime serving library-embed
// (local stack: `supabase start`, apply migrations, `supabase functions serve --no-verify-jwt`,
// then wait until the status line below shows every chunk embedded; see docs/handoff/research-library.md
// for the worktree-on-external-SSD workaround for `functions serve`). CI runs it in coach-eval.yml.
//
//   EVAL_SERVICE_KEY=<service role key> EVAL_WORKER_SECRET=<library_worker_secret> \
//     ./scripts/deno.sh run --allow-env --allow-net --allow-read=supabase/functions/_evals \
//     supabase/functions/_evals/library_eval.ts
//
// EVAL_SUPABASE_URL defaults to http://127.0.0.1:54321. The worker secret is the Vault secret
// `library_worker_secret` (select private.library_worker_secret() in the database).
//
// Two question files. EVAL_QUESTION_SET=calibration (the default) reads library_questions.json,
// the set the relevance floor and every threshold are chosen on, and prints the sweeps.
// EVAL_QUESTION_SET=holdout reads library_questions_holdout.json, written blind and never used to
// choose a threshold: it prints the table and the gates only, to confirm the chosen thresholds
// once. EVAL_HITS_FILE=<path> (calibration only; needs --allow-write=<path>) saves every question's
// search results as JSON, so a candidate rule can be tried offline without another run.
//
// Scores every question (single-topic, multi-source, follow-up and no-answer) and prints one table
// of recall@8 and MRR per search mode and kind; a no-answer question scores whether it was shown
// nothing (no-answer precision). This is E3's retrieval gate. Exits non-zero when a regional source
// reaches an athlete outside its region, or, for the hybrid search with the floor, mean recall in
// the top 8 falls under EVAL_MIN_RECALL (default 0.8), mean recall on the multi-source questions
// under EVAL_MIN_MULTI_RECALL (default 0.7), MRR under EVAL_MIN_MRR (default 0.5), or no-answer
// precision under EVAL_MIN_NO_ANSWER_PRECISION (default 0.7). The word-search fallback (the
// embedding failed) has its own gates: recall under EVAL_MIN_KEYWORD_RECALL (default 0.55) or
// no-answer precision under EVAL_MIN_KEYWORD_NO_ANSWER_PRECISION (default 0.7).

import { librarySources } from "../../library/index.ts";
import { embeddingModel } from "../_shared/library/embedding.ts";
import { libraryRowsOf } from "../_shared/library/live.ts";
import {
  type OnboardingLibraryFacts,
  onboardingLibraryQueries,
  type PlanFacts,
} from "../_shared/library/plan_explanation.ts";
import { libraryRetrievalQuery } from "../_shared/library/query.ts";
import {
  planLibraryBudgetChars,
  planLibraryHeading,
  planLibraryMatchCount,
} from "../_shared/library/plan_library.ts";
import {
  interleave,
  libraryBudgetChars,
  libraryKeywordFloor,
  libraryMatchCount,
  libraryRelevanceFloor,
  type LibraryRow,
  relevantRows,
  renderExcerpts,
  renderLibraryChunks,
} from "../_shared/library/retrieval.ts";
import holdoutFile from "./library_questions_holdout.json" with { type: "json" };
import planFile from "./library_questions_plan.json" with { type: "json" };
import questionFile from "./library_questions.json" with { type: "json" };
import {
  floorGrid,
  keysPassing,
  keywordGrid,
  keywordKeysPassing,
  type LibraryQuestion,
  percentile,
  questionKind,
  type QuestionScore,
  renderKeywordSweep,
  renderSweep,
  renderTable,
  type ScoredHit,
  scoreQuestion,
  summarise,
  summariseKind,
  summariseNoAnswer,
  sweepFloors,
  sweepKeywordFloors,
  topSources,
} from "./library_eval_metrics.ts";

const baseUrl = Deno.env.get("EVAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("EVAL_SERVICE_KEY") ?? "";
const workerSecret = Deno.env.get("EVAL_WORKER_SECRET") ?? "";
const minRecall = Number(Deno.env.get("EVAL_MIN_RECALL") ?? "0.8");
const minMultiRecall = Number(Deno.env.get("EVAL_MIN_MULTI_RECALL") ?? "0.7");
const minMrr = Number(Deno.env.get("EVAL_MIN_MRR") ?? "0.5");
const minNoAnswer = Number(Deno.env.get("EVAL_MIN_NO_ANSWER_PRECISION") ?? "0.7");
const minKeywordRecall = Number(Deno.env.get("EVAL_MIN_KEYWORD_RECALL") ?? "0.55");
const minKeywordNoAnswer = Number(Deno.env.get("EVAL_MIN_KEYWORD_NO_ANSWER_PRECISION") ?? "0.7");
const minPlanRecall = Number(Deno.env.get("EVAL_MIN_PLAN_RECALL") ?? "0.5");
const minOnboardingRecall = Number(Deno.env.get("EVAL_MIN_ONBOARDING_RECALL") ?? "0.4");
if (serviceKey === "" || workerSecret === "") {
  console.error("Set EVAL_SERVICE_KEY and EVAL_WORKER_SECRET.");
  Deno.exit(2);
}

const questionSet = Deno.env.get("EVAL_QUESTION_SET") ?? "calibration";
if (questionSet !== "calibration" && questionSet !== "holdout") {
  console.error(`EVAL_QUESTION_SET must be calibration or holdout, not ${questionSet}.`);
  Deno.exit(2);
}
const holdout = questionSet === "holdout";
const hitsFile = holdout ? "" : Deno.env.get("EVAL_HITS_FILE") ?? "";
const questions = (holdout ? holdoutFile : questionFile).questions as LibraryQuestion[];
console.log(`Question set: ${questionSet}, ${questions.length} questions`);
const regionsOf = new Map(librarySources.map((source) => [source.slug, source.region]));
const defaultRegion = ["global"];

async function post(path: string, bearer: string, body: unknown): Promise<unknown> {
  const response = await fetch(`${baseUrl}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${bearer}`,
      apikey: bearer,
    },
    body: JSON.stringify(body),
  });
  if (!response.ok) throw new Error(`${path} failed: ${response.status} ${await response.text()}`);
  return await response.json();
}

async function embed(texts: string[]): Promise<number[][]> {
  const embeddings: number[][] = [];
  for (let i = 0; i < texts.length; i += 5) {
    const result = await post("/functions/v1/library-embed", workerSecret, {
      texts: texts.slice(i, i + 5),
    }) as { embeddings: number[][] };
    embeddings.push(...result.embeddings);
  }
  return embeddings;
}

async function searchRows(
  text: string | null,
  embedding: number[] | null,
  region: readonly string[],
  matchCount = 8,
): Promise<LibraryRow[]> {
  return libraryRowsOf(
    await post("/rest/v1/rpc/search_library_v3", serviceKey, {
      query_text: text,
      query_embedding: embedding,
      query_embedding_model: embedding === null ? null : embeddingModel,
      match_count: matchCount,
      filters: { region },
    }),
  );
}

async function search(
  text: string | null,
  embedding: number[] | null,
  region: readonly string[],
  matchCount = 8,
): Promise<ScoredHit[]> {
  const rows = await searchRows(text, embedding, region, matchCount);
  return rows.map((row) => ({
    sourceKey: row.sourceId,
    vectorDistance: row.vectorDistance ?? null,
    textRank: row.textRank ?? null,
    text: `${row.header}\n${row.body}`,
  }));
}

const status = await post("/rest/v1/rpc/library_status_v1", serviceKey, {}) as {
  sources: number;
  chunks: number;
  embedded_chunks: number;
};
console.log(
  `Library: ${status.sources} sources, ${status.chunks} chunks, ${status.embedded_chunks} embedded`,
);
if (status.chunks === 0 || status.embedded_chunks !== status.chunks) {
  console.error("Not every chunk is embedded yet; wait for the cron job or call library-embed.");
  Deno.exit(2);
}

const queries = questions.map((question) =>
  libraryRetrievalQuery(question.text, question.previous ?? []).text
);
const embeddings = await embed(queries);
const hits = {
  hybrid: [] as ScoredHit[][],
  text: [] as ScoredHit[][],
  vector: [] as ScoredHit[][],
};
const leaks: string[] = [];
for (const [index, question] of questions.entries()) {
  const region = question.region ?? defaultRegion;
  hits.hybrid.push(await search(queries[index], embeddings[index], region));
  hits.text.push(await search(queries[index], null, region));
  hits.vector.push(await search(null, embeddings[index], region));
  // A source for another country must not reach an athlete outside it.
  for (const hit of hits.hybrid[index]) {
    if (!regionsOf.get(hit.sourceKey)?.some((code) => region.includes(code))) {
      leaks.push(`${question.id}: ${hit.sourceKey}`);
    }
  }
}

// Unfiltered: every row the search returned, as search_library_v2 showed them.
const unfiltered = (rows: readonly ScoredHit[][]): QuestionScore[] =>
  questions.map((question, index) =>
    scoreQuestion(question, rows[index].map((hit) => hit.sourceKey))
  );
const modes = {
  hybrid: unfiltered(hits.hybrid),
  hybrid_floor: questions.map((question, index) =>
    scoreQuestion(question, keysPassing(hits.hybrid[index], libraryRelevanceFloor))
  ),
  text_only: unfiltered(hits.text),
  text_floor: questions.map((question, index) =>
    scoreQuestion(
      question,
      keywordKeysPassing(hits.text[index], queries[index], libraryKeywordFloor),
    )
  ),
  vector_only: unfiltered(hits.vector),
};

const floor = libraryRelevanceFloor;
console.log(
  `\nRelevance floor: excerpts only when the nearest chunk is within cosine distance ${floor.maxTopDistance}; then chunks within ${floor.maxVectorDistance}. Word-search fallback (no embedding): the best chunk needs a rank of at least ${libraryKeywordFloor.minTopRank} and ${libraryKeywordFloor.minTopCoverage} of the question's topic words; then chunks ranked at least ${libraryKeywordFloor.minRowRank}. "hybrid" and "text_only" are unfiltered (what search_library_v2 showed); "hybrid_floor" is what Coach chat shows; "text_floor" is the word-search fallback when the embedding fails.`,
);
console.log(`\n${renderTable(modes)}`);
console.log("\nHybrid misses with the floor:");
for (const score of modes.hybrid_floor.filter((entry) => entry.missing.length > 0)) {
  console.log(`  ${score.id}: missing ${score.missing.join(", ")}`);
}

// How far the right chunks and the questions outside the library sit from the question.
const nearest = (rows: readonly ScoredHit[], keys?: readonly string[]) => {
  const distances = rows.filter((hit) => keys === undefined || keys.includes(hit.sourceKey))
    .flatMap((hit) => hit.vectorDistance === null ? [] : [hit.vectorDistance]);
  return distances.length === 0 ? null : Math.min(...distances);
};
const strongest = (rows: readonly ScoredHit[]) =>
  Math.max(0, ...rows.flatMap((hit) => hit.textRank === null ? [] : [hit.textRank]));
const answerable = questions.flatMap((question, index) =>
  questionKind(question) === "no_answer" ? [] : [nearest(hits.hybrid[index], question.expected)]
).filter((value): value is number => value !== null);
const outside = questions.flatMap((question, index) =>
  questionKind(question) === "no_answer" ? [nearest(hits.hybrid[index])] : []
).filter((value): value is number => value !== null);
const describe = (values: readonly number[]) =>
  [0.1, 0.25, 0.5, 0.75, 0.9, 1].map((p) => `p${p * 100} ${percentile(values, p).toFixed(4)}`)
    .join(", ");
console.log("\nCosine distance of the nearest chunk of an expected source (answerable questions):");
console.log(`  ${answerable.length} questions: ${describe(answerable)}`);
console.log("Cosine distance of the nearest chunk (no-answer questions):");
console.log(`  ${outside.length} questions: ${describe(outside)}`);
console.log(
  "\nNo-answer questions (nearest distance, strongest text rank, sources shown with the floor):",
);
for (const [index, question] of questions.entries()) {
  if (questionKind(question) !== "no_answer") continue;
  const shown = topSources(keysPassing(hits.hybrid[index], libraryRelevanceFloor));
  console.log(
    `  ${question.id}: ${nearest(hits.hybrid[index])?.toFixed(4) ?? "none"}, ${
      strongest(hits.hybrid[index]).toFixed(3)
    }, ${shown.length === 0 ? "nothing" : shown.join(", ")}`,
  );
}

// The tuning aids: only on the calibration set. The hold-out set confirms, it never tunes.
if (!holdout) {
  const strongestExpected = questions.flatMap((question, index) =>
    questionKind(question) === "no_answer"
      ? []
      : [strongest(hits.text[index].filter((hit) => question.expected.includes(hit.sourceKey)))]
  );
  const strongestOutside = questions.flatMap((question, index) =>
    questionKind(question) === "no_answer" ? [strongest(hits.text[index])] : []
  );
  console.log(
    "\nStrongest text rank of an expected source's chunk (answerable questions, word search):",
  );
  console.log(`  ${strongestExpected.length} questions: ${describe(strongestExpected)}`);
  console.log("Strongest text rank of any chunk (no-answer questions, word search):");
  console.log(`  ${strongestOutside.length} questions: ${describe(strongestOutside)}`);

  const steps = (from: number, to: number, by: number) =>
    Array.from({ length: Math.round((to - from) / by) + 1 }, (_, step) => from + step * by);
  console.log("\nFloor sweep, hybrid search: nearest-chunk limit by row limit:");
  console.log(
    renderSweep(
      sweepFloors(
        questions,
        hits.hybrid,
        floorGrid(steps(0.13, 0.18, 0.005), steps(0.15, 0.21, 0.01)),
      ),
    ),
  );
  console.log(
    "\nFloor sweep, word search alone (the fallback): best chunk's rank by its share of the question's topic words, row rank 0.002:",
  );
  console.log(
    renderKeywordSweep(
      sweepKeywordFloors(
        questions,
        hits.text,
        queries,
        keywordGrid(steps(0.003, 0.008, 0.0005), [0, 0.2, 0.25, 0.3, 0.35, 0.4, 0.45, 0.5], [
          0.002,
        ]),
      ),
    ),
  );
  console.log(
    "\nFloor sweep, word search alone: the row rank at the chosen top rank and coverage:",
  );
  console.log(
    renderKeywordSweep(
      sweepKeywordFloors(
        questions,
        hits.text,
        queries,
        keywordGrid(
          [libraryKeywordFloor.minTopRank],
          [libraryKeywordFloor.minTopCoverage],
          [0, 0.002, 0.003, 0.004, 0.005],
        ),
      ),
    ),
  );
}

if (hitsFile !== "") {
  await Deno.writeTextFile(
    hitsFile,
    JSON.stringify({
      floor: libraryRelevanceFloor,
      questions: questions.map((question, index) => ({
        question,
        query: queries[index],
        hybrid: hits.hybrid[index].map(({ text: _, ...hit }) => hit),
        text: hits.text[index],
        vector: hits.vector[index].map(({ text: _, ...hit }) => hit),
      })),
    }),
  );
  console.log(`\nSearch results saved to ${hitsFile}`);
}

// Plan explanations (chunk E5). A plan question is searched as Coach chat searches it: as asked and
// with the plan topics added, the two lists (each with the floor) merged; the lift is measured
// against the bare question. The onboarding plan's two searches (training, nutrition) are scored the
// same way against the sources a good plan prompt needs. The calibration set above is untouched.
type PlanQuestion = LibraryQuestion & { plan: PlanFacts };
type OnboardingCase = { id: string; facts: OnboardingLibraryFacts; expected: string[] };
const planQuestions = planFile.questions as unknown as PlanQuestion[];
const onboardingCases = planFile.onboarding as unknown as OnboardingCase[];
// The sources a search (or two, merged) actually shows: each list passes the floor, the lists are
// merged as production merges them, and the block is rendered at production's character budget, so
// a chunk that would not fit is not counted as found.
type Renderer = (rows: readonly LibraryRow[]) => { shown: Readonly<Record<string, unknown>> };
const shownKeys = async (
  texts: readonly string[],
  matchCount: number,
  render: Renderer,
): Promise<string[]> => {
  const vectors = await embed([...texts]);
  const lists: LibraryRow[][] = [];
  for (const [index, text] of texts.entries()) {
    lists.push(relevantRows(await searchRows(text, vectors[index], defaultRegion, matchCount)));
  }
  return Object.keys(render(lists.length === 1 ? lists[0] : interleave(lists)).shown);
};
const coachBlock = (planExplanation: boolean): Renderer => (rows) =>
  renderLibraryChunks(rows, libraryBudgetChars, false, planExplanation);
const onboardingBlock: Renderer = (rows) =>
  renderExcerpts(rows, planLibraryBudgetChars, planLibraryHeading, "");
const planScores = async (
  searches: (question: PlanQuestion) => readonly string[],
  render: Renderer,
) => {
  const scores: QuestionScore[] = [];
  for (const question of planQuestions) {
    scores.push(
      scoreQuestion(question, await shownKeys(searches(question), libraryMatchCount, render)),
    );
  }
  return scores;
};
// The hold-out run confirms the floor on the hold-out set only.
const enrichedPlan = holdout ? [] : await planScores((question) => {
  const query = libraryRetrievalQuery(question.text, [], question.plan);
  return [query.text, query.planText!];
}, coachBlock(true));
const barePlan = holdout ? [] : await planScores((question) => [question.text], coachBlock(false));
const onboardingScores: QuestionScore[] = [];
if (!holdout) {
  for (const entry of onboardingCases) {
    onboardingScores.push(
      scoreQuestion(
        { id: entry.id, text: "", expected: entry.expected },
        await shownKeys(
          onboardingLibraryQueries(entry.facts),
          planLibraryMatchCount,
          onboardingBlock,
        ),
      ),
    );
  }
}
const planSummary = summarise(enrichedPlan);
const onboardingSummary = summarise(onboardingScores);
if (!holdout) {
  console.log(
    `\nPlan explanations (${planQuestions.length} questions, with the floor): mean recall ${
      planSummary.meanRecall.toFixed(3)
    }, MRR ${planSummary.mrr.toFixed(3)}, every source found ${
      (planSummary.fullRecall * 100).toFixed(0)
    }%; the bare question gives ${summarise(barePlan).meanRecall.toFixed(3)}`,
  );
  for (const score of enrichedPlan.filter((entry) => entry.missing.length > 0)) {
    console.log(`  ${score.id}: missing ${score.missing.join(", ")}`);
  }
  console.log(
    `Onboarding plan searches (${onboardingCases.length} athletes, with the floor): mean recall ${
      onboardingSummary.meanRecall.toFixed(3)
    }, every source found ${(onboardingSummary.fullRecall * 100).toFixed(0)}%`,
  );
  for (const score of onboardingScores) {
    console.log(
      `  ${score.id}: found ${score.found.length} of ${score.found.length + score.missing.length}${
        score.missing.length === 0 ? "" : `, missing ${score.missing.join(", ")}`
      }`,
    );
  }
}

const floored = modes.hybrid_floor;
const hybrid = summarise(floored);
const multi = summariseKind(floored, "multi_source");
const followUp = summariseKind(floored, "follow_up");
const noAnswer = summariseNoAnswer(floored);
const keyword = summarise(modes.text_floor);
const keywordNoAnswer = summariseNoAnswer(modes.text_floor);
console.log(
  `\nFollow-up questions: ${followUp.questions}, mean recall ${followUp.meanRecall.toFixed(3)}`,
);
console.log(`Regional sources shown to athletes outside their region: ${leaks.length}`);
for (const leak of leaks) console.log(`  ${leak}`);
const failures = [
  leaks.length > 0 && `${leaks.length} regional sources reached the wrong athletes`,
  hybrid.meanRecall < minRecall &&
  `mean recall ${hybrid.meanRecall.toFixed(3)} is under ${minRecall}`,
  multi.meanRecall < minMultiRecall &&
  `multi-source recall ${multi.meanRecall.toFixed(3)} is under ${minMultiRecall}`,
  hybrid.mrr < minMrr && `MRR ${hybrid.mrr.toFixed(3)} is under ${minMrr}`,
  noAnswer.precision < minNoAnswer &&
  `no-answer precision ${noAnswer.precision.toFixed(3)} is under ${minNoAnswer}`,
  keyword.meanRecall < minKeywordRecall &&
  `word-search recall ${keyword.meanRecall.toFixed(3)} is under ${minKeywordRecall}`,
  !holdout && planSummary.meanRecall < minPlanRecall &&
  `plan-explanation recall ${planSummary.meanRecall.toFixed(3)} is under ${minPlanRecall}`,
  !holdout && onboardingSummary.meanRecall < minOnboardingRecall &&
  `onboarding plan recall ${
    onboardingSummary.meanRecall.toFixed(3)
  } is under ${minOnboardingRecall}`,
  keywordNoAnswer.precision < minKeywordNoAnswer &&
  `word-search no-answer precision ${
    keywordNoAnswer.precision.toFixed(3)
  } is under ${minKeywordNoAnswer}`,
].filter((failure): failure is string => failure !== false);
if (failures.length > 0) {
  console.error(`\n${failures.join("\n")}`);
  Deno.exit(1);
}
