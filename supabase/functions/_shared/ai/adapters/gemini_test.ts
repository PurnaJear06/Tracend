import { assertEquals } from "jsr:@std/assert@1";
import { routeFor, syntheticKey } from "../fakes.ts";
import { type GeminiModel, modelSpec } from "../models.ts";
import type { AiRequest } from "../types.ts";
import { geminiAdapter } from "./gemini.ts";

const gemini = (values: Record<string, string> = {}) =>
  routeFor("physique_vision", {
    PROVIDER: "gemini",
    MODEL: "gemini-3.5-flash",
    GEMINI_API_KEY: syntheticKey,
    GEMINI_PAID_DATA_TERMS_ACCEPTED: "true",
    ...values,
  });

const build = (req: AiRequest) => {
  const call = geminiAdapter.build(
    req,
    modelSpec("gemini", req.route.model) as GeminiModel,
    syntheticKey,
  );
  if (!call) throw new Error("request not built");
  return call;
};

const request = (route: AiRequest["route"], output: AiRequest["output"]): AiRequest => ({
  route,
  system: [{ type: "text", text: "Rules. ", cache: true }, { type: "text", text: "Be brief." }],
  messages: [
    { role: "user", content: [{ type: "text", text: "Earlier" }] },
    { role: "assistant", content: [{ type: "text", text: "Reply" }] },
    {
      role: "user",
      content: [
        { type: "text", text: "Compare." },
        { type: "image", mediaType: "image/jpeg", base64: "c3ludGhldGlj" },
      ],
    },
  ],
  output,
  consentProvider: "gemini",
});

Deno.test("Gemini: generateContent, key header, system instruction, roles and inline images", () => {
  const schema = { type: "object", properties: { a: { type: "string" } } };
  const call = build(request(gemini(), { kind: "json", schema }));
  assertEquals(
    call.url,
    "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.5-flash:generateContent",
  );
  assertEquals(call.headers, {
    "Content-Type": "application/json",
    "x-goog-api-key": syntheticKey,
  });
  assertEquals(call.body, {
    contents: [
      { role: "user", parts: [{ text: "Earlier" }] },
      { role: "model", parts: [{ text: "Reply" }] },
      {
        role: "user",
        parts: [{ text: "Compare." }, {
          inlineData: { mimeType: "image/jpeg", data: "c3ludGhldGlj" },
        }],
      },
    ],
    generationConfig: {
      maxOutputTokens: 2000,
      thinkingConfig: { thinkingLevel: "low" },
      responseMimeType: "application/json",
      responseJsonSchema: schema,
    },
    systemInstruction: { parts: [{ text: "Rules. Be brief." }] },
  });
});

Deno.test("Gemini thinking: off is low, adaptive follows effort (medium by default)", () => {
  const level = (values: Record<string, string>) =>
    (build(request(gemini(values), { kind: "text" })).body.generationConfig as Record<
      string,
      Record<string, unknown>
    >).thinkingConfig.thinkingLevel;
  assertEquals(level({}), "low");
  assertEquals(level({ THINKING: "adaptive" }), "medium");
  assertEquals(level({ THINKING: "adaptive", EFFORT: "high" }), "high");
  const config = build(request(gemini(), { kind: "text" })).body.generationConfig as Record<
    string,
    unknown
  >;
  assertEquals("temperature" in config, false);
  assertEquals("responseMimeType" in config, false);
});

Deno.test("an answer skips thought parts, bills thoughts as output and separates cached input", () => {
  const answer = geminiAdapter.read({
    modelVersion: "gemini-3.5-flash",
    candidates: [{
      content: { parts: [{ text: "thinking...", thought: true }, { text: "Answer" }] },
      finishReason: "STOP",
    }],
    usageMetadata: {
      promptTokenCount: 1000,
      cachedContentTokenCount: 600,
      candidatesTokenCount: 40,
      thoughtsTokenCount: 160,
    },
  });
  assertEquals(answer, {
    text: "Answer",
    finish: "end",
    tokens: { inputTokens: 400, outputTokens: 200, cacheReadTokens: 600, cacheWriteTokens: 0 },
    model: "gemini-3.5-flash",
  });
  const finish = (reason: string) =>
    geminiAdapter.read({ candidates: [{ content: { parts: [] }, finishReason: reason }] })?.finish;
  assertEquals(finish("MAX_TOKENS"), "max_tokens");
  assertEquals(finish("SAFETY"), "refused");
  assertEquals(finish("MALFORMED_FUNCTION_CALL"), "other");
  assertEquals(
    geminiAdapter.read({ promptFeedback: { blockReason: "SAFETY" }, usageMetadata: {} })?.finish,
    "refused",
  );
  assertEquals(geminiAdapter.read({}), null);
});
