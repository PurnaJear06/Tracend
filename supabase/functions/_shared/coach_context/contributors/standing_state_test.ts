import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { evalProfiles } from "../../../_evals/fixtures.ts";
import { anthropicAdapter } from "../../ai/adapters/anthropic.ts";
import { openAiCompatibleAdapter } from "../../ai/adapters/openai_compatible.ts";
import { routeFor, syntheticKey } from "../../ai/fakes.ts";
import { type AnthropicModel, modelSpec, type OpenAiCompatibleModel } from "../../ai/models.ts";
import type { AiRequest } from "../../ai/types.ts";
import {
  buildCoachChatGatewayPrompt,
  coachChatGatewaySchema,
} from "../../providers/coach_chat_provider_gateway.ts";
import {
  gatewayCheckInsShown,
  gatewayOtherMessagesShown,
  renderCoachContextParts,
} from "../../providers/coach_chat_provider.ts";
import { renderCoachContext } from "../host.ts";
import { coachContextContributors, coachContextContributorsFor } from "../registry.ts";
import {
  createStandingStateContributor,
  parseStandingState,
  standingStateBudgetChars,
  standingStateLines,
  standingStateMarked,
  standingStateRule,
  standingStateSourceFromRpc,
} from "./standing_state.ts";
import { plain } from "../../recorded_text.ts";

const today = "2026-10-31";
const turn = { userId: "u", question: "hi", localDate: today };

type Json = Record<string, unknown>;

/** A get_coach_standing_state_v1 payload for `today`, with changes. */
function payload(availability: Json = {}, changes: Json = {}): Json {
  return {
    schema_version: "1.0",
    local_date: today,
    availability: {
      schema_version: "1.0",
      local_date: today,
      status: "available",
      unavailable_today: false,
      safety_route: null,
      paused: false,
      pause: null,
      return_from_pause: null,
      offer_break: false,
      ...availability,
    },
    joint_areas: [],
    recent_pain: false,
    goal: null,
    decisions: [],
    breaks: [],
    paused_days: [],
    unavailable_days: [],
    ...changes,
  };
}

const runningBreak = {
  id: "p1",
  start_date: "2026-10-25",
  end_date: "2026-11-08",
  reason: "rest",
  note: null,
  source: "coach",
  running: true,
};

async function render(raw: unknown): Promise<string> {
  const contributor = createStandingStateContributor(
    standingStateSourceFromRpc(() => Promise.resolve({ data: raw, error: null })),
  );
  const result = await renderCoachContext([contributor], turn);
  return result.texts.standing_state ?? "";
}

Deno.test("an unavailable check-in is today's line: the session is not offered", async () => {
  const text = await render(payload({ status: "unavailable_today", unavailable_today: true }));
  const lines = text.split("\n");
  assertEquals(lines[0], standingStateRule);
  assertStringIncludes(lines[1], "said on today's check-in that they cannot train today");
  assertStringIncludes(lines[1], "Do not offer today's session.");
});

Deno.test("a running break says so with its dates and never asks again", async () => {
  const text = await render(
    payload({ status: "paused", paused: true, pause: runningBreak }, {
      paused_days: ["2026-10-31"],
    }),
  );
  assertStringIncludes(text, "on a break from 2026-10-25 to 2026-11-08 (they approved it)");
  assertStringIncludes(text, "do not ask again whether, or for how long, they are taking a break");
  assertStringIncludes(text, "the plan resumes by itself");
});

Deno.test("a break ahead, the first day back and a safety route each have their line", async () => {
  const ahead = await render(
    payload({ pause: { ...runningBreak, start_date: "2026-11-01", running: false } }),
  );
  assertStringIncludes(ahead, "A break the athlete approved runs from 2026-11-01 to 2026-11-08");
  const back = await render(
    payload({ return_from_pause: { pause_id: "p1", last_paused_day: "2026-10-30" } }),
  );
  assertStringIncludes(back, "Back from a break that ended 2026-10-30");
  assertStringIncludes(back, "never count the break as missed sessions");
  const route = await render(
    payload({ status: "safety_route", safety_route: "urgent", paused: true, pause: runningBreak }),
  );
  assertStringIncludes(route, "carries a safety route (urgent). No training today");
});

