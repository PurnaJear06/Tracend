// The simulated-athlete loop. For each conversation (a persona in a scenario) the athlete model
// writes a message; the Coach answers through the bank harness, which builds the turn as
// coach-chat does (the athlete file, the real contributors, the library, the production lookup
// runner over the persona's records) and runs the production gateway path (lookup rounds,
// proposal intent, the red-flag screen and every reply guard); the reply joins the conversation
// as coach-chat stores it; code graders and the judges grade the turn. Only the database and the
// vector search are stand-ins.
import type { TokenCounts } from "../../_shared/ai/models.ts";
import { noCoachContributions } from "../../_shared/coach_context/host.ts";
import { createLookupRunner, type LookupRound } from "../../_shared/coach_lookups/runner.ts";
import type { CoachLookupRunner } from "../../_shared/coach_lookups/runner.ts";
import { screenTurn } from "../../_shared/coach_safety/red_flags.ts";
import { stateFixture } from "../../_shared/coach_proposals/fixtures.ts";
import { coachReplyCheckFor } from "../../_shared/providers/coach_chat_provider.ts";
import { previousQuestionsOf } from "../../_shared/library/query.ts";
import { answerTurn, renderTurn } from "../coach_bank/harness.ts";
import type { DataRequest, GraderResult, Turn } from "../coach_bank/types.ts";
import { type Generate, priceTokens, runPool } from "../live_model.ts";
import {
  describeStatus,
  isCreditsError,
  type ProviderError,
  summariseErrors,
  type WireError,
} from "./diagnostics.ts";
import { providerErrorCodes } from "./verdict.ts";
import { nextAthleteMessage } from "./athlete.ts";
import {
  athleteDataText,
  athleteSees,
  checkProposal,
  gradeConversation,
  gradeTurn,
  type TurnRecord,
} from "./graders.ts";
import { type Claim, type ExpertVerdict, judgeClaims, judgeExpert } from "./judges.ts";
import { wordSearch } from "./library_search.ts";
import { inspectAnswers, type Rejection } from "./rejections.ts";
import { personaById } from "./personas.ts";
import { proposalStateOf, recordsRpc } from "./records.ts";
import type { RouterChat } from "./router_client.ts";
import { type Conversation, openingFor } from "./scenarios.ts";

/** Most athlete messages in one conversation, whatever the scenario plans. */
export const maxTurnsLimit = 10;
/** Messages coach-chat keeps of a thread (prepare_coach_chat's limit of 20). */
export const threadWindow = 20;

export type Spend = { coach: number; athlete: number; judges: number };

export const spentUsd = (spend: Spend) => spend.coach + spend.athlete + spend.judges;

export type SimulationOptions = Readonly<{
  /**
   * The gateway path with the Coach model; `onUsage` sees the tokens of every Coach call,
   * `onError` every failed one (its status and redacted body) and `onAnswer` the text of every
   * answer the model gave, whether the guard kept it or not.
   */
  coach: (
    onUsage: (tokens: TokenCounts) => void,
    onError: (error: WireError) => void,
    onAnswer: (text: string) => void,
  ) => Generate;
  coachModel: string;
  athleteModel: string;
  /** The judges' model, never the Coach's; null runs no judge. */
  judgeModel: string | null;
  chat: RouterChat;
  conversations: readonly Conversation[];
  /** Athlete messages per conversation at most (the scenario's own count when lower). */
  maxTurns: number;
  /** New Coach turns and judge calls stop once the run has spent this much. */
  maxUsd: number;
  /** Judge every Nth Coach reply (the first of each N; default every reply). */
  judgeEvery?: number;
  concurrency?: number;
}>;

export type TurnRun =
  & TurnRecord
  & Readonly<{
    grades: readonly GraderResult[];
    expert?: ExpertVerdict;
    claims?: readonly Claim[];
    judgeFailures: readonly string[];
    /** The attempts the reply check refused this turn, with the figures it named. */
    rejected: readonly Rejection[];
    costs: Readonly<{ coach: number; athlete: number; judges: number }>;
  }>;

