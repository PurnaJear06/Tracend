// The athlete file as it grounds a reply's numbers (`context_grounding.ts`), and the three surfaces
// that show Coach stored values (the file, the lookups and the contributors) against one another
// (`../grounding.ts`): every field the renderer reads and shows is declared, the declaration is
// what decides, a column is the same kind on every path, and a figure only a model wrote or only a
// proposal holds never grounds a sentence about the athlete's own target.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { evalProfiles } from "../../_evals/fixtures.ts";
import { columnGrounding, leafPaths, resolve } from "../grounding.ts";
import { changeAt, variantsOf } from "../grounding_probe.ts";
import { noCoachContributions, renderCoachContext } from "../coach_context/host.ts";
import {
  createProposalsContributor,
  parseProposalsState,
} from "../coach_context/contributors/proposals.ts";
import { ownersPlanPayload } from "../coach_context/contributors/plan_fixtures.ts";
import { parsePlanState, renderTrainingPlan } from "../coach_context/contributors/training_plan.ts";
import { planVersionsPayload, request } from "../coach_lookups/lookup_fixtures.ts";
import { renderLookup } from "../coach_lookups/render.ts";
import {
  contextForGrounds,
  contextGrounding,
  type ContextKeyGrounding,
} from "./context_grounding.ts";
import {
  coachReplyCheckFor,
  renderCoachContextParts,
  replyCheckInputsFor,
} from "./coach_chat_provider.ts";

type Ctx = Record<string, unknown>;

const withModelText = (base: Ctx): Ctx => ({
  ...base,
  latest_decision: {
    final_decision: "Train today, but cap effort at RPE 7.",
    reason: "Recovery is below baseline after a short night.",
    confidence: "medium",
  },
  context_coverage: { training: true, nutrition: false },
  omitted_sections: ["session_journal"],
  plan_proposals: [
    {
      status: "pending",
      headline: "Add a sixth session",
      proposed_training: {
        title: "Push pull legs",
        block_weeks: 6,
        sessions_per_week: 6,
        weekly_structure: [{ name: "Push" }, "Pull"],
      },
      proposed_nutrition: { calories: 2300, protein_g: 170 },
      confidence: "medium",
      effective_date: "2026-10-26",
    },
    { status: "declined", headline: "Cut to three sessions", confidence: "low" },
  ],
});

/** An older context, from before the v8 one, and the ways it names the same sections. */
const olderContext = (): Ctx => ({
  d: "2026-10-17",
  permitted_evidence: [],
  session_trends: [{
    local_date: "2026-10-15",
    workout: "Push",
    duration_seconds: 3600,
    effort: 7,
  }],
  latest_healthkit: {
    local_date: "2026-10-17",
    resting_heart_rate_bpm: 54,
    hrv_sdnn_ms: 61,
    sleep_duration_hours: 7.1,
    sleep_minutes: 426,
    steps_count: 8200,
    completeness: 0.9,
  },
  latest_weight: { weight_kg: 81.2, body_fat_pct: 17 },
  latest_measurement: { weight_kg: 81.4, body_fat_pct: 17.5 },
  eight_week_measurement_delta: { earliest: { weight_kg: 83 }, latest: { weight_kg: 81.2 } },
  seven_day_healthkit_trend: { avg_resting_hr: 55, avg_hrv_sdnn: 60, avg_sleep_minutes: 410 },
  brief_health: [{ local_date: "2026-10-17", sleep_minutes: 400, resting_heart_rate_bpm: 55 }],
});

const renamed = (from: string, to: string): Ctx => {
  const { [from]: moved, ...rest } = olderContext();
  return { ...rest, [to]: moved };
};

