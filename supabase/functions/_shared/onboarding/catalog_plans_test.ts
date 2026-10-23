import { assertEquals } from "jsr:@std/assert@1.0.14";
import { goals } from "./answers.ts";
import {
  type CatalogExercise,
  catalogVersion,
  type EquipmentItem,
  exerciseCatalogV1,
} from "./catalog.ts";
import { exerciseCatalogV2 } from "./catalog_v2.ts";
import { onboardingSystemPrompt, policiesFor, validRulesPlan } from "./generate.ts";
import { buildOnboardingProposal } from "./plan_contract.ts";
import { answersFor, weekdaysFor } from "./test_helpers.ts";

// Catalog v2 adds data the planner reads (secondary muscles, B2); the v2 entries must build
// exactly the plans and prompts catalog v1 builds. The digests cover the rules plan, the proposal
// built from it and the model's system prompt (which lists the catalog) for every case in the
// sweep. They were recorded on 477da79 (before catalog v2) and re-recorded on purpose by B2
// (templates and fractional volume changed the rules plan; the prompt changed only where a focus
// muscle's lowered weekly minimum changed). The change is described in
// docs/handoff/training-engine.md, section B2.

const equipment: Record<string, EquipmentItem[]> = {
  bodyweight: [],
  dumbbells: ["dumbbells"],
  kettlebells: ["kettlebells"],
  bands: ["bands", "pull_up_bar"],
  home: ["dumbbells", "bench", "pull_up_bar", "bands"],
  machines: ["machines", "cables"],
  gym: ["dumbbells", "barbell", "bench", "cables", "machines", "pull_up_bar", "kettlebells"],
};

async function digest(catalog: readonly CatalogExercise[]) {
  const plans: string[] = [];
  const prompts: string[] = [];
  for (const [name, items] of Object.entries(equipment)) {
    for (const experience of ["beginner", "intermediate"] as const) {
      for (const days of [1, 2, 3, 4, 5, 6]) {
        for (const goal of goals) {
          for (const sessionMinutes of [30, 45, 60, 90]) {
            for (const avoidPatterns of [[], ["squat"]] as const) {
              for (const priorityMuscles of [[], ["glutes"], ["back", "shoulders"]] as const) {
                const answers = answersFor({
                  path: experience === "intermediate" ? "experienced" : "beginner",
                  experience,
                  goal,
                  equipment: items,
                  trainingWeekdays: weekdaysFor[days],
                  sessionMinutes,
                  avoidPatterns: [...avoidPatterns],
                  priorityMuscles: [...priorityMuscles],
                });
                const policies = policiesFor(answers, catalog);
                const key = `${name}|${experience}|${days}|${goal}|${sessionMinutes}|` +
                  `${avoidPatterns.join("+")}|${priorityMuscles.join("+")}`;
                let outcome: string;
                try {
                  const plan = validRulesPlan(policies);
                  // The proposal names the catalog version, which moved to v2 with the advanced
                  // level; the digest still stands for the plan, so the label is read as v1.
                  outcome = JSON.stringify(buildOnboardingProposal(plan, policies, {
                    origin: "rules",
                    provider: null,
                    model: null,
                    fallbackReason: null,
                  })).replaceAll(`"${catalogVersion}"`, '"catalog-v1"');
                } catch (error) {
                  outcome = `refused:${(error as Error).name}:${(error as Error).message}`;
                }
                plans.push(`${key}\n${outcome}`);
                prompts.push(`${key}\n${onboardingSystemPrompt(policies)}`);
              }
            }
          }
        }
      }
    }
  }
  const hash = async (parts: string[]) => {
    const bytes = await crypto.subtle.digest(
      "SHA-256",
      new TextEncoder().encode(parts.join("\n\n")),
    );
    return [...new Uint8Array(bytes)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
  };
  return { cases: plans.length, plans: await hash(plans), prompts: await hash(prompts) };
}

const recorded = {
  cases: 10080,
  plans: "82234370a26602ec8838dc30dbe93428c8fb2c5b838ad872b63720d1b4c3b3b4",
  prompts: "b34cf68c6ed52d41f89d7e83ef9404a1da60c3923f8d0985abc68d5814d5a997",
};

Deno.test("onboarding plans and prompts are byte-identical to the recorded digests with catalog v1", async () => {
  assertEquals(await digest(exerciseCatalogV1), recorded);
});

Deno.test("the catalog v2 entries build the same plans and prompts as catalog v1", async () => {
  assertEquals(await digest(exerciseCatalogV2), recorded);
});
