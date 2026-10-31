// Guards for the shape Coach chat sends to Claude as its structured-output schema.
//
// Claude compiles a grammar the first time it sees a schema and caches it for 24 hours, keyed on
// the schema's structure. The compile grows with every optional property (each roughly doubles part
// of the grammar; the documented limit is 24) and every union (limit 16). On 2026-10-18 the answer
// schema had 24 optional properties and 4 `anyOf`s and listed the day's evidence codes, so it
// changed per athlete and per day: the compile never hit the cache and ran past the route's timeout
// on every turn (0 tokens, ~31.7 s, `provider_timeout`). These tests fail if a change brings any of
// that back. If one fails, fix the schema; do not raise a limit to make it pass.

import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import { captureLogs, claudeMessage, fakeFetch, jsonResponse, routeFor } from "../ai/fakes.ts";
import { anthropicSchema } from "../ai/adapters/anthropic.ts";
import { optionalProperties, unions } from "../ai/schema_guards.ts";
import { evalProfiles } from "../../_evals/fixtures.ts";
import {
  coachChatGatewaySchema,
  generateCoachChatViaGateway,
  identifySchema,
} from "./coach_chat_provider_gateway.ts";
import { classifyQuestion } from "./coach_chat_provider.ts";

type Node = Record<string, unknown>;

const isNode = (value: unknown): value is Node =>
  typeof value === "object" && value !== null && !Array.isArray(value);

/** The schema as sent to Claude. */
const converted = () => anthropicSchema(coachChatGatewaySchema())!;

Deno.test("the answer schema has no optional property", () => {
  assertEquals(optionalProperties(converted()), []);
});

Deno.test("the answer schema has no union", () => {
  assertEquals(unions(converted()), []);
});

Deno.test("the guards see a regression: a schema with optional properties and unions is counted", () => {
  const bad = {
    type: "object",
    properties: {
      a: { type: "string" },
      b: { anyOf: [{ type: "string" }, { type: "null" }] },
      c: { type: ["string", "null"] },
    },
    required: ["a"],
  };
  assertEquals(optionalProperties(bad), ["$.b", "$.c"]);
  assertEquals(unions(bad).length, 2);
});

// The converted schema is 2,818 bytes. A larger schema is more grammar to compile on a first use:
// when this fails because a field was added on purpose, check the compile cost (and that every new
// property is required and union-free) before raising the budget.
const schemaByteBudget = 3_100;

Deno.test("the answer schema stays within its size budget", () => {
  const bytes = new TextEncoder().encode(JSON.stringify(converted())).length;
  assert(bytes <= schemaByteBudget, `${bytes} bytes is over the budget of ${schemaByteBudget}`);
  // A budget far above the schema would stop guarding anything.
  assert(bytes > schemaByteBudget * 0.8, `${bytes} bytes: lower the budget to match`);
});

Deno.test("the schema holds nothing that varies: no evidence codes, no dates, no ids", () => {
  const text = JSON.stringify(converted());
  for (
    const code of ["RECOVERY_BELOW_BASELINE", "APPROVED_PLAN_ACTIVE", "__NO_PERMITTED_EVIDENCE__"]
  ) {
    assert(!text.includes(code), code);
  }
  // Every enum in the schema is a fixed vocabulary of the product: lookup names, proposal kinds,
  // reasons and field names, evidence sources, safety states, fact actions and fact kinds. A new
  // one is a deliberate change to this count.
  const enums: string[][] = [];
  const collect = (node: unknown) => {
    if (Array.isArray(node)) node.forEach(collect);
    else if (isNode(node)) {
      if (Array.isArray(node.enum)) enums.push(node.enum as string[]);
      Object.values(node).forEach(collect);
    }
  };
  collect(converted());
  assertEquals(enums.length, 8);
});

const rich = () => structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);
const model = JSON.stringify({
  data_requests: [],
  proposal_intent: [],
  fact_suggestions: [],
  answer: "Keep today's session light.",
  evidence: [],
  missing_data: [],
  safety_state: "allowed",
  suggested_follow_ups: [],
  reasoning_chain: [],
});

/** The schema bytes and hash one turn sent to Claude, and what its telemetry reports. */
async function sentSchema(permitted: string[], remembered: boolean, withLookups: boolean) {
  const fake = fakeFetch(() =>
    jsonResponse(claudeMessage({ content: [{ type: "text", text: model }] }))
  );
  const context = { ...rich(), permitted_evidence: permitted };
  const question = "How did my training go this week?";
  const { result: generation } = await captureLogs(() =>
    generateCoachChatViaGateway({
      question,
      context,
      contextKind: classifyQuestion(question),
      route: routeFor("coach_chat", { MODEL: "claude-haiku-5-5", MAX_OUTPUT_TOKENS: "4096" }),
      consentVendor: "anthropic",
      proposals: true,
      factSuggestions: remembered,
      ...(withLookups
        ? { lookups: () => Promise.resolve({ text: "", grounds: [], counts: [] }) }
        : {}),
    }, { fetch: fake.fetch })
  );
  const format = (fake.sent[0].body.output_config as { format: { schema: unknown } }).format;
  return { bytes: JSON.stringify(format.schema), attempt: generation.attempts[0] };
}

Deno.test("the schema sent is byte-identical for every athlete, day and remember flag", async () => {
  const runs = await Promise.all([
    sentSchema([], true, true),
    sentSchema(["RECOVERY_BELOW_BASELINE"], true, true),
    sentSchema(["RECOVERY_BELOW_BASELINE", "APPROVED_PLAN_ACTIVE"], false, true),
    sentSchema(["A_DIFFERENT_DAYS_CODE"], false, false),
  ]);
  for (const run of runs) assertEquals(run.bytes, runs[0].bytes);
  assertEquals(runs[0].bytes, JSON.stringify(converted()));
  // The telemetry names the same schema, so a drift shows in Sentry as a second hash.
  const identity = await identifySchema(coachChatGatewaySchema());
  for (const run of runs) {
    assertEquals(run.attempt.schemaSha, identity.sha);
    assertEquals(run.attempt.schemaBytes, identity.bytes);
  }
  assertEquals(identity.sha.length, 12);
  assertEquals(runs.map((run) => run.attempt.remembered), [true, true, false, false]);
});

Deno.test("a changed schema changes the hash", async () => {
  const changed = { ...coachChatGatewaySchema(), extra: true };
  assertNotEquals(
    (await identifySchema(changed)).sha,
    (await identifySchema(coachChatGatewaySchema())).sha,
  );
});

Deno.test("the investigate-first change added no schema bytes: the new kinds of record are filters on existing lookups", async () => {
  // 2,818 bytes, sha 274ee4fafead, before and after the Coverage Brief, the watch-outs, the eight
  // requests a round and the new filters (2026-10-20). A new lookup name would change both; if one
  // is added on purpose, check the compile cost first (see the header of this file).
  const identity = await identifySchema(coachChatGatewaySchema());
  assertEquals(identity.bytes, 2_818);
  assertEquals(identity.sha, "274ee4fafead");
});
