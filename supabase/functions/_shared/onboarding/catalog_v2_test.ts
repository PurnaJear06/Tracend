import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { exerciseCatalogV1, muscles } from "./catalog.ts";
import {
  type CatalogExerciseV2,
  catalogV2BySlug,
  catalogV2DetailSlugs,
  exerciseCatalogV2,
} from "./catalog_v2.ts";
import { joints, jointStressLevels } from "../training/standard/joint_stress.ts";
import { loadingEquipmentOrder, loadStepKgByEquipment } from "../training/standard/progression.ts";

const migration = new URL(
  "../../../migrations/20261015170021_exercise_catalog_v2.sql",
  import.meta.url,
);

const links = (exercise: CatalogExerciseV2) => [
  ...exercise.regressions,
  ...exercise.progressions,
  ...exercise.substitutes,
];

Deno.test("catalog v2 keeps every v1 exercise unchanged and in order", () => {
  assertEquals(exerciseCatalogV2.length, exerciseCatalogV1.length);
  exerciseCatalogV2.forEach((exercise, index) => {
    const {
      secondaryMuscles: _s,
      jointStress: _j,
      regressions: _r,
      progressions: _p,
      substitutes: _u,
      loadStepKg: _l,
      ...v1
    } = exercise;
    assertEquals(v1, exerciseCatalogV1[index]);
  });
  assertEquals([...catalogV2DetailSlugs].sort(), exerciseCatalogV1.map((e) => e.slug).sort());
});

Deno.test("every substitute, regression and progression points at another real exercise", () => {
  for (const exercise of exerciseCatalogV2) {
    for (const slug of links(exercise)) {
      assert(catalogV2BySlug.has(slug), `${exercise.slug} links to unknown ${slug}`);
      assert(slug !== exercise.slug, `${exercise.slug} links to itself`);
    }
    const all = links(exercise);
    assertEquals(new Set(all).size, all.length, `${exercise.slug} lists a link twice`);
  }
});

Deno.test("regressions and progressions mirror each other and stay in the pattern", () => {
  for (const exercise of exerciseCatalogV2) {
    for (const slug of exercise.progressions) {
      const harder = catalogV2BySlug.get(slug)!;
      assert(
        harder.regressions.includes(exercise.slug),
        `${slug} should regress to ${exercise.slug}`,
      );
      assertEquals(harder.pattern, exercise.pattern, `${exercise.slug} -> ${slug} changes pattern`);
      assert(
        !(exercise.level === "intermediate" && harder.level === "beginner"),
        `${slug} is a progression of ${exercise.slug} but a lower level`,
      );
    }
    for (const slug of exercise.regressions) {
      const easier = catalogV2BySlug.get(slug)!;
      assert(
        easier.progressions.includes(exercise.slug),
        `${slug} should progress to ${exercise.slug}`,
      );
    }
  }
});

Deno.test("progressions never loop back to an easier form", () => {
  const visit = (slug: string, path: readonly string[]): void => {
    assert(!path.includes(slug), `progression loop: ${[...path, slug].join(" -> ")}`);
    for (const next of catalogV2BySlug.get(slug)!.progressions) visit(next, [...path, slug]);
  };
  for (const exercise of exerciseCatalogV2) visit(exercise.slug, []);
});

Deno.test("substitutes are mutual and share the pattern or the target muscle", () => {
  for (const exercise of exerciseCatalogV2) {
    for (const slug of exercise.substitutes) {
      const other = catalogV2BySlug.get(slug)!;
      assert(
        other.substitutes.includes(exercise.slug),
        `${slug} should substitute ${exercise.slug}`,
      );
      assert(
        other.pattern === exercise.pattern || other.muscles[0] === exercise.muscles[0],
        `${exercise.slug} and ${slug} share neither pattern nor target`,
      );
    }
  }
});

Deno.test("secondary muscles and joint stress use the catalog vocabularies", () => {
  for (const exercise of exerciseCatalogV2) {
    for (const muscle of exercise.secondaryMuscles) {
      assert(muscles.includes(muscle), `${exercise.slug}: ${muscle}`);
      assert(!exercise.muscles.includes(muscle), `${exercise.slug}: ${muscle} is primary`);
    }
    assertEquals(Object.keys(exercise.jointStress).sort(), [...joints].sort());
    for (const joint of joints) {
      assert(jointStressLevels.includes(exercise.jointStress[joint]), exercise.slug);
    }
  }
});

Deno.test("each load step comes from the exercise's single loading implement", () => {
  for (const exercise of exerciseCatalogV2) {
    const implements_ = exercise.equipment.filter((item) =>
      loadingEquipmentOrder.value.includes(item)
    );
    assert(implements_.length <= 1, `${exercise.slug} has several loading implements`);
    const expected = implements_.length ? loadStepKgByEquipment.value[implements_[0]] : null;
    assertEquals(exercise.loadStepKg, expected, exercise.slug);
  }
  assertEquals(catalogV2BySlug.get("barbell-back-squat")!.loadStepKg, 2.5);
  assertEquals(catalogV2BySlug.get("kettlebell-swing")!.loadStepKg, 4);
  assertEquals(catalogV2BySlug.get("pull-up")!.loadStepKg, null);
  assertEquals(catalogV2BySlug.get("band-row")!.loadStepKg, null);
});

Deno.test("the catalog v2 migration mirrors catalog_v2.ts exactly", async () => {
  const sql = await Deno.readTextFile(migration);
  const array = (items: readonly string[]) =>
    items.length ? `array[${items.map((item) => `'${item}'`).join(",")}]::text[]` : "'{}'::text[]";
  const expected = exerciseCatalogV2.map((exercise) =>
    ` ('${exercise.slug}',${array(exercise.secondaryMuscles)},'${exercise.jointStress.knee}',` +
    `'${exercise.jointStress.back}','${exercise.jointStress.shoulder}',` +
    `${array(exercise.regressions)},${array(exercise.progressions)},` +
    `${array(exercise.substitutes)},` +
    `${exercise.loadStepKg === null ? "null" : exercise.loadStepKg}::numeric,` +
    `${exercise.role ? `'${exercise.role}'` : "null::text"})`
  );
  const rows = sql.split("\n").filter((line) => /^ \('[a-z0-9-]+',(array|'\{\}')/.test(line))
    .map((line) => line.replace(/,$/, ""));
  assertEquals(rows, expected);
});