Deno.test("held and limited areas, recent pain, the goal and the decisions are listed, never a pain figure", async () => {
  const text = await render(payload({}, {
    joint_areas: [{ area: "knee", state: "held" }, { area: "shoulder", state: "limited" }],
    recent_pain: true,
    goal: { goal_type: "fat_loss", phase: "cut", phase_ends_on: "2026-12-06" },
    decisions: [{
      kind: "training_pause",
      title: "Break · 1–15 Nov",
      status: "approved",
      on: "2026-10-30",
      ends_on: "2026-11-15",
    }],
  }));
  assertStringIncludes(text, "Held areas (only the athlete's own clearance lifts a hold): knee.");
  assertStringIncludes(text, "Limited areas: shoulder.");
  assertStringIncludes(text, "Pain of 4 or more out of 10 was reported");
  assertStringIncludes(text, "Goal: fat loss, phase cut until 2026-12-06.");
  assertStringIncludes(text, '2026-10-30 approved break "Break · 1–15 Nov"');
});

Deno.test("the worst case stays within the hard cap, keeps the rule and today's line, and drops from the end", () => {
  const long = "A title as long as the rules ever write it, with more words to fill it out";
  const state = parseStandingState(
    payload({
      status: "unavailable_today",
      unavailable_today: true,
      pause: { ...runningBreak, start_date: "2026-11-02", running: false },
      return_from_pause: { pause_id: "p0", last_paused_day: "2026-10-29" },
    }, {
      joint_areas: [
        { area: "knee", state: "held" },
        { area: "back", state: "held" },
        { area: "shoulder", state: "limited" },
        { area: "other", state: "limited" },
      ],
      recent_pain: true,
      goal: { goal_type: "recomposition", phase: "maintenance", phase_ends_on: "2027-01-31" },
      decisions: [1, 2, 3].map((n) => ({
        kind: "training_schedule",
        title: `${long} ${n}`,
        status: "approved",
        on: `2026-10-2${n}`,
        ends_on: null,
      })),
      breaks: [1, 2, 3].map((n) => ({
        start_date: `2026-10-0${n}`,
        last_day: `2026-10-1${n}`,
        end_date: `2026-10-1${n}`,
        source: "athlete",
        ended: "ended_early",
        ended_on: `2026-10-1${n}`,
      })),
    }),
    today,
  )!;
  const all = plain(standingStateLines(state).join("\n"));
  const kept = plain(standingStateMarked(state));
  assert(all.length > standingStateBudgetChars, `${all.length}: the case must be over the cap`);
  assert(kept.length <= standingStateBudgetChars, `${kept.length} characters`);
  const lines = kept.split("\n");
  assertEquals(lines[0], standingStateRule);
  assertStringIncludes(lines[1], "cannot train today");
  // Whole lines go from the least important end: the break history first, then the decisions.
  assert(!kept.includes("Recent breaks"));
  assert(kept.includes("A break the athlete approved runs from"));
  assert(kept.includes("Back from a break"));
  assert(kept.includes("Held areas"));
});

Deno.test("a common day costs about the budget's target: a break and the goal fit well under 1,200", () => {
  const state = parseStandingState(
    payload({ status: "paused", paused: true, pause: runningBreak }, {
      goal: { goal_type: "muscle_gain", phase: "gain", phase_ends_on: null },
    }),
    today,
  )!;
  assert(plain(standingStateMarked(state)).length < 0.8 * standingStateBudgetChars);
});

Deno.test("an unreadable state is a short block that says so, never silence", async () => {
  for (const raw of [null, { schema_version: "2.0" }, payload({}, { local_date: "2026-10-30" })]) {
    const text = await render(raw);
    assertStringIncludes(text, "could not be read just now");
    assertStringIncludes(text, standingStateRule);
  }
  const failing = createStandingStateContributor(() => Promise.reject(new Error("down")));
  const result = await renderCoachContext([failing], turn);
  assertStringIncludes(result.texts.standing_state ?? "", "could not be read just now");
  assertEquals(result.traces?.standing_state, { standing: "failed" });
});

