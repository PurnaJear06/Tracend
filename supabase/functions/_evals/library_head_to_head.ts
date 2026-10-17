// E3's head-to-head check: the retrieval questions answered end to end by Coach with retrieval (the
// shipped path: the chunks found for this question, after the athlete data) against the whole
// library in the cached prefix. Both arms use the production gateway path, so the citation guard
// and the numbers check judge both. It reports citations, repairs, cost, latency and cache use.
// Coach chat ships retrieval; this exists to re-run the comparison when the library grows (the
// design says to revisit at about 100,000 tokens) or the model changes.
//
// It needs the same database as library_eval.ts (every chunk embedded, library-embed served) and a
// gateway route with a key, because only the gateway carries library citations:
//
//   AI_COACH_CHAT_PROVIDER=anthropic AI_COACH_CHAT_MODEL=claude-haiku-5-5 \
//   AI_COACH_CHAT_MAX_OUTPUT_TOKENS=4096 AI_COACH_CHAT_TIMEOUT_MS=30000 AI_COACH_CHAT_EVALUATED=true \
//   ANTHROPIC_API_KEY=... EVAL_SERVICE_KEY=... EVAL_WORKER_SECRET=... \
//     ./scripts/deno.sh run --allow-env --allow-net --allow-read=supabase/functions/_evals \
//     supabase/functions/_evals/library_head_to_head.ts
//
// EVAL_QUESTIONS (default 24) takes an evenly spread sample of the answerable questions, and
// EVAL_MAX_USD (default 2) stops the run. Questions run one after another, so the shared prefix
// is cached after the first, as it would be for an athlete asking several questions in a row.
// Synthetic data only.
import { renderCoachContext } from "../_shared/coach_context/host.ts";
import { coachingPrinciplesContributor } from "../_shared/library/principles.ts";
import {
  createLibraryContributor,
  type LibraryRow,
  shownLibraryKeysIn,
} from "../_shared/library/retrieval.ts";
import { classifyQuestion } from "../_shared/providers/coach_chat_provider.ts";
import { baseContext } from "./coach_bank/athletes.ts";
import { fullLibraryBlock, fullLibrarySize } from "./library_full.ts";
import { type ArmAnswer, renderHeadToHead, summariseArm } from "./library_head_to_head_metrics.ts";
import { type LibraryQuestion, questionKind } from "./library_eval_metrics.ts";
import { liveModelFromEnv } from "./live_model.ts";
import questionFile from "./library_questions.json" with { type: "json" };

const baseUrl = Deno.env.get("EVAL_SUPABASE_URL") ?? "http://127.0.0.1:54321";
const serviceKey = Deno.env.get("EVAL_SERVICE_KEY") ?? "";
const workerSecret = Deno.env.get("EVAL_WORKER_SECRET") ?? "";
const sample = Number(Deno.env.get("EVAL_QUESTIONS") ?? "24");
const maxUsd = Number(Deno.env.get("EVAL_MAX_USD") ?? "2");

const live = liveModelFromEnv();
if ("error" in live || serviceKey === "" || workerSecret === "") {
  console.error(
    "error" in live ? live.error : "Set EVAL_SERVICE_KEY and EVAL_WORKER_SECRET.",
  );
  Deno.exit(2);
}
if (!live.coachRoute) {
  console.error(
    "Library citations exist only on the gateway route: set the AI_COACH_CHAT_* settings.",
  );
  Deno.exit(2);
}

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

// The production contributor over the evaluation's database and embedding endpoint.
const retrieval = createLibraryContributor({
  embed: () => async (text) =>
    ((await post("/functions/v1/library-embed", workerSecret, { texts: [text] })) as {
      embeddings: number[][];
    }).embeddings[0],
  search: async (request) => {
    const rows = await post("/rest/v1/rpc/search_library_v2", serviceKey, {
      query_text: request.text,
      query_embedding: request.embedding,
      match_count: request.matchCount,
      filters: { region: ["global"] },
    }) as { source_key: string; header: string; body: string }[];
    return rows.map((row): LibraryRow => ({
      sourceId: row.source_key,
      header: row.header,
      body: row.body,
    }));
  },
});

const questions = (questionFile.questions as LibraryQuestion[]).filter((question) =>
  questionKind(question) !== "no_answer" && question.region === undefined
);
const step = Math.max(1, Math.floor(questions.length / Math.max(1, sample)));
const chosen = questions.filter((_, index) => index % step === 0).slice(0, sample);

const size = fullLibrarySize();
console.log(
  `Whole library: ${size.sources} sources, ${size.chunks} chunks, ${size.chars} characters, about ${size.tokens.low} to ${size.tokens.high} tokens`,
);
console.log(`Model: ${live.model}. ${chosen.length} questions, two arms each.\n`);

const arms = { retrieval: [] as ArmAnswer[], full_library: [] as ArmAnswer[] };
let spent = 0;
for (const question of chosen) {
  if (spent >= maxUsd) {
    console.log(`Stopped at ${spent.toFixed(2)} USD (EVAL_MAX_USD).`);
    break;
  }
  const context = baseContext("rich");
  const previous = question.previous ?? [];
  const input = {
    userId: "eval-athlete",
    question: question.text,
    localDate: String(context.coaching_date),
    previousQuestions: previous,
  };
  const withRetrieval = await renderCoachContext([coachingPrinciplesContributor, retrieval], input);
  const digest = await renderCoachContext([coachingPrinciplesContributor], input);
  const withFull = { ...digest, stable: `${digest.stable}\n\n${fullLibraryBlock()}` };
  for (
    const [arm, contributions] of [["retrieval", withRetrieval], [
      "full_library",
      withFull,
    ]] as const
  ) {
    const answer: ArmAnswer = await (async () => {
      const base = {
        expected: question.expected,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        inputTokens: 0,
        outputTokens: 0,
        costUsd: 0,
        latencyMs: 0,
        repaired: false,
      };
      try {
        const generation = await live.generate({
          question: question.text,
          context: structuredClone(context),
          contextKind: classifyQuestion(question.text),
          contributions,
        });
        const shown = shownLibraryKeysIn(contributions);
        const attempts = generation.attempts ?? [];
        const sum = (read: (a: (typeof attempts)[number]) => number | undefined) =>
          attempts.reduce((total, a) => total + (read(a) ?? 0), 0);
        return {
          ...base,
          answered: true,
          cited: generation.answer.evidence.filter((item) =>
            item.source === "library" && shown.has(item.code)
          ).map((item) => item.code),
          cacheReadTokens: sum((a) => a.cacheReadTokens),
          cacheWriteTokens: sum((a) => a.cacheWriteTokens),
          inputTokens: sum((a) => a.promptTokens) - sum((a) => a.cacheReadTokens) -
            sum((a) => a.cacheWriteTokens),
          outputTokens: generation.outputUnits,
          costUsd: generation.estimatedCostUsd,
          latencyMs: sum((a) => a.latencyMs),
          repaired: attempts.some((a) => a.attempt === "repair"),
        };
      } catch {
        return { ...base, answered: false, cited: [] };
      }
    })();
    arms[arm].push(answer);
    spent += answer.costUsd;
  }
}

console.log(renderHeadToHead({
  retrieval: summariseArm(arms.retrieval),
  full_library: summariseArm(arms.full_library),
}));
