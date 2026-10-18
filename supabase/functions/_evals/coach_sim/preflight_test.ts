// The preflight picks a working request per model, or stops the run. Stubbed router, no network.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  decidePreflight,
  idCandidates,
  preflightChat,
  preflightCoach,
  renderPreflight,
} from "./preflight.ts";
import { coachChatGatewaySchema } from "../../_shared/providers/coach_chat_provider_gateway.ts";
import { chatModes, structuredMode } from "./wire.ts";

// Built at run time so the repository holds no key-shaped literal.
const key = `sk-nry-${"a1B2c3D4".repeat(4)}`;
const route = { baseUrl: "https://router.example/v1", apiKey: key };

const completion = (content: string, finish = "stop") =>
  new Response(
    JSON.stringify({
      model: "served",
      choices: [{ message: { role: "assistant", content }, finish_reason: finish }],
      usage: { prompt_tokens: 20, completion_tokens: 8 },
    }),
    { status: 200 },
  );

const rejection = (status: number, message: string) =>
  new Response(JSON.stringify({ error: { type: "validation_error", message } }), { status });

type Sent = Record<string, unknown>;

/** A router that answers by what the request carries; records the bodies it was sent. */
function router(answer: (body: Sent) => Response) {
  const sent: Sent[] = [];
  const fetcher = ((_input: string | URL | Request, init?: RequestInit) => {
    const body = JSON.parse(String(init?.body));
    sent.push(body);
    return Promise.resolve(answer(body));
  }) as typeof fetch;
  return { fetcher, sent };
}

Deno.test("the run's own mode is kept when it works, after one request", async () => {
  const { fetcher, sent } = router(() => completion('{"ok": true}'));
  const result = await preflightCoach({
    ...route,
    fetcher,
    candidates: ["claude-haiku-5.5"],
  });
  assertEquals(result.working?.model, "claude-haiku-5.5");
  assertEquals(result.working?.mode.responseFormat, true);
  assertEquals(sent.length, 1);
  // The request is the gateway's, rewritten for Claude: JSON mode, no thinking, no temperature.
  assertEquals(sent[0].model, "claude-haiku-5.5");
  assertEquals(sent[0].response_format, { type: "json_object" });
  assertEquals(sent[0].thinking, undefined);
  assertEquals(sent[0].temperature, undefined);
  assert(decidePreflight([result]).proceed);
});

Deno.test("when the router rejects response_format for Claude, the plain-text mode is chosen and reported", async () => {
  const { fetcher, sent } = router((body) =>
    body.response_format
      ? rejection(400, `response_format is not supported for this model (key ${key})`)
      : completion('Sure, here you go:\n```json\n{"ok": true}\n```')
  );
  const result = await preflightCoach({ ...route, fetcher, candidates: ["claude-haiku-5.5"] });
  assertEquals(result.working?.mode, { responseFormat: false, maxTokensField: "max_tokens" });
  assertEquals(result.attempts.map((a) => [a.ok, a.status]), [[false, 400], [true, 200]]);
  assertStringIncludes(result.attempts[0].detail, "response_format is not supported");
  assert(!JSON.stringify(result).includes("sk-nry"), "the key must not be recorded");
  assertEquals(sent[1].response_format, undefined);
  const lines = renderPreflight([result]).join("\n");
  assertStringIncludes(lines, "plain text, JSON asked in the prompt");
  assertStringIncludes(lines, "HTTP 400");
});

Deno.test("another spelling of the model id and max_completion_tokens are tried", async () => {
  const { fetcher } = router((body) =>
    body.model !== "anthropic/claude-haiku-5.5"
      ? rejection(404, "model not found")
      : "max_tokens" in body
      ? rejection(400, "Unsupported parameter: max_tokens. Use max_completion_tokens.")
      : completion('{"ok": true}')
  );
  const candidates = idCandidates(
    ["gpt-5", "anthropic/claude-haiku-5.5", "claude-haiku-5-5"],
    "claude-haiku-5.5",
  );
  // The listed spellings come first, then the usual ones the listing does not show.
  assertEquals(candidates.slice(0, 3), [
    "claude-haiku-5.5",
    "anthropic/claude-haiku-5.5",
    "claude-haiku-5-5",
  ]);
  assertEquals(new Set(candidates).size, candidates.length);
  const result = await preflightCoach({ ...route, fetcher, candidates });
  assertEquals(result.working, {
    model: "anthropic/claude-haiku-5.5",
    mode: { responseFormat: true, maxTokensField: "max_completion_tokens" },
  });
});

