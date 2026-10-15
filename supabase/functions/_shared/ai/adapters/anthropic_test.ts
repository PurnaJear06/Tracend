import { assertEquals } from "jsr:@std/assert@1";
import { claudeMessage, routeFor, syntheticKey } from "../fakes.ts";
import { type AnthropicModel, modelSpec } from "../models.ts";
import type { AiRequest } from "../types.ts";
import { anthropicAdapter, anthropicSchema } from "./anthropic.ts";

const claudeModels = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"] as const;

const spec = (model: string) => modelSpec("anthropic", model) as AnthropicModel;

function request(
  model: string,
  values: Record<string, string> = {},
  extra: Partial<AiRequest> = {},
): AiRequest {
  return {
    route: routeFor("coach_chat", { MODEL: model, ...values }),
    system: [{ type: "text", text: "Tracend rules.", cache: true }, {
      type: "text",
      text: "Athlete file.",
    }],
    messages: [{ role: "user", content: [{ type: "text", text: "Should I train today?" }] }],
    output: { kind: "text" },
    consentVendor: "anthropic",
    ...extra,
  };
}

const build = (req: AiRequest) => {
  const call = anthropicAdapter.build(req, spec(req.route.model), syntheticKey);
  if (!call) throw new Error("request not built");
  return call;
};

Deno.test("Claude requests use the Messages API with the documented headers", () => {
  const call = build(request("claude-sonnet-5-5"));
  assertEquals(call.url, "https://api.anthropic.com/v1/messages");
  assertEquals(call.headers, {
    "content-type": "application/json",
    "x-api-key": syntheticKey,
    "anthropic-version": "2023-06-01",
  });
  assertEquals(call.body.model, "claude-sonnet-5-5");
  assertEquals(call.body.max_tokens, 2000);
});

Deno.test("no sampling parameters, tools or forced tool choice reach a Claude 5 model", () => {
  const json = { kind: "json" as const, schema: { type: "object", properties: {} } };
  for (const model of claudeModels) {
    // Opus 5.5 has no "off" route.
    for (const thinking of model === "claude-opus-5-5" ? ["adaptive"] : ["off", "adaptive"]) {
      for (const output of [{ kind: "text" as const }, json]) {
        const body = build(request(model, { THINKING: thinking, EFFORT: "high" }, { output })).body;
        for (const field of ["temperature", "top_p", "top_k", "tools", "tool_choice"]) {
          assertEquals(field in body, false, `${model} ${thinking} ${output.kind} ${field}`);
        }
      }
    }
  }
});

Deno.test("thinking maps per model", () => {
  const thinking = (model: string, setting: string) =>
    build(request(model, { THINKING: setting })).body.thinking;
  assertEquals(thinking("claude-haiku-5-5", "off"), { type: "disabled" });
  assertEquals(thinking("claude-sonnet-5-5", "off"), { type: "between_tools" });
  // Opus 5.5 rejects every way of turning thinking off; route() refuses "off", and a request
  // built around it is not sent.
  const opusOff = { ...routeFor("coach_chat", { MODEL: "claude-opus-5-5", THINKING: "adaptive" }) };
  assertEquals(
    anthropicAdapter.build(
      { ...request("claude-sonnet-5-5"), route: { ...opusOff, thinking: "off" } },
      spec("claude-opus-5-5"),
      syntheticKey,
    ),
    null,
  );
  for (const model of claudeModels) {
    assertEquals(thinking(model, "adaptive"), { type: "adaptive" });
  }
});

Deno.test("effort goes in output_config; no effort and text output send no output_config", () => {
  assertEquals(build(request("claude-haiku-5-5", { EFFORT: "medium" })).body.output_config, {
    effort: "medium",
  });
  assertEquals("output_config" in build(request("claude-haiku-5-5")).body, false);
});

Deno.test("JSON output uses output_config.format with a schema Claude accepts", () => {
  const schema = {
    type: "object",
    properties: {
      action: { type: "string", enum: ["PROCEED", "ADJUST"], maxLength: 10 },
      notes: { type: "array", minItems: 0, maxItems: 8, items: { type: "string", minLength: 1 } },
      picks: { type: "array", minItems: 2, items: { type: "integer", minimum: 0, maximum: 5 } },
      detail: {
        properties: { reason: { type: "string", format: "date-time" } },
        required: ["reason"],
      },
    },
    required: ["action", "notes", "picks", "detail"],
  };
  const body = build(
    request("claude-sonnet-5-5", { EFFORT: "low" }, { output: { kind: "json", schema } }),
  ).body;
  assertEquals(body.output_config, {
    effort: "low",
    format: {
      type: "json_schema",
      schema: {
        type: "object",
        properties: {
          action: { type: "string", enum: ["PROCEED", "ADJUST"] },
          notes: { type: "array", minItems: 0, items: { type: "string" } },
          picks: { type: "array", items: { type: "integer" } },
          // Properties without a type are an object schema too; format is removed.
          detail: {
            additionalProperties: false,
            properties: { reason: { type: "string" } },
            required: ["reason"],
          },
        },
        required: ["action", "notes", "picks", "detail"],
        additionalProperties: false,
      },
    },
  });
});