Deno.test("the parser refuses a payload that is not exactly the standing state", () => {
  const bad: Json[] = [
    payload({ status: "resting" }),
    payload({ paused: "yes" }),
    payload({ pause: { ...runningBreak, end_date: "soon" } }),
    payload({}, { joint_areas: [{ area: "knee", state: "watch" }] }),
    payload({}, { decisions: [{ kind: "x", status: "pending", on: today }] }),
    payload({}, { paused_days: ["tomorrow"] }),
  ];
  for (const raw of bad) assertEquals(parseStandingState(raw, today), null, JSON.stringify(raw));
});

Deno.test("the block is the last contributor, volatile, on both routes: right before the question and after the cache breakpoint", async () => {
  const ids = coachContextContributors.map((item) => item.id);
  assertEquals(ids.at(-1), "standing_state");
  assertEquals(coachContextContributors.at(-1)?.slot, "volatile");
  for (const gateway of [true, false]) {
    assertEquals(coachContextContributorsFor(gateway).at(-1)?.id, "standing_state");
  }
  const contributions = await renderCoachContext(
    [createStandingStateContributor(() =>
      Promise.resolve(
        parseStandingState(
          payload({ status: "unavailable_today", unavailable_today: true }),
          today,
        ),
      )
    )],
    turn,
  );
  const prompt = buildCoachChatGatewayPrompt("hi", context(), "general", contributions);
  const parts = prompt.messages[0].content.map((part) => part.type === "text" ? part : null);
  assertEquals(parts[0]?.cache, true);
  assert(!parts[0]!.text.includes("standing_state"), "never in the cached prefix");
  assertStringIncludes(parts[1]!.text, '<reference_data source="standing_state">');
  assertEquals(parts[2]!.text, "User's message:\nhi");
});

// ---- provider-neutral memory -------------------------------------------------------------------

/** The text of every message a built provider request carries, in order. */
function requestText(body: Record<string, unknown>): string {
  const pieces: string[] = [];
  const walk = (value: unknown) => {
    if (typeof value === "string") pieces.push(value);
    else if (Array.isArray(value)) value.forEach(walk);
    else if (value && typeof value === "object") {
      for (const [key, inner] of Object.entries(value)) {
        if (key === "text" || key === "content" || key === "messages") walk(inner);
      }
    }
  };
  walk(body.messages);
  return pieces.join("\n");
}

Deno.test("the standing state is the same text on an Anthropic route and an OpenAI-compatible route, cached or not", async () => {
  const contributions = await renderCoachContext(
    [createStandingStateContributor(() =>
      Promise.resolve(
        parseStandingState(payload({ status: "paused", paused: true, pause: runningBreak }), today),
      )
    )],
    turn,
  );
  const block = contributions.volatile;
  assertStringIncludes(block, "on a break from 2026-10-25 to 2026-11-08");
  const prompt = buildCoachChatGatewayPrompt("What's today?", context(), "general", contributions);
  const anthropicRoute = routeFor("coach_chat", { MODEL: "claude-haiku-5-5" });
  const openAiRoute = routeFor("coach_chat", {
    PROVIDER: "openai_compatible",
    MODEL: "deepseek-flash",
    BASE_URL: "https://api.deepseek.com/v1",
    OPENAI_COMPATIBLE_API_KEY_COACH_CHAT: syntheticKey,
  });
  const request = (route: AiRequest["route"]): AiRequest => ({
    route,
    system: prompt.system,
    messages: prompt.messages,
    output: { kind: "json", schema: coachChatGatewaySchema() },
    consentVendor: route.vendor,
  });
  const anthropic = anthropicAdapter.build(
    request(anthropicRoute),
    modelSpec("anthropic", anthropicRoute.model) as AnthropicModel,
    syntheticKey,
  );
  const openAi = openAiCompatibleAdapter.build(
    request(openAiRoute),
    modelSpec("openai_compatible", openAiRoute.model) as OpenAiCompatibleModel,
    syntheticKey,
  );
  assert(anthropic !== null && openAi !== null);
  // The OpenAI-compatible adapter ignores cache flags; the block's words are identical either way.
  for (const body of [anthropic.body, openAi.body]) {
    const text = requestText(body);
    assertEquals(text.split(block).length - 1, 1, "the block is sent once, word for word");
  }
});