export type ConversationRun = Readonly<{
  id: string;
  conversation: Conversation;
  turns: readonly TurnRun[];
  grades: readonly GraderResult[];
  /** Why it ended before its planned messages, if it did. */
  ended: "planned" | "athlete_done" | "budget" | "credits" | "athlete_failed" | "harness_error";
  /** An exception in the simulator itself, or the athlete model failing. */
  error?: string;
  costUsd: number;
}>;

type Ending = Readonly<{ ended: ConversationRun["ended"]; error?: string }>;

export type SimulationResult = Readonly<{
  conversations: readonly ConversationRun[];
  spend: Spend;
  stoppedForBudget: boolean;
  /** Every failed model call (Coach, athlete, judges) with where it happened. */
  errors: readonly ProviderError[];
  /** Output tokens of every judge call that answered or ran out (thinking included). */
  judgeOutputTokens: readonly number[];
}>;

/** This many Coach turns ending in a provider error, with no model answer yet, stop the run. */
export const brokenRouteTurns = 6;

/** The text an athlete sees for a reply: the answer, or what the app shows instead. */
const shownToAthlete = (turn: TurnRecord) =>
  turn.reply.outcome === "dead_end"
    ? "(No reply: the app showed an error.)"
    : turn.shown ?? turn.reply.answer;

