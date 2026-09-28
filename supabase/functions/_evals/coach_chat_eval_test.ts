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

Deno.test("a cheap sample covers every category before repeating one", () => {
  const categories = [...new Set((prompts as Array<{ category: string }>).map((p) => p.category))];
  const planned = evalProfiles().flatMap((profile) =>
    (prompts as Array<{ id: string; category: string }>).map((prompt) => ({
      profileId: profile.id,
      category: prompt.category,
      id: prompt.id,
    }))
  );
  const sample = sampleJobs(planned, categories.length);
  assertEquals(sample.length, categories.length);
  assertEquals(new Set(sample.map((job) => job.category)).size, categories.length);
  assertEquals(new Set(sample.map((job) => job.profileId)).size, evalProfiles().length);
  assertEquals(sampleJobs(planned, 0).length, planned.length);
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
