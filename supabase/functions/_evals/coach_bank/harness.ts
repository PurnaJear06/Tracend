// Runs bank cases: builds the turn exactly as coach-chat does (athlete file plus the reference-data
// contributors), asks the model through the production path (which runs the data-lookup rounds), and grades the
// reply. A case that expects a red-flag hit never reaches a model: the
// screen answers it, as in production.
import {
  type CoachContextContributor,
  type CoachContributions,
  renderCoachContext,
} from "../../_shared/coach_context/host.ts";
import { createGoalPhaseContributor } from "../../_shared/coach_context/contributors/goal_phase.ts";
import { createNutritionStateContributor } from "../../_shared/coach_context/contributors/nutrition_state.ts";
import { createTrainingPlanContributor } from "../../_shared/coach_context/contributors/training_plan.ts";
import { createScreeningContributor } from "../../_shared/coach_context/contributors/screening.ts";
import { createCoverageBriefContributor } from "../../_shared/coach_context/contributors/coverage_brief.ts";
import { createWatchOutsContributor } from "../../_shared/coach_context/contributors/watch_outs.ts";
import {
  createStandingStateContributor,
  parseStandingState,
  type StandingStateSource,
} from "../../_shared/coach_context/contributors/standing_state.ts";
import { addDays } from "../../_shared/training/schedule/week_ahead.ts";
import { createConfirmedFactsContributor } from "../../_shared/coach_context/contributors/confirmed_facts.ts";
import { createCoachNotesContributor } from "../../_shared/coach_context/contributors/coach_notes.ts";
import { coachingPrinciplesContributor } from "../../_shared/library/principles.ts";
import { chunkSource } from "../../_shared/library/chunk.ts";
import {
  createLibraryContributor,
  type LibraryRow,
  type LibrarySearch,
} from "../../_shared/library/retrieval.ts";
import { librarySources } from "../../../library/index.ts";
import { buildCoachChatDataSummary } from "../../_shared/coach_chat_fallback.ts";
import {
  classifyQuestion,
  coachChatFailureUsage,
  type CoachChatGeneration,
  CoachChatUnavailableError,
} from "../../_shared/providers/coach_chat_provider.ts";
import type { CoachLookupRunner } from "../../_shared/coach_lookups/runner.ts";
import type { Generate } from "../live_model.ts";
import { type Prepared } from "./graders.ts";
import { bankLookupRunner } from "./lookups.ts";
import type { Athlete, BankCase, Contributors, DataRequest, Reply, Turn } from "./types.ts";

/** A prepared case, with the contributor text the model sees before any lookup. */
export type PreparedRun = Prepared & Readonly<{ firstRound: CoachContributions }>;

const evalUserId = "eval-athlete";

/** The chunks of the given sources, as the search would return them, in the order given. */
export function libraryRowsOf(keys: readonly string[]): LibraryRow[] {
  return keys.flatMap((key) => {
    const source = librarySources.find((item) => item.slug === key);
    if (!source) throw new Error(`unknown library source ${key}`);
    return chunkSource(source).map((chunk) => ({
      sourceId: source.slug,
      title: source.title,
      year: source.year,
      header: chunk.header,
      body: chunk.body,
    }));
  });
}

/**
 * A get_coach_data_index_v1 payload for a case: the kinds the athlete file shows have records back
 * to well before the file's window, up to the newest row it holds; the rest have none. Synthetic.
 */
export function bankIndex(
  context: Record<string, unknown>,
  contributors: Contributors,
): Record<string, unknown> {
  const today = String(context.coaching_date);
  const newest = (key: string, field: string): string | null => {
    const rows = Array.isArray(context[key]) ? context[key] as Record<string, unknown>[] : [];
    const dates = rows.map((row) => String(row[field] ?? "")).filter(Boolean).sort();
    return dates.at(-1) ?? null;
  };
  const kind = (last: string | null, back: number, count: number) =>
    last === null
      ? { first: null, last: null, count: 0 }
      : { first: addDays(today, -back), last, count };
  const weekdays = Array.isArray((contributors.trainingPlan as { sessions?: unknown[] })?.sessions)
    ? [
      ...new Set(
        (contributors.trainingPlan as { sessions: { weekday: number | null }[] }).sessions
          .map((session) => session.weekday).filter((day): day is number => day !== null),
      ),
    ].sort()
    : [];
  return {
    schema_version: "1.2",
    local_date: today,
    domains: {
      workouts: kind(newest("training_log_28d", "local_date"), 150, 61),
      meals: kind(newest("nutrition_daily_28d", "local_date"), 120, 80),
      body: kind(newest("weight_series_8w", "measured_on"), 150, 40),
      check_ins: kind(newest("check_ins_14d", "local_date"), 100, 60),
      recovery: kind(newest("health_daily_28d", "local_date"), 150, 120),
      plan_history: kind(context.active_plan ? addDays(today, -60) : null, 60, 2),
      goals: kind(context.active_goal ? addDays(today, -100) : null, 100, 1),
      weekly_reviews: kind(null, 0, 0),
      health_history: kind(null, 0, 0),
      watch_workouts: kind(newest("watch_workouts_14d", "local_date"), 150, 40),
      proposals: kind(null, 0, 0),
      daily_decisions: kind(null, 0, 0),
      past_messages: kind(null, 0, 0),
    },
    schedule: weekdays.length ? { version: 3, starts_on: addDays(today, -60), weekdays } : null,
  };
}

