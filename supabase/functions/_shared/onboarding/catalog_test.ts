import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { allowedExercises, catalogBySlug, exerciseCatalogV1 } from "./catalog.ts";

// The seed, then the advanced staples added by the next migration; rows keep catalog.ts's order.
const migrations = [
  "../../../migrations/20261002091000_exercise_catalog.sql",
  "../../../migrations/20261023100050_advanced_level_catalog.sql",
].map((path) => new URL(path, import.meta.url));

Deno.test("the catalog migrations seed exactly the TypeScript catalog", async () => {
  const sql = (await Promise.all(migrations.map((url) => Deno.readTextFile(url)))).join("\n");
  const rows = [...sql.matchAll(/^ \('([a-z0-9-]+)','((?:[^']|'')+)','([a-z_]+)',/gm)]
    .map(([, slug, name, pattern]) => ({ slug, name: name.replaceAll("''", "'"), pattern }));
  assertEquals(
    rows,
    exerciseCatalogV1.map(({ slug, name, pattern }) => ({ slug, name, pattern })),
  );
  for (const exercise of exerciseCatalogV1) {
    const equipment = exercise.equipment.length
      ? `array[${exercise.equipment.map((item) => `'${item}'`).join(",")}]::text[]`
      : "'{}'::text[]";
    const muscles = `array[${exercise.muscles.map((item) => `'${item}'`).join(",")}]::text[]`;
    assert(
      sql.includes(
        `('${exercise.slug}','${
          exercise.name.replaceAll("'", "''")
        }','${exercise.pattern}',${muscles},${equipment},'${exercise.level}',${exercise.compound})`,
      ),
      `${exercise.slug} differs between catalog.ts and the migration`,
    );
  }
});

Deno.test("catalog slugs are unique", () => {
  const slugs = exerciseCatalogV1.map((exercise) => exercise.slug);
  assertEquals(new Set(slugs).size, slugs.length);
});

Deno.test("every equipment set covers a squat or lunge, a hinge, a push and a pull", () => {
  for (const equipment of [[], ["dumbbells"], ["bands"], ["kettlebells"], ["machines"]] as const) {
    for (const experience of ["beginner", "intermediate", "advanced"] as const) {
      const patterns = new Set(
        allowedExercises(exerciseCatalogV1, equipment, experience).map((exercise) =>
          exercise.pattern
        ),
      );
      for (
        const group of [["squat", "lunge"], ["hinge"], ["horizontal_push", "vertical_push"], [
          "horizontal_pull",
          "vertical_pull",
        ]]
      ) {
        assert(
          group.some((pattern) => patterns.has(pattern as never)),
          `${equipment.join("+") || "bodyweight"} ${experience} lacks ${group.join("/")}`,
        );
      }
    }
  }
});

Deno.test("an athlete is offered the exercises at or below their own level", () => {
  const equipment = ["pull_up_bar", "barbell", "dumbbells", "bench"] as const;
  const offered = (experience: "beginner" | "intermediate" | "advanced") =>
    new Set(allowedExercises(exerciseCatalogV1, equipment, experience).map((e) => e.slug));
  const staples = [
    "weighted-pull-up",
    "close-grip-bench-press",
    "incline-barbell-bench-press",
    "bulgarian-split-squat",
  ];
  for (const slug of staples) {
    assertEquals(catalogBySlug.get(slug)?.level, "advanced", slug);
    assert(offered("advanced").has(slug), `${slug} is offered to an advanced athlete`);
    assert(!offered("intermediate").has(slug), `${slug} is not offered to an intermediate`);
    assert(!offered("beginner").has(slug), `${slug} is not offered to a beginner`);
  }
  // Everything the lower levels have, the advanced level has too.
  for (const slug of offered("intermediate")) assert(offered("advanced").has(slug), slug);
  for (const slug of offered("beginner")) assert(offered("intermediate").has(slug), slug);
});

Deno.test("beginners are offered only beginner exercises", () => {
  const offered = allowedExercises(exerciseCatalogV1, ["pull_up_bar", "barbell"], "beginner");
  assert(offered.every((exercise) => exercise.level === "beginner"));
  assert(!offered.some((exercise) => exercise.slug === "pull-up"));
  assert(
    allowedExercises(exerciseCatalogV1, ["pull_up_bar"], "intermediate")
      .some((exercise) => exercise.slug === "pull-up"),
  );
});
