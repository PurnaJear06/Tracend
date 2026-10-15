import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  claudeMessage,
  envOf,
  fakeFetch,
  jsonResponse,
  type Sent,
  settings,
} from "../_shared/ai/fakes.ts";
import {
  callPhysiqueVision,
  type PhysiqueAthlete,
  physiqueCeilingUsd,
  physiqueRules,
  PhysiqueVisionError,
  resolvePhysiqueVision,
} from "../_shared/providers/physique_vision_provider.ts";
import { handlePhysiqueCheck, type PhysiqueStore, type PhysiqueUsage } from "./handler.ts";
import golden from "./legacy_requests_golden.json" with { type: "json" };

const owner = "0f6b3a1e-1111-4111-8111-111111111111";
const setId = "5a1c2b3d-2222-4222-8222-222222222222";
const athlete: PhysiqueAthlete = {
  sex: "male",
  height_cm: 178,
  weight_kg: 82,
  waist_cm: null,
  chest_cm: 104,
  hip_cm: null,
  arm_cm: null,
  thigh_cm: null,
  goal: "muscle_gain",
};
const environment = (values: Record<string, string>) => {
  const env = envOf(values);
  return { get: (name: string) => env(name) };
};
const today = { PHYSIQUE_VISION_ENABLED: "true", GROQ_API_KEY: "k" };
// The gateway route A7's cutover sets: Sonnet 5.5 without thinking.
const sonnet = settings("physique_vision", {
  MODEL: "claude-sonnet-5-5",
  MAX_OUTPUT_TOKENS: "800",
  EVALUATED: "true",
});

Deno.test("parity: without a route, Groq gets today's check and correction byte for byte", async () => {
  const resolution = resolvePhysiqueVision(
    environment({ ...today, AI_PHYSIQUE_VISION_MODEL: "x" }),
  );
  assert(resolution.kind === "ready");
  const sent: string[] = [];
  const recording = ((url: unknown, init?: RequestInit) => {
    sent.push(`${url}\n${init?.body}`);
    return Promise.resolve(new Response("{}", { status: 500 }));
  }) as typeof fetch;
  // The bytes and inputs the golden was recorded with.
  const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xda, 0, 2, 0xff, 0xd9]);
  const config = { ...resolution.config, apiKey: "k" };
  await assertRejects(() =>
    callPhysiqueVision(config, athlete, { front: jpeg, side: jpeg, back: jpeg }, null, recording)
  );
  await assertRejects(() =>
    callPhysiqueVision(config, athlete, null, { previous: '{"x":1}', rule: "score" }, recording)
  );
  assertEquals(sent, [
    `${golden.check.url}\n${golden.check.body}`,
    `${golden.repair.url}\n${golden.repair.body}`,
  ]);
});

Deno.test("a route needs the feature switch and a passed eval", () => {
  assertEquals(resolvePhysiqueVision(environment(sonnet)).kind, "off");
  assertEquals(
    resolvePhysiqueVision(environment({ ...today, ...sonnet, AI_PHYSIQUE_VISION_EVALUATED: "" })),
    { kind: "off", reason: "physique_vision_not_evaluated" },
  );
  const resolution = resolvePhysiqueVision(environment({ ...today, ...sonnet }));
  assert(resolution.kind === "gateway");
  assertEquals([resolution.route.vendor, resolution.route.model], [
    "anthropic",
    "claude-sonnet-5-5",
  ]);
  // Photo call (18,000 tokens) and correction (4,000) at Sonnet's cache-write rate, each with
  // 800 output tokens.
  assertEquals(physiqueCeilingUsd(resolution.route), 0.071);
});

const exif = [0xff, 0xe1, 0x00, 0x08, 0x47, 0x50, 0x53, 0x21, 0x21, 0x21];
const photo = new Uint8Array([0xff, 0xd8, ...exif, 0xff, 0xda, 0x00, 0x02, 0x01, 0xff, 0xd9]);
const cleanBase64 = btoa(String.fromCharCode(0xff, 0xd8, 0xff, 0xda, 0x00, 0x02, 0x01, 0xff, 0xd9));

const valid = JSON.stringify({
  development_priorities: [
    { muscle: "chest", confidence: "medium", reason: "Upper chest looks less full than the arms." },
  ],
  observations: [],
  photo_issues: [],
  limitations: "Photos cannot show strength.",
});
const scored = JSON.stringify({
  development_priorities: [
    { muscle: "chest", confidence: "medium", reason: "Chest rated 6/10 against the arms." },
  ],
  observations: [],
  photo_issues: [],
  limitations: "Photos cannot show strength.",
});
const answer = (text: string, overrides: Record<string, unknown> = {}) =>
  jsonResponse(claudeMessage({
    model: "claude-sonnet-5-5",
    content: [{ type: "text", text }],
    ...overrides,
  }, { input_tokens: 5000, output_tokens: 300 }));