/** The contexts a turn can carry: each eval athlete, an older one, and the other shapes the file reads. */
const contexts = (): Ctx[] => {
  const rich = withModelText(structuredClone(evalProfiles()[0].context) as Ctx);
  const { weight_series_8w: _weights, ...noSeries } = rich;
  return [
    ...evalProfiles().map((profile) => withModelText(structuredClone(profile.context) as Ctx)),
    olderContext(),
    ...["last_3_sessions_summary", "focused_execution", "recent_execution", "brief_sessions"]
      .map((alias) => renamed("session_trends", alias)),
    renamed("latest_healthkit", "today_healthkit"),
    {
      ...noSeries,
      measurement_history: [{ measured_on: "2026-10-01", weight_kg: 82, waist_cm: 88 }],
    },
    {
      ...rich,
      plan_status: {
        has_active_plan: false,
        has_nutrition_target: false,
        reason: "see_professional",
        screening_outcome: "moderate_until_cleared",
        screened_on: "2026-10-10",
      },
    },
  ];
};

const fileOf = (ctx: Ctx) => renderCoachContextParts(ctx, 400_000).file;
const groundedFileOf = (ctx: Ctx, rules?: Record<string, ContextKeyGrounding>) =>
  fileOf(contextForGrounds(ctx, rules));

