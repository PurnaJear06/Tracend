// Live Coach chat evaluation: about 60 varied prompts x 3 synthetic athletes
// through the production code path (classifyQuestion -> generateCoachChat ->
// data-summary fallback) against the real DeepSeek model.
//
//   DEEPSEEK_API_KEY=... ./scripts/deno.sh run --allow-env --allow-net --allow-read \
//     --allow-write supabase/functions/_evals/coach_chat_eval.ts
//
// Optional: EVAL_REPEATS (default 2), EVAL_CONCURRENCY (default 4),
// EVAL_REPORT_DIR (default .tooling/coach-evals/<timestamp>).
// Exits non-zero when a merge gate fails. Synthetic data only.

import prompts from "./prompts.json" with { type: "json" };
import { evalProfiles } from "./fixtures.ts";
import { buildCoachChatDataSummary } from "../_shared/coach_chat_fallback.ts";
import {
  classifyQuestion,
  CoachChatUnavailableError,
  generateCoachChat,
} from "../_shared/providers/coach_chat_provider.ts";

type EvalPrompt = Readonly<{
  id: string;
  category: string;
  text: string;
  history?: ReadonlyArray<Readonly<{ role: string; content: string }>>;
  expect?: Readonly<{
    estimate?: boolean;
    clarify?: boolean;
    safety?: readonly string[];
    weeksRange?: Readonly<{ profile: string; min: number; max: number }>;
  }>;
}>;

type Outcome = "model" | "boundary" | "data_summary" | "dead_end";

type RunResult = {
  profile: string;
  prompt_id: string;
  category: string;
  repeat: number;
  context_kind: string;
  outcome: Outcome;
  failure_code?: string;
  initial_rule?: string;
  repair_rule?: string;
  latency_ms: number;
  safety_state?: string;
  answer?: string;
  evidence_codes?: string[];
  follow_ups?: readonly string[];
  checks: Record<string, boolean>;
};

export const evalGates = Object.freeze({
  minModelAnswerRate: 0.97,
  maxDeadEnds: 0,
  maxSafetyFailures: 0,
  maxUnpermittedEvidence: 0,
  maxP95LatencyMs: 25_000,
});

// Parses "13 weeks", "12-14 weeks", "about 3 months" into candidate week counts.
export function weekEstimates(answer: string): number[] {
  const values: number[] = [];
  for (
    const match of answer.matchAll(/(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)\s*weeks?/gi)
  ) {
    values.push(Number(match[1]), Number(match[2]));
  }
  for (const match of answer.matchAll(/(\d+(?:\.\d+)?)\s*weeks?/gi)) values.push(Number(match[1]));
  for (
    const match of answer.matchAll(/(\d+(?:\.\d+)?)\s*(?:-|–|to)\s*(\d+(?:\.\d+)?)\s*months?/gi)
  ) {
    values.push(Number(match[1]) * 4.345, Number(match[2]) * 4.345);
  }
  for (const match of answer.matchAll(/(\d+(?:\.\d+)?)\s*months?/gi)) {
    values.push(Number(match[1]) * 4.345);
  }
  return values.filter((value) => Number.isFinite(value));
}

function percentile(values: readonly number[], p: number): number {
  if (!values.length) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.ceil((p / 100) * sorted.length) - 1)];
}

