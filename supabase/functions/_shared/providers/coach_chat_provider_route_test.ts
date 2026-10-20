import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { routeFor } from "../ai/fakes.ts";
import { route } from "../ai/routes.ts";
import {
  type RouteSignals,
  routeSignalsOf,
  selectCoachChatRoute,
  strongRouteReasons,
} from "./coach_chat_provider_route.ts";
import {
  type CoachContributions,
  noCoachContributions,
  renderCoachContext,
} from "../coach_context/host.ts";
import { createScreeningContributor } from "../coach_context/contributors/screening.ts";
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

const calm: RouteSignals = {
  screening: "cleared",
  pain: "none",
  proposalsWaiting: 0,
  watchOutDecisions: 0,
};

Deno.test("each structural signal asks for the stronger route, and nothing else does", () => {
  assertEquals(strongRouteReasons(calm), []);
  assertEquals(strongRouteReasons({ ...calm, screening: "moderate_until_cleared" }), [
    "screening_not_cleared",
  ]);
  assertEquals(strongRouteReasons({ ...calm, screening: "see_professional" }), [
    "screening_not_cleared",
  ]);
  assertEquals(strongRouteReasons({ ...calm, screening: "unknown" }), ["screening_not_cleared"]);
  assertEquals(strongRouteReasons({ ...calm, pain: "on_record" }), ["pain_on_record"]);
  assertEquals(strongRouteReasons({ ...calm, pain: "unknown" }), ["pain_unknown"]);
  assertEquals(strongRouteReasons({ ...calm, proposalsWaiting: 1 }), ["proposal_waiting"]);
  assertEquals(strongRouteReasons({ ...calm, watchOutDecisions: 1 }), []);
  assertEquals(strongRouteReasons({ ...calm, watchOutDecisions: 2 }), ["several_watch_outs"]);
  assertEquals(
    strongRouteReasons({
      screening: "unknown",
      pain: "on_record",
      proposalsWaiting: 2,
      watchOutDecisions: 3,
    }),
    ["screening_not_cleared", "pain_on_record", "proposal_waiting", "several_watch_outs"],
  );
});

const outcome = (id: string, state: "rendered" | "empty" | "failed" | "timeout") => ({
  id,
  slot: "volatile" as const,
  outcome: state,
  chars: 0,
  clipped: false,
});

Deno.test("the signals come from what the contributors reported, never from the question", () => {
  const contributions = (
    traces: Record<string, Record<string, number | boolean | null>>,
    outcomes = Object.keys(traces).map((id) => outcome(id, "rendered")),
  ): CoachContributions => ({ ...noCoachContributions, outcomes, traces });
  assertEquals(routeSignalsOf(null), calm);
  assertEquals(routeSignalsOf(contributions({})), calm);
  assertEquals(
    routeSignalsOf(contributions({
      watch_outs: { lines: 4, decisions: 3, pain: true },
      coach_proposals: { waiting: 1 },
    })),
    { screening: "cleared", pain: "on_record", proposalsWaiting: 1, watchOutDecisions: 3 },
  );
  assertEquals(
    routeSignalsOf(contributions({ watch_outs: { lines: 1, decisions: 0, pain: false } })),
    calm,
  );
});

Deno.test("the signals do not depend on what rendered: pain on record counts when there is nothing to show", () => {
  const empty: CoachContributions = {
    ...noCoachContributions,
    outcomes: [outcome("watch_outs", "empty")],
    traces: { watch_outs: { lines: 0, decisions: 0, pain: true } },
  };
  assertEquals(routeSignalsOf(empty).pain, "on_record");
  assertEquals(strongRouteReasons(routeSignalsOf(empty)), ["pain_on_record"]);
  // Nothing found and no pain: the default route.
  const quiet: CoachContributions = {
    ...empty,
    traces: { watch_outs: { lines: 0, decisions: 0, pain: false } },
  };
  assertEquals(routeSignalsOf(quiet).pain, "none");
});

