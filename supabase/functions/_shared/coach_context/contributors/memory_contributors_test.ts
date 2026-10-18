import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { factWire, makeFact } from "../../coach_memory/memory_fixtures.ts";
import type { ServiceRpc } from "../service_source.ts";
import { coachNotesContributorBudgetChars, createCoachNotesContributor } from "./coach_notes.ts";
import {
  confirmedFactsContributorBudgetChars,
  createConfirmedFactsContributor,
} from "./confirmed_facts.ts";
import { createMemorySource, memoryReadShareMs } from "./memory_source.ts";

const payload = (facts: unknown[], notes: unknown[]) => ({
  schema_version: "1.0",
  local_date: "2026-10-18",
  facts,
  notes,
});

function counting(data: unknown): { rpc: ServiceRpc; calls: () => number } {
  let calls = 0;
  return {
    rpc: () => {
      calls++;
      return Promise.resolve({ data, error: null });
    },
    calls: () => calls,
  };
}

const input = { userId: "u1", question: "What should I do today?", localDate: "2026-10-18" };

Deno.test("the facts contributor is stable and renders the confirmed facts with their dates", async () => {
  const fact = makeFact("injury_limitation", "knee", "Left knee hurts on deep squats", {
    reconfirmOn: "2026-10-01",
  });
  const { rpc } = counting(payload([factWire(fact)], []));
  const contributor = createConfirmedFactsContributor(createMemorySource(rpc));
  assertEquals(contributor.slot, "stable");
  assertEquals(contributor.budgetChars, confirmedFactsContributorBudgetChars);
  const text = (await contributor.render(input)) as string;
  assertStringIncludes(text, "Left knee hurts on deep squats (confirmed 2026-09-01");
  assertStringIncludes(text, "re-check, due since 2026-10-01");
  assertEquals(text.length <= contributor.budgetChars, true);
});

Deno.test("the notes contributor is volatile and labels the notes as the Coach's own", async () => {
  const { rpc } = counting(payload([], [{
    id: "n1",
    entry_kind: "conversation",
    note_date: "2026-10-12",
    summary: "Asked about training.",
  }]));
  const contributor = createCoachNotesContributor(createMemorySource(rpc));
  assertEquals(contributor.slot, "volatile");
  assertEquals(contributor.budgetChars, coachNotesContributorBudgetChars);
  const text = (await contributor.render(input)) as string;
  assertStringIncludes(text, "- 2026-10-12: Asked about training.");
  assertStringIncludes(text, "not confirmed by the athlete");
});

Deno.test("an athlete with no memory renders nothing, and so does a memory that cannot be read", async () => {
  const empty = counting(payload([], []));
  assertEquals(
    await createConfirmedFactsContributor(createMemorySource(empty.rpc)).render(input),
    null,
  );
  assertEquals(
    await createCoachNotesContributor(createMemorySource(empty.rpc)).render(input),
    null,
  );
  const broken: ServiceRpc = () => Promise.resolve({ data: null, error: { message: "down" } });
  assertEquals(
    await createConfirmedFactsContributor(createMemorySource(broken)).render(input),
    null,
  );
});

Deno.test("both contributors and the reply share one read of the memory", async () => {
  const { rpc, calls } = counting(payload([], []));
  const source = createMemorySource(rpc);
  await Promise.all([
    createConfirmedFactsContributor(source).render(input),
    createCoachNotesContributor(source).render(input),
    source(input),
  ]);
  assertEquals(calls(), 1);
});

Deno.test("a read is shared only for the same athlete, day and question, and only briefly", async () => {
  const { rpc, calls } = counting(payload([], []));
  let time = 1_000;
  const source = createMemorySource(rpc, () => time);
  await source(input);
  await source({ ...input, question: "Another question" });
  await source({ ...input, userId: "u2" });
  await source({ ...input, localDate: "2026-10-19" });
  assertEquals(calls(), 4);
  time += memoryReadShareMs + 1;
  await source(input);
  assertEquals(calls(), 5);
});

Deno.test("a failed read is not shared", async () => {
  let calls = 0;
  const rpc: ServiceRpc = () => {
    calls++;
    return Promise.resolve(
      calls === 1
        ? { data: null, error: { message: "down" } }
        : { data: payload([], []), error: null },
    );
  };
  const source = createMemorySource(rpc);
  assertEquals(await source(input), null);
  assertEquals((await source(input))?.localDate, "2026-10-18");
  assertEquals(calls, 2);
});
