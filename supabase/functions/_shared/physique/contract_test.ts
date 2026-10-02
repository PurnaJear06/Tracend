import { assertEquals } from "jsr:@std/assert@1.0.14";
import { capConfidence, parsePhysiqueResult } from "./contract.ts";

const reply = (overrides: Record<string, unknown> = {}) =>
  JSON.stringify({
    development_priorities: [
      {
        muscle: "chest",
        confidence: "high",
        reason: "Upper chest looks less full than the shoulders.",
      },
      { muscle: "calves", confidence: "medium", reason: "Calves look small next to the thighs." },
    ],
    observations: ["Back width is a clear strength."],
    photo_issues: [],
    limitations: "Photos cannot show strength or how muscles were trained.",
    ...overrides,
  });

Deno.test("a valid reply keeps the model's assessment", () => {
  const parsed = parsePhysiqueResult(reply());
  assertEquals(parsed.ok, true);
  if (!parsed.ok) return;
  assertEquals(parsed.result.schema_version, "1.0");
  assertEquals(parsed.result.development_priorities.map((p) => p.muscle), ["chest", "calves"]);
  assertEquals(parsed.result.development_priorities[0].confidence, "high");
});

Deno.test("photo issues lower confidence", () => {
  assertEquals(capConfidence("high", 1), "medium");
  assertEquals(capConfidence("medium", 1), "medium");
  assertEquals(capConfidence("high", 2), "low");
  const parsed = parsePhysiqueResult(reply({ photo_issues: ["lighting"] }));
  assertEquals(parsed.ok && parsed.result.development_priorities[0].confidence, "medium");
});

Deno.test("any broken rule rejects the whole reply", () => {
  const cases: [string, string][] = [
    ["not json", "not_json"],
    ["[]", "not_object"],
    [reply({ body_fat: "15%" }), "unexpected_keys"],
    [reply({ development_priorities: [] }), "priority_count"],
    [
      reply({
        development_priorities: [{ muscle: "forearms", confidence: "low", reason: "Small." }],
      }),
      "unknown_muscle",
    ],
    [
      reply({
        development_priorities: [
          { muscle: "chest", confidence: "low", reason: "A." },
          { muscle: "chest", confidence: "low", reason: "B." },
        ],
      }),
      "duplicate_muscle",
    ],
    [
      reply({
        development_priorities: [{ muscle: "chest", confidence: "sure", reason: "Small." }],
      }),
      "confidence",
    ],
    [
      reply({
        development_priorities: [{ muscle: "chest", confidence: "low", reason: "x".repeat(121) }],
      }),
      "reason_length",
    ],
    [reply({ photo_issues: ["dark"] }), "photo_issues"],
    [reply({ observations: ["a", "b", "c", "d"] }), "observations"],
    [reply({ limitations: "" }), "limitations"],
    [reply({ observations: ["Around 18% body fat."] }), "body_composition_figure"],
    [reply({ observations: ["Some visible fat around the waist."] }), "body_composition_figure"],
    [reply({ observations: ["Overall physique 7/10."] }), "score"],
    [reply({ observations: ["A very attractive build."] }), "appearance_judgement"],
    [reply({ observations: ["Signs of gynecomastia."] }), "medical"],
    [reply({ limitations: "Skin tone made lighting hard to judge." }), "sensitive_trait"],
    [reply({ observations: ["Cut calories to show the abs."] }), "eating"],
  ];
  for (const [content, rule] of cases) {
    assertEquals(parsePhysiqueResult(content), { ok: false, rule }, content);
  }
});

Deno.test("ordinary words that contain refused ones are allowed", () => {
  const parsed = parsePhysiqueResult(reply({
    observations: ["The photo angle shows the shoulders well.", "Average image quality."],
    limitations: "Photos cannot show strength; the shot hides the lower back.",
  }));
  assertEquals(parsed.ok, true);
});