/** What the turn's contributors read beyond the case data: a search for the library contributor. */
export type TurnOptions = Readonly<{
  /**
   * Runs the library search when the athlete's contributors name no fixed sources (the simulator's
   * stand-in for the database search).
   */
  librarySearch?: LibrarySearch;
}>;

/** The real contributors over the athlete's reference data, in the registry's order. */
function contributorsOf(athlete: Athlete, options: TurnOptions = {}): CoachContextContributor[] {
  const { context, contributors } = athlete;
  const list: CoachContextContributor[] = [];
  // The real standing state over the case's payload, read by the plan and the watch-outs too.
  const standing: StandingStateSource | undefined = contributors.standingState === undefined
    ? undefined
    : (_user, localDate) =>
      Promise.resolve(parseStandingState(contributors.standingState, localDate));
  if (contributors.principles !== false) list.push(coachingPrinciplesContributor);
  const screening = contributors.screening === undefined ? "cleared" : contributors.screening;
  list.push(
    createScreeningContributor(() =>
      screening === "unreadable"
        ? Promise.reject(new Error("screening unreadable"))
        : Promise.resolve(
          screening ? { outcome: screening, screenedAt: "2026-09-01T09:00:00Z" } : null,
        )
    ),
  );
  if (contributors.memory) {
    // The real contributors over the memory the case gives the athlete.
    const read = () =>
      Promise.resolve({
        localDate: "",
        facts: contributors.memory?.facts ?? [],
        notes: contributors.memory?.notes ?? [],
      });
    list.push(createConfirmedFactsContributor(read), createCoachNotesContributor(read));
  }
  if (contributors.nutritionState) {
    list.push(createNutritionStateContributor(() => Promise.resolve(contributors.nutritionState)));
  }
  if (contributors.trainingPlan) {
    list.push(
      createTrainingPlanContributor(
        () => Promise.resolve(contributors.trainingPlan),
        undefined,
        undefined,
        standing,
      ),
    );
  }
  if (contributors.goalPhase) {
    list.push(createGoalPhaseContributor(() => Promise.resolve(contributors.goalPhase)));
  }
  if (contributors.trainingPlan || contributors.watchFacts || contributors.schedule) {
    // The real watch-outs over the case's payloads: the plan state, the facts, the last weeks' plan.
    list.push(createWatchOutsContributor({
      planState: () => Promise.resolve(contributors.trainingPlan ?? null),
      facts: () => Promise.resolve(contributors.watchFacts ?? null),
      schedule: () => Promise.resolve(contributors.schedule ?? null),
      standing,
    }));
  }
  // The real Coverage Brief over the athlete's index (the simulator's personas carry one) or one
  // shaped like the athlete's file; the gateway route has it on every turn.
  const index = contributors.dataIndex ?? bankIndex(context, contributors);
  list.push(createCoverageBriefContributor(() => Promise.resolve(index)));
  if (contributors.library) {
    // The real contributor over fixed search results: the bank tests how Coach uses the excerpts,
    // not the search (library_eval.ts measures that against the database).
    const rows = libraryRowsOf(contributors.library);
    list.push(createLibraryContributor({
      embed: () => () => Promise.resolve([0]),
      search: () => Promise.resolve(rows),
    }));
  } else if (options.librarySearch) {
    list.push(createLibraryContributor({
      embed: () => () => Promise.resolve([0]),
      search: options.librarySearch,
    }));
  }
  if (standing) list.push(createStandingStateContributor(standing));
  return list;
}

/**
 * The contributor text of one turn, rendered by the real host as coach-chat renders it: the
 * question, the coaching date and the athlete's earlier questions (newest first) for the library.
 */
