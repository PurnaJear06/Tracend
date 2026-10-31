// The personas' records and the views built from them: one set of figures everywhere, payloads the
// production parsers read, and turns that fit the prompt budget. No model.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { createLookupRunner } from "../../_shared/coach_lookups/runner.ts";
import {
  parsePlanState,
  renderTrainingPlan,
} from "../../_shared/coach_context/contributors/training_plan.ts";
import {
  parseNutritionState,
  renderNutritionState,
} from "../../_shared/coach_context/contributors/nutrition_state.ts";
import { renderCoverageBrief } from "../../_shared/coach_context/contributors/coverage_brief.ts";
import { exerciseCatalogV1 } from "../../_shared/onboarding/catalog.ts";
import { buildCoachChatGatewayPrompt } from "../../_shared/providers/coach_chat_provider_gateway.ts";
import { renderTurn } from "../coach_bank/harness.ts";
import { wordSearch } from "./library_search.ts";
import { personaIds, personas } from "./personas.ts";
import { addDays, recordsRpc, weekdayOf } from "./records.ts";
import { estimateRun } from "./run.ts";
import {
  athleteFor,
  conversations,
  openingFor,
  scenarios,
  selectConversations,
} from "./scenarios.ts";

const primary = personas.find((p) => p.id === "primary")!;

Deno.test("four personas with months of records: sessions, weigh-ins, complete and partial meal days, check-ins", () => {
  assertEquals(personas.map((p) => p.id), [...personaIds]);
  for (const persona of personas) {
    const { records } = persona;
    assert(records.sessions.length >= 30, persona.id);
    assert(records.weights.length >= 20, persona.id);
    assert(records.mealDays.some((d) => d.complete) && records.mealDays.some((d) => !d.complete));
    assert(records.checkIns.length >= 14, persona.id);
    assert(
      records.sessions.every((s) => s.local_date < records.spec.today),
      "nothing logged today",
    );
  }
  // The returning lifter has six months with no sessions at all.
  const returning = personas.find((p) => p.id === "returning")!.records.sessions;
  assertEquals(
    returning.filter((s) => s.local_date > "2026-03-15" && s.local_date < "2026-09-21"),
    [],
  );
});

Deno.test("the primary athlete's bench is stuck at 100 kg and last Tuesday was the bad session", () => {
  // Today is Friday 16 October, so last Tuesday is the 13th.
  const today = primary.records.spec.today;
  assertEquals(weekdayOf(today), 5);
  const lastTuesday = addDays(today, -3);
  assertEquals(weekdayOf(lastTuesday), 2);
  const bench = primary.records.sessions.flatMap((s) =>
    s.exercises.filter((e) => e.slug === "barbell-bench-press").map((e) => ({
      date: s.local_date,
      e,
    }))
  ).filter((row) => row.date >= "2026-08-20");
  assert(bench.length >= 6);
  assert(bench.every((row) => row.e.sets[0].load_kg === 100));
  const tuesday = primary.records.sessions.find((s) => s.local_date === lastTuesday)!;
  assertEquals(tuesday.effort, 9);
  assertEquals(
    primary.records.recovery.find((d) => d.local_date === lastTuesday)?.sleep_minutes,
    292,
  );
  assertEquals(primary.records.mealDays.find((d) => d.local_date === lastTuesday)?.complete, false);
});

Deno.test("the contributor payloads are ones the production parsers read", () => {
  for (const persona of personas) {
    const { contributors } = persona.athlete();
    assert(renderTrainingPlan(parsePlanState(contributors.trainingPlan)), persona.id);
    assert(renderNutritionState(parseNutritionState(contributors.nutritionState)), persona.id);
    const brief = renderCoverageBrief(contributors.dataIndex, persona.records.spec.today);
    assertStringIncludes(brief, "- training | ");
    assert(!brief.includes("counts unavailable"), persona.id);
    assert(!/- training \|[^\n]*none yet/.test(brief), persona.id);
    assert(!/- plan_ahead \|[^\n]*no active plan/.test(brief), persona.id);
  }
});

Deno.test("the lookup stand-in answers every lookup in its RPC shape, as the production runner renders it", async () => {
  const run = createLookupRunner(recordsRpc(primary.records, primary.extras), "u");
  const round = await run([
    { lookup: "workouts", from: "2026-10-13", to: "2026-10-13", filter: null },
    { lookup: "exercise_history", from: "2026-08-01", to: "2026-10-16", filter: "bench" },
    { lookup: "meals", from: "2026-10-12", to: "2026-10-13", filter: null },
    { lookup: "body", from: "2026-09-01", to: "2026-10-16", filter: null },
  ]);
  assertStringIncludes(
    round.text,
    "Barbell bench press (planned 4 x 4-6): 100 kg x 3 (0 reps in reserve)",
  );
  assertStringIncludes(
    round.text,
    "Next target (Tracend): Barbell bench press: 100 kg x 4 reps, 4 sets; hold",
  );
  assertStringIncludes(round.text, "(partial)");
  assert(!round.text.includes("could not be read"), round.text);
  const others = await run(
    ([
      "check_ins",
      "recovery",
      "plan_history",
      "goals",
      "weekly_reviews",
      "health_history",
      "past_messages",
    ] as const)
      .map((lookup) => ({ lookup, from: "2026-01-01", to: "2026-10-16", filter: null })),
  );
  assert(!others.text.includes("could not be read"), others.text);
  assertStringIncludes(others.text, "Slept about 5 hours");
  assertStringIncludes(others.text, "Nutrition target v2 (active)");
});

