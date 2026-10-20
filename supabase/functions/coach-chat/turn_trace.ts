// What a Coach turn leaves for the lead to query (A10): which guard rules an attempt broke, how
// the turn fell back to the data summary, and which lookups ran. Names and counts only, never
// message content, a figure or a lookup's rows. They are stored on the assistant message
// (coach_messages.guard_faults and .lookups, migration 20261018100020; .lookup_rounds, migration
// 20261020100017), so "why did that turn fall back?" is a query on one row. The library version the turn searched (E3,
// coach_messages.library_version, migration 20261018200044) says which library content the answer
// was shown.
import type { CoachChatAttemptTelemetry } from "../_shared/providers/coach_chat_provider.ts";
import type { LookupCount } from "../_shared/coach_lookups/runner.ts";

/** The most entries the guard_faults and lookups columns hold (the first migration's check). */
export const mostTraceEntries = 12;
/**
 * The most entries the lookup_rounds column holds: two rounds of eight distinct lookups, and one
 * entry that says a refused request was corrected (migration 20261020100017).
 */
export const mostRoundEntries = 17;

const quietOutcomes = new Set(["valid", "invalid", "lookup", "truncated"]);

/**
 * Entries like `rule:numbers_not_grounded:2` (attempts that broke the rule), `outcome:repair_timeout`
 * (an attempt that never produced an answer), `salvage:numbers_stripped` (the reply was cut
 * instead of falling back: its sentences with figures that are not in the athlete's data were
 * removed) and `fallback:provider_response_invalid` (the turn ended in the data summary). Empty
 * when the turn was clean.
 */
export function guardFaultsOf(
  attempts: readonly CoachChatAttemptTelemetry[],
  fallbackCode?: string,
  cuts: readonly string[] = [],
): string[] {
  const rules = new Map<string, number>();
  const outcomes = new Set<string>();
  for (const attempt of attempts) {
    for (const rule of [attempt.rule, ...(attempt.alsoRules ?? [])]) {
      if (rule) rules.set(rule, (rules.get(rule) ?? 0) + 1);
    }
    if (!quietOutcomes.has(attempt.outcome)) outcomes.add(`${attempt.attempt}_${attempt.outcome}`);
  }
  const entries = [
    ...[...rules].map(([rule, count]) => `rule:${rule}:${count}`),
    ...[...outcomes].map((outcome) => `outcome:${outcome}`),
    ...cuts.map((cut) => `salvage:${cut}`),
    ...(fallbackCode ? [`fallback:${fallbackCode}`] : []),
  ];
  return entries.slice(0, mostTraceEntries);
}

/** Entries like `exercise_history:14`: the lookup and the rows it returned, summed over rounds. */
export function lookupTrace(counts: readonly LookupCount[] | undefined): string[] {
  const rows = new Map<string, number>();
  for (const count of counts ?? []) {
    rows.set(count.lookup, (rows.get(count.lookup) ?? 0) + count.rows);
  }
  return [...rows].map(([lookup, total]) => `${lookup}:${total}`).slice(0, mostTraceEntries);
}

/**
 * Whether the turn sent a corrected round: an attempt whose data_requests the catalogue refused,
 * followed by a lookup call that was told why (the gateway sends one per turn at most).
 */
export function correctionSent(attempts: readonly CoachChatAttemptTelemetry[]): boolean {
  return attempts.some((attempt, index) =>
    attempt.rule === "lookup_request_invalid" && attempts[index + 1]?.attempt === "lookup"
  );
}

/**
 * Entries like `r1_workouts:4`, `r1_plan_history_proposals:3` and `r2_recovery:28`: the round a
 * lookup ran in (`r1` is the first), its name, its mode when the filter selects different records
 * (`plan_history` reads plan versions, the schedule or proposals), and the rows it returned, summed
 * within the round; and `correction:1` when a refused request was corrected. They show how wide the
 * first round was and what the second one followed up, so the lead can measure how Coach
 * investigates. A count with no round is read as round 1. Written to lookup_rounds; the older
 * lookups column keeps its names and totals.
 */
export function lookupRoundsTrace(
  counts: readonly LookupCount[] | undefined,
  attempts: readonly CoachChatAttemptTelemetry[] = [],
): string[] {
  const rows = new Map<string, number>();
  for (const count of counts ?? []) {
    const key = `r${count.round ?? 1}_${count.lookup}${count.mode ? `_${count.mode}` : ""}`;
    rows.set(key, (rows.get(key) ?? 0) + count.rows);
  }
  return [
    ...[...rows].map(([entry, total]) => `${entry}:${total}`),
    ...(correctionSent(attempts) ? ["correction:1"] : []),
  ].slice(0, mostRoundEntries);
}

/** The service-role update the trace is written with, typed structurally. */
export type TraceClient = Readonly<{
  from(table: "coach_messages"): {
    update(
      values: {
        guard_faults?: string[];
        lookups?: string[];
        lookup_rounds?: string[];
        library_version?: string;
      },
    ): {
      eq(column: "id", value: string): {
        eq(column: "user_id", value: string): PromiseLike<{ error: unknown }>;
      };
    };
  };
}>;

/** The library version, when the turn searched the library and it reported one. */
const libraryVersionPattern = /^[0-9a-f]{16}$/;

/**
 * Writes the trace on the assistant message. A clean turn that did not search the library writes
 * nothing. A failure never fails the turn: it is reported to the caller as false.
 */
export async function recordTurnTrace(
  client: TraceClient,
  userId: string,
  messageId: string | undefined,
  trace: Readonly<{
    guardFaults: readonly string[];
    lookups: readonly string[];
    /** Per round and mode (`lookupRoundsTrace`); absent from a caller that has none. */
    lookupRounds?: readonly string[];
    libraryVersion?: string | null;
  }>,
): Promise<boolean> {
  const libraryVersion = typeof trace.libraryVersion === "string" &&
      libraryVersionPattern.test(trace.libraryVersion)
    ? trace.libraryVersion
    : null;
  const rounds = trace.lookupRounds ?? [];
  if (
    !messageId ||
    (trace.guardFaults.length === 0 && trace.lookups.length === 0 && rounds.length === 0 &&
      libraryVersion === null)
  ) return true;
  try {
    const { error } = await client.from("coach_messages").update({
      ...(trace.guardFaults.length ? { guard_faults: [...trace.guardFaults] } : {}),
      ...(trace.lookups.length ? { lookups: [...trace.lookups] } : {}),
      ...(rounds.length ? { lookup_rounds: [...rounds] } : {}),
      ...(libraryVersion ? { library_version: libraryVersion } : {}),
    }).eq("id", messageId).eq("user_id", userId);
    return !error;
  } catch {
    return false;
  }
}
