import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { exerciseCatalogV2 } from "../onboarding/catalog_v2.ts";
import { homeAlternativesFor, minimalHomeKit } from "./home_alternatives.ts";

Deno.test("a gym press has bodyweight and minimal-kit catalog alternatives", () => {
  const home = homeAlternativesFor("barbell-bench-press", "intermediate");
  assertEquals(home.already, null);
  assert(home.bodyweight.includes("Push-up"));
  assertEquals(home.minimal, ["Dumbbell floor press"]);
});

Deno.test("every alternative is a real catalog exercise with the equipment its kind allows", () => {
  const names = new Map(exerciseCatalogV2.map((exercise) => [exercise.name, exercise]));
  for (const exercise of exerciseCatalogV2) {
    const home = homeAlternativesFor(exercise.slug, "advanced");
    assert(home.bodyweight.length <= 2 && home.minimal.length <= 2);
    for (const name of home.bodyweight) assertEquals(names.get(name)!.equipment, []);
    for (const name of home.minimal) {
      const kit = names.get(name)!.equipment;
      assert(kit.length > 0 && kit.every((item) => minimalHomeKit.includes(item)), name);
    }
    for (const name of [...home.bodyweight, ...home.minimal]) {
      assert(name !== exercise.name, `${exercise.slug} offers itself`);
    }
  }
});

Deno.test("an exercise that needs no gym kit says so", () => {
  assertEquals(homeAlternativesFor("push-up", "intermediate").already, "bodyweight");
  assertEquals(homeAlternativesFor("dumbbell-curl", "intermediate").already, "minimal");
  assertEquals(homeAlternativesFor("barbell-row", "intermediate").already, null);
});

Deno.test("movement patterns the athlete avoids are left out, and unknown exercises have none", () => {
  assertEquals(homeAlternativesFor("barbell-bench-press", "intermediate", ["horizontal_push"]), {
    already: null,
    bodyweight: [],
    minimal: [],
  });
  assertEquals(homeAlternativesFor("a-custom-lift", "intermediate"), {
    already: null,
    bodyweight: [],
    minimal: [],
  });
  assertEquals(homeAlternativesFor(null, "intermediate"), {
    already: null,
    bodyweight: [],
    minimal: [],
  });
});

Deno.test("home alternatives come from the exercises the athlete's level is offered", () => {
  // A pull-up's harder form, the weighted pull-up, needs only a bar and a dumbbell: home kit for an
  // advanced athlete, and not offered to an intermediate one.
  assert(homeAlternativesFor("pull-up", "advanced").minimal.includes("Weighted pull-up"));
  assert(!homeAlternativesFor("pull-up", "intermediate").minimal.includes("Weighted pull-up"));
  assert(!homeAlternativesFor("pull-up", "beginner").minimal.includes("Weighted pull-up"));
  // An intermediate's alternatives never include an advanced exercise.
  for (const exercise of exerciseCatalogV2) {
    const home = homeAlternativesFor(exercise.slug, "intermediate");
    for (const name of [...home.bodyweight, ...home.minimal]) {
      const found = exerciseCatalogV2.find((item) => item.name === name)!;
      assert(found.level !== "advanced", `${exercise.slug} offers ${name}`);
    }
  }
});
