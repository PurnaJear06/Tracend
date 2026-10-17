import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  createGoalPhaseContributor,
  goalPhaseContributorBudgetChars,
  goalPhaseSourceFromRpc,
  renderGoalPhasePayload,
} from "./goal_phase.ts";
import { renderCoachContext, validateCoachContextContributors } from "../host.ts";
import { coachContextContributors } from "../registry.ts";
import { longCutPayload } from "../../training/goal_phase/fixtures.ts";

const input = { userId: "user-1", question: "Should I keep cutting?", localDate: "2026-10-14" };

Deno.test("the contributor is volatile and fits its budget on the owner's case", async () => {
  const contributor = createGoalPhaseContributor(() => Promise.resolve(longCutPayload));
  assertEquals(contributor.slot, "volatile");
  assertEquals(contributor.budgetChars, goalPhaseContributorBudgetChars);
  const text = (await contributor.render(input))!;
  assert(text.length <= goalPhaseContributorBudgetChars, `${text.length} chars`);
  const rendered = await renderCoachContext([contributor], input);
  assertEquals(rendered.stable, "");
  assertStringIncludes(rendered.volatile, '<reference_data source="goal_phase">');
  assertStringIncludes(rendered.volatile, "-15.2 kg (-16.9%)");
  assertStringIncludes(rendered.volatile, "60 kg on 2026-07-02");
  assertStringIncludes(rendered.volatile, "consider_maintenance_or_diet_break");
  assertEquals(rendered.outcomes[0].outcome, "rendered");
  assertEquals(rendered.outcomes[0].clipped, false);
});

Deno.test("no active goal renders nothing; a failing source leaves the contributor out", async () => {
  assertEquals(
    renderGoalPhasePayload({ schema_version: "1.0", goal: null, readings: [] }, "2026-10-14"),
    null,
  );
  const failing = createGoalPhaseContributor(() => Promise.reject(new Error("down")));
  const result = await renderCoachContext([failing], input);
  assertEquals(result.outcomes[0].outcome, "failed");
  assertEquals(result.volatile, "");
});

Deno.test("the RPC source asks for the user and raises on an error", async () => {
  const calls: unknown[] = [];
  const source = goalPhaseSourceFromRpc((name, params) => {
    calls.push([name, params]);
    return Promise.resolve({ data: longCutPayload, error: null });
  });
  assertEquals(await source("user-1"), longCutPayload);
  assertEquals(calls, [["get_goal_phase_inputs_v1", { p_user_id: "user-1" }]]);
  const broken = goalPhaseSourceFromRpc(() =>
    Promise.resolve({ data: null, error: { code: "x" } })
  );
  await assertRejects(() => broken("user-1"));
});

Deno.test("the registry holds the goal phase contributor after the screening and is valid", () => {
  validateCoachContextContributors(coachContextContributors);
  assertEquals(coachContextContributors.map((c) => c.id), [
    "coaching_principles",
    "screening",
    "goal_phase",
  ]);
});
