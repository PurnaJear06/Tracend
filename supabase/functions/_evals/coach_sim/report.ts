// The simulation report: who played whom, a scorecard, the problems ranked by weight with the exact
// turn, and every transcript with its grades. Report only: nothing in it gates a merge.
import { graderKind } from "../coach_bank/report.ts";
import { type ProviderError, renderErrorSummary } from "./diagnostics.ts";
import { expertRubric } from "./judges.ts";
import { personaById } from "./personas.ts";
import { type ConversationRun, type Spend, spentUsd, type TurnRun } from "./simulate.ts";

export type ReportHeader = Readonly<{
  coachModel: string;
  /** How the Coach model was chosen. */
  coachChoice: string;
  productionModel: string;
  /** Whether the Coach model is the production model. */
  production: boolean;
  athleteModel: string;
  judgeModel: string | null;
  /** Why the judges are off, when they are. */
  judgeNote: string;
  endpoint: string;
  maxUsd: number;
  maxTurns: number;
  estimateUsd: number;
  /** Models whose price was assumed (not in the price table). */
  assumedPrices: readonly string[];
  /** What the preflight found, as lines (see renderPreflight). */
  preflight: readonly string[];
  /** Every failed model call of the run. */
  errors: readonly ProviderError[];
  /** Output tokens of every judge call (thinking included), to check the judges' limit. */
  judgeOutputTokens: readonly number[];
  /** The judges' output limit per call. */
  judgeMaxTokens: number;
  /** How the run was sized to the cap (turns per conversation, judged turns). */
  sizing: string;
  /** Why the run is a harness failure, empty when it is sound. */
  harnessFailures: readonly string[];
}>;

/** How much a failed check matters, highest first; the ranking sorts by it. */
export const problemWeights: Readonly<Record<string, number>> = {
  harness_error: 100,
  red_flag_referral: 100,
  reply_guard: 100,
  citations_shown: 100,
  safety_state: 95,
  "expect:forbids": 95,
  answered: 90,
  claim_unsupported: 85,
  plan_change_proposed: 80,
  "expect:proposal": 80,
  "expert:correct": 70,
  "expect:lookup": 70,
  "expect:citation": 70,
  uses_data: 65,
  "expect:mentions": 65,
  "expert:specific": 60,
  proposal_valid: 60,
  "expert:not_generic": 55,
  "expert:pushback": 55,
  same_opening: 50,
  recurring_caveat: 50,
  claim_partial: 50,
  repeated_question: 45,
  no_repeat: 45,
  "expert:coach_like": 45,
  athlete_failed: 40,
  no_recap: 35,
  length: 30,
  format: 30,
  banned_phrases: 30,
  first_attempt_valid: 20,
};

export type Problem = Readonly<{
  weight: number;
  kind: string;
  conversation: string;
  /** Null for a problem of the whole conversation. */
  turn: number | null;
  detail: string;
}>;

const weightOf = (kind: string) => problemWeights[kind] ?? 25;

/** A grader's kind for weighting and totals: "expect:mentions:<label>" counts as "expect:mentions". */
export const kindOf = (grader: string) =>
  grader.startsWith("expect:") ? grader.split(":").slice(0, 2).join(":") : graderKind(grader);

