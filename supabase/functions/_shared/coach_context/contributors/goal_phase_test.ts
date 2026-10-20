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
import {
  parseGoalPhaseInputs,
  reviewGoalPhase,
  summarizeGoalPhase,
} from "../../training/goal_phase/index.ts";

const input = { userId: "user-1", question: "Should I keep cutting?", localDate: "2026-10-14" };

Deno.test("the contributor is volatile and fits its budget on the owner's case", async () => {
  const contributor = createGoalPhaseContributor(() => Promise.resolve(longCutPayload));
  assertEquals(contributor.slot, "volatile");
  assertEquals(contributor.budgetChars, goalPhaseContributorBudgetChars);
  const text = (await contributor.render(input)) as string;
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
    "confirmed_facts",
    "goal_phase",
    "training_plan",
    "nutrition_state",
    "coach_proposals",
    "heart_rate_profile",
    "coach_notes",
    "watch_outs",
    "coverage_brief",
    "library",
  ]);
});

Deno.test("eight excluded readings, a long history and a long run still fit with the outcome and every reason", async () => {
  const first = Date.parse("2025-12-01T00:00:00Z");
  const spikes = new Set([5, 9, 13, 17, 21, 25, 29, 33]);
  const readings = Array.from({ length: 45 }, (_, index) => ({
    date: new Date(first + index * 7 * 86_400_000).toISOString().slice(0, 10),
    kg: spikes.has(index) ? 60 : Math.round((100 - index * 0.5) * 10) / 10,
  }));
  const payload = {
    ...longCutPayload,
    goal: {
      ...longCutPayload.goal,
      activated_on: "2026-03-02",
      target: {
        ...longCutPayload.goal.target,
        physique: "athletic",
        physique_note: "lean and strong enough to run a half marathon and still lift three days " +
          "a week without losing the muscle I built over the last four years",
        date: "2026-12-31",
      },
    },
    readings,
  };
  const contributor = createGoalPhaseContributor(() => Promise.resolve(payload));
  const text = (await contributor.render({ ...input, localDate: "2026-10-05" })) as string;
  assert(text.length <= goalPhaseContributorBudgetChars, `${text.length} chars`);
  const rendered = await renderCoachContext([contributor], { ...input, localDate: "2026-10-05" });
  assertEquals(rendered.outcomes[0].clipped, false);
  const summary = summarizeGoalPhase(parseGoalPhaseInputs(payload, "2026-10-05"));
  assertEquals(summary.excluded.length, 8);
  assertEquals(summary.continuousLoss?.beganBeforeGoalPhase, true);
  const review = reviewGoalPhase(summary);
  assertEquals(review.reasons.length >= 2, true);
  assertStringIncludes(text, `Review outcome: ${review.outcome}`);
  for (const reason of review.reasons) assertStringIncludes(text, reason.detail);
  assert(text.indexOf("Review outcome") < text.indexOf("Recorded history"));
  assertEquals(text.split("\n").filter((line) => line.startsWith("- Excluded reading")).length, 3);
  assertStringIncludes(text, "and 5 more excluded readings");
});
