import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { catalogV2BySlug } from "../onboarding/catalog_v2.ts";
import { proposalRpcPayloads, stateFixture } from "./fixtures.ts";
import { parseAthleteState } from "./state.ts";
import { swapCandidates } from "./training.ts";

const withExperience = (experience: string) => {
  const data = structuredClone(proposalRpcPayloads());
  data.inputs.profile.experience = experience;
  return parseAthleteState(data);
};

Deno.test("the athlete's level reaches the rules as it is stored, advanced included", () => {
  assertEquals(withExperience("beginner")?.profile.experience, "beginner");
  assertEquals(withExperience("intermediate")?.profile.experience, "intermediate");
  assertEquals(withExperience("advanced")?.profile.experience, "advanced");
  assertEquals(withExperience("expert"), null);
});

Deno.test("swaps offer the advanced staples only to an advanced athlete, and never a harsher joint rating", () => {
  const level = (experience: "intermediate" | "advanced") =>
    stateFixture({ profile: { ...stateFixture().profile, experience } });
  const slugs = (from: string, experience: "intermediate" | "advanced") =>
    swapCandidates(from, level(experience), []).map((exercise) => exercise.slug);
  // A close-grip bench press replaces the bench press at the same shoulder rating; an
  // intermediate is not offered it.
  assert(slugs("barbell-bench-press", "advanced").includes("close-grip-bench-press"));
  assert(!slugs("barbell-bench-press", "intermediate").includes("close-grip-bench-press"));
  // The lat pulldown lists the weighted pull-up as a substitute and an advanced athlete may do it,
  // but it would load the shoulder harder: only the joint rule keeps it from being offered, while
  // the way back from it is.
  assert(catalogV2BySlug.get("lat-pulldown")!.substitutes.includes("weighted-pull-up"));
  assert(!slugs("lat-pulldown", "advanced").includes("weighted-pull-up"));
  assert(slugs("weighted-pull-up", "advanced").includes("lat-pulldown"));
  // The Bulgarian split squat loads the knee harder than the step-up and the lunge, so it is not
  // offered as their swap either; the swap away from it is.
  assert(!slugs("dumbbell-step-up", "advanced").includes("bulgarian-split-squat"));
  assert(slugs("bulgarian-split-squat", "advanced").includes("dumbbell-step-up"));
});