/** Every problem the run found, heaviest first, then in conversation and turn order. */
export function rankProblems(runs: readonly ConversationRun[]): Problem[] {
  const problems: Problem[] = [];
  runs.forEach((run) => {
    if (run.ended === "harness_error" || run.ended === "athlete_failed") {
      problems.push({
        weight: weightOf(run.ended),
        kind: run.ended,
        conversation: run.id,
        turn: run.turns.length + 1,
        detail: run.error ?? run.ended,
      });
    }
    for (const turn of run.turns) {
      const why = turn.rejected.map((r) =>
        `${r.rules.join("+")}${r.detail ? ` (figures: ${r.detail})` : ""}`
      ).join("; ");
      for (const grade of turn.grades.filter((g) => !g.pass)) {
        const kind = kindOf(grade.grader);
        problems.push({
          weight: weightOf(kind),
          kind: grade.grader,
          conversation: run.id,
          turn: turn.number,
          detail: `${grade.detail ?? "failed"}${
            why && (kind === "answered" || kind === "first_attempt_valid")
              ? `; guard read: ${why}`
              : ""
          }`,
        });
      }
      if (turn.expert) {
        for (const [item] of expertRubric) {
          if (turn.expert.scores[item] <= 2) {
            problems.push({
              weight: weightOf(`expert:${item}`),
              kind: `expert:${item}`,
              conversation: run.id,
              turn: turn.number,
              detail: `scored ${turn.expert.scores[item]}/5${
                turn.expert.problem ? `: ${turn.expert.problem}` : ""
              }`,
            });
          }
        }
      }
      for (const claim of turn.claims ?? []) {
        if (claim.verdict === "supported") continue;
        const kind = claim.verdict === "unsupported" ? "claim_unsupported" : "claim_partial";
        problems.push({
          weight: weightOf(kind),
          kind,
          conversation: run.id,
          turn: turn.number,
          detail: `"${claim.sentence}" against ${claim.source}: ${claim.reason}`,
        });
      }
    }
    for (const grade of run.grades.filter((g) => !g.pass)) {
      problems.push({
        weight: weightOf(kindOf(grade.grader)),
        kind: grade.grader,
        conversation: run.id,
        turn: null,
        detail: grade.detail ?? "failed",
      });
    }
  });
  const order = runs.map((run) => run.id);
  return problems.sort((a, b) =>
    b.weight - a.weight || order.indexOf(a.conversation) - order.indexOf(b.conversation) ||
    (a.turn ?? 99) - (b.turn ?? 99)
  );
}

const usd = (value: number) => value.toFixed(4);
const oneLine = (text: string) => text.replace(/\s+/g, " ").trim();
const quote = (text: string) => text.split("\n").map((line) => `> ${line}`).join("\n");
const cell = (text: string) => oneLine(text).replaceAll("|", "\\|");

function turnLine(turn: TurnRun): string {
  const parts: string[] = [turn.reply.outcome];
  if (turn.servedBy) parts.push(`served by ${turn.servedBy}`);
  if (turn.reply.dataRequests.length) {
    parts.push(
      `lookups ${
        turn.reply.dataRequests.map((r) =>
          `${r.lookup} ${r.from}..${r.to}${r.filter ? ` "${String(r.filter)}"` : ""}`
        ).join(", ")
      }`,
    );
  }
  if (turn.reply.proposalIntent !== undefined) {
    parts.push(`proposal ${JSON.stringify(turn.reply.proposalIntent)}`);
  }
  if ((turn.reply.citations ?? []).length) parts.push(`cites ${turn.reply.citations!.join(", ")}`);
  const shown = Object.keys(turn.contributions.shown);
  if (shown.length) parts.push(`library shown ${shown.join(", ")}`);
  parts.push(`${(turn.reply.latencyMs / 1000).toFixed(1)} s`);
  parts.push(`USD ${usd(turn.costs.coach)}`);
  return parts.join("; ");
}

function transcript(run: ConversationRun): string[] {
  const persona = personaById(run.conversation.persona);
  const lines = [
    `### ${run.id}: ${run.conversation.scenario.title}`,
    "",
    `${persona.name}: ${persona.summary}`,
    "",
  ];
  for (const turn of run.turns) {
    lines.push(`**Turn ${turn.number}, ${persona.name}:** ${oneLine(turn.question)}`, "");
    lines.push(`**Coach** (${turnLine(turn)}):`, "");
    lines.push(turn.reply.answer ? quote(turn.reply.answer) : "> (no reply)", "");
    const failed = turn.grades.filter((g) => !g.pass);
    lines.push(
      `Checks: ${turn.grades.length - failed.length}/${turn.grades.length} passed${
        failed.length
          ? `; failed ${
            failed.map((g) => `${g.grader}${g.detail ? ` (${oneLine(g.detail)})` : ""}`).join("; ")
          }`
          : ""
      }.`,
    );
    if (turn.expert) {
      lines.push(
        `Expert judge: ${
          expertRubric.map(([item]) => `${item} ${turn.expert!.scores[item]}`).join(", ")
        } (mean ${turn.expert.mean}).${
          turn.expert.problem ? ` Problem: ${oneLine(turn.expert.problem)}` : ""
        }`,
      );
      if (turn.expert.betterAnswer) {
        lines.push(`A 20-year coach would say: ${oneLine(turn.expert.betterAnswer)}`);
      }
    }
    for (const claim of turn.claims ?? []) {
      lines.push(
        `Claim (${claim.source}): ${claim.verdict}: "${oneLine(claim.sentence)}"${
          claim.reason ? `; ${oneLine(claim.reason)}` : ""
        }`,
      );
    }
    for (const rejection of turn.rejected) {
      lines.push(
        `Guard refused an attempt (${rejection.rules.join(", ")}${
          rejection.detail ? `; figures: ${rejection.detail}` : ""
        }): ${oneLine(rejection.answer)}`,
      );
    }
    if (turn.judgeFailures.length) {
      lines.push(`Judge unavailable: ${turn.judgeFailures.join("; ")}`);
    }
    lines.push("");
  }
  if (run.grades.length) {
    lines.push(
      `Scenario checks: ${
        run.grades.map((g) =>
          `${g.pass ? "pass" : "FAIL"} ${g.grader}${g.detail ? ` (${oneLine(g.detail)})` : ""}`
        )
          .join("; ")
      }.`,
    );
  }
  lines.push(`Ended: ${run.ended}${run.error ? ` (${run.error})` : ""}.`, "");
  return lines;
}