Deno.test("every scenario runs 6-10 messages and the conversations cover every persona", () => {
  assertEquals(scenarios.length, 12);
  for (const scenario of scenarios) {
    assert(scenario.turns >= 6 && scenario.turns <= 10, scenario.id);
    assert(scenario.beats.length >= scenario.turns - 2, scenario.id);
  }
  const all = conversations();
  assertEquals(new Set(all.map((c) => c.persona)), new Set(personaIds));
  assertEquals(new Set(all.map((c) => c.id)).size, all.length);
  assertEquals(selectConversations("knee-off").map((c) => c.id), [
    "primary/knee-off",
    "woman_40s/knee-off",
  ]);
  assertEquals(selectConversations("primary/last-tuesday").length, 1);
  assertEquals(selectConversations("").length, all.length);
});

Deno.test("each persona's first turn builds within the prompt budget with library excerpts shown", async () => {
  for (const persona of personas) {
    const athlete = persona.athlete();
    const question = "Is creatine worth taking while I cut?";
    const contributions = await renderTurn(athlete, question, [], {
      librarySearch: wordSearch(persona.region),
    });
    assert(Object.keys(contributions.shown).length > 0, persona.id);
    const prompt = buildCoachChatGatewayPrompt(
      question,
      athlete.context,
      "general",
      contributions,
      undefined,
      { sections: [], closed: false },
      true,
      true,
    );
    assert(prompt.messages[0].content.length >= 2);
  }
});

Deno.test("the cost estimate grows with turns and counts the judges", () => {
  const base = {
    conversations: selectConversations("primary/bench-plateau"),
    coachModel: "claude-haiku-5-5",
    athleteModel: "deepseek-v4-flash",
    promptTokens: () => 12_000,
  };
  const short = estimateRun({ ...base, maxTurns: 3, judgeModel: null });
  const long = estimateRun({ ...base, maxTurns: 6, judgeModel: null });
  const judged = estimateRun({ ...base, maxTurns: 6, judgeModel: "claude-sonnet-5-5" });
  assertEquals(short.turns, 3);
  assertEquals(long.turns, 6);
  assert(long.usd > short.usd && judged.usd > long.usd);
  // Six Haiku turns: 6 x (20,200 in x 0.10 + 900 out x 0.50) per million, plus five athlete calls.
  assertEquals(long.usd, Math.round((6 * 0.002470 + 5 * 0.00063) * 10_000) / 10_000);
});

Deno.test("every exercise in a persona's plan and logs is one the product's catalog has, by name and slug", () => {
  const catalog = new Map(exerciseCatalogV1.map((exercise) => [exercise.slug, exercise.name]));
  for (const persona of personas) {
    const seen = new Map<string, string>();
    const walk = (value: unknown): void => {
      if (!value || typeof value !== "object") return;
      const item = value as { name?: unknown; slug?: unknown };
      if (typeof item.name === "string" && typeof item.slug === "string") {
        seen.set(item.slug, item.name);
      }
      Object.values(value).forEach(walk);
    };
    walk(persona.records);
    walk(persona.extras);
    assert(seen.size >= 10, persona.id);
    for (const [slug, name] of seen) {
      assertEquals(catalog.get(slug), name, `${persona.id}: ${slug} is not a catalog exercise`);
    }
  }
});

// Review of #154: the windows are prepare_coach_chat_v8's, `coaching_date - (days - 1)` through the
// coaching date (build_coach_athlete_context, migration 20260927230000).
Deno.test("the athlete file's windows end on the coaching date and start days - 1 before it", () => {
  for (const persona of personas) {
    const file = persona.athlete().context;
    const today = String(file.coaching_date);
    const { records } = persona;
    const since = (days: number) => addDays(today, -(days - 1));
    const sessionsIn = (days: number) =>
      records.sessions.filter((s) => s.local_date >= since(days) && s.local_date <= today).length;
    const log = file.training_log_28d as { local_date: string }[];
    assertEquals(log.length, sessionsIn(28), persona.id);
    assert(log.every((s) => s.local_date >= since(28) && s.local_date <= today), persona.id);
    const totals = file.training_totals as Record<string, { sessions: number }>;
    assertEquals(totals.last_7_days.sessions, sessionsIn(7), persona.id);
    assertEquals(totals.last_14_days.sessions, sessionsIn(14), persona.id);
    const checkIns = file.check_ins_14d as { local_date: string }[];
    assertEquals(
      checkIns.length,
      records.checkIns.filter((c) => c.local_date >= since(14) && c.local_date <= today).length,
      persona.id,
    );
    const meals = file.nutrition_adherence as { days_with_confirmed_meals_7d: number };
    assertEquals(
      meals.days_with_confirmed_meals_7d,
      records.mealDays.filter((d) => d.local_date >= since(7) && d.local_date <= today).length,
      persona.id,
    );
  }
});

Deno.test("the standing-state scenarios give Coach the break or the can't-train day in the standing state", async () => {
  const persona = personas.find((item) => item.id === "primary")!;
  const cases: [string, string][] = [
    ["checkin-unavailable-hi", "said on today's check-in that they cannot train today"],
    ["break-across-chats", "the athlete is on a break from"],
    ["first-day-back", "Back from a break that ended"],
    ["end-break-early", "Back from a break that ended"],
  ];
  for (const [id, words] of cases) {
    const scenario = scenarios.find((item) => item.id === id)!;
    const athlete = athleteFor(scenario, persona.athlete());
    const contributions = await renderTurn(athlete, openingFor(scenario, "primary"));
    assertStringIncludes(contributions.texts.standing_state ?? "", words, id);
  }
  const unavailable = athleteFor(
    scenarios.find((item) => item.id === "checkin-unavailable-hi")!,
    persona.athlete(),
  );
  const today = String(unavailable.context.coaching_date);
  const row = (unavailable.context.check_ins_14d as Record<string, unknown>[])
    .find((item) => item.local_date === today);
  if (row) assertEquals(row.available_to_train, false);
});
