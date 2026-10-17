import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { sampleJobs } from "./coach_chat_eval.ts";
import { evalCoachingDate, evalProfiles } from "./fixtures.ts";
import prompts from "./prompts.json" with { type: "json" };
import {
  buildCoachChatUserMessage,
  classifyQuestion,
} from "../_shared/providers/coach_chat_provider.ts";

type SampledPrompt = { id: string; category: string };

function plannedJobs() {
  return evalProfiles().flatMap((profile) =>
    (prompts as SampledPrompt[]).flatMap((prompt) =>
      [1, 2].map((repeat) => ({
        profileId: profile.id,
        category: prompt.category,
        promptId: prompt.id,
        repeat,
      }))
    )
  );
}

Deno.test("a cheap sample runs one prompt of every category and every athlete", () => {
  const planned = plannedJobs();
  const categories = new Set(planned.map((job) => job.category));
  const sample = sampleJobs(planned, categories.size);
  assertEquals(sample.length, categories.size);
  assertEquals(new Set(sample.map((job) => job.category)), categories);
  assertEquals(new Set(sample.map((job) => job.profileId)).size, evalProfiles().length);
  assertEquals(sampleJobs(planned, 0).length, planned.length);
});

Deno.test("larger samples rotate prompts within a category before repeating one", () => {
  const categories = new Set(plannedJobs().map((job) => job.category)).size;
  const sample = sampleJobs(plannedJobs(), categories * 2);
  const mixed = sample.filter((job) => job.category === "mixed");
  assertEquals(mixed.length, 2);
  assertEquals(new Set(mixed.map((job) => job.promptId)).size, 2);
});

Deno.test("eval prompts are unique and cover the operating categories", () => {
  const ids = prompts.map((p) => p.id);
  assertEquals(new Set(ids).size, ids.length);
  for (
    const category of [
      "real_failure",
      "mixed",
      "typos",
      "long",
      "projection",
      "unmeasured",
      "plan_change",
      "follow_up",
      "short",
    ]
  ) {
    assert(prompts.some((p) => p.category === category), `missing category ${category}`);
  }
  assert(!prompts.some((p) => p.category === "safety"), "safety prompts live in the answer bank");
});

Deno.test("eval athletes render within budget for every prompt", () => {
  for (const profile of evalProfiles()) {
    assertEquals(profile.context.coaching_date, evalCoachingDate);
    for (const prompt of prompts) {
      const message = buildCoachChatUserMessage(
        prompt.text,
        profile.context,
        classifyQuestion(prompt.text),
      );
      assert(message.endsWith(prompt.text));
      assert(!message.includes("## Omitted This Turn"), `${profile.id} lost sections`);
    }
  }
});

Deno.test("rich athlete totals match its training log", () => {
  const rich = evalProfiles().find((p) => p.id === "rich")!.context;
  const log = rich.training_log_28d as Array<{ local_date: string }>;
  const totals = rich.training_totals as Record<string, { sessions: number }>;
  assertEquals(totals.last_28_days.sessions, log.length);
  assert(totals.last_14_days.sessions < totals.last_28_days.sessions);
});
