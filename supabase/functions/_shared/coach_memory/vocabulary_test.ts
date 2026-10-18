import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  coachNoteLifetimeDays,
  factKinds,
  factSources,
  isFactKind,
  isFactSource,
  maxActiveFacts,
  maxCoachNotes,
  maxFactStatementChars,
  maxFactSubjectChars,
  noteConcerns,
  noteTopics,
  volatileFactKinds,
} from "./vocabulary.ts";

const migration = Deno.readTextFileSync(
  new URL("../../../migrations/20261018150020_coach_memory.sql", import.meta.url),
);

const listAfter = (marker: string): string[] => {
  const start = migration.indexOf(marker);
  if (start < 0) throw new Error(`marker not found: ${marker}`);
  const end = migration.indexOf(")", start);
  return [...migration.slice(start, end).matchAll(/'([a-z_]+)'/g)].map((m) => m[1]);
};

Deno.test("the database accepts exactly the fact kinds and sources the code names", () => {
  assertEquals(
    listAfter("kind text not null check (kind in ("),
    [...factKinds],
  );
  assertEquals(
    listAfter("source text not null check (source in ("),
    [...factSources],
  );
  // The save function checks the same kinds before the table does.
  const inFunction = listAfter("if p_kind is null or p_kind not in (");
  assertEquals(inFunction, [...factKinds]);
});

Deno.test("the database lapses exactly the volatile kinds", () => {
  const fn = migration.slice(
    migration.indexOf("create function private.coach_fact_reconfirm_at"),
    migration.indexOf("create table public.coach_facts"),
  );
  const lapsing = [...fn.matchAll(/when '([a-z_]+)' then from_ts \+ interval '(\d+) days'/g)];
  assertEquals(lapsing.map((m) => m[1]), [...volatileFactKinds]);
  assertEquals(lapsing.map((m) => m[2]), ["28", "90"]);
});

Deno.test("the limits in the code are the limits in the database", () => {
  assertEquals(migration.includes(`>= ${maxActiveFacts} then`), true);
  assertEquals(migration.includes(`ranked.place > ${maxCoachNotes}`), true);
  assertEquals(migration.includes(`interval '${coachNoteLifetimeDays} days')`), true);
  assertEquals(
    migration.includes(`char_length(subject) between 1 and ${maxFactSubjectChars}`),
    true,
  );
  assertEquals(
    migration.includes(`char_length(statement) between 1 and ${maxFactStatementChars}`),
    true,
  );
  assertEquals(
    migration.includes(
      `'max_facts', ${maxActiveFacts}, 'max_notes', ${maxCoachNotes}, 'note_days', ${coachNoteLifetimeDays}`,
    ),
    true,
  );
});

Deno.test("note topics and concerns are lower-case snake words the database pattern accepts", () => {
  for (const word of [...noteTopics, ...noteConcerns]) assertEquals(/^[a-z_]+$/.test(word), true);
});

Deno.test("the kind and source guards", () => {
  assertEquals(factKinds.every(isFactKind), true);
  assertEquals(factSources.every(isFactSource), true);
  assertEquals(isFactKind("goal"), false);
  assertEquals(isFactKind(4), false);
  assertEquals(isFactSource("model"), false);
});
