// Confirmed facts as the Coach contributors see them: parsed from the database's answer, rendered
// into the stable part of the Coach's file, and checked for facts that are due to be asked about
// again. The database owns every date; this module only reads them.
import { plain, record } from "../recorded_text.ts";
import { dateOf, flatten } from "./text.ts";
import {
  type FactKind,
  factKindLabels,
  type FactSource,
  factSourceLabels,
  isFactKind,
  isFactSource,
} from "./vocabulary.ts";

export type CoachFact = Readonly<{
  /** The id of this version; a suggestion that replaces the fact names it. */
  id: string;
  lineageId: string;
  version: number;
  kind: FactKind;
  subject: string;
  statement: string;
  source: FactSource;
  /** YYYY-MM-DD. */
  confirmedOn: string;
  /** YYYY-MM-DD when Coach should ask again; null for kinds that do not lapse. */
  reconfirmOn: string | null;
}>;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};

/** The facts in a `facts` array of a memory payload; a malformed row is left out. */
export function parseFacts(raw: unknown): CoachFact[] {
  if (!Array.isArray(raw)) return [];
  const facts: CoachFact[] = [];
  for (const item of raw) {
    const row = rec(item);
    const confirmedOn = dateOf(row.confirmed_at);
    if (
      typeof row.id !== "string" || typeof row.lineage_id !== "string" ||
      typeof row.version !== "number" || !isFactKind(row.kind) ||
      typeof row.subject !== "string" || typeof row.statement !== "string" ||
      !isFactSource(row.source) || confirmedOn === ""
    ) continue;
    facts.push({
      id: row.id,
      lineageId: row.lineage_id,
      version: row.version,
      kind: row.kind,
      subject: row.subject,
      statement: row.statement,
      source: row.source,
      confirmedOn,
      reconfirmOn: dateOf(row.reconfirm_at) || null,
    });
  }
  return facts;
}

// Re-confirming --------------------------------------------------------------------------------

/** Coach asks about at most this many old facts in one conversation. */
export const maxReconfirmPrompts = 2;

/** An injury is asked about before a schedule, and both before anything else. */
const askOrder: readonly FactKind[] = ["injury_limitation", "schedule_constraint"];

/**
 * The facts whose re-confirm date has come, the most overdue first (ties: injury, then schedule,
 * then the older confirmation), at most two. A fact the athlete just confirmed has a fresh date,
 * so it drops out; the scheduler holds no state of its own.
 */
export function factsDueForReconfirm(facts: readonly CoachFact[], today: string): CoachFact[] {
  return facts
    .filter((fact) => fact.reconfirmOn !== null && fact.reconfirmOn <= today)
    .toSorted((a, b) =>
      a.reconfirmOn!.localeCompare(b.reconfirmOn!) ||
      askOrder.indexOf(a.kind) - askOrder.indexOf(b.kind) ||
      a.confirmedOn.localeCompare(b.confirmedOn) || a.id.localeCompare(b.id)
    )
    .slice(0, maxReconfirmPrompts);
}

// Rendering -----------------------------------------------------------------------------------------

/** Safety first, then what shapes the plan, then taste: also the order lines are dropped last. */
const renderOrder: readonly FactKind[] = [
  "injury_limitation",
  "allergy",
  "schedule_constraint",
  "equipment",
  "coaching_style",
  "exercise_dislike",
  "food_dislike",
  "exercise_like",
  "food_like",
  "other_preference",
];

export const confirmedFactsHeading = "## Confirmed by the athlete";

const preface = "The athlete confirmed these facts about themselves; each line shows its date. " +
  "They rank above the Coach's notes, earlier chat messages and the library, and below Tracend's " +
  "own calculations. Respect them in every answer. When the athlete's message contradicts one, " +
  "say so and ask whether to update it; never act as if it had changed. Only the athlete can " +
  "change a fact; you cannot. The id in square brackets is for fact_suggestions only: never " +
  'print it. A line marked "re-check" is old: ask about it once, briefly, if it matters to the ' +
  "question.";

// The statement is the athlete's own and its dates are records; the id in brackets and the preface
// are not (`../recorded_text.ts`).
function factLine(fact: CoachFact, due: boolean): string {
  const marker = due ? `; re-check, due since ${record(fact.reconfirmOn ?? "")}` : "";
  return `- [${fact.id}] ${record(flatten(fact.statement, 200))} (confirmed ${
    record(fact.confirmedOn)
  }, ${factSourceLabels[fact.source]}${marker})`;
}

/** The facts section as the model reads it (`renderConfirmedFactsMarked` without its marks). */
export function renderConfirmedFacts(
  facts: readonly CoachFact[],
  today: string,
  budgetChars: number,
): string | null {
  const marked = renderConfirmedFactsMarked(facts, today, budgetChars);
  return marked === null ? null : plain(marked);
}

/**
 * The facts section of the Coach's file, or null when the athlete has confirmed none, with the
 * values in it marked (`../recorded_text.ts`). Kinds appear
 * in a fixed order and facts within a kind by confirmation date, so the text only changes when a
 * fact does. When it does not fit the budget the last kinds are dropped whole and the count of
 * facts left out is stated.
 */
export function renderConfirmedFactsMarked(
  facts: readonly CoachFact[],
  today: string,
  budgetChars: number,
): string | null {
  if (facts.length === 0) return null;
  // Only the facts the scheduler picks (at most two) are marked for a re-check.
  const dueIds = new Set(factsDueForReconfirm(facts, today).map((fact) => fact.id));
  const entries = renderOrder.flatMap((kind) =>
    facts.filter((fact) => fact.kind === kind).toSorted((a, b) =>
      a.confirmedOn.localeCompare(b.confirmedOn) || a.id.localeCompare(b.id)
    ).map((fact) => ({ kind, line: factLine(fact, dueIds.has(fact.id)) }))
  );
  const render = (count: number) => {
    const lines: string[] = [];
    let current: FactKind | null = null;
    for (const entry of entries.slice(0, count)) {
      if (entry.kind !== current) lines.push(`${factKindLabels[entry.kind]}:`);
      current = entry.kind;
      lines.push(entry.line);
    }
    const omitted = entries.length - count;
    return [
      confirmedFactsHeading,
      preface,
      ...lines,
      ...(omitted > 0 ? [`(${omitted} more confirmed facts are not shown here.)`] : []),
    ].join("\n");
  };
  for (let count = entries.length; count > 0; count--) {
    const text = render(count);
    if (plain(text).length <= budgetChars) return text;
  }
  return null;
}
