// The simulated-athlete run: athletes with months of synthetic records talk to the Coach for six to
// ten messages per scenario, through the production gateway path over the eval router, and every
// turn is graded by code, an expert-coach judge and (for cited research) a claim-support judge.
// Report only: it exits 0 whatever the quality, 1 on a harness error and 2 when it cannot start. A
// harness error is a failed preflight (one tiny request to the Coach, the athlete and the judge, in
// the mode the run uses, with the other modes and model spellings tried first), an exception in the
// simulator, more than 20% of Coach turns ending in a provider error, a judge that gives no
// verdicts, or an athlete model that cannot continue: a run that did not reach its models measures
// nothing, so it must not look green. Every failed call records its HTTP status and the first 300
// characters of the redacted body in simulation.json.
//
// Only in GitHub Actions (coach-eval.yml, Run workflow with `simulate`): it needs EVAL_BASE_URL and
// EVAL_API_KEY, the eval router. Optional: EVAL_SIM_FILTER (comma-separated parts of conversation
// ids, personas or scenarios), EVAL_SIM_MAX_TURNS (default 6, at most 10), EVAL_MAX_USD (default
// 3), EVAL_CONCURRENCY (default 3), EVAL_COACH_MODEL, EVAL_ATHLETE_MODEL, EVAL_JUDGE_MODEL (any
// router model id; the judge must differ from the Coach) and EVAL_REPORT_DIR.
import type { TokenCounts } from "../../_shared/ai/models.ts";
import { buildCoachChatGatewayPrompt } from "../../_shared/providers/coach_chat_provider_gateway.ts";
import { classifyQuestion } from "../../_shared/providers/coach_chat_provider.ts";
import { renderTurn } from "../coach_bank/harness.ts";
import {
  knownPrice,
  priceTokens,
  productionCoachModel,
  routerGatewayFromEnv,
} from "../live_model.ts";
import { summariseErrors } from "./diagnostics.ts";
import { assertDistinctJudge } from "./judges.ts";
import {
  decidePreflight,
  idCandidates,
  preflightChat,
  preflightCoach,
  type PreflightResult,
  renderPreflight,
} from "./preflight.ts";
import { personaById, type PersonaId } from "./personas.ts";
import { renderReport, renderSummary } from "./report.ts";
import {
  athletePreferences,
  type ChatMode,
  defaultChatMode,
  judgePreferences,
  pickModel,
  routerChat,
} from "./router_client.ts";
import { type Conversation, openingFor, selectConversations } from "./scenarios.ts";
import { maxTurnsLimit, simulate, spentUsd } from "./simulate.ts";
import { harnessFailures } from "./verdict.ts";
import { wordSearch } from "./library_search.ts";

/** Characters per token assumed for the estimate (the bank measured about 1.8 on athlete files). */
const charsPerToken = 3;

export type EstimateInput = Readonly<{
  conversations: readonly Conversation[];
  maxTurns: number;
  coachModel: string;
  athleteModel: string;
  judgeModel: string | null;
  /** Prompt tokens of a first Coach call for the persona. */
  promptTokens: (persona: PersonaId) => number;
}>;

const tokens = (input: number, output: number): TokenCounts => ({
  inputTokens: input,
  outputTokens: output,
  cacheReadTokens: 0,
  cacheWriteTokens: 0,
});

/**
 * What a run should cost at list prices, before it starts. Per Coach turn: 1.6 calls (lookup
 * rounds and repairs) of the persona's prompt plus 1,000 tokens of looked-up rows, and 900 output
 * tokens; per athlete message 1,500 in and 150 out; per judged turn 2,500 in and 450 out, and a
 * claim check on a third of the turns. No prompt cache is assumed.
 */
export function estimateRun(input: EstimateInput): { usd: number; turns: number } {
  let usd = 0;
  let turns = 0;
  for (const conversation of input.conversations) {
    const count = Math.min(conversation.scenario.turns, input.maxTurns, maxTurnsLimit);
    turns += count;
    const prompt = input.promptTokens(conversation.persona);
    usd += count * priceTokens(input.coachModel, tokens(Math.round(prompt * 1.6) + 1_000, 900)).usd;
    usd += (count - 1) * priceTokens(input.athleteModel, tokens(1_500, 150)).usd;
    if (input.judgeModel) {
      usd += count * priceTokens(input.judgeModel, tokens(2_500, 450)).usd;
      usd += (count / 3) * priceTokens(input.judgeModel, tokens(2_500, 500)).usd;
    }
  }
  return { usd: Math.round(usd * 10_000) / 10_000, turns };
}

