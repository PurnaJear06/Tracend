// On-demand data lookups (A10): the answer may carry `data_requests: [{lookup, from, to,
// filter?}]`; the server runs them read-only and calls the model again, at most two rounds. The
// bank grades the request a model makes and the dated rows its final answer cites. The lookup
// names below are the one place to change if the shipped names differ.
import type { DataRequest, LookupRow } from "./types.ts";

export const lookupNames = Object.freeze({
  exerciseHistory: "exercise_history",
  meals: "meals",
});

/** The `data_requests` of an answer, or none when the field is absent or malformed. */
export function dataRequestsOf(answer: unknown): DataRequest[] {
  const raw = (answer as { data_requests?: unknown } | null)?.data_requests;
  if (!Array.isArray(raw)) return [];
  return raw.flatMap((item) => {
    const request = item as Record<string, unknown> | null;
    if (
      !request || typeof request.lookup !== "string" || typeof request.from !== "string" ||
      typeof request.to !== "string"
    ) return [];
    return [{
      lookup: request.lookup,
      from: request.from,
      to: request.to,
      ...(request.filter === undefined ? {} : { filter: request.filter }),
    }];
  });
}

/** The rows of the requested lookups as the second round's reference data. */
export function renderLookupRows(
  requests: readonly DataRequest[],
  rows: Readonly<Record<string, readonly LookupRow[]>>,
): string | null {
  const blocks = requests.flatMap((request) => {
    const found = (rows[request.lookup] ?? []).filter((row) =>
      row.date >= request.from && row.date <= request.to
    );
    return found.length === 0 ? [] : [
      `Lookup ${request.lookup}, ${request.from} to ${request.to} (${found.length} rows):`,
      ...found.map((row) => `- ${row.date}: ${row.text}`),
    ];
  });
  return blocks.length === 0 ? null : blocks.join("\n");
}

/** Every row of every lookup the case supplies, as grounding text for the numbers check. */
export function allLookupRows(rows: Readonly<Record<string, readonly LookupRow[]>>): string {
  return Object.entries(rows).map(([name, list]) =>
    [`Lookup ${name}:`, ...list.map((row) => `- ${row.date}: ${row.text}`)].join("\n")
  ).join("\n");
}
