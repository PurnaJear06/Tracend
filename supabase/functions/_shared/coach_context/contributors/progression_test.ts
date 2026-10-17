import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { renderCoachContext, validateCoachContextContributors } from "../host.ts";
import {
  createProgressionContributor,
  progressionContributorBudgetChars,
  progressionSourceFromRpc,
  renderProgressionTargets,
} from "./progression.ts";
import { parseProgressionSummary } from "../../training/progression/targets.ts";

const input = { userId: "user-1", question: "Should I add weight?", localDate: "2026-10-17" };

function row(name: string, overrides: Record<string, unknown> = {}) {
  return {
    planned_exercise_id: crypto.randomUUID(),
    exercise_key: name.toLowerCase().replaceAll(" ", "-"),
    name,
    action: "add_reps",
    reason: "within_range",
    load_kg: 15,
    reps: 11,
    sets: 2,
    confidence: "high",
    basis: {
      last_date: "2026-10-10",
      recent: [{ local_date: "2026-10-10", load_kg: 15, sets: 2, min_reps: 10, min_rir: 2 }],
    },
    ...overrides,
  };
}

const summary = (targets: unknown[]) => ({ schema_version: "1.0", targets });

Deno.test("the contributor is valid, volatile and inside the host's budget", () => {
  const contributor = createProgressionContributor(() => Promise.resolve(summary([])));
  validateCoachContextContributors([contributor]);
  assertEquals(contributor.id, "progression");
  assertEquals(contributor.slot, "volatile");
  assertEquals(contributor.budgetChars, progressionContributorBudgetChars);
});

Deno.test("targets render as labelled reference lines for Coach", async () => {
  const contributor = createProgressionContributor(() =>
    Promise.resolve(summary([
      row("Cable fly"),
      row("Barbell bench press", {
        action: "add_load",
        reason: "top_of_range",
        load_kg: 62.5,
        reps: 5,
        sets: 3,
      }),
    ]))
  );
  const result = await renderCoachContext([contributor], input);
  assertEquals(result.stable, "");
  assertStringIncludes(result.volatile, '<reference_data source="progression">');
  assertStringIncludes(result.volatile, "Explain them; do not change them");
  assertStringIncludes(result.volatile, "- Cable fly: 15 kg x 11 reps, 2 sets; add reps");
  assertStringIncludes(
    result.volatile,
    "- Barbell bench press: 62.5 kg x 5 reps, 3 sets; add load",
  );
  assertEquals(result.outcomes.map((o) => [o.id, o.outcome]), [["progression", "rendered"]]);
});

Deno.test("the text states that heart rate sets no target", () => {
  const text = renderProgressionTargets(parseProgressionSummary(summary([row("Cable fly")])));
  assertStringIncludes(text!, "never heart rate");
});

Deno.test("an athlete without targets adds nothing to the prompt", async () => {
  const result = await renderCoachContext(
    [createProgressionContributor(() => Promise.resolve(summary([])))],
    input,
  );
  assertEquals(result.volatile, "");
  assertEquals(result.outcomes[0].outcome, "empty");
});

Deno.test("a malformed summary adds nothing rather than a guess", async () => {
  const result = await renderCoachContext(
    [createProgressionContributor(() => Promise.resolve({ schema_version: "9.9", targets: [] }))],
    input,
  );
  assertEquals(result.outcomes[0].outcome, "empty");
});

Deno.test("a failing source leaves the turn without progression, never failing it", async () => {
  const result = await renderCoachContext(
    [createProgressionContributor(() => Promise.reject(new Error("db down")))],
    input,
  );
  assertEquals(result.volatile, "");
  assertEquals(result.outcomes[0].outcome, "failed");
});

Deno.test("many targets are capped and the rest counted", () => {
  const rows = Array.from({ length: 15 }, (_, i) => row(`Exercise ${i}`));
  const text = renderProgressionTargets(parseProgressionSummary(summary(rows)))!;
  assertEquals(text.split("\n- ").length - 1, 13);
  assertStringIncludes(text, "- 3 more exercises have targets.");
});

Deno.test("a typical day's targets fit the contributor's budget", () => {
  const rows = Array.from({ length: 12 }, (_, i) => row(`Barbell bench press ${i}`));
  const text = renderProgressionTargets(parseProgressionSummary(summary(rows)))!;
  assert(text.length <= progressionContributorBudgetChars, `${text.length} chars`);
});

Deno.test("the RPC source asks for the athlete's summary and rejects an error", async () => {
  const calls: unknown[] = [];
  const source = progressionSourceFromRpc((name, params) => {
    calls.push([name, params]);
    return Promise.resolve({ data: summary([]), error: null });
  });
  assertEquals(await source("user-9"), summary([]));
  assertEquals(calls, [["get_progression_summary_v1", { p_user_id: "user-9" }]]);
  const failing = progressionSourceFromRpc(() =>
    Promise.resolve({ data: null, error: { message: "x" } })
  );
  await assertRejects(() => failing("user-9"));
});
