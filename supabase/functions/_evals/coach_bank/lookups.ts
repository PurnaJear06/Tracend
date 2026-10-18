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
      const found = (rows[request.lookup] ?? []).filter((row) =>
        row.date >= request.from && row.date <= request.to
      );
      const lines = found.length === 0
        ? ["No records in this range."]
        : found.map((row) => `- ${row.date}: ${row.text}`);
      return { request, lines, rows: found.length };
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

/** Every row of every lookup the case supplies, as grounding text for the numbers check. */
export function allLookupRows(rows: Readonly<Record<string, readonly LookupRow[]>>): string {
  return Object.entries(rows).map(([name, list]) =>
    [`Lookup ${name}:`, ...list.map((row) => `- ${row.date}: ${row.text}`)].join("\n")
  ).join("\n");
}