export async function simulate(options: SimulationOptions): Promise<SimulationResult> {
  const spend: Spend = { coach: 0, athlete: 0, judges: 0 };
  let stoppedForBudget = false;
  const errors: ProviderError[] = [];
  const judgeOutputTokens: number[] = [];
  let coachErrorTurns = 0;
  let coachAnswers = 0;
  // The router account ran out of credit: nothing more can be asked of it.
  let creditsOut = false;
  const overBudget = () => {
    if (spentUsd(spend) >= options.maxUsd) stoppedForBudget = true;
    return stoppedForBudget || creditsOut;
  };
  const logError = (error: ProviderError) => {
    if (isCreditsError(error)) creditsOut = true;
    errors.push(error);
  };
  const turnsFor = (conversation: Conversation) =>
    Math.min(conversation.scenario.turns, options.maxTurns, maxTurnsLimit);

  const logJudgeError = (error: WireError | undefined, conversation: string, turn: number) => {
    if (error && options.judgeModel) {
      logError({ ...error, source: "judge", model: options.judgeModel, conversation, turn });
    }
  };

  const runOne = async (conversation: Conversation): Promise<ConversationRun> => {
    const turns: TurnRun[] = [];
    let outcome: Ending;
    try {
      outcome = await converse(conversation, turns);
    } catch (thrown) {
      outcome = {
        ended: "harness_error",
        error: thrown instanceof Error ? `${thrown.name}: ${thrown.message}` : String(thrown),
      };
    }
    const { ended, error } = outcome;
    return {
      id: conversation.id,
      conversation,
      turns,
      grades: turns.length ? gradeConversation(conversation.scenario, turns) : [],
      ended,
      ...(error ? { error } : {}),
      costUsd: turns.reduce((sum, t) => sum + t.costs.coach + t.costs.athlete + t.costs.judges, 0),
    };
  };

  const converse = async (conversation: Conversation, turns: TurnRun[]): Promise<Ending> => {
    const { scenario } = conversation;
    const persona = personaById(conversation.persona);
    const base = persona.athlete();
    const search = wordSearch(persona.region);
    const runner = createLookupRunner(recordsRpc(persona.records, persona.extras), "sim-athlete");
    const proposalState = proposalStateOf(persona.records, stateFixture(), persona.profile);
    let turnTokens: TokenCounts[] = [];
    let turnAnswers: string[] = [];
    let current = 0;
    const generate = options.coach(
      (tokens) => turnTokens.push(tokens),
      (error) =>
        logError({
          ...error,
          source: "coach",
          model: options.coachModel,
          conversation: conversation.id,
          turn: current,
        }),
      (text) => turnAnswers.push(text),
    );
    const planned = turnsFor(conversation);
    const thread: Turn[] = [];
    const seen: Turn[] = [];

    for (let number = 1; number <= planned; number++) {
      let athleteCost = 0;
      let athleteDone = false;
      let question = openingFor(scenario, persona.id);
      if (number > 1) {
        if (creditsOut) return { ended: "credits" };
        if (overBudget()) return { ended: "budget" };
        const next = await nextAthleteMessage(
          options.chat,
          options.athleteModel,
          persona,
          scenario,
          seen,
          number,
          planned,
        );
        athleteCost = next.costUsd;
        spend.athlete += next.costUsd;
        if (next.error) {
          logError({
            ...next.error,
            source: "athlete",
            model: options.athleteModel,
            conversation: conversation.id,
            turn: number,
          });
        }
        if (creditsOut) return { ended: "credits" };
        if (!next.message) {
          return { ended: "athlete_failed", error: `athlete model: ${next.failure}` };
        }
        question = next.message.message;
        athleteDone = next.message.done;
      }
      if (creditsOut) return { ended: "credits" };
      if (overBudget()) return { ended: "budget" };

      const context = { ...base.context, recent_messages: thread.slice(-threadWindow) };
      const athlete = { ...base, context };
      // A red-flag turn is answered by the fixed referral, and coach-chat renders no contributor.
      const contributions = screenTurn(question, context)
        ? noCoachContributions
        : await renderTurn(athlete, question, previousQuestionsOf(context, question), {
          librarySearch: search,
        });
      const requested: DataRequest[] = [];
      const rounds: LookupRound[] = [];
      const lookups: CoachLookupRunner = async (requests) => {
        requested.push(...requests.map((request) => ({
          lookup: request.lookup,
          from: request.from,
          to: request.to,
          ...(request.filter === null ? {} : { filter: request.filter }),
        })));
        const round = await runner(requests);
        rounds.push(round);
        return round;
      };
      turnTokens = [];
      turnAnswers = [];
      current = number;
      const answered = await answerTurn({
        question,
        context,
        contributions,
        lookups,
        requested,
        factSuggestions: true,
      }, generate);
      const coachCost = turnTokens.reduce(
        (sum, tokens) => sum + priceTokens(options.coachModel, tokens).usd,
        0,
      );
      spend.coach += coachCost;
      const metadata = answered.failure?.metadata;
      let record: TurnRecord = {
        number,
        question,
        reply: { ...answered.reply, costUsd: coachCost },
        attempts: answered.generation?.attempts ?? metadata?.attempts ?? [],
        failedRules: [metadata?.initialRule, metadata?.repairRule].flatMap((rule) =>
          rule === undefined ? [] : [String(rule)]
        ),
        servedBy: answered.generation?.model ?? null,
        context,
        contributions,
        lookedUp: rounds.map((round) => round.text).join("\n\n"),
        grounds: rounds.flatMap((round) => round.grounds),
        history: [...thread],
        proposalState,
      };
      // What the athlete reads: the proposal step runs after the reply guard, as in coach-chat.
      const proposalCheck = record.reply.proposalIntent === undefined ? null : checkProposal(
        record.reply.proposalIntent,
        question,
        String(base.context.coaching_date),
        proposalState,
      );
      const shown = athleteSees(record.reply, proposalCheck);
      if (shown !== record.reply.answer) record = { ...record, shown };
      const grades = gradeTurn(record, turns);
      const rejected = inspectAnswers(
        turnAnswers,
        coachReplyCheckFor(context, question, contributions, record.grounds),
        new Set(Object.keys(contributions.shown)),
      );
      if (record.reply.outcome === "model") coachAnswers++;
      else if (
        record.reply.failureCode !== undefined && providerErrorCodes.has(record.reply.failureCode)
      ) coachErrorTurns++;

      let judgeCost = 0;
      const judgeFailures: string[] = [];
      let expert: ExpertVerdict | undefined;
      let claims: readonly Claim[] | undefined;
      if (
        options.judgeModel && record.reply.outcome === "model" &&
        (number - 1) % (options.judgeEvery ?? 1) === 0 && !overBudget()
      ) {
        const judged = await judgeExpert(options.chat, options.judgeModel, {
          athleteData: athleteDataText(record),
          coachBrief: scenario.coachBrief,
          earlier: seen,
          question,
          reply: shownToAthlete(record),
          lookedUp: record.lookedUp,
        });
        judgeCost += judged.costUsd;
        if (judged.outputTokens !== undefined) judgeOutputTokens.push(judged.outputTokens);
        if (judged.verdict) expert = judged.verdict;
        else {
          judgeFailures.push(`expert: ${judged.failure}`);
          logJudgeError(judged.error, conversation.id, number);
        }
        const cited = (record.reply.citations ?? []).filter((key) =>
          Object.hasOwn(contributions.shown, key)
        );
        if (cited.length > 0 && !overBudget()) {
          const checked = await judgeClaims(options.chat, options.judgeModel, {
            reply: shownToAthlete(record),
            excerpts: Object.fromEntries(cited.map((key) => [key, contributions.shown[key].text])),
          });
          judgeCost += checked.costUsd;
          if (checked.outputTokens !== undefined) judgeOutputTokens.push(checked.outputTokens);
          if (checked.verdict) claims = checked.verdict;
          else {
            judgeFailures.push(`claims: ${checked.failure}`);
            logJudgeError(checked.error, conversation.id, number);
          }
        }
        spend.judges += judgeCost;
      }

      turns.push({
        ...record,
        grades,
        ...(expert ? { expert } : {}),
        ...(claims ? { claims } : {}),
        judgeFailures,
        rejected,
        costs: { coach: coachCost, athlete: athleteCost, judges: judgeCost },
      });

      // The thread as coach-chat stores it (prepare_coach_chat_v10): the question always, the
      // answer as the athlete read it, a labelled data summary marked as the app's own reply, and
      // nothing when nothing arrived.
      thread.push({ role: "user", content: question });
      if (record.reply.outcome === "model" || record.reply.outcome === "boundary") {
        thread.push({ role: "assistant", content: shownToAthlete(record) });
      } else if (record.reply.outcome === "data_summary") {
        thread.push({
          role: "assistant",
          content: record.reply.answer,
          answer_source: "data_summary",
        });
      }
      seen.push({ role: "user", content: question }, {
        role: "assistant",
        content: shownToAthlete(record),
      });
      // The athlete may close the conversation once it has had a fair run.
      if (athleteDone && number >= 4) return { ended: "athlete_done" };
      // A route that has only failed so far is broken: stop instead of spending the whole run on it.
      if (coachAnswers === 0 && coachErrorTurns >= brokenRouteTurns) {
        return {
          ended: "harness_error",
          error: `the Coach route failed ${coachErrorTurns} turns and answered none: ${
            summariseErrors(errors.filter((e) => e.source === "coach")).slice(0, 2).map((g) =>
              `${describeStatus(g.status, g.kind)} ${g.body}`
            ).join(" | ") || "no error was captured"
          }`,
        };
      }
    }
    return { ended: "planned" };
  };

  const runs = await runPool(
    options.conversations.map((conversation) => () => runOne(conversation)),
    options.concurrency ?? 3,
  );
  const order = options.conversations.map((c) => c.id);
  return {
    conversations: [...runs].sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id)),
    spend,
    stoppedForBudget,
    errors: errors.slice(0, 500),
    judgeOutputTokens,
  };
}
