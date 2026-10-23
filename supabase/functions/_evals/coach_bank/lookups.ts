// On-demand data lookups (A10): the answer may carry `data_requests: [{lookup, from, to,
// filter}]` (filter "" for none); coach-chat validates them against the catalogue (`_shared/coach_lookups/`), runs
// them read-only and calls the model again, at most two rounds. The bank uses that same loop
// (generateCoachChatViaGateway) and only replaces what runs the lookups: a runner that serves the
// case's rows instead of the database and records the requests the loop passed it, so the bank
// grades what the model asked for and the dated rows its final answer cites.
import type { CoachLookupName } from "../../_shared/coach_lookups/catalogue.ts";
import type { CoachLookupRunner } from "../../_shared/coach_lookups/runner.ts";
import type { DataRequest, LookupRow } from "./types.ts";

export const lookupNames = Object.freeze(
  {
    exerciseHistory: "exercise_history",
    meals: "meals",
  } as const satisfies Record<string, CoachLookupName>,
);

/** The rows of one lookup within the range a request names, which is all the database would return. */
const served = (
  rows: Readonly<Record<string, readonly LookupRow[]>>,
  request: Readonly<{ lookup: string; from: string; to: string }>,
): LookupRow[] =>
  (rows[request.lookup] ?? []).filter((row) => row.date >= request.from && row.date <= request.to);

const linesOf = (found: readonly LookupRow[]): string[] =>
  found.length === 0
    ? ["No records in this range."]
    : found.map((row) => `- ${row.date}: ${row.text}`);

/**
 * A runner that serves a case's rows. Every request the loop validated and passed to it is
 * appended to `seen`; a lookup the case has no rows for answers with no records, as the database
 * would for an empty range.
 */
export function bankLookupRunner(
  rows: Readonly<Record<string, readonly LookupRow[]>>,
  seen: DataRequest[],
): CoachLookupRunner {
  return (requests) => {
    const blocks = requests.map((request) => {
      seen.push({
        lookup: request.lookup,
        from: request.from,
        to: request.to,
        ...(request.filter === null ? {} : { filter: request.filter }),
      });
      const found = served(rows, request);
      return { request, lines: linesOf(found), rows: found.length };
    });
    return Promise.resolve({
      text: "<looked_up_data>\n" + blocks.map((block) =>
        [
          `### ${block.request.lookup} ${block.request.from} to ${block.request.to}: ${block.rows} rows`,
          ...block.lines,
        ].join("\n")
      ).join("\n\n") + "\n</looked_up_data>",
      grounds: blocks.flatMap((block) => block.lines),
      counts: blocks.map((block) => ({ lookup: block.request.lookup, rows: block.rows })),
    });
  };
}

/**
 * What the numbers check is given for a turn that asked for `requests`: the rows those requests
 * return (only the lookups asked for, within the dates asked for), the lines the runner hands the
 * loop as its grounds. A figure from a row the model did not ask for is not grounded.
 */
export function servedGrounds(
  rows: Readonly<Record<string, readonly LookupRow[]>>,
  requests: readonly DataRequest[],
): string[] {
  return requests.flatMap((request) => linesOf(served(rows, request)));
}
