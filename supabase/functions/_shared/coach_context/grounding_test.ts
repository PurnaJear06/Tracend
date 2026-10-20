import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { replyCheckInputsFor } from "../providers/coach_chat_provider.ts";
import { evalProfiles } from "../../_evals/fixtures.ts";
import { noCoachContributions } from "./host.ts";
import { contributorGrounding, groundingOf } from "./grounding.ts";
import { coachContextContributors } from "./registry.ts";

Deno.test("every registered contributor declares what it may ground, and nothing else is declared", () => {
  assertEquals(
    Object.keys(contributorGrounding).sort(),
    coachContextContributors.map((contributor) => contributor.id).sort(),
  );
  assertEquals(groundingOf("library"), "excluded");
  assertEquals(groundingOf("coaching_principles"), "guidance");
  // An id nobody declared grounds nothing.
  assertEquals(groundingOf("some_new_block"), "excluded");
});

const contributions = (
  texts: Record<string, string>,
  records: Record<string, readonly string[]> = {},
) => ({ ...noCoachContributions, texts, records });

Deno.test("library text grounds nothing here, the principles digest only as guidance, other blocks as records", () => {
  const context = { coaching_date: "2026-10-17", permitted_evidence: [] };
  const inputs = replyCheckInputsFor(
    context,
    "How much protein?",
    contributions({
      library: "Excerpt: 1.9 g per kg",
      coaching_principles: "Guidance: 1.6 g per kg",
      watch_outs: "Recovery score 31 on 2026-10-17 (below 40)",
    }, { watch_outs: ["score 31 on 2026-10-17"] }),
  );
  const has = (ground: typeof inputs.ground, value: number) =>
    ground.values.some((figure) => figure.value === value);
  assert(!has(inputs.ground, 1.9));
  assert(has(inputs.ground, 1.6));
  assert(has(inputs.ground, 31));
  assert(!has(inputs.athleteGround!, 1.6));
  assert(has(inputs.athleteGround!, 31));
  // The threshold in the text is fixed wording: only the value that was marked grounds.
  assert(!has(inputs.ground, 40));
  assert(!has(inputs.athleteGround!, 40));
});

Deno.test("the latest daily decision is a model's words about an earlier day: its figures ground nothing today", () => {
  const rich = structuredClone(evalProfiles().find((p) => p.id === "rich")!.context);
  const withDecision = {
    ...rich,
    latest_decision: {
      final_decision: "Keep the plan at 8472 steps",
      confidence: "high",
      reason: "Recovery was 3731 on that day",
    },
  };
  const inputs = replyCheckInputsFor(withDecision, "How am I doing?", null);
  for (const ground of [inputs.ground, inputs.athleteGround!]) {
    assert(!ground.values.some((figure) => figure.value === 8472));
    assert(!ground.values.some((figure) => figure.value === 3731));
  }
});