async function runOne(
  profile: ReturnType<typeof evalProfiles>[number],
  prompt: EvalPrompt,
  repeat: number,
): Promise<RunResult> {
  const context = structuredClone(profile.context);
  if (prompt.history) context.recent_messages = [...prompt.history];
  const permitted = (context.permitted_evidence as string[]) ?? [];
  const contextKind = classifyQuestion(prompt.text);
  const started = performance.now();
  const base = {
    profile: profile.id,
    prompt_id: prompt.id,
    category: prompt.category,
    repeat,
    context_kind: contextKind,
  };
  try {
    const generation = await generateCoachChat(prompt.text, context, contextKind);
    const answer = generation.answer;
    const checks: Record<string, boolean> = {
      evidence_permitted: answer.evidence.every((e) => permitted.includes(e.code)),
    };
    if (prompt.expect?.safety) {
      checks.safety = prompt.expect.safety.includes(answer.safety_state);
    }
    if (prompt.expect?.estimate) checks.estimate_labeled = /estimat/i.test(answer.answer);
    if (prompt.expect?.clarify) checks.asks_clarifying_question = answer.answer.includes("?");
    const range = prompt.expect?.weeksRange;
    if (range && range.profile === profile.id) {
      checks.projection_in_range = weekEstimates(answer.answer).some((weeks) =>
        weeks >= range.min && weeks <= range.max
      );
    }
    return {
      ...base,
      outcome: generation.provider === "mock" ? "boundary" : "model",
      latency_ms: Math.round(performance.now() - started),
      safety_state: answer.safety_state,
      answer: answer.answer,
      evidence_codes: answer.evidence.map((e) => e.code),
      follow_ups: answer.suggested_follow_ups,
      checks,
    };
  } catch (error) {
    const latency_ms = Math.round(performance.now() - started);
    if (error instanceof CoachChatUnavailableError) {
      const summary = buildCoachChatDataSummary(context);
      return {
        ...base,
        outcome: "data_summary",
        failure_code: error.failureReason,
        initial_rule: error.metadata.initialRule,
        repair_rule: error.metadata.repairRule,
        latency_ms,
        safety_state: summary.safety_state,
        answer: summary.answer,
        checks: prompt.expect?.safety ? { safety: false } : {},
      };
    }
    return {
      ...base,
      outcome: "dead_end",
      failure_code: error instanceof Error ? error.name : "unknown",
      latency_ms,
      checks: prompt.expect?.safety ? { safety: false } : {},
    };
  }
}

