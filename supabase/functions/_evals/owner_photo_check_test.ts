import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  claudeMessage,
  envOf,
  fakeFetch,
  jsonResponse,
  syntheticKey,
} from "../_shared/ai/fakes.ts";
import { physiqueRules } from "../_shared/providers/physique_vision_provider.ts";
import golden from "../_shared/meal_vision/munch_label_golden.json" with { type: "json" };
import { plateAnswer } from "../_shared/meal_vision/test_fixtures.ts";
import { mealVisionInstructions } from "../meal-analyze/vision.ts";
import { type CheckIo, type FolderEntry, runOwnerPhotoCheck } from "./owner_photo_check.ts";

// Offline: a fake folder and a fake fetch. Nothing reads a real photo or reaches the network.
const jpeg = new Uint8Array([0xff, 0xd8, 0xff, 0xda, 0, 2, 0xff, 0xd9]);
const file = (name: string): FolderEntry => ({ name, isDirectory: false });
const directory = (name: string): FolderEntry => ({ name, isDirectory: true });

const dal = {
  name: "Dal tadka",
  serving_label: "1 bowl",
  calories: 220,
  protein_g: 11,
  carbohydrate_g: 28,
  fat_g: 8,
  confidence: "medium" as const,
  assumptions: ["Ghee on top is about 1 tsp"],
  question: "Was ghee added after cooking?",
};
const plate = (candidates: typeof dal[]) => JSON.stringify(plateAnswer(candidates));
const validPhysique = JSON.stringify({
  development_priorities: [
    { muscle: "chest", confidence: "medium", reason: "Upper chest looks less full than the arms." },
  ],
  observations: [],
  photo_issues: [],
  limitations: "Photos cannot show strength.",
});

function harness(
  tree: Record<string, FolderEntry[]>,
  respond: (text: string) => Response,
  env: Record<string, string> = { ANTHROPIC_API_KEY: syntheticKey },
) {
  const fake = fakeFetch(() => respond(""));
  const lines: string[] = [];
  const reads: string[] = [];
  const io: CheckIo = {
    env: envOf(env),
    fetch: fake.fetch,
    listDir: (path) => {
      const entries = tree[path];
      return entries ? Promise.resolve(entries) : Promise.reject(new Error(`no folder ${path}`));
    },
    readFile: (path) => {
      reads.push(path);
      return Promise.resolve(jpeg);
    },
    log: (line) => lines.push(line),
  };
  return { io, lines, reads, sent: fake.sent };
}

const answer = (text: string, model: string) =>
  jsonResponse(claudeMessage({ model, content: [{ type: "text", text }] }, {
    input_tokens: 3000,
    output_tokens: 300,
  }));

Deno.test("meal: each photo goes to Anthropic with the feature's own request and its parse is printed", async () => {
  const run = harness(
    { "/photos": [file("lunch.JPG"), file("notes.txt"), file("breakfast.jpg"), directory("old")] },
    () => answer(plate([dal]), "claude-haiku-5-5"),
  );
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos"], run.io), 0);

  assertEquals(run.reads, ["/photos/breakfast.jpg", "/photos/lunch.JPG"]);
  assertEquals(run.sent.length, 2);
  for (const sent of run.sent) {
    assertEquals(sent.url, "https://api.anthropic.com/v1/messages");
    assertEquals(sent.body.model, "claude-haiku-5-5");
    assertEquals(sent.body.max_tokens, 2000);
    assertStringIncludes(JSON.stringify(sent.body.system), mealVisionInstructions.slice(0, 60));
    assert(JSON.stringify(sent.body.messages).includes('"type":"image"'));
  }
  const output = run.lines.join("\n");
  assertStringIncludes(output, "Dal tadka | 1 bowl | 220 kcal");
  assertStringIncludes(output, "confidence medium | plate, estimate");
  assertStringIncludes(output, "asks: Was ghee added after cooking?");
  assertStringIncludes(output, "Done: 2 checked");
  // The key is sent as a header and never printed.
  assertEquals(run.sent[0].headers["x-api-key"], syntheticKey);
  assert(!output.includes(syntheticKey));
});