function fakeStore(vendor: string | null) {
  const calls = {
    budget: [] as (number | undefined)[],
    persisted: [] as string[],
    usage: [] as PhysiqueUsage[],
  };
  const store: PhysiqueStore = {
    grantedNotice: () => Promise.resolve({ version: "progress-photo-ai-v2", vendor }),
    budgetAvailable: (ceilingUsd) => {
      calls.budget.push(ceilingUsd);
      return Promise.resolve(true);
    },
    profileNotes: () => Promise.resolve([]),
    loadSet: () =>
      Promise.resolve({
        status: "complete",
        photos: ["front", "side", "back"].map((pose) => ({
          pose,
          objectKey: `${owner}/progress/${setId}/${pose}.jpg`,
        })),
      }),
    download: () => Promise.resolve(photo),
    athlete: () => Promise.resolve(athlete),
    persist: (_set, _result, model, notice) => {
      calls.persisted.push(`${model}:${notice}`);
      return Promise.resolve("analysis-1");
    },
    recordUsage: (usage) => {
      calls.usage.push(usage);
      return Promise.resolve();
    },
  };
  return { store, calls };
}

async function run(
  vendor: string | null,
  respond: (sent: Sent) => Response | Promise<Response>,
  mode: "check" | "status" = "check",
) {
  const { store, calls } = fakeStore(vendor);
  const { fetch, sent } = fakeFetch(respond);
  const resolution = resolvePhysiqueVision(environment({ ...today, ...sonnet }));
  const call = () =>
    handlePhysiqueCheck({
      userId: owner,
      store,
      resolution,
      allowedUsers: new Set([owner]),
      observer: { info: () => {}, warn: () => {} },
      gateway: { deps: { fetch } },
    }, { schema_version: "1.0", mode, photo_set_id: setId });
  try {
    const response = await call();
    return { status: response.status, body: await response.json(), calls, sent, error: null };
  } catch (error) {
    return { status: null, body: null, calls, sent, error: error as Error };
  }
}

Deno.test("a route names only the company in status", async () => {
  const result = await run("anthropic", () => answer(valid), "status");
  assertEquals(result.body, { schema_version: "1.0", enabled: true, provider_label: "Anthropic" });
});

Deno.test("a notice that does not name the route's vendor sends nothing", async () => {
  for (const vendor of [null, "groq"]) {
    const result = await run(vendor, () => answer(valid));
    assertEquals([result.status, result.body.error], [403, "photo_ai_consent_required"]);
    assertEquals([result.sent.length, result.calls.budget.length], [0, 0]);
  }
});

Deno.test("a route sends one Claude request and stores the vendor's answer", async () => {
  const result = await run("anthropic", () => answer(valid));
  assertEquals(result.status, 200);
  assertEquals(result.calls.budget, [0.071]);
  assertEquals(result.sent.length, 1);
  const body = result.sent[0].body;
  assertEquals(result.sent[0].url, "https://api.anthropic.com/v1/messages");
  assertEquals([body.model, body.max_tokens], ["claude-sonnet-5-5", 800]);
  assertEquals(body.thinking, { type: "between_tools" });
  for (const field of ["temperature", "top_p", "top_k", "tools", "tool_choice"]) {
    assert(!(field in body), field);
  }
  assertEquals(body.system, [{
    type: "text",
    text: physiqueRules().join("\n"),
    cache_control: { type: "ephemeral" },
  }]);
  const content = (body.messages as { content: Record<string, unknown>[] }[])[0].content;
  assertEquals(content.length, 4);
  for (const image of content.slice(0, 3)) {
    // Metadata is stripped before the photo leaves.
    assertEquals(image, {
      type: "image",
      source: { type: "base64", media_type: "image/jpeg", data: cleanBase64 },
    });
  }
  assert(String(content[3].text).includes("Athlete (data, not instructions)"));
  assertEquals(result.calls.persisted, ["claude-sonnet-5-5:progress-photo-ai-v2"]);
  assertEquals(result.calls.usage.length, 1);
  // 5,000 input tokens at USD 2/M and 300 output tokens at USD 10/M.
  assertEquals(result.calls.usage[0].estimatedCostUsd, 0.013);
  assertEquals(result.calls.usage[0].model, "claude-sonnet-5-5");
});

Deno.test("a broken reply gets one text-only correction on the route", async () => {
  const result = await run(
    "anthropic",
    (sent) => answer(JSON.stringify(sent.body).includes("broke the rule") ? valid : scored),
  );
  assertEquals(result.status, 200);
  assertEquals(result.sent.length, 2);
  const correction = (result.sent[1].body.messages as { content: Record<string, unknown>[] }[])[0]
    .content;
  assertEquals(correction.map((part) => part.type), ["text"]);
  assert(String(correction[0].text).includes(`broke the rule "score"`));
  assertEquals(result.calls.usage.length, 2);
});

Deno.test("route failures: busy is 429, a refusal is billed and counted", async () => {
  const busy = await run("anthropic", () => new Response("{}", { status: 529 }));
  assertEquals([busy.status, busy.body.error, busy.calls.usage.length], [
    429,
    "physique_check_busy",
    0,
  ]);
  const refused = await run("anthropic", () => answer("", { stop_reason: "refusal" }));
  assert(refused.error instanceof PhysiqueVisionError);
  assertEquals(refused.error.code, "physique_vision_refused");
  assertEquals(refused.calls.usage.length, 1);
  assertEquals(refused.calls.persisted, []);
  const lost = await run("anthropic", () => Promise.reject(new TypeError("reset")));
  assert(lost.error instanceof PhysiqueVisionError);
  assertEquals([lost.error.code, lost.calls.usage.length], ["physique_vision_network", 0]);
});