// ---- the token budget: the standing state is paid for by the trimmed lists ------------------------

/** A realistic athlete file: the owner's day had 14 check-ins and 8 messages in another chat. */
function context(): Json {
  const base = structuredClone(evalProfiles().find((p) => p.id === "rich")!.context) as Json;
  const checkIns = Array.from({ length: 14 }, (_, days) => ({
    local_date: `2026-10-${String(31 - days).padStart(2, "0")}`,
    sleep_quality: 4,
    energy: 4,
    soreness: 2,
    hunger: 3,
    mood: 4,
    pain_severity: 0,
    available_to_train: days !== 0,
  }));
  // A Coach reply of about 1,300 characters, as the owner's break reply was (advice, a home routine
  // offer, a question about kit): the prompt shows a long reply's first 300 and last 900 characters.
  const reply = (
    "A 15-day break is fine after a long block. Walk daily, keep protein high and sleep well. " +
    "When you come back, the first week eases in with lighter loads so your joints and tendons " +
    "catch up with your muscles. "
  ).repeat(6);
  const other = Array.from(
    { length: 10 },
    (_, index) =>
      index % 2 === 0
        ? {
          role: "user",
          content: "I'm thinking of taking 15 days off from the gym, what do you say?",
        }
        : { role: "assistant", content: reply },
  );
  return { ...base, check_ins_14d: checkIns, recent_other_conversations: other };
}

Deno.test("the net prompt goes down: the trimmed check-ins and other conversations pay for the standing state", async () => {
  const ctx = context();
  const size = (parts: { file: string; recent: string }) => parts.file.length + parts.recent.length;
  // Today's DeepSeek rendering is the gateway's rendering before this change except for the evidence
  // id wording, which a file without the two lists measures on its own.
  const without = { ...ctx, check_ins_14d: [], recent_other_conversations: [] };
  const wording = size(renderCoachContextParts(without, 200_000, false)) -
    size(renderCoachContextParts(without, 200_000, true));
  const before = size(renderCoachContextParts(ctx, 200_000, false)) - wording;
  const lists = size(renderCoachContextParts(ctx, 200_000, true));
  const standing = await renderCoachContext(
    [createStandingStateContributor(() =>
      Promise.resolve(
        parseStandingState(
          payload({ status: "paused", paused: true, pause: runningBreak }, {
            goal: { goal_type: "fat_loss", phase: "cut", phase_ends_on: "2026-12-06" },
            joint_areas: [{ area: "knee", state: "limited" }],
            decisions: [{
              kind: "training_pause",
              title: "Break · 25 Oct–8 Nov",
              status: "approved",
              on: "2026-10-24",
              ends_on: "2026-11-08",
            }],
          }),
          today,
        ),
      )
    )],
    turn,
  );
  const after = lists + standing.volatile.length + 2;
  assert(after < before, `after ${after} characters, before ${before}`);
  // The two lists alone shrink by more than the whole labelled block costs.
  assert(before - lists > standing.volatile.length, `${before - lists} saved`);
  const shown = renderCoachContextParts(ctx, 200_000, true);
  assertStringIncludes(shown.file, `## Check-ins (newest ${gatewayCheckInsShown},`);
  assertStringIncludes(shown.file, "Older check-ins: the check_ins lookup.");
  assertStringIncludes(
    shown.recent,
    "Earlier messages of other conversations: the past_messages lookup.",
  );
  assertEquals(
    (shown.recent.split("## This Conversation")[0].match(/\*\*(USER|ASSISTANT):\*\*/g) ?? [])
      .length,
    gatewayOtherMessagesShown,
  );
});
