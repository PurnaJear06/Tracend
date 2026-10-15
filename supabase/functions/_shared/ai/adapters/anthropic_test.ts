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
    consentProvider: "anthropic",
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
    for (const thinking of ["off", "adaptive"]) {
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
  // Opus 5.5 rejects every way of turning thinking off: the field is left out.
  assertEquals(thinking("claude-opus-5-5", "off"), undefined);
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
        type: "object",
        additionalProperties: true,
        properties: { reason: { type: "string" } },
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
          detail: {
            type: "object",
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

Deno.test("anthropicSchema keeps data values as they are", () => {
  assertEquals(
    anthropicSchema({ type: "string", enum: [{ maxLength: 1 }], examples: [{ minimum: 1 }] }),
    { type: "string", enum: [{ maxLength: 1 }], examples: [{ minimum: 1 }] },
  );
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
});
