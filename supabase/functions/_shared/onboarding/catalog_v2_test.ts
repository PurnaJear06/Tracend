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

// The v2 columns come from B1's migration; the advanced-level migration then sets them for its new
// rows and rewrites the links of existing rows that point at them. A later row for a slug wins.
const migrations = [
  "../../../migrations/20261015170021_exercise_catalog_v2.sql",
  "../../../migrations/20261023100050_advanced_level_catalog.sql",
].map((path) => new URL(path, import.meta.url));

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
  // The weighted pull-up is loaded with a dumbbell, so it steps like one.
  assertEquals(catalogV2BySlug.get("weighted-pull-up")!.loadStepKg, 2.5);
  assertEquals(catalogV2BySlug.get("close-grip-bench-press")!.loadStepKg, 2.5);
  assertEquals(catalogV2BySlug.get("bulgarian-split-squat")!.loadStepKg, 2.5);
});

Deno.test("the catalog v2 migrations mirror catalog_v2.ts exactly", async () => {
  const sql = (await Promise.all(migrations.map((url) => Deno.readTextFile(url)))).join("\n");
  const array = (items: readonly string[]) =>
    items.length ? `array[${items.map((item) => `'${item}'`).join(",")}]::text[]` : "'{}'::text[]";
  const expected = new Map(exerciseCatalogV2.map((exercise) => [
    exercise.slug,
    ` ('${exercise.slug}',${array(exercise.secondaryMuscles)},'${exercise.jointStress.knee}',` +
    `'${exercise.jointStress.back}','${exercise.jointStress.shoulder}',` +
    `${array(exercise.regressions)},${array(exercise.progressions)},` +
    `${array(exercise.substitutes)},` +
    `${exercise.loadStepKg === null ? "null" : exercise.loadStepKg}::numeric,` +
    `${exercise.role ? `'${exercise.role}'` : "null::text"})`,
  ]));
  const final = new Map<string, string>();
  for (const line of sql.split("\n")) {
    if (!/^ \('[a-z0-9-]+',(array|'\{\}')/.test(line)) continue;
    const row = line.replace(/,$/, "");
    final.set(row.slice(3, row.indexOf("'", 3)), row);
  }
  assertEquals(final, expected);
});

Deno.test("the advanced staples are rated, linked and loaded like the exercises beside them", () => {
  const staple = (slug: string) => catalogV2BySlug.get(slug)!;
  // Linked to the forms they build on.
  assertEquals(staple("weighted-pull-up").regressions, ["pull-up", "chin-up"]);
  assertEquals(staple("pull-up").progressions, ["weighted-pull-up"]);
  assertEquals(staple("chin-up").progressions, ["weighted-pull-up"]);
  assertEquals(staple("bulgarian-split-squat").regressions, ["dumbbell-reverse-lunge"]);
  assert(staple("dumbbell-reverse-lunge").progressions.includes("bulgarian-split-squat"));
  for (const slug of ["close-grip-bench-press", "incline-barbell-bench-press"]) {
    assert(staple("barbell-bench-press").substitutes.includes(slug), slug);
  }
  for (
    const slug of [
      "weighted-pull-up",
      "close-grip-bench-press",
      "incline-barbell-bench-press",
      "bulgarian-split-squat",
    ]
  ) {
    assertEquals(staple(slug).level, "advanced", slug);
    assertEquals(staple(slug).role, "variation", slug);
    assert(staple(slug).compound, slug);
  }
  // Joint stress (in-house): load added to a pull-up is harsher on the shoulder than the pull-up,
  // the bench press variations keep the bench press's shoulder rating, and the Bulgarian split
  // squat loads the front knee at least as much as the lunges it follows.
  const shoulder = (slug: string) => jointStressLevels.indexOf(staple(slug).jointStress.shoulder);
  const knee = (slug: string) => jointStressLevels.indexOf(staple(slug).jointStress.knee);
  assert(shoulder("weighted-pull-up") > shoulder("pull-up"));
  assertEquals(shoulder("close-grip-bench-press"), shoulder("barbell-bench-press"));
  assertEquals(shoulder("incline-barbell-bench-press"), shoulder("barbell-bench-press"));
  assert(knee("bulgarian-split-squat") >= knee("barbell-reverse-lunge"));
  // Progression increments: the loading implement's step (a dumbbell between the feet for the
  // weighted pull-up).
  for (const slug of ["weighted-pull-up", "close-grip-bench-press", "bulgarian-split-squat"]) {
    assertEquals(staple(slug).loadStepKg, 2.5, slug);
  }
});
