import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  type PhysiqueCall,
  type PhysiquePhotos,
  PhysiqueVisionError,
  type PhysiqueVisionResolution,
} from "../_shared/providers/physique_vision_provider.ts";
import type { PhysiqueResult } from "../_shared/physique/contract.ts";
import {
  handlePhysiqueCheck,
  type PhysiqueDeps,
  type PhysiqueStore,
  type PhysiqueUsage,
} from "./handler.ts";

const owner = "0f6b3a1e-1111-4111-8111-111111111111";
const setId = "5a1c2b3d-2222-4222-8222-222222222222";
const ready: PhysiqueVisionResolution = {
  kind: "ready",
  config: { provider: "groq", label: "Groq", model: "qwen/qwen3.8-27b", apiKey: "test-key" },
};

const exif = [0xff, 0xe1, 0x00, 0x08, 0x47, 0x50, 0x53, 0x21, 0x21, 0x21];
const photo = new Uint8Array([0xff, 0xd8, ...exif, 0xff, 0xda, 0x00, 0x02, 0x01, 0xff, 0xd9]);

const valid = JSON.stringify({
  development_priorities: [
    { muscle: "chest", confidence: "medium", reason: "Upper chest looks less full than the arms." },
  ],
  observations: [],
  photo_issues: [],
  limitations: "Photos cannot show strength.",
});

function fakeStore(overrides: Partial<PhysiqueStore> = {}) {
  const calls = {
    persisted: [] as { result: PhysiqueResult; metadata: Record<string, unknown> }[],
    usage: [] as PhysiqueUsage[],
  };
  const store: PhysiqueStore = {
    grantedNotice: () => Promise.resolve("progress-photo-ai-v1"),
    budgetAvailable: () => Promise.resolve(true),
    profileNotes: () => Promise.resolve(["Old shoulder niggle"]),
    loadSet: () =>
      Promise.resolve({
        status: "complete",
        photos: ["front", "side", "back", "lower"].map((pose) => ({
          pose,
          objectKey: `${owner}/progress/${setId}/${pose}.jpg`,
        })),
      }),
    download: () => Promise.resolve(photo),
    athlete: () =>
      Promise.resolve({
        sex: "male",
        height_cm: 178,
        weight_kg: 82,
        waist_cm: null,
        chest_cm: null,
        hip_cm: null,
        arm_cm: null,
        thigh_cm: null,
        goal: "muscle_gain",
      }),
    persist: (_set, result, _model, _notice, metadata) => {
      calls.persisted.push({ result, metadata });
      return Promise.resolve("analysis-1");
    },
    recordUsage: (usage) => {
      calls.usage.push(usage);
      return Promise.resolve();
    },
    ...overrides,
  };
  return { store, calls };
}

const answering = (contents: string[], remainingTokens: number | null = null) => {
  const sent: (PhysiquePhotos | null)[] = [];
  const call = (
    _config: unknown,
    _athlete: unknown,
    photos: PhysiquePhotos | null,
  ): Promise<PhysiqueCall> => {
    sent.push(photos);
    return Promise.resolve({
      content: contents[sent.length - 1],
      inputUnits: photos ? 6800 : 900,
      outputUnits: 300,
      latencyMs: 9000,
      estimatedCostUsd: 0.007,
      remainingTokens,
    });
  };
  return { call: call as PhysiqueDeps["call"], sent };
};

async function run(
  store: PhysiqueStore,
  body: Record<string, unknown>,
  extra: Partial<PhysiqueDeps> = {},
) {
  const response = await handlePhysiqueCheck({
    userId: owner,
    store,
    resolution: ready,
    allowedUsers: new Set([owner]),
    observer: { info: () => {}, warn: () => {} },
    ...extra,
  }, body);
  return { status: response.status, body: await response.json() };
}

const check = { schema_version: "1.0", mode: "check", photo_set_id: setId };
const status = { schema_version: "1.0", mode: "status" };

Deno.test("status: only allowlisted accounts with the provider ready, never with an eating concern", async () => {
  assertEquals((await run(fakeStore().store, status)).body, {
    schema_version: "1.0",
    enabled: true,
    provider_label: "Groq",
  });
  assertEquals(
    (await run(fakeStore().store, status, { allowedUsers: new Set() })).body.enabled,
    false,
  );
  assertEquals(
    (await run(fakeStore().store, status, {
      resolution: { kind: "off", reason: "physique_vision_disabled" },
    })).body.enabled,
    false,
  );
  const concern = fakeStore({ profileNotes: () => Promise.resolve(["Recovering from bulimia"]) });
  assertEquals((await run(concern.store, status)).body.enabled, false);
  assertEquals((await run(concern.store, check)).status, 403);
});