/** The prompt tokens of the first Coach call for each persona in the run (no model involved). */
export async function promptTokensByPersona(
  conversations: readonly Conversation[],
): Promise<Map<PersonaId, number>> {
  const sizes = new Map<PersonaId, number>();
  for (const conversation of conversations) {
    if (sizes.has(conversation.persona)) continue;
    const persona = personaById(conversation.persona);
    const athlete = persona.athlete();
    const question = openingFor(conversation.scenario, persona.id);
    const contributions = await renderTurn(athlete, question, [], {
      librarySearch: wordSearch(persona.region),
    });
    const prompt = buildCoachChatGatewayPrompt(
      question,
      athlete.context,
      classifyQuestion(question),
      contributions,
      undefined,
      { sections: [], closed: false },
      true,
      true,
    );
    const chars = [...prompt.system, ...prompt.messages.flatMap((m) => m.content)].reduce(
      (sum, part) => sum + (part.type === "text" ? part.text.length : 0),
      0,
    );
    sizes.set(conversation.persona, Math.ceil(chars / charsPerToken));
  }
  return sizes;
}

const integer = (raw: string | undefined, fallback: number, min: number, max: number) => {
  const value = Number(raw);
  return Number.isInteger(value) && value >= min && value <= max ? value : fallback;
};

