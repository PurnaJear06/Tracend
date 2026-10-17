import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { exerciseCatalogV2 } from "../onboarding/catalog_v2.ts";
import { homeAlternativesFor, minimalHomeKit } from "./home_alternatives.ts";

Deno.test("a gym press has bodyweight and minimal-kit catalog alternatives", () => {
  const home = homeAlternativesFor("barbell-bench-press");
  assertEquals(home.already, null);
  assert(home.bodyweight.includes("Push-up"));
  assertEquals(home.minimal, ["Dumbbell floor press"]);
});

Deno.test("every alternative is a real catalog exercise with the equipment its kind allows", () => {
  const names = new Map(exerciseCatalogV2.map((exercise) => [exercise.name, exercise]));
  for (const exercise of exerciseCatalogV2) {
    const home = homeAlternativesFor(exercise.slug);
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
  assertEquals(homeAlternativesFor("push-up").already, "bodyweight");
  assertEquals(homeAlternativesFor("dumbbell-curl").already, "minimal");
  assertEquals(homeAlternativesFor("barbell-row").already, null);
});

Deno.test("movement patterns the athlete avoids are left out, and unknown exercises have none", () => {
  assertEquals(homeAlternativesFor("barbell-bench-press", ["horizontal_push"]), {
    already: null,
    bodyweight: [],
    minimal: [],
  });
  assertEquals(homeAlternativesFor("a-custom-lift"), {
    already: null,
    bodyweight: [],
    minimal: [],
  });
  assertEquals(homeAlternativesFor(null), { already: null, bodyweight: [], minimal: [] });
});