Deno.test("a check needs the allowlist, the current notice, budget and a complete set", async () => {
  const never = (() => {
    throw new Error("no model call expected");
  }) as unknown as PhysiqueDeps["call"];
  const cases: [Partial<PhysiqueStore>, Partial<PhysiqueDeps>, number, string][] = [
    [{}, { allowedUsers: new Set() }, 403, "physique_check_unavailable"],
    [{ grantedNotice: () => Promise.resolve(null) }, {}, 403, "photo_ai_consent_required"],
    [{ budgetAvailable: () => Promise.resolve(false) }, {}, 429, "ai_usage_limit"],
    [{ loadSet: () => Promise.resolve(null) }, {}, 404, "photo_set_not_found"],
    [
      { loadSet: () => Promise.resolve({ status: "draft", photos: [] }) },
      {},
      404,
      "photo_set_not_found",
    ],
    [
      { download: () => Promise.resolve(new Uint8Array([0x89, 0x50, 0x4e, 0x47])) },
      {},
      422,
      "photo_set_unsupported",
    ],
    [
      { download: () => Promise.resolve(new Uint8Array(3_100_000).fill(0)) },
      {},
      422,
      "photo_set_unsupported",
    ],
    [{ download: () => Promise.resolve(null) }, {}, 503, "physique_check_failed"],
  ];
  for (const [overrides, extra, code, error] of cases) {
    const { store, calls } = fakeStore(overrides);
    const result = await run(store, check, { call: never, ...extra });
    assertEquals([result.status, result.body.error], [code, error]);
    assertEquals(calls.usage.length, 0);
  }
  assertEquals(
    (await run(fakeStore().store, { ...check, photo_set_id: "nope" })).status,
    422,
  );
});

Deno.test("a valid answer is stored with its telemetry; the photos leave without metadata", async () => {
  const { store, calls } = fakeStore();
  const model = answering([valid]);
  const result = await run(store, check, { call: model.call });
  assertEquals(result.status, 200);
  assertEquals(result.body.analysis_id, "analysis-1");
  assertEquals(result.body.result.development_priorities[0].muscle, "chest");
  assertEquals(calls.persisted[0].metadata.attempts, 1);
  assertEquals(calls.usage.length, 1);
  const sent = model.sent[0]!;
  for (const bytes of [sent.front, sent.side, sent.back]) {
    assert(!new TextDecoder().decode(bytes).includes("GPS"));
  }
});

Deno.test("a broken reply gets one text-only correction when the minute has room", async () => {
  const { store, calls } = fakeStore();
  const broken = valid.replace("Photos cannot show strength.", "About 15% body fat.");
  const model = answering([broken, valid], 4000);
  const result = await run(store, check, { call: model.call });
  assertEquals(result.status, 200);
  assertEquals(model.sent[1], null);
  assertEquals(calls.persisted[0].metadata.first_rule_broken, "body_composition_figure");
  assertEquals(calls.persisted[0].metadata.attempts, 2);
  assertEquals(calls.usage.length, 2);
});

Deno.test("without room, a broken reply stores nothing but its tokens are counted", async () => {
  const { store, calls } = fakeStore();
  const model = answering(["not json"], 900);
  const result = await run(store, check, { call: model.call });
  assertEquals([result.status, result.body.error], [502, "physique_check_invalid"]);
  assertEquals(model.sent.length, 1);
  assertEquals(calls.persisted.length, 0);
  assertEquals(calls.usage.length, 1);
});

Deno.test("Groq busy answers 429 and records nothing", async () => {
  const { store, calls } = fakeStore();
  const busy =
    (() => Promise.reject(new PhysiqueVisionError("physique_vision_busy"))) as PhysiqueDeps["call"];
  const result = await run(store, check, { call: busy });
  assertEquals([result.status, result.body.error], [429, "physique_check_busy"]);
  assertEquals(calls.usage.length, 0);
});

Deno.test("a failed usage record never fails a stored answer", async () => {
  const warnings: string[] = [];
  const { store, calls } = fakeStore({ recordUsage: () => Promise.reject(new Error("down")) });
  const result = await run(store, check, {
    call: answering([valid]).call,
    observer: { info: () => {}, warn: (event) => warnings.push(event) },
  });
  assertEquals(result.status, 200);
  assertEquals(calls.persisted.length, 1);
  assertEquals(warnings, ["physique_check_usage_not_recorded"]);
});

Deno.test("usage is recorded before storing, so a failed store still counts the call", async () => {
  const order: string[] = [];
  const { store } = fakeStore({
    recordUsage: () => {
      order.push("usage");
      return Promise.resolve();
    },
    persist: () => {
      order.push("persist");
      return Promise.reject(new Error("database down"));
    },
  });
  let failed = false;
  try {
    await run(store, check, { call: answering([valid]).call });
  } catch {
    failed = true;
  }
  assert(failed);
  assertEquals(order, ["usage", "persist"]);
});
