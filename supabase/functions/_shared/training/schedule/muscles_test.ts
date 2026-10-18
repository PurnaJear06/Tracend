import { assertEquals } from "jsr:@std/assert@1.0.14";
import { exerciseCatalogV1 } from "../../onboarding/catalog.ts";
import { frontSideDelts, rearDelts, sessionMuscles, setsThatTrainAMuscle } from "./muscles.ts";

Deno.test("a muscle needs the standard's weekly minimum over its minimum sessions: 2 direct sets", () => {
  assertEquals(setsThatTrainAMuscle, 2);
});

Deno.test("direct sets count for every primary muscle of the exercise, most sets first", () => {
  const { muscles, unknown } = sessionMuscles([
    { slug: "barbell-bench-press", sets: 4 },
    { slug: "cable-lateral-raise", sets: 3 },
    { slug: "cable-triceps-pressdown", sets: 3 },
  ]);
  // Chest 4, triceps 4 + 3, front and side delts 3.
  assertEquals(muscles, ["triceps", "chest", "front and side delts"]);
  assertEquals(unknown, 0);
});

Deno.test("one accessory set does not make a session train a muscle", () => {
  const { muscles } = sessionMuscles([
    { slug: "barbell-back-squat", sets: 4 },
    { slug: "standing-calf-raise", sets: 1 },
  ]);
  assertEquals(muscles, ["glutes", "quads"]);
});

Deno.test("an exercise without a catalog entry is counted as unknown, never guessed", () => {
  const result = sessionMuscles([
    { slug: null, sets: 4 },
    { slug: "not-in-the-catalog", sets: 3 },
    { slug: "lat-pulldown", sets: 3 },
  ]);
  assertEquals(result.muscles, ["back", "biceps"]);
  assertEquals(result.unknown, 2);
});

Deno.test("every catalog exercise maps to at least one muscle", () => {
  for (const item of exerciseCatalogV1) {
    assertEquals(
      sessionMuscles([{ slug: item.slug, sets: 3 }]).muscles.length > 0,
      true,
      item.slug,
    );
  }
});

Deno.test("rear-delt work (the catalog's rear_delts pattern) is a different group from pressing and raises", () => {
  assertEquals(
    sessionMuscles([{ slug: "face-pull", sets: 3 }, { slug: "dumbbell-rear-delt-fly", sets: 3 }])
      .muscles,
    [rearDelts],
  );
  assertEquals(
    sessionMuscles([
      { slug: "barbell-overhead-press", sets: 3 },
      { slug: "cable-lateral-raise", sets: 3 },
    ]).muscles,
    [frontSideDelts, "triceps"],
  );
  // An incline press lists shoulders as a primary muscle: that is front-delt work.
  assertEquals(
    sessionMuscles([{ slug: "incline-dumbbell-press", sets: 3 }]).muscles,
    ["chest", frontSideDelts],
  );
});
