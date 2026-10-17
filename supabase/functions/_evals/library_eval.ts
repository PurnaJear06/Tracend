// Retrieval evaluation for the research library: for each question in library_questions.json,
// embed it with the real gte-small model, run the real hybrid search (search_library_v1, top 8)
// and score recall of the sources a good answer needs. Also scores full-text-only and
// vector-only searches, to show what the hybrid adds. Synthetic questions, no athlete data.
//
// It needs a database whose chunks are all embedded and an Edge runtime serving library-embed
// (local stack: `supabase start`, apply migrations, `supabase functions serve --no-verify-jwt`,
// then wait until the status line below shows every chunk embedded; see docs/handoff/research-library.md
// for the worktree-on-external-SSD workaround for `functions serve`).
//
//   EVAL_SERVICE_KEY=<service role key> EVAL_WORKER_SECRET=<library_worker_secret> \
//     ./scripts/deno.sh run --allow-env --allow-net --allow-read=supabase/functions/_evals \
//     supabase/functions/_evals/library_eval.ts
//
// EVAL_SUPABASE_URL defaults to http://127.0.0.1:54321. The worker secret is the Vault secret
// `library_worker_secret` (select private.library_worker_secret() in the database).
// Scores every question (single-topic, multi-source and no-answer, library_questions.json) and
// prints one table of recall@8 and MRR per search mode and kind. A no_answer question is not
// scored: the search returns its nearest chunks whatever the question, so the table lists the
// sources it brought back for review; whether Coach then declines is graded by the answer bank.
// Exits non-zero when, for the hybrid search, mean recall in the top 8 falls under EVAL_MIN_RECALL
// (default 0.8), mean recall on the multi-source questions under EVAL_MIN_MULTI_RECALL (default
// 0.7), or MRR under EVAL_MIN_MRR (default 0.5). The last two are first estimates: the first run
// that measures them sets the floor to keep.

import { librarySources } from "../../library/index.ts";
import questionFile from "./library_questions.json" with { type: "json" };
import {
  type LibraryQuestion,
  type QuestionScore,
  renderTable,
  scoreQuestion,
  summarise,
  summariseKind,
  topSources,
} from "./library_eval_metrics.ts";

const baseUrl = Deno.env.get("EVAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("EVAL_SERVICE_KEY") ?? "";
const workerSecret = Deno.env.get("EVAL_WORKER_SECRET") ?? "";
const minRecall = Number(Deno.env.get("EVAL_MIN_RECALL") ?? "0.8");
const minMultiRecall = Number(Deno.env.get("EVAL_MIN_MULTI_RECALL") ?? "0.7");
const minMrr = Number(Deno.env.get("EVAL_MIN_MRR") ?? "0.5");
if (serviceKey === "" || workerSecret === "") {
  console.error("Set EVAL_SERVICE_KEY and EVAL_WORKER_SECRET.");
  Deno.exit(2);
}

const questions = questionFile.questions as LibraryQuestion[];
const keyByUrl = new Map(librarySources.map((source) => [source.url, source.slug]));

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

type Hit = Readonly<{ url: string }>;

async function search(
  text: string | null,
  embedding: number[] | null,
): Promise<string[]> {
  const rows = await post("/rest/v1/rpc/search_library_v1", serviceKey, {
    query_text: text,
    query_embedding: embedding,
    match_count: 8,
    filters: null,
  }) as Hit[];
  return rows.flatMap((row) => {
    const key = keyByUrl.get(row.url);
    return key === undefined ? [] : [key];
  });
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

const embeddings = await embed(questions.map((question) => question.text));
const modes = {
  hybrid: [] as QuestionScore[],
  text_only: [] as QuestionScore[],
  vector_only: [] as QuestionScore[],
};
for (const [index, question] of questions.entries()) {
  modes.hybrid.push(scoreQuestion(question, await search(question.text, embeddings[index])));
  modes.text_only.push(scoreQuestion(question, await search(question.text, null)));
  modes.vector_only.push(scoreQuestion(question, await search(null, embeddings[index])));
}

console.log(`\n${renderTable(modes)}`);
console.log("\nHybrid misses:");
for (const score of modes.hybrid.filter((entry) => entry.missing.length > 0)) {
  console.log(`  ${score.id}: missing ${score.missing.join(", ")}`);
}
console.log("\nNo-answer questions (nearest sources the hybrid search returned):");
for (const score of modes.hybrid.filter((entry) => entry.kind === "no_answer")) {
  console.log(`  ${score.id}: ${topSources(score.retrieved).join(", ")}`);
}

const hybrid = summarise(modes.hybrid);
const multi = summariseKind(modes.hybrid, "multi_source");
const failures = [
  hybrid.meanRecall < minRecall &&
  `mean recall ${hybrid.meanRecall.toFixed(3)} is under ${minRecall}`,
  multi.meanRecall < minMultiRecall &&
  `multi-source recall ${multi.meanRecall.toFixed(3)} is under ${minMultiRecall}`,
  hybrid.mrr < minMrr && `MRR ${hybrid.mrr.toFixed(3)} is under ${minMrr}`,
].filter((failure): failure is string => failure !== false);
if (failures.length > 0) {
  console.error(`\n${failures.join("\n")}`);
  Deno.exit(1);
}
