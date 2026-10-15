import { assertEquals } from "jsr:@std/assert@1";
import { routeFor, syntheticKey } from "../fakes.ts";
import { modelSpec, type OpenAiCompatibleModel } from "../models.ts";
import type { AiRequest } from "../types.ts";
import { openAiCompatibleAdapter } from "./openai_compatible.ts";

const deepseek = (values: Record<string, string> = {}) =>
  routeFor("daily_decision", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_DAILY_DECISION: syntheticKey,
    ...values,
  });

const groq = () =>
  routeFor("meal_vision", {
    PROVIDER: "openai_compatible",
    MODEL: "qwen/qwen3.8-27b",
    BASE_URL: "https://api.groq.com/openai/v1",
    OPENAI_COMPATIBLE_API_KEY_MEAL_VISION: syntheticKey,
  });

const build = (req: AiRequest) => {
  const spec = modelSpec("openai_compatible", req.route.model) as OpenAiCompatibleModel;
  const call = openAiCompatibleAdapter.build(req, spec, syntheticKey);
  if (!call) throw new Error("request not built");
  return call;
};

const textRequest = (route: AiRequest["route"], output: AiRequest["output"]): AiRequest => ({
  route,
  system: [{ type: "text", text: "Rules. ", cache: true }, { type: "text", text: "Return JSON." }],
  messages: [
    { role: "user", content: [{ type: "text", text: "Earlier question" }] },
    { role: "assistant", content: [{ type: "text", text: "Earlier answer" }] },
    { role: "user", content: [{ type: "text", text: "Today?" }] },
  ],
  output,
  consentProvider: "openai_compatible",
});

Deno.test("DeepSeek: chat completions, bearer key, JSON mode, thinking disabled for off", () => {
  const call = build(textRequest(deepseek(), { kind: "json", schema: { type: "object" } }));
  assertEquals(call.url, "https://api.deepseek.com/v1/chat/completions");
  assertEquals(call.headers, {
    "Content-Type": "application/json",
    Authorization: `Bearer ${syntheticKey}`,
  });
  assertEquals(call.body, {
    model: "deepseek-flash",
    max_tokens: 2000,
    thinking: { type: "disabled" },
    messages: [
      { role: "system", content: "Rules. Return JSON." },
      { role: "user", content: "Earlier question" },
      { role: "assistant", content: "Earlier answer" },
      { role: "user", content: "Today?" },
    ],
    response_format: { type: "json_object" },
  });
});

Deno.test("DeepSeek adaptive thinking sends the request the live Coach uses", () => {
  const body = build(textRequest(deepseek({ THINKING: "adaptive" }), { kind: "text" })).body;
  assertEquals(body.thinking, { type: "enabled" });
  assertEquals(body.reasoning_effort, "high");
  assertEquals("response_format" in body, false);
  assertEquals("temperature" in body, false);
});

Deno.test("Groq: max_completion_tokens, images as data URLs, no reasoning options", () => {
  const body = build({
    route: groq(),
    system: [],
    messages: [{
      role: "user",
      content: [
        { type: "text", text: "Identify the meal." },
        { type: "image", mediaType: "image/jpeg", base64: "c3ludGhldGlj" },
      ],
    }],
    output: { kind: "json", schema: { type: "object" } },
    consentProvider: "openai_compatible",
  }).body;
  assertEquals(body, {
    model: "qwen/qwen3.8-27b",
    max_completion_tokens: 2000,
    messages: [{
      role: "user",
      content: [
        { type: "text", text: "Identify the meal." },
        { type: "image_url", image_url: { url: "data:image/jpeg;base64,c3ludGhldGlj" } },
      ],
    }],
    response_format: { type: "json_object" },
  });
});

Deno.test("an answer maps content, finish reason and usage, cache hits apart", () => {
  const reply = (finish: string, usage: Record<string, unknown>) => ({
    model: "deepseek-flash",
    choices: [{ message: { role: "assistant", content: "{}" }, finish_reason: finish }],
    usage,
  });
  assertEquals(
    openAiCompatibleAdapter.read(reply("stop", {
      prompt_tokens: 1000,
      completion_tokens: 300,
      prompt_cache_hit_tokens: 800,
      prompt_cache_miss_tokens: 200,
    })),
    {
      text: "{}",
      finish: "end",
      tokens: { inputTokens: 200, outputTokens: 300, cacheReadTokens: 800, cacheWriteTokens: 0 },
      model: "deepseek-flash",
    },
  );
  assertEquals(
    openAiCompatibleAdapter.read(reply("length", {
      prompt_tokens: 500,
      completion_tokens: 50,
      prompt_tokens_details: { cached_tokens: 100 },
    }))?.tokens,
    { inputTokens: 400, outputTokens: 50, cacheReadTokens: 100, cacheWriteTokens: 0 },
  );
  assertEquals(openAiCompatibleAdapter.read(reply("length", {}))?.finish, "max_tokens");
  assertEquals(openAiCompatibleAdapter.read(reply("content_filter", {}))?.finish, "refused");
  assertEquals(openAiCompatibleAdapter.read(reply("tool_calls", {}))?.finish, "other");
  assertEquals(openAiCompatibleAdapter.read({ choices: [] }), null);
});