const keyOf = (path: string) => path.split(/[.[]/)[0];

/** What the declaration says of one field: true grounds, false does not, undefined is not declared. */
function declared(rule: ContextKeyGrounding | undefined, path: string): boolean | undefined {
  if (rule === undefined || rule === "notInFile") return undefined;
  if (rule === "records") return true;
  if (rule === "modelText") return false;
  const kinds = resolve(rule);
  if (kinds.records.has(path) || kinds.controls.has(path)) return true;
  if (kinds.modelText.has(path) || kinds.figures.has(path)) return false;
  return undefined;
}

/** Every field the file shows that the table does not declare, or declares and gets wrong. */
function violations(rules: Record<string, ContextKeyGrounding>): {
  problems: string[];
  verified: Set<string>;
} {
  const problems: string[] = [];
  const verified = new Set<string>();
  let seed = 0;
  for (const ctx of contexts()) {
    const base = fileOf(ctx);
    const baseGrounded = groundedFileOf(ctx, rules);
    for (const path of leafPaths(ctx)) {
      const key = keyOf(path);
      if (rules[key] === "notInFile") continue;
      seed += 1;
      let effect: { shown: boolean; grounds: boolean } = { shown: false, grounds: false };
      for (let variant = 0; variant < 3 && !effect.shown; variant++) {
        const changed = changeAt(ctx, path, (value) => {
          const options = variantsOf(value, seed);
          return options[Math.min(variant, options.length - 1)];
        });
        if (fileOf(changed) === base) continue;
        effect = { shown: true, grounds: groundedFileOf(changed, rules) !== baseGrounded };
      }
      if (!effect.shown) continue;
      const expected = declared(rules[key], path);
      if (expected === undefined) problems.push(`${path} is shown and not declared`);
      else if (expected !== effect.grounds) {
        problems.push(`${path} grounds=${effect.grounds}, declared=${expected}`);
      } else verified.add(key);
    }
  }
  return { problems, verified };
}

Deno.test("every field of the athlete file that is shown is declared, and grounds as declared", () => {
  const { problems, verified } = violations(contextGrounding);
  assertEquals(problems, []);
  // Every key was checked on at least one field that the file shows (verified, not walked).
  const unchecked = Object.entries(contextGrounding)
    .filter(([key, rule]) => rule !== "notInFile" && !verified.has(key)).map(([key]) => key);
  assertEquals(unchecked, []);
});

Deno.test("a key or a field the table does not declare fails the leaf test, and grounds nothing", () => {
  const { active_goal: _goal, ...without } = contextGrounding;
  assert(violations(without).problems.some((p) => p.startsWith("active_goal.")));
  const noFields = {
    ...contextGrounding,
    active_plan: { records: ["active_plan.version_number"] },
  };
  const problems = violations(noFields).problems;
  assert(problems.includes("active_plan.sessions_per_week is shown and not declared"));
  assert(problems.includes("active_plan.title is shown and not declared"));
  // A field the table does not know is not kept, and neither is a key.
  const ctx = {
    ...contexts()[0],
    active_plan: { version_number: 2, sessions_per_week: 4, summary: "x 9911" },
    invented_section: { note: "y 9912" },
  };
  const kept = contextForGrounds(ctx);
  assertEquals(kept.active_plan, { version_number: 2, sessions_per_week: 4 });
  assert(!("invented_section" in kept));
});

/** A proxy that records every path the renderer reads (`a.b` for a field, `a[].b` inside a list). */
function spy(value: unknown, path: string, seen: Set<string>): unknown {
  if (value === null || typeof value !== "object") return value;
  return new Proxy(value, {
    get(target, key, receiver) {
      const read = Reflect.get(target, key, receiver);
      if (typeof key !== "string" || typeof read === "function") return read;
      if (Array.isArray(target)) {
        if (!/^\d+$/.test(key)) return read;
        seen.add(`${path}[]`);
        return spy(read, `${path}[]`, seen);
      }
      const child = path === "" ? key : `${path}.${key}`;
      seen.add(child);
      return spy(read, child, seen);
    },
  });
}

Deno.test("every path the renderer reads is declared, on every athlete and on an older context", () => {
  for (const ctx of contexts()) {
    const seen = new Set<string>();
    renderCoachContextParts(spy(ctx, "", seen) as Ctx, 400_000);
    assert(seen.size > 20);
    const undeclared = [...seen].filter((path) => {
      const rule = contextGrounding[keyOf(path)];
      if (rule === undefined) return true;
      if (typeof rule !== "object") return false;
      const kinds = resolve(rule);
      return path !== keyOf(path) && ![...kinds.records, ...kinds.modelText, ...kinds.controls]
        .some((declaredPath) => declaredPath === path || declaredPath.startsWith(`${path}.`));
    });
    assertEquals(undeclared, []);
  }
});

const ctxWith = (patch: Ctx): Ctx => ({ ...contexts()[0], ...patch });
const has = (
  side: "ground" | "athleteGround",
  inputs: ReturnType<typeof replyCheckInputsFor>,
  value: number,
) => inputs[side]!.values.some((figure) => figure.value === value);

Deno.test("only a model's words and a proposal's figures are held back; records ground", () => {
  const ctx = ctxWith({
    active_plan: {
      title: "Upper Lower 4713",
      version_number: 2,
      sessions_per_week: 4,
      rationale: "Model says bench 9137 kg for 4713 reps",
    },
    plan_proposals: [{
      status: "declined",
      proposed_training: "Model wrote 8261 sets",
      proposed_nutrition: { calories: 5521, protein_g: 5577 },
    }],
    latest_decision: { final_decision: "Cap at 6217 kcal", reason: "Reason 7351" },
  });
  const inputs = replyCheckInputsFor(ctx, "How am I doing?", null);
  for (const value of [9137, 8261, 5521, 5577, 6217, 7351]) {
    assert(!has("ground", inputs, value), `${value} grounds`);
    assert(!has("athleteGround", inputs, value), `${value} grounds the athlete's own target`);
  }
  // The plan's title is the athlete's plan, as the app shows it: a record (4713 is in it).
  assert(has("athleteGround", inputs, 4713));
  assert(has("athleteGround", inputs, 4));
  assert(has("ground", inputs, 2));
});

Deno.test("a title and a workout name are records on every path; a rationale is model text on every path", () => {
  const title = 4713;
  const workout = 4715;
  const rationale = 4717;
  // The athlete file.
  const file = replyCheckInputsFor(
    ctxWith({
      active_plan: {
        title: `Block ${title}`,
        version_number: 1,
        sessions_per_week: 4,
        rationale: `Because ${rationale}`,
      },
    }),
    "q",
    null,
  );
  // The lookup.
  const lookup = renderLookup(
    request("plan_history", "2026-08-01", "2026-10-17"),
    {
      ...planVersionsPayload,
      training: [{
        ...planVersionsPayload.training[0],
        title: `Block ${title}`,
        rationale: `Because ${rationale}`,
        sessions: [{ ...planVersionsPayload.training[0].sessions[0], name: `Push day ${workout}` }],
      }],
    },
  );
  const viaLookup = replyCheckInputsFor(contexts()[0], "q", null, lookup.grounds as string[]);
  // The contributor.
  const text = renderTrainingPlan(parsePlanState(ownersPlanPayload()))!
    .replace("Upper lower push pull", `Block ${title}`)
    .replace("Push day", `Push day ${workout}`);
  const viaContributor = replyCheckInputsFor(contexts()[0], "q", {
    ...noCoachContributions,
    texts: { training_plan: text },
  });
  assertEquals(columnGrounding["training_plans.title"], "records");
  assertEquals(columnGrounding["planned_workouts.name"], "records");
  assertEquals(columnGrounding["training_plan_versions.rationale"], "modelText");
  for (
    const [surface, inputs] of [["lookup", viaLookup], ["contributor", viaContributor]] as const
  ) {
    assert(has("athleteGround", inputs, title), `${surface} title`);
    assert(has("athleteGround", inputs, workout), `${surface} workout name`);
  }
  assert(has("athleteGround", file, title), "file title");
  for (const [surface, inputs] of [["file", file], ["lookup", viaLookup]] as const) {
    assert(!has("ground", inputs, rationale), `${surface} rationale`);
  }
});

Deno.test("a figure of a proposal a lookup returned grounds a figure, never the athlete's own target", () => {
  const inputs = replyCheckInputsFor(ctxWith({}), "What did you suggest?", null, [], [
    "Why: raise intake to 3187 kcal. Gain: 4291 more steps. Cost: one extra day.",
  ]);
  for (const value of [3187, 4291]) {
    assert(has("ground", inputs, value), `${value} ground`);
    assert(!has("athleteGround", inputs, value), `${value} athleteGround`);
  }
});

const pendingProposal = {
  schema_version: "1.1",
  local_date: "2026-10-17",
  block: null,
  phase: null,
  proposals: [{
    kind: "nutrition_targets",
    title: "Raise intake",
    status: "pending",
    created_on: "2026-10-17",
    expires_at: "2026-10-24T08:00:00Z",
    ends_on: null,
    figures: { calories: 2350, protein_g: 165 },
  }],
};

Deno.test("a pending proposal Tracend built grounds a figure as the proposal's, never as the athlete's target", async () => {
  const contributions = await renderCoachContext(
    [createProposalsContributor(() => Promise.resolve(pendingProposal))],
    { userId: "u", question: "q", localDate: "2026-10-17" },
  );
  assertEquals(parseProposalsState(pendingProposal)!.proposals[0].figures, {
    calories: 2350,
    proteinG: 165,
  });
  assertEquals(contributions.figures?.coach_proposals?.length, 1);
  assert(contributions.texts.coach_proposals.includes("2350 kcal a day, 165 g protein"));
  const inputs = replyCheckInputsFor(ctxWith({}), "q", contributions);
  assert(has("ground", inputs, 2350));
  assert(!has("athleteGround", inputs, 2350));
  const check = (answer: string) =>
    coachReplyCheckFor(ctxWith({}), "q", contributions)(answer, [], answer);
  assertEquals(check("The pending proposal would move you to 2,350 kcal."), null);
  assertEquals(check("The proposal sets 2,350 kcal and 165 g protein."), null);
  assert(check("If you approve it, your daily target becomes 2,350 kcal.") !== null);
  // A figure the proposal does not hold is still refused.
  assert(check("The pending proposal would move you to 2,650 kcal.") !== null);
});
