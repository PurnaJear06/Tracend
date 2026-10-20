// The athlete file as it grounds a reply's numbers (`context_grounding.ts`): every field the
// renderer shows is declared, the declaration is what decides, and a figure only a model wrote or
// only a proposal holds never grounds a sentence about the athlete's own target.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { evalProfiles } from "../../_evals/fixtures.ts";
import {
  contextForGrounds,
  contextGrounding,
  type ContextKeyGrounding,
} from "./context_grounding.ts";
import { renderCoachContextParts, replyCheckInputsFor } from "./coach_chat_provider.ts";

type Path = readonly (string | number)[];

const rich = (): Record<string, unknown> => {
  const base = structuredClone(
    evalProfiles().find((p) => p.id === "rich")!.context,
  ) as Record<string, unknown>;
  return {
    ...base,
    latest_decision: {
      final_decision: "Train today, but cap effort at RPE 7.",
      reason: "Recovery is below baseline after a short night.",
      confidence: "medium",
    },
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
  };
};

const leaves = (node: unknown, path: Path = []): Path[] => {
  if (Array.isArray(node)) return node.flatMap((item, i) => leaves(item, [...path, i]));
  if (node !== null && typeof node === "object") {
    return Object.entries(node).flatMap(([k, v]) => leaves(v, [...path, k]));
  }
  return [path];
};

const withMarker = (ctx: Record<string, unknown>, path: Path, marker: string) => {
  const copy = structuredClone(ctx) as Record<string, unknown>;
  let node = copy as unknown as Record<string | number, unknown>;
  for (const step of path.slice(0, -1)) node = node[step] as typeof node;
  node[path[path.length - 1]] = marker;
  return copy;
};

const fileOf = (ctx: Record<string, unknown>) => renderCoachContextParts(ctx, 400_000).file;

/** What the declaration says of one leaf: whether it grounds, or undefined when it is not declared. */
const declared = (rule: ContextKeyGrounding | undefined, path: Path): boolean | undefined => {
  if (rule === undefined) return undefined;
  if (rule === "records") return true;
  if (rule === "modelText") return false;
  if (rule === "conversation") return undefined;
  const field = path.find((step): step is string => typeof step === "string" && step !== path[0]);
  if (field === undefined) return undefined;
  if (rule.records.includes(field)) return true;
  if (rule.modelText.includes(field)) return false;
  return undefined;
};

/** Every leaf the file shows that the table does not declare, or declares and then gets wrong. */
function violations(
  ctx: Record<string, unknown>,
  rules: Readonly<Record<string, ContextKeyGrounding>>,
): { problems: string[]; checked: number } {
  const problems: string[] = [];
  let checked = 0;
  let n = 0;
  for (const path of leaves(ctx)) {
    const key = String(path[0]);
    if (rules[key] === "conversation") continue;
    const marker = `ZQ${String(++n).padStart(4, "0")}X`;
    const marked = withMarker(ctx, path, marker);
    if (!fileOf(marked).includes(marker)) continue;
    checked++;
    const expected = declared(rules[key], path);
    if (expected === undefined) {
      problems.push(`${path.join(".")} is shown and not declared`);
      continue;
    }
    const grounds = fileOf(contextForGrounds(marked, rules)).includes(marker);
    if (grounds !== expected) {
      problems.push(`${path.join(".")} grounds=${grounds}, declared=${expected}`);
    }
  }
  return { problems, checked };
}

Deno.test("every field of the athlete file that is shown is declared, and grounds as declared", () => {
  const { problems, checked } = violations(rich(), contextGrounding);
  assertEquals(problems, []);
  assert(checked >= 120, `only ${checked} fields were shown and checked`);
});

Deno.test("a field or section the table does not declare fails the leaf test", () => {
  const { active_goal: _goal, ...without } = contextGrounding;
  assert(violations(rich(), without).problems.some((p) => p.startsWith("active_goal.")));
  const noFields = {
    ...contextGrounding,
    active_plan: { records: ["version_number"], modelText: ["title"] },
  };
  const problems = violations(rich(), noFields).problems;
  assert(problems.some((p) => p === "active_plan.sessions_per_week is shown and not declared"));
  assert(problems.some((p) => p === "active_plan.rationale is shown and not declared"));
});

Deno.test("every key the renderer reads is declared", () => {
  const ctx = rich();
  const seen = new Set<string>();
  const spy = new Proxy(ctx, {
    get(target, key, receiver) {
      if (typeof key === "string") seen.add(key);
      return Reflect.get(target, key, receiver);
    },
  });
  renderCoachContextParts(spy, 400_000);
  assertEquals([...seen].filter((key) => !(key in contextGrounding)), []);
});

Deno.test("only a model's words and a proposal's figures are held back; records ground", () => {
  const ctx = {
    ...rich(),
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
  };
  const inputs = replyCheckInputsFor(ctx, "How am I doing?", null);
  const has = (side: "ground" | "athleteGround", value: number) =>
    inputs[side]!.values.some((figure) => figure.value === value);
  for (const value of [9137, 4713, 8261, 5521, 5577, 6217, 7351]) {
    assert(!has("ground", value), `${value} grounds`);
    assert(!has("athleteGround", value), `${value} grounds the athlete's own target`);
  }
  assert(has("athleteGround", 4), "the plan's sessions per week still ground");
  assert(has("ground", 2), "the plan version still grounds");
});

Deno.test("realistic figures in the file still ground, and the file itself is unchanged", () => {
  const ctx = rich();
  const inputs = replyCheckInputsFor(ctx, "How am I doing?", null);
  const planned = (ctx.nutrition_targets as Record<string, unknown>).calories as number;
  assert(inputs.athleteGround!.values.some((figure) => figure.value === planned));
  const days = ctx.health_daily_28d as { resting_hr?: number }[];
  const hr = days.find((day) => typeof day.resting_hr === "number")?.resting_hr;
  assert(hr === undefined || inputs.athleteGround!.values.some((figure) => figure.value === hr));
  const full = fileOf(ctx);
  assert(full.includes("## Latest Decision"));
  assert(full.includes("## Plan Proposals"));
  assert(full.includes("Cut with strength focus"));
});

Deno.test("a figure of a proposal a lookup returned grounds a figure, never the athlete's own target", () => {
  const inputs = replyCheckInputsFor(rich(), "What did you suggest?", null, [], [
    "Why: raise intake to 3187 kcal. Gain: 4291 more steps. Cost: one extra day.",
  ]);
  for (const value of [3187, 4291]) {
    assert(inputs.ground.values.some((figure) => figure.value === value), `${value} ground`);
    assert(
      !inputs.athleteGround!.values.some((figure) => figure.value === value),
      `${value} athleteGround`,
    );
  }
});
