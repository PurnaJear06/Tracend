import { assertEquals } from "jsr:@std/assert@1";
import { decisionSchema } from "../providers/gemini_coach_model_provider.ts";
import { isSupportedSchema, matchesSchema } from "./json_schema.ts";

const schema = {
  type: "object",
  additionalProperties: false,
  properties: {
    action: { type: "string", enum: ["PROCEED", "ADJUST"] },
    summary: { type: "string", minLength: 1, maxLength: 20, description: "One line." },
    sets: { type: "integer", minimum: 1, maximum: 10 },
    load: { type: ["number", "null"], exclusiveMinimum: 0 },
    notes: { type: "array", maxItems: 2, items: { type: "string", pattern: "^[a-z ]+$" } },
    kind: { const: "daily" },
    extra: { anyOf: [{ type: "string" }, { type: "boolean" }] },
  },
  required: ["action", "summary", "sets", "load", "notes", "kind"],
};

const valid = {
  action: "PROCEED",
  summary: "Keep the plan",
  sets: 3,
  load: null,
  notes: ["easy day"],
  kind: "daily",
};

Deno.test("the gateway's own schemas and the decision schema are supported", () => {
  assertEquals(isSupportedSchema(schema), true);
  assertEquals(isSupportedSchema(decisionSchema), true);
});

Deno.test("schemas with keywords the checker cannot enforce are unsupported", () => {
  for (
    const unsupported of [
      { $ref: "#/$defs/x" },
      { type: "object", oneOf: [] },
      { type: "object", patternProperties: {} },
      { type: "object", properties: { a: { allOf: [] } } },
      { type: "strings" },
      { type: "string", pattern: "(" },
      { type: "array", maxItems: -1 },
      { type: "array", items: [{ type: "string" }] },
      "not a schema",
    ]
  ) {
    assertEquals(isSupportedSchema(unsupported), false, JSON.stringify(unsupported));
  }
});

Deno.test("a matching value passes", () => {
  assertEquals(matchesSchema(valid, schema), true);
  assertEquals(matchesSchema({ ...valid, load: 42.5, extra: true }, schema), true);
});

Deno.test("each constraint is enforced", () => {
  const failing: Record<string, unknown>[] = [
    { ...valid, action: "SKIP" },
    { ...valid, summary: "" },
    { ...valid, summary: "x".repeat(21) },
    { ...valid, sets: 2.5 },
    { ...valid, sets: 0 },
    { ...valid, sets: 11 },
    { ...valid, load: 0 },
    { ...valid, load: "heavy" },
    { ...valid, notes: ["a", "b", "c"] },
    { ...valid, notes: ["Capital"] },
    { ...valid, kind: "weekly" },
    { ...valid, extra: 3 },
    { ...valid, surprise: true },
  ];
  for (const value of failing) {
    assertEquals(matchesSchema(value, schema), false, JSON.stringify(value));
  }
  const { summary: _summary, ...withoutSummary } = valid;
  assertEquals(matchesSchema(withoutSummary, schema), false);
  assertEquals(matchesSchema([valid], schema), false);
  assertEquals(matchesSchema(null, schema), false);
});
