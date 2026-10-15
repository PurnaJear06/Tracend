import { assertEquals } from "jsr:@std/assert@1.0.14";
import { goals } from "./answers.ts";
import { type CatalogExercise, type EquipmentItem, exerciseCatalogV1 } from "./catalog.ts";
import { exerciseCatalogV2 } from "./catalog_v2.ts";
import { onboardingSystemPrompt, policiesFor, validRulesPlan } from "./generate.ts";
import { buildOnboardingProposal } from "./plan_contract.ts";
import { answersFor, weekdaysFor } from "./test_helpers.ts";

// Catalog v2 adds data for later chunks (B2); it must not change a single
// byte of what onboarding produces today. The digests below were recorded on
// the commit before catalog v2 existed (477da79) and cover the rules plan, the
// proposal built from it and the model's system prompt (which lists the
// catalog) for every case in the sweep.

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
                  outcome = JSON.stringify(buildOnboardingProposal(plan, policies, {
                    origin: "rules",
                    provider: null,
                    model: null,
                    fallbackReason: null,
                  }));
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
  plans: "6719a6cf28d903ba1bc0277cafc5efc0842c9f905de746705d2b924915bce609",
  prompts: "58b00b718a5af7648803596b0f8b351a03762315c973b76f775a25ca2f8848da",
};

Deno.test("today's onboarding plans and prompts are byte-identical with catalog v1", async () => {
  assertEquals(await digest(exerciseCatalogV1), recorded);
});

Deno.test("the catalog v2 entries build the same plans and prompts as catalog v1", async () => {
  assertEquals(await digest(exerciseCatalogV2), recorded);
});