Deno.test("a pain signal that is unknown fails toward the stronger route: a timeout, a failure, unreadable facts", () => {
  for (const state of ["timeout", "failed"] as const) {
    const lost: CoachContributions = {
      ...noCoachContributions,
      outcomes: [outcome("watch_outs", state)],
    };
    assertEquals(routeSignalsOf(lost).pain, "unknown", state);
    assertEquals(strongRouteReasons(routeSignalsOf(lost)), ["pain_unknown"], state);
  }
  // The block rendered or was empty but its facts could not be read: pain null.
  const unreadable: CoachContributions = {
    ...noCoachContributions,
    outcomes: [outcome("watch_outs", "empty")],
    traces: { watch_outs: { lines: 0, decisions: 0, pain: null } },
  };
  assertEquals(routeSignalsOf(unreadable).pain, "unknown");
  // A route without the contributor (the legacy path, a test) has nothing to know.
  assertEquals(routeSignalsOf({ ...noCoachContributions, outcomes: [] }).pain, "none");
});

Deno.test("a screening that is not cleared, or could not be read, is read from the real screening block", async () => {
  const turn = (
    source: Parameters<typeof createScreeningContributor>[0],
  ) =>
    renderCoachContext([createScreeningContributor(source)], {
      userId: "user-1",
      question: "check my training",
      localDate: "2026-10-20",
    });
  const states = {
    moderate: await turn(() =>
      Promise.resolve({ outcome: "moderate_until_cleared", screenedAt: "2026-09-01T09:00:00Z" })
    ),
    cleared: await turn(() =>
      Promise.resolve({ outcome: "cleared", screenedAt: "2026-09-01T09:00:00Z" })
    ),
    never: await turn(() => Promise.resolve(null)),
    unreadable: await turn(() => Promise.reject(new Error("down"))),
  };
  assertEquals(routeSignalsOf(states.moderate).screening, "moderate_until_cleared");
  assertEquals(routeSignalsOf(states.cleared).screening, "cleared");
  assertEquals(routeSignalsOf(states.never).screening, "cleared");
  assertEquals(routeSignalsOf(states.unreadable).screening, "unknown");
  assertEquals(strongRouteReasons(routeSignalsOf(states.moderate)), ["screening_not_cleared"]);
  assertEquals(strongRouteReasons(routeSignalsOf(states.unreadable)), ["screening_not_cleared"]);
  assertEquals(strongRouteReasons(routeSignalsOf(states.cleared)), []);
});

Deno.test("the same words choose the same route for the same records: the question is not an input", () => {
  const strong = sonnet();
  const defaultRoute = haiku();
  const questions = ["How is my progress this month?", "hi", "check my training"];
  for (const _question of questions) {
    assertEquals(selectCoachChatRoute(calm, defaultRoute, strong).tier, "default");
    assertEquals(
      selectCoachChatRoute({ ...calm, pain: "on_record" }, defaultRoute, strong).tier,
      "strong",
    );
  }
});

Deno.test("the stronger route answers when a signal asks for it and it is set", () => {
  const strong = sonnet();
  const picked = selectCoachChatRoute({ ...calm, pain: "on_record" }, haiku(), strong);
  assertEquals(picked.tier, "strong");
  assertEquals(picked.route, strong);
  assertEquals(picked.reasons, ["pain_on_record"]);
});

Deno.test("the default route answers without a stronger route or without a signal", () => {
  const defaultRoute = haiku();
  const calmTurn = selectCoachChatRoute(calm, defaultRoute, sonnet());
  assertEquals([calmTurn.tier, calmTurn.route], ["default", defaultRoute]);
  const unset = selectCoachChatRoute({ ...calm, pain: "on_record" }, defaultRoute, null);
  assertEquals([unset.tier, unset.route], ["default", defaultRoute]);
  assertEquals(unset.reasons, ["pain_on_record"]);
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
