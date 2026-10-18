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
// Scores every question (single-topic, multi-source, follow-up and no-answer) and prints one table
// of recall@8 and MRR per search mode and kind; a no-answer question scores whether it was shown
// nothing (no-answer precision). This is E3's retrieval gate. Exits non-zero when a regional source
// reaches an athlete outside its region, or, for the hybrid search with the floor, mean recall in
// the top 8 falls under EVAL_MIN_RECALL (default 0.8), mean recall on the multi-source questions
// under EVAL_MIN_MULTI_RECALL (default 0.7), MRR under EVAL_MIN_MRR (default 0.5), or no-answer
// precision under EVAL_MIN_NO_ANSWER_PRECISION (default 0.7).

import { librarySources } from "../../library/index.ts";
import { embeddingModel } from "../_shared/library/embedding.ts";
import { libraryRowsOf } from "../_shared/library/live.ts";
import { libraryRetrievalQuery } from "../_shared/library/query.ts";
import { libraryRelevanceFloor } from "../_shared/library/retrieval.ts";
import questionFile from "./library_questions.json" with { type: "json" };
import {
  keysPassing,
  type LibraryQuestion,
  percentile,
  questionKind,
  type QuestionScore,
  renderSweep,
  renderTable,
  type ScoredHit,
  scoreQuestion,
  summarise,
  summariseKind,
  summariseNoAnswer,
  sweepFloors,
  topSources,
} from "./library_eval_metrics.ts";

const baseUrl = Deno.env.get("EVAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("EVAL_SERVICE_KEY") ?? "";
const workerSecret = Deno.env.get("EVAL_WORKER_SECRET") ?? "";
const minRecall = Number(Deno.env.get("EVAL_MIN_RECALL") ?? "0.8");
const minMultiRecall = Number(Deno.env.get("EVAL_MIN_MULTI_RECALL") ?? "0.7");
const minMrr = Number(Deno.env.get("EVAL_MIN_MRR") ?? "0.5");
const minNoAnswer = Number(Deno.env.get("EVAL_MIN_NO_ANSWER_PRECISION") ?? "0.7");
if (serviceKey === "" || workerSecret === "") {
  console.error("Set EVAL_SERVICE_KEY and EVAL_WORKER_SECRET.");
  Deno.exit(2);
}

const questions = questionFile.questions as LibraryQuestion[];
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

async function search(
  text: string | null,
  embedding: number[] | null,
  region: readonly string[],
): Promise<ScoredHit[]> {
  const rows = libraryRowsOf(
    await post("/rest/v1/rpc/search_library_v3", serviceKey, {
      query_text: text,
      query_embedding: embedding,
      query_embedding_model: embedding === null ? null : embeddingModel,
      match_count: 8,
      filters: { region },
    }),
  );
  return rows.map((row) => ({
    sourceKey: row.sourceId,
    vectorDistance: row.vectorDistance ?? null,
    textRank: row.textRank ?? null,
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

const unfloored = { maxVectorDistance: Number.POSITIVE_INFINITY, strongTextRank: 0 };
const scored = (rows: readonly ScoredHit[][], floor = unfloored): QuestionScore[] =>
  questions.map((question, index) => scoreQuestion(question, keysPassing(rows[index], floor)));
const modes = {
  hybrid: scored(hits.hybrid),
  hybrid_floor: scored(hits.hybrid, libraryRelevanceFloor),
  text_only: scored(hits.text),
  text_floor: scored(hits.text, libraryRelevanceFloor),
  vector_only: scored(hits.vector),
};

console.log(
  `\nRelevance floor: cosine distance at most ${libraryRelevanceFloor.maxVectorDistance}, or a text rank of at least ${libraryRelevanceFloor.strongTextRank}. "hybrid" and "text_only" are unfiltered (what search_library_v2 showed); "hybrid_floor" is what Coach chat shows; "text_floor" is the word-search fallback when the embedding fails.`,
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

const distanceSteps = Array.from({ length: 21 }, (_, step) => 0.1 + step * 0.01);
console.log(
  "\nFloor sweep, hybrid search (strong text rank 'none' keeps a row on its distance alone):",
);
console.log(
  renderSweep(
    sweepFloors(questions, hits.hybrid, distanceSteps, [
      Number.POSITIVE_INFINITY,
      0.05,
      0.1,
      0.15,
      0.2,
    ]),
  ),
);
console.log("\nFloor sweep, word search alone (the fallback), by strong text rank:");
console.log(
  renderSweep(sweepFloors(questions, hits.text, [0], [0.01, 0.02, 0.05, 0.1, 0.15, 0.2])),
);

const floored = modes.hybrid_floor;
const hybrid = summarise(floored);
const multi = summariseKind(floored, "multi_source");
const followUp = summariseKind(floored, "follow_up");
const noAnswer = summariseNoAnswer(floored);
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
].filter((failure): failure is string => failure !== false);
if (failures.length > 0) {
  console.error(`\n${failures.join("\n")}`);
  Deno.exit(1);
}
