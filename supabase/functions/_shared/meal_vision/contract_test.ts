// The meal photo answer schema and its parser. Like Coach chat's (coach_chat_schema_test.ts),
// the schema Claude compiles must have no optional property and no union and must not vary per
// photo; if a guard fails, fix the schema rather than the limit.

import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import { anthropicSchema } from "../ai/adapters/anthropic.ts";
import { isSupportedSchema, matchesSchema } from "../ai/json_schema.ts";
import { enums, optionalProperties, unions } from "../ai/schema_guards.ts";
import { type MealAnswer, mealAnswerSchema, parseMealAnswer } from "./contract.ts";
import golden from "./munch_label_golden.json" with { type: "json" };
import { dal, noProduct, plateAnswer } from "./test_fixtures.ts";

const schema = mealAnswerSchema as unknown as Record<string, unknown>;
const converted = () => anthropicSchema(schema)!;

Deno.test("the meal schema is one the gateway can check and Claude can take", () => {
  assert(isSupportedSchema(schema));
  assert(converted() !== null);
});

Deno.test("the meal schema has no optional property and no union", () => {
  assertEquals(optionalProperties(converted()), []);
  assertEquals(unions(converted()), []);
});

Deno.test("the meal schema's only enums are the image kind, the unit and the confidence", () => {
  assertEquals(enums(converted()), [
    ["plate", "pack_front", "nutrition_label", "no_food"],
    ["g", "ml"],
    ["low", "medium", "high"],
  ]);
});

// The converted schema is 1,685 bytes. If a field is added on purpose, check that it is required
// and union-free before raising the budget.
const schemaByteBudget = 1_800;

Deno.test("the meal schema stays within its size budget", () => {
  const bytes = new TextEncoder().encode(JSON.stringify(converted())).length;
  assert(bytes <= schemaByteBudget, `${bytes} bytes is over the budget of ${schemaByteBudget}`);
  assert(bytes > schemaByteBudget * 0.8, `${bytes} bytes: lower the budget to match`);
});

Deno.test("every answer the parser accepts matches the schema", () => {
  for (
    const answer of [
      golden.answer,
      golden.live_answer,
      plateAnswer([dal]),
      plateAnswer([]),
    ]
  ) {
    assert(matchesSchema(answer, schema), JSON.stringify(answer).slice(0, 80));
    parseMealAnswer(structuredClone(answer));
  }
});

Deno.test("the candidates must fit the kind: none, at least one, or exactly the product", () => {
  const bad: unknown[] = [
    { ...plateAnswer([]), image_kind: "plate" },
    { ...plateAnswer([dal]), image_kind: "no_food" },
    { ...golden.answer, candidates: [] },
    { ...golden.answer, candidates: [dal, dal] },
    { ...golden.answer, image_kind: "pack_front", candidates: [dal, dal] },
  ];
  for (const answer of bad) {
    assertThrows(
      () => parseMealAnswer(answer),
      Error,
      "meal_vision_response_invalid",
      JSON.stringify(answer).slice(0, 80),
    );
  }
});

Deno.test("a field of the wrong type, out of range or missing is refused", () => {
  const changes: Record<string, unknown>[] = [
    { image_kind: "mixed" },
    { quantity_unit: "l" },
    { product_name: 7 },
    { brand: "b".repeat(81) },
    { net_quantity: -1 },
    { per_100_kcal: Number.POSITIVE_INFINITY },
    { per_serving_kcal: "98" },
    { has_per_100: "true" },
    { servings_per_pack: 1e9 },
  ];
  for (const change of changes) {
    assertThrows(
      () => parseMealAnswer({ ...golden.answer, ...change }),
      Error,
      "meal_vision_response_invalid",
    );
  }
  const { brand: _brand, ...withoutBrand } = golden.answer;
  assertThrows(() => parseMealAnswer(withoutBrand), Error, "meal_vision_response_invalid");
  assertThrows(() => parseMealAnswer(null), Error, "meal_vision_response_invalid");
  assertThrows(() => parseMealAnswer([]), Error, "meal_vision_response_invalid");
  // A candidate the tables could never store is refused too.
  assertThrows(
    () => parseMealAnswer(plateAnswer([{ ...dal, calories: 9000 }])),
    Error,
    "meal_vision_response_invalid",
  );
});

Deno.test("only the schema's fields come out of the parser", () => {
  const parsed = parseMealAnswer({ ...golden.answer, injected: "x" }) as MealAnswer & {
    injected?: string;
  };
  assertEquals(parsed.injected, undefined);
  assertEquals(Object.keys(parsed).sort(), Object.keys(mealAnswerSchema.properties).sort());
  assertEquals(Object.keys(noProduct).length + 2, Object.keys(mealAnswerSchema.properties).length);
});
