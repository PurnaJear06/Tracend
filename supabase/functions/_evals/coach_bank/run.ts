// The live Coach answer bank: every case, run against the real model through the production path,
// graded by code (and, when configured, a tone judge), gated as report.ts describes.
//
//   ./scripts/deno.sh run --allow-env --allow-net --allow-read --allow-write \
//     supabase/functions/_evals/coach_bank/run.ts
//
// The model comes from live_model.ts: a gateway route from AI_COACH_CHAT_*, else the router
// gateway route when EVAL_BASE_URL and EVAL_API_KEY are set (the production gateway path over the
// eval router, so the library cases run too), else DeepSeek. Optional: EVAL_REPEATS (default 3 per model case), EVAL_CONCURRENCY (default 4),
// EVAL_MAX_USD (default 3; the run stops there and fails), EVAL_REPORT_DIR (default
// .tooling/coach-evals/<timestamp>), EVAL_CASES (comma-separated id parts to run a few cases) and
// the tone judge settings in judge.ts. Exits 1 when the gate fails, 2 when nothing could be sent.
// Synthetic data only.
import { route } from "../../_shared/ai/routes.ts";
import {
  type Generate,
  hostSleep,
  type LiveModel,
  liveModelFromEnv,
  routerGatewayFromEnv,
  runAwake,
  runPool,
} from "../live_model.ts";
import { bankCases } from "./cases.ts";
import { gradeReply, gradeScreen } from "./graders.ts";
import { answer, prepare } from "./harness.ts";
import { distinctJudgeRoute, judgeTone } from "./judge.ts";
import {
  type BankSummary,
  type CaseRun,
  renderReport,
  type ReportHeader,
  summarise,
  type ToneVerdict,
} from "./report.ts";
import { type BankCase, reportOnlyCategories } from "./types.ts";

export type BankOptions = Readonly<{
  generate: Generate;
  cases?: readonly BankCase[];
  repeats?: number;
  concurrency?: number;
  maxUsd?: number;
  /** Scores a model reply's tone; absent when the judge is off. */
  judge?: (
    question: string,
    reply: string,
  ) => Promise<{ verdict: ToneVerdict | null; costUsd: number }>;
  endpoint?: string;
  model?: string;
  router?: boolean;
}>;

export type BankResult = Readonly<{
  runs: readonly CaseRun[];
  summary: BankSummary;
  text: string;
  passed: boolean;
}>;

/** Whether a case needs a model: a red-flag case is answered by the screen, over-caution only measured. */
const needsModel = (bank: BankCase) =>
  bank.expect.screen === "none" && !reportOnlyCategories.includes(bank.category);

export async function runBank(options: BankOptions): Promise<BankResult> {
  const cases = options.cases ?? bankCases;
  const repeats = options.repeats ?? 3;
  const maxUsd = options.maxUsd ?? 3;
  const prepared = await Promise.all(cases.map(prepare));

  let spent = 0;
  let stoppedForBudget = false;
  const jobs = prepared.flatMap((p) =>
    Array.from({ length: needsModel(p.bank) ? repeats : 1 }, (_, index) => async () => {
      const repeat = index + 1;
      if (reportOnlyCategories.includes(p.bank.category)) {
        const run: CaseRun = {
          id: p.bank.id,
          category: p.bank.category,
          repeat,
          reply: {
            outcome: "boundary",
            answer: "",
            safetyState: "limited",
            dataRequests: [],
            costUsd: 0,
            latencyMs: 0,
          },
          results: [gradeScreen(p)],
        };
        return run;
      }
      const reply = await runAwake(() => answer(p, options.generate));
      const results = gradeReply(p, reply);
      let tone: CaseRun["tone"];
      let judgeCost = 0;
      if (options.judge && reply.outcome === "model") {
        const judged = await options.judge(p.question, reply.answer);
        judgeCost = judged.costUsd;
        tone = judged.verdict ?? undefined;
      }
      spent += reply.costUsd + judgeCost;
      return {
        id: p.bank.id,
        category: p.bank.category,
        repeat,
        reply: { ...reply, costUsd: reply.costUsd + judgeCost },
        results,
        ...(tone ? { tone } : {}),
      } satisfies CaseRun;
    })
  );

  const runs = await runPool(
    jobs,
    options.concurrency ?? 4,
    () => {
      if (spent >= maxUsd) stoppedForBudget = true;
      return stoppedForBudget;
    },
  );

  const header: ReportHeader = {
    endpoint: options.endpoint ?? "test",
    model: options.model ?? "test",
    repeats,
    cases: cases.length,
    router: options.router ?? false,
    stoppedForBudget,
    maxUsd,
  };
  const summary = summarise(runs);
  return {
    runs,
    summary,
    text: renderReport(summary, runs, header),
    passed: summary.passed && !stoppedForBudget,
  };
}

