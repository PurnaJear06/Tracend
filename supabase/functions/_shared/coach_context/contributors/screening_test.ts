import { assert, assertEquals, assertRejects, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  createScreeningContributor,
  renderScreening,
  screeningBudgetChars,
  screeningOutcomeIn,
  screeningSourceFromQuery,
} from "./screening.ts";
import { renderCoachContext } from "../host.ts";
import { coachContextContributors } from "../registry.ts";

const input = { userId: "user-1", question: "Can I go heavy?", localDate: "2026-10-17" };

Deno.test("each outcome renders its date and the rule it implies", () => {
  const moderate = renderScreening({
    outcome: "moderate_until_cleared",
    screenedAt: "2026-10-12T08:30:00+00:00",
  })!;
  assertStringIncludes(moderate, "answered on 2026-10-12");
  assertStringIncludes(moderate, "Outcome: moderate_until_cleared");
  assertStringIncludes(moderate, "no maximal or near-failure sets");
  assertStringIncludes(moderate, "clearance");
  const professional = renderScreening({
    outcome: "see_professional",
    screenedAt: "2026-10-12T08:30:00+00:00",
  })!;
  assertStringIncludes(professional, "Outcome: see_professional");
  assertStringIncludes(professional, "no training prescriptions of any kind");
  assertStringIncludes(professional, "doctor or qualified exercise professional");
  const cleared = renderScreening({ outcome: "cleared", screenedAt: "2026-10-12T08:30:00Z" })!;
  assertStringIncludes(cleared, "no cap on effort");
  for (const text of [moderate, professional, cleared]) {
    assert(text.length <= screeningBudgetChars, `${text.length} chars`);
  }
});

Deno.test("never screened reads as cleared and renders nothing", () => {
  assertEquals(renderScreening(null), null);
  assertEquals(screeningOutcomeIn(""), "cleared");
});

Deno.test("the contributor is stable, and the guard reads the outcome the model saw", async () => {
  const contributor = createScreeningContributor(() =>
    Promise.resolve({ outcome: "moderate_until_cleared", screenedAt: "2026-10-12T08:30:00Z" })
  );
  assertEquals(contributor.slot, "stable");
  const rendered = await renderCoachContext([contributor], input);
  assertEquals(rendered.volatile, "");
  assertStringIncludes(rendered.stable, '<reference_data source="screening">');
  assertEquals(rendered.outcomes[0].outcome, "rendered");
  assertEquals(rendered.outcomes[0].clipped, false);
  assertEquals(screeningOutcomeIn(rendered.stable), "moderate_until_cleared");
  assertEquals(screeningOutcomeIn(rendered.volatile), "cleared");
});

Deno.test("a failing source leaves the contributor out; the turn goes on", async () => {
  const failing = createScreeningContributor(() => Promise.reject(new Error("down")));
  const result = await renderCoachContext([failing], input);
  assertEquals(result.outcomes[0].outcome, "failed");
  assertEquals(result.stable, "");
});

Deno.test("the query source reads the newest row, ignores a value it does not know, raises on error", async () => {
  const row = (outcome: string) => () =>
    Promise.resolve({ data: { outcome, screened_at: "2026-10-12T08:30:00Z" }, error: null });
  assertEquals(await screeningSourceFromQuery(row("see_professional"))("u"), {
    outcome: "see_professional",
    screenedAt: "2026-10-12T08:30:00Z",
  });
  assertEquals(await screeningSourceFromQuery(row("surprise"))("u"), null);
  assertEquals(
    await screeningSourceFromQuery(() => Promise.resolve({ data: null, error: null }))("u"),
    null,
  );
  await assertRejects(() =>
    screeningSourceFromQuery(() => Promise.resolve({ data: null, error: { code: "x" } }))("u")
  );
});

Deno.test("the screening comes first in the registry, before the cached goal phase block", () => {
  assertEquals(coachContextContributors[0].id, "screening");
});
