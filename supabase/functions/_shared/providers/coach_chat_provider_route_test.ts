import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { routeFor } from "../ai/fakes.ts";
import { route } from "../ai/routes.ts";
import { needsStrongerCoachRoute, selectCoachChatRoute } from "./coach_chat_provider_route.ts";
import {
  chooseCoachChatRoute,
  coachChatReservationCapUsd,
  coachChatReservationUsd,
} from "./coach_chat_provider_gateway.ts";
import { coachContextContributors } from "../coach_context/registry.ts";

const haiku = () =>
  routeFor("coach_chat", {
    MODEL: "claude-haiku-5-5",
    MAX_OUTPUT_TOKENS: "4096",
    EVALUATED: "true",
  });
const sonnet = () =>
  routeFor("coach_chat_strong", {
    MODEL: "claude-sonnet-5-5",
    MAX_OUTPUT_TOKENS: "4096",
    EVALUATED: "true",
  });

Deno.test("progress, weight and goal, nutrition-number and plan questions need the stronger route", () => {
  for (
    const question of [
      "How is my progress this month?",
      "Why has my weight stalled?",
      "Am I losing weight fast enough?",
      "Should I raise my protein?",
      "How many calories should I eat on rest days?",
      "Can you change my plan so legs come twice a week?",
      "Is my cut going to plateau?",
      "Do I need a deload?",
      "How is my progress over the last month?",
      "Should I change my calories?",
    ]
  ) {
    assert(needsStrongerCoachRoute(question), question);
  }
});

Deno.test("conversation and simple questions stay on the default route", () => {
  for (
    const question of [
      "hi",
      "thanks, that helps",
      "I'm feeling unmotivated today",
      "how do I breathe during a squat?",
      "what time should I train?",
      "good morning coach",
      "how many sets should I do today?",
      "should I go heavier?",
      "what's my plan today?",
      "what's my body fat goal?",
      "what's my protein target?",
      "what weight should I use for squats?",
    ]
  ) {
    assert(!needsStrongerCoachRoute(question), question);
  }
});

Deno.test("the stronger route answers when it is set and its vendor holds the athlete's consent", () => {
  const strong = sonnet();
  const picked = selectCoachChatRoute(
    "Why has my weight stalled?",
    haiku(),
    () => strong,
    "anthropic",
  );
  assertEquals(picked.tier, "strong");
  assertEquals(picked.route, strong);
});

Deno.test("the default route answers without a stronger route, for a simple question, or on another vendor's notice", () => {
  const defaultRoute = haiku();
  const asked = { count: 0 };
  const simple = selectCoachChatRoute("hi", defaultRoute, () => {
    asked.count++;
    return sonnet();
  }, "anthropic");
  assertEquals([simple.tier, simple.route, asked.count], ["default", defaultRoute, 0]);

  const unset = selectCoachChatRoute(
    "Why has my weight stalled?",
    defaultRoute,
    () => null,
    "anthropic",
  );
  assertEquals([unset.tier, unset.route], ["default", defaultRoute]);

  const other = selectCoachChatRoute(
    "Why has my weight stalled?",
    defaultRoute,
    () => sonnet(),
    "deepseek",
  );
  assertEquals(other.tier, "default");
  assertEquals("strongSkipped" in other && other.strongSkipped, "consent_vendor_differs");
  const noNotice = selectCoachChatRoute(
    "Why has my weight stalled?",
    defaultRoute,
    () => sonnet(),
    null,
  );
  assertEquals(noNotice.tier, "default");
});

Deno.test("the second route is a gateway feature with its own settings and is not set by default", () => {
  assertEquals(route("coach_chat_strong", () => undefined), null);
  const settings: Record<string, string> = {
    AI_COACH_CHAT_STRONG_PROVIDER: "anthropic",
    AI_COACH_CHAT_STRONG_MODEL: "claude-sonnet-5-5",
    AI_COACH_CHAT_STRONG_MAX_OUTPUT_TOKENS: "4096",
    AI_COACH_CHAT_STRONG_TIMEOUT_MS: "30000",
    AI_COACH_CHAT_STRONG_EVALUATED: "true",
    ANTHROPIC_API_KEY: "synthetic-key",
  };
  const found = route("coach_chat_strong", (name) => settings[name])!;
  assertEquals([found.feature, found.vendor, found.model], [
    "coach_chat_strong",
    "anthropic",
    "claude-sonnet-5-5",
  ]);
});

Deno.test("the budget places follow the route: Sonnet reserves more than Haiku and still fits one reservation", () => {
  const strong = sonnet();
  const standard = haiku();
  assert(chooseCoachChatRoute(strong, coachContextContributors).route !== null);
  assert(chooseCoachChatRoute(standard, coachContextContributors).route !== null);
  const strongUsd = coachChatReservationUsd(strong, coachContextContributors)!;
  const standardUsd = coachChatReservationUsd(standard, coachContextContributors)!;
  assert(strongUsd > standardUsd, `${strongUsd} should exceed ${standardUsd}`);
  assert(strongUsd <= coachChatReservationCapUsd);
});
