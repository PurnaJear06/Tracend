import { assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import {
  createProposalsContributor,
  parseProposalsState,
  proposalsContributorBudgetChars,
  renderProposals,
} from "./proposals.ts";

const base = { schema_version: "1.0", local_date: "2026-10-20", block: null, phase: null };

const render = (payload: Record<string, unknown>) =>
  renderProposals(parseProposalsState({ ...base, proposals: [], ...payload }));

Deno.test("nothing to report renders nothing", () => {
  assertEquals(render({}), null);
  assertEquals(renderProposals(parseProposalsState(null)), null);
  assertEquals(renderProposals(parseProposalsState({ schema_version: "2.0" })), null);
});

Deno.test("a running block and its last day are stated", () => {
  const text = render({
    block: {
      title: "Bodyweight block until 30 Oct",
      kind: "temporary_block",
      ends_on: "2026-10-30",
    },
  })!;
  assertStringIncludes(text, '"Bodyweight block until 30 Oct" until 2026-10-30');
  assertStringIncludes(text, "regular plan returns by itself the day after");
});

Deno.test("a diet break in progress and one that has ended are told apart", () => {
  const running = render({
    phase: { phase: "diet_break", started_on: "2026-10-18", ends_on: "2026-10-31" },
  })!;
  assertStringIncludes(running, "in a diet break since 2026-10-18, ending 2026-10-31");
  const ended = render({
    phase: { phase: "diet_break", started_on: "2026-10-01", ends_on: "2026-10-14" },
  })!;
  assertStringIncludes(ended, "diet break ended on 2026-10-14");
  assertStringIncludes(ended, "Nutrition does not change back by itself");
  assertStringIncludes(ended, "as a proposal for the athlete to approve");
});

Deno.test("waiting and answered proposals are listed with what happened to them", () => {
  const text = render({
    proposals: [
      {
        kind: "nutrition_targets",
        title: "Lower your calories",
        status: "pending",
        created_on: "2026-10-20",
        expires_at: "2026-10-23T09:00:00Z",
        ends_on: null,
      },
      {
        kind: "temporary_block",
        title: "Bodyweight block until 15 Oct",
        status: "accepted",
        created_on: "2026-10-05",
        expires_at: "2026-10-08T09:00:00Z",
        ends_on: "2026-10-15",
      },
      {
        kind: "training_schedule",
        title: "Train 4 days a week",
        status: "declined",
        created_on: "2026-10-01",
        expires_at: "2026-10-04T09:00:00Z",
        ends_on: null,
      },
    ],
  })!;
  assertStringIncludes(
    text,
    'Waiting for the athlete to answer (not applied yet): "Lower your calories" (open until 2026-10-23)',
  );
  assertStringIncludes(
    text,
    '"Bodyweight block until 15 Oct", 2026-10-05: approved and applied, ended 2026-10-15',
  );
  assertStringIncludes(text, '"Train 4 days a week", 2026-10-01: declined (not now)');
});

Deno.test("the contributor renders from its source and stays inside its budget", async () => {
  const contributor = createProposalsContributor(() =>
    Promise.resolve({
      ...base,
      proposals: Array.from({ length: 8 }, (_, i) => ({
        kind: "nutrition_targets",
        title: `Lower your calories ${i}`,
        status: "declined",
        created_on: "2026-10-01",
        expires_at: null,
        ends_on: null,
      })),
    })
  );
  assertEquals(contributor.id, "coach_proposals");
  assertEquals(contributor.slot, "volatile");
  const rendered = await contributor.render({
    userId: "u",
    question: "q",
    localDate: "2026-10-20",
  });
  const { text, trace } = rendered as { text: string; trace: Record<string, unknown> };
  assertEquals(text.length < proposalsContributorBudgetChars, true);
  // The route reads how many proposals wait; no text travels with it.
  assertEquals(trace, { waiting: 0 });
});

Deno.test("the contributor reports how many proposals wait for an answer", async () => {
  const contributor = createProposalsContributor(() =>
    Promise.resolve({
      ...base,
      proposals: ["pending", "pending", "declined"].map((status, i) => ({
        kind: "nutrition_targets",
        title: `Change ${i}`,
        status,
        created_on: "2026-10-18",
        expires_at: "2026-10-23T00:00:00Z",
        ends_on: null,
      })),
    })
  );
  const rendered = await contributor.render({
    userId: "u",
    question: "q",
    localDate: "2026-10-20",
  });
  assertEquals((rendered as { trace: unknown }).trace, { waiting: 2 });
  const none = createProposalsContributor(() => Promise.resolve({ ...base, proposals: [] }));
  assertEquals(await none.render({ userId: "u", question: "q", localDate: "2026-10-20" }), null);
});