async function main(): Promise<void> {
  const env = (name: string) => Deno.env.get(name)?.trim() || undefined;
  const routed = await routerGatewayFromEnv();
  if ("error" in routed) {
    console.error(routed.error);
    Deno.exit(2);
  }
  const conversations = selectConversations(env("EVAL_SIM_FILTER"));
  if (conversations.length === 0) {
    console.error("EVAL_SIM_FILTER matched no conversation.");
    Deno.exit(2);
  }
  const maxTurns = integer(env("EVAL_SIM_MAX_TURNS"), 6, 1, maxTurnsLimit);
  const maxUsd = Number(env("EVAL_MAX_USD") ?? "3");
  let coachModel = routed.coachModel;
  // When the router cannot list its models, the athlete is the Coach's model, which it serves.
  const athleteModel = env("EVAL_ATHLETE_MODEL") ??
    (routed.available.length
      ? pickModel(routed.available, athletePreferences, [coachModel]) ?? coachModel
      : coachModel);
  const judgeModel = env("EVAL_JUDGE_MODEL") ??
    pickModel(routed.available, judgePreferences, [coachModel]);
  try {
    if (judgeModel) assertDistinctJudge(judgeModel, coachModel);
  } catch (error) {
    console.error((error as Error).message);
    Deno.exit(2);
  }
  const judgeNote = judgeModel ? "" : "the router lists no model other than the Coach's";

  const reportDir = env("EVAL_REPORT_DIR") ??
    `.tooling/coach-evals/simulation-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  await Deno.mkdir(reportDir, { recursive: true });

  // One tiny request per model, in the mode the run will use; the other modes and spellings are
  // tried when it fails. A model with no working request stops the run before it spends anything.
  const route = { baseUrl: routed.baseUrl, apiKey: routed.apiKey };
  const [coachCheck, athleteCheck] = await Promise.all([
    preflightCoach({ ...route, candidates: idCandidates(routed.available, coachModel) }),
    preflightChat({ ...route, role: "athlete", model: athleteModel }),
  ]);
  const judgeCheck: PreflightResult | null = judgeModel === null
    ? null
    : judgeModel === athleteModel
    ? { ...athleteCheck, role: "judge" }
    : await preflightChat({ ...route, role: "judge", model: judgeModel });
  const checks = [coachCheck, athleteCheck, ...(judgeCheck ? [judgeCheck] : [])];
  const preflight = renderPreflight(checks);
  console.log(["Preflight:", ...preflight].join("\n"));
  const decision = decidePreflight(checks);
  if (!decision.proceed) {
    await Deno.writeTextFile(
      `${reportDir}/preflight.json`,
      JSON.stringify({ message: decision.message, checks }, null, 2),
    );
    await Deno.writeTextFile(
      `${reportDir}/simulation.md`,
      ["# Coach simulation: preflight failed", "", decision.message, "", ...preflight].join("\n"),
    );
    const stepSummary = Deno.env.get("GITHUB_STEP_SUMMARY");
    if (stepSummary) {
      await Deno.writeTextFile(
        stepSummary,
        ["## Coach simulation: preflight failed", "", decision.message, "", ...preflight, ""]
          .join("\n"),
        { append: true },
      );
    }
    console.error(`::error::${decision.message}`);
    Deno.exit(1);
  }
  const played = coachCheck.working!;
  coachModel = played.model;
  const modes = new Map<string, ChatMode>();
  for (const check of [athleteCheck, ...(judgeCheck ? [judgeCheck] : [])]) {
    modes.set(check.working!.model, check.working!.mode);
  }

  const sizes = await promptTokensByPersona(conversations);
  const estimate = estimateRun({
    conversations,
    maxTurns,
    coachModel,
    athleteModel,
    judgeModel,
    promptTokens: (persona) => sizes.get(persona) ?? 10_000,
  });
  const assumedPrices = [coachModel, athleteModel, judgeModel].filter((m): m is string =>
    m !== null && knownPrice(m) === null
  );
  console.log(
    [
      `Coach: ${coachModel} (${routed.choice}).`,
      `Athlete: ${athleteModel}. Judges: ${judgeModel ?? `off (${judgeNote})`}.`,
      `Router models listed: ${routed.available.length || "none"}.`,
      `${conversations.length} conversations, up to ${estimate.turns} Coach turns. Estimated cost USD ${
        estimate.usd.toFixed(4)
      } at list prices${
        assumedPrices.length ? ` (assumed prices for ${assumedPrices.join(", ")})` : ""
      }; cap USD ${maxUsd}.`,
    ].join("\n"),
  );

  const result = await simulate({
    coach: routed.generateFor(played),
    coachModel,
    athleteModel,
    judgeModel,
    chat: routerChat(routed.baseUrl, routed.apiKey, {
      modeFor: (model) => modes.get(model) ?? defaultChatMode,
    }),
    conversations,
    maxTurns,
    maxUsd,
    concurrency: integer(env("EVAL_CONCURRENCY"), 3, 1, 8),
  });
  const failures = harnessFailures(result.conversations, judgeModel !== null);
  const text = renderReport(result.conversations, result.spend, result.stoppedForBudget, {
    coachModel,
    coachChoice: routed.choice,
    productionModel: productionCoachModel,
    production: routed.production,
    athleteModel,
    judgeModel,
    judgeNote,
    endpoint: new URL(routed.baseUrl).host,
    maxUsd,
    maxTurns,
    estimateUsd: estimate.usd,
    assumedPrices,
    preflight,
    errors: result.errors,
    harnessFailures: failures,
  });
  await Deno.writeTextFile(`${reportDir}/simulation.md`, text);
  await Deno.writeTextFile(
    `${reportDir}/simulation.json`,
    JSON.stringify(
      {
        coachModel,
        athleteModel,
        judgeModel,
        spend: result.spend,
        stoppedForBudget: result.stoppedForBudget,
        preflight: checks,
        harnessFailures: failures,
        errorSummary: summariseErrors(result.errors),
        providerErrors: result.errors,
        conversations: result.conversations.map((run) => ({
          ...run,
          turns: run.turns.map(({ context: _context, contributions, ...turn }) => ({
            ...turn,
            libraryShown: Object.keys(contributions.shown),
          })),
        })),
      },
      null,
      2,
    ),
  );
  const stepSummary = Deno.env.get("GITHUB_STEP_SUMMARY");
  if (stepSummary) await Deno.writeTextFile(stepSummary, renderSummary(text), { append: true });
  console.log(renderSummary(text));
  console.log(
    `Spent USD ${spentUsd(result.spend).toFixed(4)}. Full report: ${reportDir}/simulation.md`,
  );
  if (failures.length > 0) {
    for (const reason of failures) console.error(`::error::${reason.replace(/\s+/g, " ")}`);
    Deno.exit(1);
  }
}

if (import.meta.main) await main();