Deno.test("meal: no food is printed as such, and an unusable answer does not stop the rest", async () => {
  let calls = 0;
  const run = harness(
    { "/photos": [file("a.jpg"), file("b.jpg")] },
    () => {
      calls += 1;
      return answer(
        calls === 1 ? '{"candidates": ' : plate([]),
        "claude-haiku-5-5",
      );
    },
  );
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos"], run.io), 0);
  const output = run.lines.join("\n");
  assertStringIncludes(output, "no usable answer");
  assertStringIncludes(output, "no food found");
});

Deno.test("meal: a nutrition label prints its source, sizes and per-gram values", async () => {
  const run = harness(
    { "/photos": [file("label.jpg")] },
    () => answer(JSON.stringify(golden.answer), "claude-haiku-5-5"),
  );
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos"], run.io), 0);
  const output = run.lines.join("\n");
  assertStringIncludes(output, "Nestlé Munch Max Nuts | Whole pack (37.4 g) | 195.6 kcal");
  assertStringIncludes(output, "confidence high | nutrition_label, label");
  assertStringIncludes(output, "per g 5.23 kcal; serving 18.7 g, pack 37.4 g, 2 servings");
});

Deno.test("meal: stops before a call that could pass the spend cap", async () => {
  const run = harness(
    { "/photos": [file("a.jpg"), file("b.jpg")] },
    () => answer(plate([dal]), "claude-haiku-5-5"),
  );
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos", "--cap-usd", "0.001"], run.io), 3);
  assertEquals(run.sent.length, 0);
  assertStringIncludes(run.lines.join("\n"), "Stopped before a.jpg");
});

Deno.test("physique: a set goes through the feature's handler and the parsed result is printed", async () => {
  const run = harness(
    {
      "/sets": [directory("june"), file("readme.txt")],
      "/sets/june": [file("Front.jpg"), file("side.jpeg"), file("back.JPG")],
    },
    () => answer(validPhysique, "claude-sonnet-5-5"),
  );
  assertEquals(await runOwnerPhotoCheck(["physique", "/sets"], run.io), 0);

  assertEquals(run.sent.length, 1);
  const sent = run.sent[0];
  assertEquals(sent.body.model, "claude-sonnet-5-5");
  assertEquals(sent.body.max_tokens, 800);
  assertStringIncludes(JSON.stringify(sent.body.system), physiqueRules()[0].slice(0, 60));
  assertEquals(JSON.stringify(sent.body.messages).split('"type":"image"').length - 1, 3);
  const output = run.lines.join("\n");
  assertStringIncludes(output, '"muscle": "chest"');
  assertStringIncludes(output, "Done: 1 checked");
  assert(!output.includes(syntheticKey));
});

Deno.test("physique: a reply that breaks the contract is shown as refused, with the rule", async () => {
  const scored = validPhysique.replace(
    "Upper chest looks less full than the arms.",
    "Chest rated 6/10.",
  );
  const run = harness(
    {
      "/sets": [directory("june")],
      "/sets/june": [file("front.jpg"), file("side.jpg"), file("back.jpg")],
    },
    () => answer(scored, "claude-sonnet-5-5"),
  );
  assertEquals(await runOwnerPhotoCheck(["physique", "/sets"], run.io), 0);
  assertEquals(run.sent.length, 2);
  const output = run.lines.join("\n");
  assertStringIncludes(output, "no result stored: 502 physique_check_invalid");
});

Deno.test("physique: an incomplete set is refused before anything is sent", async () => {
  const run = harness(
    { "/sets": [directory("june")], "/sets/june": [file("front.jpg"), file("side.jpg")] },
    () => answer(validPhysique, "claude-sonnet-5-5"),
  );
  assertEquals(await runOwnerPhotoCheck(["physique", "/sets"], run.io), 2);
  assertEquals(run.sent.length, 0);
});

Deno.test("bad arguments or a missing key stop before any call", async () => {
  const none = harness({}, () => answer("{}", "claude-haiku-5-5"));
  assertEquals(await runOwnerPhotoCheck([], none.io), 2);
  assertEquals(await runOwnerPhotoCheck(["meal"], none.io), 2);
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos", "--cap-usd", "50"], none.io), 2);
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos", "--cap-usd", "0"], none.io), 2);
  const keyless = harness(
    { "/photos": [file("a.jpg")] },
    () => answer("{}", "claude-haiku-5-5"),
    {},
  );
  assertEquals(await runOwnerPhotoCheck(["meal", "/photos"], keyless.io), 2);
  assertEquals(keyless.sent.length + none.sent.length, 0);
});