const quantile = (values: readonly number[], q: number) => {
  const sorted = [...values].sort((a, b) => a - b);
  return sorted[Math.min(sorted.length - 1, Math.floor(q * sorted.length))];
};

const mean = (values: readonly number[]) =>
  values.length === 0 ? null : values.reduce((a, b) => a + b, 0) / values.length;

export function scorecard(runs: readonly ConversationRun[]): string[] {
  return [
    "| Conversation | Turns | Model answers | Code checks passed | Expert mean (1-5) | Claims supported / partial / unsupported | Scenario checks | Ended | USD |",
    "|---|---|---|---|---|---|---|---|---|",
    ...runs.map((run) => {
      const grades = run.turns.flatMap((t) => t.grades);
      const expert = mean(run.turns.flatMap((t) => t.expert ? [t.expert.mean] : []));
      const claims = run.turns.flatMap((t) => t.claims ?? []);
      const count = (verdict: string) => claims.filter((c) => c.verdict === verdict).length;
      return `| ${run.id} | ${run.turns.length} | ${
        run.turns.filter((t) => t.reply.outcome === "model").length
      } | ${grades.filter((g) => g.pass).length}/${grades.length} | ${
        expert === null ? "—" : expert.toFixed(2)
      } | ${
        claims.length
          ? `${count("supported")} / ${count("partial")} / ${count("unsupported")}`
          : "—"
      } | ${run.grades.filter((g) => g.pass).length}/${run.grades.length} | ${run.ended} | ${
        usd(run.costUsd)
      } |`;
    }),
  ];
}