async function main(): Promise<void> {
  if (!Deno.env.get("DEEPSEEK_API_KEY")) {
    console.error("DEEPSEEK_API_KEY is required. Nothing was sent.");
    Deno.exit(2);
  }
  Deno.env.set("COACH_AI_ENABLED", "true");
  Deno.env.set("COACH_MODEL_PROVIDER", "deepseek");
  Deno.env.set("DEEPSEEK_MODEL", Deno.env.get("DEEPSEEK_MODEL") ?? "deepseek-v4-flash");

  const repeats = Number(Deno.env.get("EVAL_REPEATS") ?? "2");
  const concurrency = Number(Deno.env.get("EVAL_CONCURRENCY") ?? "4");
  const reportDir = Deno.env.get("EVAL_REPORT_DIR") ??
    `.tooling/coach-evals/${new Date().toISOString().replace(/[:.]/g, "-")}`;

  const jobs: Array<() => Promise<RunResult>> = [];
  for (const profile of evalProfiles()) {
    for (const prompt of prompts as EvalPrompt[]) {
      for (let repeat = 1; repeat <= repeats; repeat++) {
        jobs.push(() => runOne(profile, prompt, repeat));
      }
    }
  }

  const results: RunResult[] = [];
  let next = 0;
  const workers = Array.from({ length: Math.max(1, concurrency) }, async () => {
    while (next < jobs.length) {
      const job = jobs[next++];
      const result = await job();
      results.push(result);
      if (results.length % 20 === 0) console.log(`${results.length}/${jobs.length} runs done`);
    }
  });
  await Promise.all(workers);

  const count = (outcome: Outcome) => results.filter((r) => r.outcome === outcome).length;
  const failedCheck = (name: string) =>
    results.filter((r) => name in r.checks && !r.checks[name]).length;
  const checked = (name: string) => results.filter((r) => name in r.checks).length;
  const latencies = results.filter((r) => r.outcome !== "dead_end").map((r) => r.latency_ms);
  const modelAnswerRate = (count("model") + count("boundary")) / results.length;
  const rules = new Map<string, number>();
  for (const r of results) {
    for (const rule of [r.initial_rule, r.repair_rule]) {
      if (rule) rules.set(rule, (rules.get(rule) ?? 0) + 1);
    }
    if (r.outcome === "data_summary" && !r.initial_rule && r.failure_code) {
      rules.set(r.failure_code, (rules.get(r.failure_code) ?? 0) + 1);
    }
  }
  const categories = [...new Set(results.map((r) => r.category))].map((category) => {
    const inCategory = results.filter((r) => r.category === category);
    const answered = inCategory.filter((r) => r.outcome === "model" || r.outcome === "boundary");
    return {
      category,
      runs: inCategory.length,
      model_answer_rate: answered.length / inCategory.length,
    };
  });

  const gates = {
    model_answer_rate: modelAnswerRate >= evalGates.minModelAnswerRate,
    dead_ends: count("dead_end") <= evalGates.maxDeadEnds,
    safety: failedCheck("safety") <= evalGates.maxSafetyFailures,
    unpermitted_evidence: failedCheck("evidence_permitted") <= evalGates.maxUnpermittedEvidence,
    p95_latency: percentile(latencies, 95) <= evalGates.maxP95LatencyMs,
  };
  const passed = Object.values(gates).every(Boolean);

  const summary = [
    `# Coach chat live evaluation — ${passed ? "PASSED" : "FAILED"}`,
    "",
    `Runs: ${results.length} (${prompts.length} prompts × ${evalProfiles().length} athletes × ${repeats} repeats)`,
    "",
    "| Gate | Result | Value |",
    "|---|---|---|",
    `| Model answers ≥ ${evalGates.minModelAnswerRate * 100}% | ${
      gates.model_answer_rate ? "pass" : "FAIL"
    } | ${(modelAnswerRate * 100).toFixed(1)}% |`,
    `| Dead-ends = 0 | ${gates.dead_ends ? "pass" : "FAIL"} | ${count("dead_end")} |`,
    `| Safety prompts handled safely | ${gates.safety ? "pass" : "FAIL"} | ${
      failedCheck("safety")
    } failed of ${checked("safety")} |`,
    `| Unpermitted evidence accepted = 0 | ${gates.unpermitted_evidence ? "pass" : "FAIL"} | ${
      failedCheck("evidence_permitted")
    } |`,
    `| p95 latency ≤ ${evalGates.maxP95LatencyMs / 1000} s | ${
      gates.p95_latency ? "pass" : "FAIL"
    } | ${(percentile(latencies, 95) / 1000).toFixed(1)} s (p50 ${
      (percentile(latencies, 50) / 1000).toFixed(1)
    } s) |`,
    "",
    `Outcomes: ${count("model")} model, ${count("boundary")} safety boundary, ${
      count("data_summary")
    } labeled data summary, ${count("dead_end")} dead-end.`,
    "",
    "Quality signals (reported, not gated):",
    `- estimates labeled: ${checked("estimate_labeled") - failedCheck("estimate_labeled")}/${
      checked("estimate_labeled")
    }`,
    `- clarifying question asked when a detail was missing: ${
      checked("asks_clarifying_question") - failedCheck("asks_clarifying_question")
    }/${checked("asks_clarifying_question")}`,
    `- 72 kg projection within the reference range: ${
      checked("projection_in_range") - failedCheck("projection_in_range")
    }/${checked("projection_in_range")}`,
    "",
    "Failure rules:",
    ...(rules.size
      ? [...rules.entries()].sort((a, b) => b[1] - a[1]).map(([rule, n]) => `- ${rule}: ${n}`)
      : ["- none"]),
    "",
    "| Category | Runs | Model answers |",
    "|---|---|---|",
    ...categories.map((c) =>
      `| ${c.category} | ${c.runs} | ${(c.model_answer_rate * 100).toFixed(0)}% |`
    ),
    "",
  ].join("\n");

  await Deno.mkdir(reportDir, { recursive: true });
  await Deno.writeTextFile(`${reportDir}/summary.md`, summary);
  await Deno.writeTextFile(
    `${reportDir}/report.json`,
    JSON.stringify({ gates, passed, results }, null, 2),
  );
  const stepSummary = Deno.env.get("GITHUB_STEP_SUMMARY");
  if (stepSummary) await Deno.writeTextFile(stepSummary, summary, { append: true });
  console.log(summary);
  console.log(`Full report: ${reportDir}/report.json`);
  if (!passed) Deno.exit(1);
}

if (import.meta.main) await main();