Deno.test("schemas Claude cannot take are refused before sending", () => {
  assertEquals(
    anthropicSchema({ type: "string", enum: ["a", 1, null, true], description: "kept" }),
    { type: "string", enum: ["a", 1, null, true], description: "kept" },
  );
  // A string with no object shape is not closed.
  assertEquals(anthropicSchema({ type: "string" }), { type: "string" });
  for (
    const schema of [
      { type: "object", additionalProperties: true },
      { type: "object", additionalProperties: { type: "number" } },
      { type: "array", items: { type: "object", additionalProperties: { type: "string" } } },
      { enum: [{ a: 1 }] },
      { enum: [["a"]] },
      { const: { a: 1 } },
      { anyOf: [{ type: "string" }, { type: "object", additionalProperties: true }] },
    ]
  ) {
    assertEquals(anthropicSchema(schema), null, JSON.stringify(schema));
    assertEquals(
      anthropicAdapter.build(
        request("claude-sonnet-5-5", {}, { output: { kind: "json", schema } }),
        spec("claude-sonnet-5-5"),
        syntheticKey,
      ),
      null,
      JSON.stringify(schema),
    );
  }
});

Deno.test("cache flags become cache_control on that block only; images are base64 blocks", () => {
  const body = build(request("claude-sonnet-5-5", {}, {
    messages: [{
      role: "user",
      content: [
        { type: "text", text: "Weekly summary.", cache: true },
        { type: "image", mediaType: "image/jpeg", base64: "c3ludGhldGlj" },
        { type: "text", text: "What is on the plate?" },
      ],
    }],
  })).body;
  assertEquals(body.system, [
    { type: "text", text: "Tracend rules.", cache_control: { type: "ephemeral" } },
    { type: "text", text: "Athlete file." },
  ]);
  assertEquals(body.messages, [{
    role: "user",
    content: [
      { type: "text", text: "Weekly summary.", cache_control: { type: "ephemeral" } },
      { type: "image", source: { type: "base64", media_type: "image/jpeg", data: "c3ludGhldGlj" } },
      { type: "text", text: "What is on the plate?" },
    ],
  }]);
});

Deno.test("more than four cache breakpoints cannot be sent", () => {
  const cached = { type: "text" as const, text: "x", cache: true };
  const req = request("claude-sonnet-5-5", {}, {
    system: [cached, cached, cached],
    messages: [{ role: "user", content: [cached, cached] }],
  });
  assertEquals(anthropicAdapter.build(req, spec(req.route.model), syntheticKey), null);
});

Deno.test("an answer maps text, stop reason, usage and model", () => {
  const answer = anthropicAdapter.read(claudeMessage({
    content: [
      { type: "thinking", thinking: "", signature: "sig" },
      { type: "text", text: "Train " },
      { type: "text", text: "as planned." },
    ],
  }, {
    input_tokens: 12,
    output_tokens: 34,
    cache_read_input_tokens: 56,
    cache_creation_input_tokens: 78,
  }));
  assertEquals(answer, {
    text: "Train as planned.",
    finish: "end",
    tokens: { inputTokens: 12, outputTokens: 34, cacheReadTokens: 56, cacheWriteTokens: 78 },
    model: "claude-sonnet-5-5",
  });
  const finish = (stop: string) =>
    anthropicAdapter.read(claudeMessage({ stop_reason: stop }))?.finish;
  assertEquals(finish("max_tokens"), "max_tokens");
  assertEquals(finish("refusal"), "refused");
  assertEquals(finish("tool_use"), "other");
  assertEquals(finish("model_context_window_exceeded"), "other");
  assertEquals(anthropicAdapter.read({ type: "error" }), null);
  // A billed answer with a broken shape keeps its usage.
  assertEquals(
    anthropicAdapter.read({ usage: { input_tokens: 5, output_tokens: 7 }, content: "oops" }),
    {
      text: "",
      finish: "other",
      tokens: { inputTokens: 5, outputTokens: 7, cacheReadTokens: 0, cacheWriteTokens: 0 },
      model: null,
    },
  );
});
