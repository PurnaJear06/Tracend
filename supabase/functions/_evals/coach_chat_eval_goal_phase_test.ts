// Deterministic Coach eval for the goal-phase failure: a long cut seen through a six-week window,
// a stale goal detail, one impossible reading, a healthy BMI with no target. No model is called;
// the checks run on the rendered prompt, the calculators and the reply check.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { calculateCoachNumbers, formatCoachCalculations } from "../_shared/coach_calculations.ts";
import { renderCoachContext } from "../_shared/coach_context/host.ts";
import {
  createGoalPhaseContributor,
  renderGoalPhasePayload,
} from "../_shared/coach_context/contributors/goal_phase.ts";
import { buildCoachChatGatewayPrompt } from "../_shared/providers/coach_chat_provider_gateway.ts";
import {
  coachChatInstructions,
  formatContextAsMarkdown,
} from "../_shared/providers/coach_chat_provider.ts";
import { weightClaimCheckFor } from "../_shared/training/goal_phase/guard.ts";
import {
  lateGoalPayload,
  longCutContext,
  longCutPayload,
} from "../_shared/training/goal_phase/fixtures.ts";

const question = "I feel weird. Should I keep cutting?";

async function promptText(context: Record<string, unknown>, payload: unknown): Promise<string> {
  const contributions = await renderCoachContext(
    [createGoalPhaseContributor(() => Promise.resolve(payload))],
    { userId: "eval-user", question, localDate: "2026-10-14" },
  );
  const prompt = buildCoachChatGatewayPrompt(question, context, "general", contributions);
  return [
    ...prompt.system.flatMap((part) => part.type === "text" ? [part.text] : []),
    ...prompt.messages.flatMap((message) =>
      typeof message.content === "string"
        ? [message.content]
        : message.content.flatMap((part) => part.type === "text" ? [part.text] : [])
    ),
  ].join("\n");
}

Deno.test("15 kg over 19 weeks through a 6-week window: the prompt carries the whole-phase totals", async () => {
  const text = await promptText(longCutContext, longCutPayload);
  assertStringIncludes(text, "Start 90 kg (2026-06-03");
  assertStringIncludes(text, "-15.2 kg (-16.9%) over 18.9 weeks");
  assertStringIncludes(text, "Review outcome: consider_maintenance_or_diet_break (no target set)");
  assertStringIncludes(text, "Target: none set");
});

Deno.test("a goal activated a month into the cut: the prompt carries the whole recorded journey", async () => {
  const text = await promptText(longCutContext, lateGoalPayload);
  assertStringIncludes(text, "Recorded history, all weight readings: 90 kg on 2026-06-03");
  assertStringIncludes(text, "-15.2 kg (-16.9%) over 18.9 weeks");
  assertStringIncludes(text, "Goal phase (fat loss, since 2026-07-03)");
  assertStringIncludes(text, "18.9 weeks of falling weight since 2026-06-03");
});

Deno.test("a stale goal detail never reaches Coach as a figure", () => {
  const markdown = formatContextAsMarkdown(longCutContext, 28_000);
  assert(!markdown.includes("86.2"), "the July weight is dropped from the goal details");
  assertStringIncludes(markdown, "Aggressive fat loss with muscle retention");
  assertStringIncludes(markdown, "not updated since");
});

Deno.test("the six-week window gives no future weight and no projection without a target", () => {
  const weight = calculateCoachNumbers(longCutContext)!.weight!;
  assertEquals(weight.latest_kg, 74.8);
  assertEquals(weight.projection?.horizons ?? [], []);
  assertEquals(weight.projection?.targets ?? [], []);
  const text = formatCoachCalculations(calculateCoachNumbers(longCutContext));
  assert(!/reach \d+(\.\d+)? kg/.test(text), "no 'reach N kg' rows");
  assertStringIncludes(text, "No target weight is ahead");
  assert(!/in \d+ weeks: about/.test(text), "no 'in N weeks' weight");
});

Deno.test("one impossible 60 kg reading inside the window moves no trend", () => {
  const clean = calculateCoachNumbers(longCutContext)!.weight!;
  const series = [...(longCutContext.weight_series_8w as Record<string, unknown>[])];
  series.splice(4, 0, {
    measured_on: "2026-09-20",
    weight_kg: 60,
    waist_cm: null,
    source: "manual",
  });
  const dirty = calculateCoachNumbers({ ...longCutContext, weight_series_8w: series })!.weight!;
  assertEquals(dirty.excluded_readings, [{
    date: "2026-09-20",
    kg: 60,
    reason: "implausible_jump",
  }]);
  assertEquals(dirty.trends, clean.trends);
  assertEquals(dirty.latest_kg, clean.latest_kg);
  assertStringIncludes(
    formatCoachCalculations(calculateCoachNumbers({ ...longCutContext, weight_series_8w: series })),
    "Excluded reading",
  );
});

Deno.test("a projection never goes below the healthy BMI floor", () => {
  // 160 cm: the BMI 18.5 floor is 47.4 kg. 50 kg and falling 0.6 kg a week, target 45 kg.
  const series = [0, 1, 2, 3, 4, 5].map((week) => ({
    measured_on: new Date(Date.parse("2026-09-09T00:00:00Z") + week * 7 * 86_400_000)
      .toISOString().slice(0, 10),
    weight_kg: Number((53 - 0.6 * week).toFixed(1)),
    waist_cm: null,
    source: "manual",
  })).reverse();
  const context = {
    coaching_date: "2026-10-14",
    profile_context: { height_cm: 160 },
    active_goal: { goal_type: "fat_loss", details: { target_weight_kg: 45 } },
    weight_series_8w: series,
  };
  const projection = calculateCoachNumbers(context)!.weight!.projection!;
  for (const row of projection.targets) assert(row.target_kg >= 47.4, `${row.target_kg}`);
  for (const row of projection.horizons) assert(row.kg_low >= 47.4, `${row.kg_low}`);
});

Deno.test("healthy BMI, fat loss and no target: Coach is told to ask for one", () => {
  const payload = {
    ...longCutPayload,
    readings: [
      { date: "2026-09-01", kg: 82 },
      { date: "2026-09-08", kg: 81.8 },
      { date: "2026-09-15", kg: 81.6 },
      { date: "2026-09-22", kg: 81.5 },
      { date: "2026-09-29", kg: 81.3 },
    ],
    goal: { ...longCutPayload.goal, activated_on: "2026-09-01" },
  };
  const text = renderGoalPhasePayload(payload, "2026-10-14")!;
  assertStringIncludes(text, "Review outcome: ask_target (no target set)");
  const rules = coachChatInstructions([]);
  assertStringIncludes(rules, "ask for one: a target weight, a body-fat range, a physique goal");
});

Deno.test("the rules cap reply length, forbid claimed actions and unsupported history", () => {
  const rules = coachChatInstructions([]);
  assertStringIncludes(rules, "about 120 words, at most 3 bullets and 1 question");
  assertStringIncludes(rules, "You have no tools");
  assertStringIncludes(rules, 'Never say "since you started"');
  assert(!rules.includes("working with this athlete through their journey"));
});

Deno.test("the reply check refuses the original failure and passes the corrected reply", () => {
  const check = weightClaimCheckFor(longCutContext, question);
  assertEquals(
    check("You have lost about 7 kg. If you keep going you would be at about 66.5 kg in 12 weeks."),
    "projection_without_target",
  );
  assertEquals(
    check(
      "You are down 15.2 kg since 3 June, from 90 kg to 74.8 kg. Your BMI is 23, a healthy weight. A short maintenance period is worth considering. What weight or look do you want to aim for?",
    ),
    null,
  );
});
