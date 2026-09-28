import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { routedFetch, sampleJobs, weekEstimates } from "./coach_chat_eval.ts";
import { evalCoachingDate, evalProfiles } from "./fixtures.ts";
import prompts from "./prompts.json" with { type: "json" };
import {
  buildCoachChatUserMessage,
  classifyQuestion,
} from "../_shared/providers/coach_chat_provider.ts";

Deno.test("a router run changes only the URL and says thinking is off", async () => {
  let sent: { url: string; init?: RequestInit } | undefined;
  const fetcher = routedFetch("https://router.example/v1/", (input, init) => {
    sent = { url: String(input), init };
    return Promise.resolve(new Response("{}"));
  });
  await fetcher("https://api.deepseek.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: "Bearer synthetic-key" },
    body: JSON.stringify({ model: "deepseek-v4-flash", thinking: { type: "disabled" } }),
  });
  assertEquals(sent?.url, "https://router.example/v1/chat/completions");
  assertEquals(
    (sent?.init?.headers as Record<string, string>).Authorization,
    "Bearer synthetic-key",
  );
  assertEquals(JSON.parse(String(sent?.init?.body)), {
    model: "deepseek-v4-flash",
    thinking: { type: "disabled" },
    reasoning_effort: "none",
  });
});

type SampledPrompt = { id: string; category: string; expect?: { safety?: string[] } };

function plannedJobs() {
  return evalProfiles().flatMap((profile) =>
    (prompts as SampledPrompt[]).flatMap((prompt) =>
      [1, 2].map((repeat) => ({
        profileId: profile.id,
        category: prompt.category,
        promptId: prompt.id,
        safety: Boolean(prompt.expect?.safety),
        repeat,
      }))
    )
  );
}

Deno.test("a cheap sample runs every safety prompt and one prompt of every other category", () => {
  const planned = plannedJobs();
  const safetyIds = (prompts as SampledPrompt[]).filter((p) => p.expect?.safety).map((p) => p.id);
  const categories = new Set(planned.map((job) => job.category));
  const sample = sampleJobs(planned, 17);
  assertEquals(sample.length, 17);
  assertEquals(safetyIds.length, 6);
  for (const id of safetyIds) {
    assertEquals(sample.filter((job) => job.promptId === id).length, 1, id);
  }
  assertEquals(new Set(sample.map((job) => job.category)), categories);
  assertEquals(new Set(sample.map((job) => job.profileId)).size, evalProfiles().length);
  assertEquals(sampleJobs(planned, 0).length, planned.length);
});

Deno.test("a sample smaller than the safety set still runs every safety prompt", () => {
  const sample = sampleJobs(plannedJobs(), 3);
  assertEquals(sample.length, 6);
  assert(sample.every((job) => job.safety));
});

Deno.test("larger samples rotate prompts within a category before repeating one", () => {
  const sample = sampleJobs(plannedJobs(), 6 + 11 * 2);
  const mixed = sample.filter((job) => job.category === "mixed");
  assertEquals(mixed.length, 2);
  assertEquals(new Set(mixed.map((job) => job.promptId)).size, 2);
});

Deno.test("eval projection parser reads weeks, ranges and months", () => {
  assertEquals(weekEstimates("About 13 weeks at this pace."), [13]);
  assertEquals(weekEstimates("Roughly 12-14 weeks.").includes(14), true);
  assert(weekEstimates("around 3 months").some((weeks) => weeks > 13 && weeks < 13.1));
});

Deno.test("eval prompts are unique and cover the failure categories", () => {
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
      "safety",
      "follow_up",
      "short",
    ]
  ) {
    assert(prompts.some((p) => p.category === category), `missing category ${category}`);
  }
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