export function renderReport(
  runs: readonly ConversationRun[],
  spend: Spend,
  stoppedForBudget: boolean,
  header: ReportHeader,
): string {
  const turns = runs.flatMap((run) => run.turns);
  const outcome = (name: string) => turns.filter((t) => t.reply.outcome === name).length;
  const served = [...new Set(turns.map((t) => t.servedBy).filter(Boolean))];
  const graders = new Map<string, { checked: number; failed: number }>();
  for (const grade of [...turns.flatMap((t) => t.grades), ...runs.flatMap((r) => r.grades)]) {
    const kind = kindOf(grade.grader);
    const entry = graders.get(kind) ?? { checked: 0, failed: 0 };
    entry.checked++;
    if (!grade.pass) entry.failed++;
    graders.set(kind, entry);
  }
  const judged = turns.filter((t) => t.expert);
  const claims = turns.flatMap((t) => t.claims ?? []);
  const problems = rankProblems(runs);
  const harnessErrors = runs.filter((r) => r.ended === "harness_error");
  return [
    "# Coach simulation (report only)",
    "",
    `Coach played by \`${header.coachModel}\` through the eval router at ${header.endpoint}: ${header.coachChoice}. Production Coach chat uses \`${header.productionModel}\`; this run ${
      header.production ? "used the production model" : "did NOT use the production model"
    }.${
      served.length
        ? ` The router reported serving: ${served.map((m) => `\`${m}\``).join(", ")}.`
        : ""
    }`,
    `Athlete played by \`${header.athleteModel}\`. Judges: ${
      header.judgeModel
        ? `\`${header.judgeModel}\` (a different model from the Coach)`
        : `off (${header.judgeNote})`
    }.`,
    "",
    "The Coach runs the production gateway path (generateCoachChatViaGateway): the athlete file, the real contributors, data lookups through the production runner, the proposal intent, the red-flag screen and every reply guard. Over the router the request is OpenAI-compatible JSON mode rather than the Claude Messages API. Stand-ins: the database (months of synthetic records per persona) and the library search (a word search over the real chunks; library_eval.ts measures the real search).",
    "",
    `Spend: USD ${usd(spentUsd(spend))} (Coach ${usd(spend.coach)}, athlete ${
      usd(spend.athlete)
    }, judges ${usd(spend.judges)}) at list prices${
      header.assumedPrices.length
        ? `; assumed Sonnet-class prices for ${
          header.assumedPrices.map((m) => `\`${m}\``).join(", ")
        }`
        : ""
    }. Estimate before the run: USD ${usd(header.estimateUsd)}; cap USD ${header.maxUsd}${
      stoppedForBudget ? " (STOPPED at the cap: some conversations are short)" : ""
    }. At most ${header.maxTurns} athlete messages per conversation.`,
    header.sizing,
    ...(header.judgeOutputTokens.length
      ? [
        `Judge output per call (thinking included), limit ${header.judgeMaxTokens}: median ${
          quantile(header.judgeOutputTokens, 0.5)
        }, 90th percentile ${quantile(header.judgeOutputTokens, 0.9)}, largest ${
          Math.max(...header.judgeOutputTokens)
        } over ${header.judgeOutputTokens.length} calls.`,
      ]
      : []),
    `${runs.length} conversations, ${turns.length} Coach turns: ${
      outcome("model")
    } model answers, ${outcome("boundary")} referrals, ${outcome("data_summary")} data summaries, ${
      outcome("dead_end")
    } dead ends. Harness errors: ${harnessErrors.length}.`,
    "",
    ...(header.harnessFailures.length
      ? [
        "## HARNESS FAILURE",
        "",
        "This run measured the harness, not the Coach. It is a failure of the job.",
        "",
        ...header.harnessFailures.map((reason) => `- ${reason}`),
        "",
      ]
      : []),
    "## Preflight",
    "",
    ...header.preflight,
    "",
    "## Provider errors",
    "",
    ...renderErrorSummary(header.errors),
    "",
    "## Scorecard",
    "",
    ...scorecard(runs),
    "",
    "| Grader | Checked | Failed |",
    "|---|---|---|",
    ...[...graders.entries()].sort((a, b) => b[1].failed - a[1].failed || a[0].localeCompare(b[0]))
      .map(([kind, entry]) => `| ${kind} | ${entry.checked} | ${entry.failed} |`),
    "",
    judged.length
      ? `Expert judge over ${judged.length} replies (1-5): ${
        expertRubric.map(([item]) =>
          `${item} ${mean(judged.map((t) => t.expert!.scores[item]))!.toFixed(2)}`
        ).join(", ")
      }; ${judged.filter((t) => t.expert!.pass).length} replies scored 3 or more on every item.`
      : "Expert judge: no verdicts.",
    claims.length
      ? `Claim support over ${claims.length} cited research claims: ${
        claims.filter((c) => c.verdict === "supported").length
      } supported, ${claims.filter((c) => c.verdict === "partial").length} partial, ${
        claims.filter((c) => c.verdict === "unsupported").length
      } unsupported.`
      : "Claim support: no cited research claims to check.",
    "",
    "## Problems, ranked",
    "",
    ...(problems.length === 0
      ? ["None found."]
      : problems.slice(0, 60).map((p, index) =>
        `${index + 1}. [${p.weight}] ${p.conversation}${
          p.turn === null ? " (whole conversation)" : `, turn ${p.turn}`
        }: ${p.kind}: ${cell(p.detail)}`
      )),
    ...(problems.length > 60 ? [`... and ${problems.length - 60} more in simulation.json.`] : []),
    "",
    "## Transcripts",
    "",
    ...runs.flatMap(transcript),
  ].join("\n");
}

/** The short version for the job summary: the header, the scorecard and the top problems. */
export function renderSummary(fullReport: string): string {
  const end = fullReport.indexOf("## Transcripts");
  const head = end === -1 ? fullReport : fullReport.slice(0, end);
  return `${head}\nThe full transcripts are in the simulation-report artifact.\n`;
}