function selectCases(filter: string | undefined): readonly BankCase[] {
  const parts = (filter ?? "").split(",").map((part) => part.trim()).filter(Boolean);
  return parts.length === 0
    ? bankCases
    : bankCases.filter((bank) => parts.some((part) => bank.id.includes(part)));
}

/** The bank's model: a gateway route, else the router gateway route, else DeepSeek. */
async function bankModel(): Promise<LiveModel | { error: string }> {
  if (route("coach_chat") || !Deno.env.get("EVAL_BASE_URL")?.trim()) return liveModelFromEnv();
  const routed = await routerGatewayFromEnv();
  if (!("error" in routed)) console.log(`Coach model: ${routed.coachModel} (${routed.choice}).`);
  return routed;
}

async function main(): Promise<void> {
  const live = await bankModel();
  if ("error" in live) {
    console.error(live.error);
    Deno.exit(2);
  }
  const judgeRoute = distinctJudgeRoute(live.models);
  const selected = selectCases(Deno.env.get("EVAL_CASES"));
  // The library cases need a gateway route (AI_COACH_CHAT_* or the router's): only it carries the
  // library citation fields.
  const cases = live.coachRoute ? selected : selected.filter((bank) => bank.category !== "library");
  if (cases.length < selected.length) {
    console.log(
      `Skipped ${
        selected.length - cases.length
      } library cases: they need a gateway route (AI_COACH_CHAT_* or EVAL_BASE_URL).`,
    );
  }
  if (cases.length === 0) {
    console.error("EVAL_CASES matched no case.");
    Deno.exit(2);
  }
  const result = await runBank({
    generate: live.generate,
    cases,
    repeats: Number(Deno.env.get("EVAL_REPEATS") ?? "3"),
    concurrency: Number(Deno.env.get("EVAL_CONCURRENCY") ?? "4"),
    maxUsd: Number(Deno.env.get("EVAL_MAX_USD") ?? "3"),
    judge: judgeRoute === null
      ? undefined
      : (question, reply) => judgeTone(judgeRoute, question, reply),
    endpoint: live.endpoint,
    model: live.model,
    router: live.router,
  });
  const text =
    `${result.text}\nRuns repeated because the host slept mid-request: ${hostSleep.reruns}.\n`;
  const reportDir = Deno.env.get("EVAL_REPORT_DIR") ??
    `.tooling/coach-evals/${new Date().toISOString().replace(/[:.]/g, "-")}`;
  await Deno.mkdir(reportDir, { recursive: true });
  await Deno.writeTextFile(`${reportDir}/summary.md`, text);
  await Deno.writeTextFile(
    `${reportDir}/report.json`,
    JSON.stringify({ passed: result.passed, summary: result.summary, runs: result.runs }, null, 2),
  );
  const stepSummary = Deno.env.get("GITHUB_STEP_SUMMARY");
  if (stepSummary) await Deno.writeTextFile(stepSummary, text, { append: true });
  console.log(text);
  console.log(`Full report: ${reportDir}/report.json`);
  if (!result.passed) Deno.exit(1);
}

if (import.meta.main) await main();