Deno.test("a finish reason the gateway would refuse is no pass; Claude's own end_turn is translated", async () => {
  const odd = router(() => completion('{"ok": true}', "weird_reason"));
  const refused = await preflightCoach({
    ...route,
    fetcher: odd.fetcher,
    candidates: ["m"],
    modes: [{ responseFormat: true, maxTokensField: "max_tokens" }],
  });
  assertEquals(refused.working, null);
  assertStringIncludes(refused.attempts[0].detail, "finish_reason=weird_reason");

  const claude = router(() => completion('{"ok": true}', "end_turn"));
  const accepted = await preflightCoach({ ...route, fetcher: claude.fetcher, candidates: ["m"] });
  assert(accepted.working);
});

Deno.test("with no working request the preflight says which model failed, with the status and body, and the run does not start", async () => {
  const { fetcher } = router(() => rejection(403, "plan does not include claude-haiku-5.5"));
  const coach = await preflightCoach({ ...route, fetcher, candidates: ["claude-haiku-5.5"] });
  assertEquals(coach.working, null);
  assertEquals(coach.attempts.length, 4);
  assert(coach.attempts.every((a) => a.status === 403));
  const athlete = await preflightChat({
    ...route,
    fetcher: router(() => completion('{"ok": true}')).fetcher,
    role: "athlete",
    model: "deepseek-v4-flash",
  });
  assert(athlete.working);
  const decision = decidePreflight([coach, athlete]);
  assertEquals(decision.proceed, false);
  assertStringIncludes((decision as { message: string }).message, "coach `claude-haiku-5.5`");
  assert(!(decision as { message: string }).message.includes("athlete"));
  assertStringIncludes(renderPreflight([coach]).join("\n"), "HTTP 403");
  assertStringIncludes(renderPreflight([coach]).join("\n"), "NO WORKING REQUEST");
});

Deno.test("the judge and the athlete are checked the way the run asks them", async () => {
  const { fetcher, sent } = router((body) =>
    body.response_format ? rejection(400, "json mode unsupported") : completion('{"ok": true}')
  );
  const judge = await preflightChat({
    ...route,
    fetcher,
    role: "judge",
    model: "claude-sonnet-5.5",
  });
  assertEquals(judge.working?.mode.responseFormat, false);
  assertEquals(sent[0].response_format, { type: "json_object" });
  assertEquals(judge.attempts.map((a) => a.status), [400, 200]);
});

Deno.test("the Coach is asked with the answer schema first and keeps it when the router takes it", async () => {
  const schema = coachChatGatewaySchema();
  const { fetcher, sent } = router(() => completion('{"ok": true}'));
  const result = await preflightCoach({
    ...route,
    fetcher,
    schema,
    modes: [structuredMode, ...chatModes],
    candidates: ["claude-sonnet-5.5"],
  });
  assertEquals(result.working?.mode, structuredMode);
  assertEquals(sent.length, 1);
  assertEquals((sent[0].response_format as { type: string }).type, "json_schema");
  const lines = renderPreflight([result]).join("\n");
  assertStringIncludes(lines, "structured output");
  assert(!lines.includes("first mode tried failed"), lines);
});

Deno.test("a router that rejects json_schema falls back to the JSON object mode", async () => {
  const { fetcher } = router((body) =>
    (body.response_format as { type: string }).type === "json_schema"
      ? rejection(400, "json_schema is not supported")
      : completion('{"ok": true}')
  );
  const result = await preflightCoach({
    ...route,
    fetcher,
    schema: coachChatGatewaySchema(),
    modes: [structuredMode, ...chatModes],
    candidates: ["claude-sonnet-5.5"],
  });
  assertEquals(result.working?.mode, chatModes[0]);
  assertEquals(result.attempts.map((a) => [a.ok, a.status]), [[false, 400], [true, 200]]);
  assertStringIncludes(renderPreflight([result]).join("\n"), "first mode tried failed");
});
