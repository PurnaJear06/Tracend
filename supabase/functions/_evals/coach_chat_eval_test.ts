import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { weekEstimates } from "./coach_chat_eval.ts";
import { evalCoachingDate, evalProfiles } from "./fixtures.ts";
import prompts from "./prompts.json" with { type: "json" };
import {
  buildCoachChatUserMessage,
  classifyQuestion,
} from "../_shared/providers/coach_chat_provider.ts";

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
