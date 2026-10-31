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
// Two backends. The eval router (coach-eval.yml, Run workflow with `simulate`): EVAL_BASE_URL and
// EVAL_API_KEY. Or, run locally without EVAL_BASE_URL, Claude directly: the Coach on the
// production route the AI_COACH_CHAT_* settings give (AI_COACH_CHAT_PROVIDER=anthropic and the
// model, output tokens, timeout and EVALUATED that production sets) through the same gateway path
// and timing, with ANTHROPIC_API_KEY, and the athlete (Haiku) and the judges (Sonnet when the cap
// allows) on the Messages API with that key. Optional: EVAL_SIM_FILTER (comma-separated parts of conversation
// ids, personas or scenarios), EVAL_SIM_MAX_TURNS (default 3, at most 10; lowered to fit the cap, never below 2), EVAL_MAX_USD (default
// 3), EVAL_CONCURRENCY (default 3), EVAL_COACH_MODEL, EVAL_ATHLETE_MODEL, EVAL_JUDGE_MODEL (any
// model id the backend serves; the judge must differ from the Coach) and EVAL_REPORT_DIR.
import type { TokenCounts } from "../../_shared/ai/models.ts";
import {
  buildCoachChatGatewayPrompt,
  coachChatGatewaySchema,
} from "../../_shared/providers/coach_chat_provider_gateway.ts";
import { classifyQuestion } from "../../_shared/providers/coach_chat_provider.ts";
import { renderTurn } from "../coach_bank/harness.ts";
import { anthropicMessagesUrl } from "../../_shared/ai/adapters/anthropic.ts";
import {
  type CoachGenerateFactory,
  knownPrice,
  priceTokens,
  productionCoachModel,
  type RouterGateway,
  routerGatewayFromEnv,
  routerModelEntry,
} from "../live_model.ts";
import {
  anthropicChat,
  type AnthropicGateway,
  anthropicGatewayFromEnv,
  anthropicModels,
} from "./anthropic_client.ts";
import { summariseErrors } from "./diagnostics.ts";
import { assertDistinctJudge, judgeMaxTokens } from "./judges.ts";
import {
  decidePreflight,
  idCandidates,
  preflightChat,
  preflightCoach,
  preflightDirect,
  type PreflightResult,
  renderPreflight,
} from "./preflight.ts";
import { personaById, type PersonaId } from "./personas.ts";
import { renderReport, renderSummary } from "./report.ts";
import {
  athletePreferences,
  type ChatMode,
  chatModes,
  defaultChatMode,
  judgePreferences,
  pickModel,
  pickModels,
  type RouterChat,
  routerChat,
  structuredMode,
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
  /** Judge every Nth Coach reply (default every reply). */
  judgeEvery?: number;
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
 * tokens; per athlete message 1,500 in and 150 out; per judged turn 8,500 in (the athlete data the Coach saw) and 2,000 out (a
 * Claude judge's thinking counts as output), and a claim check on a third of the judged turns
 * (3,000 in, 1,500 out). No prompt cache is assumed.
 */
export function estimateRun(input: EstimateInput): { usd: number; turns: number } {
  let usd = 0;
  let turns = 0;
  const every = input.judgeEvery ?? 1;
  for (const conversation of input.conversations) {
    const count = Math.min(conversation.scenario.turns, input.maxTurns, maxTurnsLimit);
    turns += count;
    const prompt = input.promptTokens(conversation.persona);
    usd += count * priceTokens(input.coachModel, tokens(Math.round(prompt * 1.6) + 1_000, 900)).usd;
    usd += (count - 1) * priceTokens(input.athleteModel, tokens(1_500, 150)).usd;
    if (input.judgeModel) {
      const judged = Math.ceil(count / every);
      usd += judged * priceTokens(input.judgeModel, tokens(8_500, 2_000)).usd;
      usd += (judged / 3) * priceTokens(input.judgeModel, tokens(3_000, 1_500)).usd;
    }
  }
  return { usd: Math.round(usd * 10_000) / 10_000, turns };
}

/** The share of the cap an estimate may use: the estimate is a list-price guess, not a bound. */
export const capShare = 0.85;
/** The fewest messages per conversation a fitted run keeps: a second message tests the follow-up. */
export const fewestTurns = 2;

export type Fit = Readonly<{
  maxTurns: number;
  judgeEvery: number;
  estimateUsd: number;
  /** Coach turns the run plans at that size. */
  turns: number;
  /** Whether the estimate is within capShare of the cap. */
  fits: boolean;
}>;

/**
 * The biggest run that fits the cap, so that every conversation runs instead of the last ones
 * being skipped: from the requested messages per conversation down to two, each judged on every
 * reply and then on every other one; when none fits, two messages and the first reply judged (the
 * cap still stops it, and the report says so).
 */
export function fitRun(
  input: Omit<EstimateInput, "maxTurns" | "judgeEvery">,
  requested: number,
  maxUsd: number,
): Fit {
  const floor = Math.min(requested, fewestTurns);
  for (let turns = requested; turns >= floor; turns--) {
    for (const judgeEvery of input.judgeModel ? [1, 2] : [1]) {
      const estimate = estimateRun({ ...input, maxTurns: turns, judgeEvery });
      if (estimate.usd <= maxUsd * capShare) {
        return {
          maxTurns: turns,
          judgeEvery,
          estimateUsd: estimate.usd,
          turns: estimate.turns,
          fits: true,
        };
      }
    }
  }
  const judgeEvery = input.judgeModel ? 2 : 1;
  const estimate = estimateRun({ ...input, maxTurns: floor, judgeEvery });
  return {
    maxTurns: floor,
    judgeEvery,
    estimateUsd: estimate.usd,
    turns: estimate.turns,
    fits: false,
  };
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

const coachModes: readonly ChatMode[] = [structuredMode, ...chatModes];

/** Coach models tried, in order, when the production model has no working request at the router. */
const coachFallbacks: readonly string[] = ["claude-sonnet-5-5"];

/** Where the run's models answer: the eval router, or Claude's API directly. */
type Backend = Readonly<{
  /** The model ids the backend serves, empty when it could not list them. */
  available: readonly string[];
  /** The host, for the report. */
  endpoint: string;
  coachCheck: PreflightResult;
  coachChoice: string;
  production: boolean;
  /** The first preflight line: what the backend says about the Coach model. */
  listing: string;
  preflightChat: (role: "athlete" | "judge", model: string) => Promise<PreflightResult>;
  chat: (modes: ReadonlyMap<string, ChatMode>) => RouterChat;
  generateFor: (played: Readonly<{ model: string; mode: ChatMode }>) => CoachGenerateFactory;
}>;

/**
 * The eval router: the Coach is asked with the answer schema enforced (structured output) first,
 * as production asks Claude, and in the plainer modes when the router does not take that; the
 * other spellings of the model id are tried too.
 */
async function routerBackend(
  routed: RouterGateway,
  coachNamed: boolean,
): Promise<Backend> {
  const route = { baseUrl: routed.baseUrl, apiKey: routed.apiKey };
  const coachProbe = { ...route, schema: coachChatGatewaySchema(), modes: coachModes };
  let coachCheck = await preflightCoach({
    ...coachProbe,
    candidates: idCandidates(routed.available, routed.coachModel),
  });
  const wanted = coachCheck.wanted;
  let coachChoice = routed.choice;
  let production = routed.production;
  // The production model is asked for first. When the router has no working request for it (it
  // answered 502 for hours on 2026-10-18) and nobody named a Coach model, the run is played by
  // the next model on the list instead of not running; the report says so on its first line.
  if (coachCheck.working === null && !coachNamed && routed.production) {
    const fallback = pickModel(routed.available, coachFallbacks, [routed.coachModel]);
    if (fallback) {
      const second = await preflightCoach({
        ...coachProbe,
        candidates: idCandidates(routed.available, fallback),
      });
      if (second.working) {
        const first = coachCheck.attempts[0];
        coachChoice =
          `${routed.choice}, but it had no working request at the router (the listed id answered ${
            first ? (first.status === null ? "nothing" : `HTTP ${first.status}`) : "nothing"
          } in every mode; the other spellings HTTP ${
            coachCheck.attempts.at(-1)?.status ?? "none"
          }), so ${second.working.model} played`;
        production = false;
        coachCheck = { ...second, attempts: [...coachCheck.attempts, ...second.attempts] };
      }
    }
  }
  return {
    available: routed.available,
    endpoint: new URL(routed.baseUrl).host,
    coachCheck,
    coachChoice,
    production,
    listing: `The router's listing for \`${wanted}\`: ${await routerModelEntry(
      routed.baseUrl,
      routed.apiKey,
      wanted,
    )}`,
    preflightChat: (role, model) => preflightChat({ ...route, role, model }),
    chat: (modes) =>
      routerChat(routed.baseUrl, routed.apiKey, {
        modeFor: (model) => modes.get(model) ?? defaultChatMode,
      }),
    generateFor: routed.generateFor,
  };
}

/**
 * Claude's API directly (no router): the Coach on the production route the AI_COACH_CHAT_*
 * settings give, through the gateway's own Claude request; the athlete and the judges on the
 * Messages API with the same key.
 */
async function anthropicBackend(direct: AnthropicGateway): Promise<Backend> {
  const chat = anthropicChat(direct.apiKey);
  const secrets = [direct.apiKey];
  return {
    available: anthropicModels,
    endpoint: new URL(anthropicMessagesUrl).host,
    coachCheck: await preflightDirect(chat, "coach", direct.coachModel, secrets),
    coachChoice: direct.choice,
    production: direct.production,
    listing:
      `The Coach route: ${direct.coachRoute.providerLabel} \`${direct.coachModel}\`, ${direct.coachRoute.maxOutputTokens} output tokens, ${direct.coachRoute.timeoutMs} ms per attempt (production gateway path, Anthropic directly).`,
    preflightChat: (role, model) => preflightDirect(chat, role, model, secrets),
    chat: () => chat,
    generateFor: () => direct.generateWith,
  };
}

async function main(): Promise<void> {
  const env = (name: string) => Deno.env.get(name)?.trim() || undefined;
  let backend: Backend;
  if (env("EVAL_BASE_URL")) {
    const routed = await routerGatewayFromEnv();
    if ("error" in routed) {
      console.error(routed.error);
      Deno.exit(2);
    }
    backend = await routerBackend(routed, Boolean(env("EVAL_COACH_MODEL")));
  } else {
    const direct = anthropicGatewayFromEnv();
    if ("error" in direct) {
      console.error(direct.error);
      Deno.exit(2);
    }
    backend = await anthropicBackend(direct);
  }
  const conversations = selectConversations(env("EVAL_SIM_FILTER"));
  if (conversations.length === 0) {
    console.error("EVAL_SIM_FILTER matched no conversation.");
    Deno.exit(2);
  }
  const requestedTurns = integer(env("EVAL_SIM_MAX_TURNS"), 3, 1, maxTurnsLimit);
  const maxUsd = Number(env("EVAL_MAX_USD") ?? "3");
  const reportDir = env("EVAL_REPORT_DIR") ??
    `.tooling/coach-evals/simulation-${new Date().toISOString().replace(/[:.]/g, "-")}`;
  await Deno.mkdir(reportDir, { recursive: true });

  const { coachCheck, coachChoice, production, available } = backend;
  let coachModel = coachCheck.working?.model ?? coachCheck.wanted;
  // When the router cannot list its models, the athlete is the Coach's model, which it serves.
  const athleteModel = env("EVAL_ATHLETE_MODEL") ??
    (available.length
      ? pickModel(available, athletePreferences, [coachModel]) ?? coachModel
      : coachModel);
  const sizes = await promptTokensByPersona(conversations);
  const promptTokens = (persona: PersonaId) => sizes.get(persona) ?? 10_000;
  const sizeFor = (judge: string | null) =>
    fitRun(
      { conversations, coachModel, athleteModel, judgeModel: judge, promptTokens },
      requestedTurns,
      maxUsd,
    );
  // The judge is the strongest listed model other than the Coach that the cap can pay for, with
  // every conversation running. When none can be paid for there is no judge, and the report says
  // so: the conversations all run, graded by code.
  const judgeCandidates = env("EVAL_JUDGE_MODEL")
    ? [env("EVAL_JUDGE_MODEL")!]
    : pickModels(available, judgePreferences, [coachModel]);
  let judgeModel: string | null = env("EVAL_JUDGE_MODEL") ??
    judgeCandidates.find((candidate) => sizeFor(candidate).fits) ?? null;
  try {
    if (judgeModel) assertDistinctJudge(judgeModel, coachModel);
  } catch (error) {
    console.error((error as Error).message);
    Deno.exit(2);
  }
  let judgeNote = judgeCandidates.length === 0
    ? "the router lists no model other than the Coach's"
    : `no judge among ${
      judgeCandidates.join(", ")
    } fits the USD ${maxUsd} cap with every conversation running`;
  const athleteCheck = await backend.preflightChat("athlete", athleteModel);
  const judgeCheck: PreflightResult | null = judgeModel === null
    ? null
    : judgeModel === athleteModel
    ? { ...athleteCheck, role: "judge" }
    : await backend.preflightChat("judge", judgeModel);
  const checks = [coachCheck, athleteCheck, ...(judgeCheck ? [judgeCheck] : [])];
  const preflight = [
    backend.listing,
    ...renderPreflight(checks),
  ];
  console.log(["Preflight:", ...preflight].join("\n"));
  // A judge is report-only: one with no working request is dropped, the Coach and the athlete are not.
  const decision = decidePreflight(checks.filter((check) => check.role !== "judge"));
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
  let judgeWorking = judgeCheck;
  if (judgeCheck && judgeCheck.working === null) {
    judgeNote = `the judge ${judgeModel} had no working request (see Preflight)`;
    judgeModel = null;
    judgeWorking = null;
  }
  const modes = new Map<string, ChatMode>();
  for (const check of [athleteCheck, ...(judgeWorking ? [judgeWorking] : [])]) {
    modes.set(check.working!.model, check.working!.mode);
  }

  const fit = sizeFor(judgeModel);
  const sizing =
    `Sized to the cap so that every conversation runs: ${fit.maxTurns} athlete messages per conversation (asked for ${requestedTurns}), ${
      judgeModel
        ? `judging ${fit.judgeEvery === 1 ? "every reply" : "every other reply"}`
        : "no judges"
    }; estimate USD ${fit.estimateUsd.toFixed(4)} against ${
      capShare * 100
    }% of the USD ${maxUsd} cap${
      fit.fits
        ? ""
        : " (DOES NOT FIT: the cap will stop the run and later conversations may be short)"
    }.`;
  const assumedPrices = [coachModel, athleteModel, judgeModel].filter((m): m is string =>
    m !== null && knownPrice(m) === null
  );
  console.log(
    [
      `Coach: ${coachModel} (${coachChoice}).`,
      `Athlete: ${athleteModel}. Judges: ${judgeModel ?? `off (${judgeNote})`}.`,
      `Models listed: ${available.length || "none"} (${backend.endpoint}).`,
      `${conversations.length} conversations, up to ${fit.turns} Coach turns. Estimated cost USD ${
        fit.estimateUsd.toFixed(4)
      } at list prices${
        assumedPrices.length ? ` (assumed prices for ${assumedPrices.join(", ")})` : ""
      }; cap USD ${maxUsd}.`,
      sizing,
    ].join("\n"),
  );

  // The estimate is printed before any Coach turn; a run whose smallest size is estimated over the
  // cap itself does not start (one that fits only past capShare still runs and the cap stops it).
  if (fit.estimateUsd > maxUsd) {
    const message = `The estimate USD ${
      fit.estimateUsd.toFixed(4)
    } exceeds the USD ${maxUsd} cap at the smallest size. The run did not start.`;
    await Deno.writeTextFile(
      `${reportDir}/simulation.md`,
      ["# Coach simulation: over the cap", "", message, "", sizing].join("\n"),
    );
    console.error(message);
    Deno.exit(2);
  }

  const result = await simulate({
    coach: backend.generateFor(played),
    coachModel,
    athleteModel,
    judgeModel,
    chat: backend.chat(modes),
    conversations,
    maxTurns: fit.maxTurns,
    judgeEvery: fit.judgeEvery,
    maxUsd,
    concurrency: integer(env("EVAL_CONCURRENCY"), 3, 1, 8),
  });
  const failures = harnessFailures(result.conversations, judgeModel !== null, result.errors);
  const text = renderReport(result.conversations, result.spend, result.stoppedForBudget, {
    coachModel,
    coachChoice,
    productionModel: productionCoachModel,
    production,
    athleteModel,
    judgeModel,
    judgeNote,
    endpoint: backend.endpoint,
    maxUsd,
    maxTurns: fit.maxTurns,
    estimateUsd: fit.estimateUsd,
    judgeOutputTokens: result.judgeOutputTokens,
    judgeMaxTokens,
    sizing,
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
          turns: run.turns.map((
            { context: _context, contributions, proposalState: _plan, ...turn },
          ) => ({
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