export function renderTurn(
  athlete: Athlete,
  question: string,
  previousQuestions: readonly string[] = [],
  options: TurnOptions = {},
): Promise<CoachContributions> {
  return renderCoachContext(contributorsOf(athlete, options), {
    userId: evalUserId,
    question,
    localDate: String(athlete.context.coaching_date),
    previousQuestions,
  });
}

/**
 * The turn for a case. `contributions` is what the final answer is graded against; the rows its
 * lookups returned are added when it is graded, from the requests the loop accepted
 * (`servedGrounds`), so only what the model asked for, within the dates it asked for, grounds a
 * figure. `firstRound` is what the model sees first.
 */
export async function prepare(bank: BankCase): Promise<PreparedRun> {
  const athlete = bank.athlete();
  const { context } = athlete;
  const firstRound = await renderTurn(athlete, bank.question);
  const history = (Array.isArray(context.recent_messages) ? context.recent_messages : []) as Turn[];
  return {
    bank,
    context,
    question: bank.question,
    history,
    firstRound,
    contributions: firstRound,
  };
}

function replyFrom(
  generation: CoachChatGeneration,
  requests: readonly DataRequest[],
  costUsd: number,
  started: number,
): Reply {
  return {
    outcome: generation.provider === "mock" ? "boundary" : "model",
    answer: generation.answer.answer,
    safetyState: generation.answer.safety_state,
    dataRequests: requests,
    ...(generation.proposalIntent === undefined
      ? {}
      : { proposalIntent: generation.proposalIntent }),
    citations: generation.answer.evidence.filter((item) => item.source === "library").map((item) =>
      item.code
    ),
    costUsd,
    latencyMs: Math.round(performance.now() - started),
  };
}

/** One question to the model, however its context and lookups were built. */
export type TurnRequest = Readonly<{
  question: string;
  context: Record<string, unknown>;
  /** The contributor text the model sees before any lookup. */
  contributions: CoachContributions;
  /** Runs the lookups the model asks for; it appends each request it is given to `requested`. */
  lookups: CoachLookupRunner;
  requested: readonly DataRequest[];
  factSuggestions: boolean;
}>;

/** The reply, with the generation it came from or the failure that made it a data summary. */
export type TurnAnswer = Readonly<{
  reply: Reply;
  generation?: CoachChatGeneration;
  failure?: CoachChatUnavailableError;
}>;

/**
 * One answer through the production loop. When the model asks for data, the loop validates the
 * request and calls the turn's runner; the model is called again with the rows (at most two
 * rounds). A failure becomes what the athlete would get: a labelled data summary, or nothing.
 */
export async function answerTurn(turn: TurnRequest, generate: Generate): Promise<TurnAnswer> {
  const started = performance.now();
  try {
    const generation = await generate({
      question: turn.question,
      context: structuredClone(turn.context),
      contextKind: classifyQuestion(turn.question),
      contributions: turn.contributions,
      lookups: turn.lookups,
      factSuggestions: turn.factSuggestions,
    });
    return {
      reply: replyFrom(generation, [...turn.requested], generation.estimatedCostUsd, started),
      generation,
    };
  } catch (error) {
    const latencyMs = Math.round(performance.now() - started);
    if (error instanceof CoachChatUnavailableError) {
      // The fallback the athlete would get: a labelled data summary.
      const summary = buildCoachChatDataSummary(structuredClone(turn.context), turn.question);
      return {
        reply: {
          outcome: "data_summary",
          answer: summary.answer,
          safetyState: summary.safety_state,
          dataRequests: [...turn.requested],
          costUsd: coachChatFailureUsage(error).estimatedCostUsd,
          latencyMs,
          failureCode: error.failureReason,
        },
        failure: error,
      };
    }
    return {
      reply: {
        outcome: "dead_end",
        answer: "",
        safetyState: "unavailable",
        dataRequests: [],
        costUsd: 0,
        latencyMs,
        failureCode: error instanceof Error ? error.name : "unknown",
      },
    };
  }
}

/**
 * One answer to a prepared case: the bank's runner serves the case's rows and records what was
 * asked, and the reply carries the requests the loop accepted.
 */
export async function answer(p: PreparedRun, generate: Generate): Promise<Reply> {
  const { contributors } = p.bank.athlete();
  const requested: DataRequest[] = [];
  const turn = await answerTurn({
    question: p.question,
    context: p.context,
    contributions: p.firstRound,
    lookups: bankLookupRunner(contributors.lookupRows ?? {}, requested),
    requested,
    factSuggestions: contributors.memory?.remember !== false,
  }, generate);
  return turn.reply;
}
