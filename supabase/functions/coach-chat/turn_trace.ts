// What a Coach turn leaves for the lead to query (A10): which guard rules an attempt broke, how
// the turn fell back to the data summary, and which lookups ran. Names and counts only, never
// message content, a figure or a lookup's rows. They are stored on the assistant message
// (coach_messages.guard_faults and .lookups, migration 20261018100020), so "why did that turn
// fall back?" is a query on one row.
import type { CoachChatAttemptTelemetry } from "../_shared/providers/coach_chat_provider.ts";
import type { LookupCount } from "../_shared/coach_lookups/runner.ts";

/** The most entries a column holds (the migration's check). */
export const mostTraceEntries = 12;

const quietOutcomes = new Set(["valid", "invalid", "lookup", "truncated"]);

/**
 * Entries like `rule:numbers_not_grounded:2` (attempts that broke the rule), `outcome:repair_timeout`
 * (an attempt that never produced an answer) and `fallback:provider_response_invalid` (the turn
 * ended in the data summary). Empty when the turn was clean.
 */
export function guardFaultsOf(
  attempts: readonly CoachChatAttemptTelemetry[],
  fallbackCode?: string,
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

/** The service-role update the trace is written with, typed structurally. */
export type TraceClient = Readonly<{
  from(table: "coach_messages"): {
    update(values: { guard_faults?: string[]; lookups?: string[] }): {
      eq(column: "id", value: string): {
        eq(column: "user_id", value: string): PromiseLike<{ error: unknown }>;
      };
    };
  };
}>;

/**
 * Writes the trace on the assistant message. A clean turn writes nothing. A failure never fails
 * the turn: it is reported to the caller as false.
 */
export async function recordTurnTrace(
  client: TraceClient,
  userId: string,
  messageId: string | undefined,
  trace: Readonly<{ guardFaults: readonly string[]; lookups: readonly string[] }>,
): Promise<boolean> {
  if (!messageId || (trace.guardFaults.length === 0 && trace.lookups.length === 0)) return true;
  try {
    const { error } = await client.from("coach_messages").update({
      ...(trace.guardFaults.length ? { guard_faults: [...trace.guardFaults] } : {}),
      ...(trace.lookups.length ? { lookups: [...trace.lookups] } : {}),
    }).eq("id", messageId).eq("user_id", userId);
    return !error;
  } catch {
    return false;
  }
}
