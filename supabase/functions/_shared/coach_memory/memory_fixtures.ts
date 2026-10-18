// Test fixtures for Coach memory: saved facts and the database's answers in their wire shape.
import type { CoachFact } from "./facts.ts";
import type { FactKind } from "./vocabulary.ts";

let counter = 0;

/** A saved fact, confirmed on 2026-09-01 unless the overrides say otherwise. */
export function makeFact(
  kind: FactKind,
  subject: string,
  statement: string,
  overrides: Partial<CoachFact> = {},
): CoachFact {
  counter++;
  const id = `00000000-0000-4000-8000-${String(counter).padStart(12, "0")}`;
  return {
    id,
    lineageId: id,
    version: 1,
    kind,
    subject,
    statement,
    source: "athlete_typed",
    confirmedOn: "2026-09-01",
    reconfirmOn: null,
    ...overrides,
  };
}

/** A fact as get_coach_memory_context_v1 and get_my_coach_memory_v1 send it. */
export function factWire(fact: CoachFact): Record<string, unknown> {
  return {
    id: fact.id,
    lineage_id: fact.lineageId,
    version: fact.version,
    kind: fact.kind,
    subject: fact.subject,
    statement: fact.statement,
    source: fact.source,
    confirmed_at: `${fact.confirmedOn}T09:00:00+00:00`,
    reconfirm_at: fact.reconfirmOn ? `${fact.reconfirmOn}T09:00:00+00:00` : null,
    reconfirm_due: false,
  };
}
