import { assertAlmostEquals, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { type ArmAnswer, renderHeadToHead, summariseArm } from "./library_head_to_head_metrics.ts";

const answer = (overrides: Partial<ArmAnswer> = {}): ArmAnswer => ({
  answered: true,
  cited: ["a_2020_one"],
  expected: ["a_2020_one", "b_2021_two"],
  cacheReadTokens: 1000,
  cacheWriteTokens: 0,
  inputTokens: 200,
  outputTokens: 150,
  costUsd: 0.001,
  latencyMs: 2000,
  repaired: false,
  ...overrides,
});

Deno.test("an arm's summary scores citations against the expected sources", () => {
  const summary = summariseArm([
    answer(),
    answer({ cited: ["a_2020_one", "b_2021_two", "z_2019_other"], repaired: true }),
    answer({ cited: [] }),
    answer({ answered: false, cited: [] }),
  ]);
  assertEquals(summary.questions, 4);
  assertEquals(summary.answeredRate, 0.75);
  assertAlmostEquals(summary.citesExpected, 2 / 3);
  assertAlmostEquals(summary.meanExpectedCited, (0.5 + 1 + 0) / 3);
  assertAlmostEquals(summary.citationPrecision, 3 / 4);
  assertEquals(summary.repairRate, 0.25);
  assertEquals(summary.meanCostUsd, 0.001);
});

Deno.test("an empty arm scores zero without dividing by zero", () => {
  const summary = summariseArm([]);
  assertEquals(summary.answeredRate, 0);
  assertEquals(summary.citationPrecision, 0);
  assertEquals(summary.meanLatencyMs, 0);
});

Deno.test("the table has a column per arm", () => {
  const table = renderHeadToHead({
    retrieval: summariseArm([answer()]),
    full_library: summariseArm([answer({ costUsd: 0.002 })]),
  });
  assertStringIncludes(table, "| measure | retrieval | full_library |");
  assertStringIncludes(table, "| cost per turn (USD) | 0.00100 | 0.00200 |");
});
