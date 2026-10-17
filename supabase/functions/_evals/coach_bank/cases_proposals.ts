// Proposal cases (A8): a change the athlete asks for in chat must come back as a `proposal_intent`
// the rules accept (Coach says a proposal is waiting for approval and never that it changed
// anything), and a question that asks for no change must not propose one. The refused request
// (calories below the floor) is in the floor cases.
import { athlete, baseContext } from "./athletes.ts";
import { proposalWords } from "./phrases.ts";
import type { Athlete, BankCase } from "./types.ts";

const plain = (): Athlete => athlete(baseContext("rich"));

const proposes = (
  id: string,
  question: string,
  description: string,
  good: string,
  intent: Readonly<Record<string, unknown>>,
  expected: Extract<NonNullable<BankCase["expect"]["proposal"]>, { kind: "intent" }>,
  bad: BankCase["bad"],
): BankCase => ({
  id,
  category: "proposals",
  description,
  athlete: plain,
  question,
  expect: { screen: "none", mentions: [proposalWords], proposal: expected },
  good: [good],
  goodIntent: intent,
  bad,
});

export const proposalCases: readonly BankCase[] = [
  proposes(
    "proposal-home-block",
    "I'll be home for 10-15 days with no gym.",
    "A spell without the gym: a temporary block that ends on its date.",
    "Here's a proposal you can approve below: bodyweight sessions on your usual training days until you're back, then your regular plan returns. Tracend checks the volume against your limits first. Do you have a pull-up bar or bands at home?",
    {
      kind: "temporary_block",
      reason: "travel",
      setting: "bodyweight",
      start_date: "2026-09-27",
      end_date: "2026-10-11",
    },
    { kind: "intent", intent: "temporary_block" },
    [
      {
        reply:
          "Done. I've switched you to bodyweight sessions until you're back, then your plan returns.",
        fails: "reply_guard",
      },
      {
        reply:
          "Here's a proposal you can approve below: bodyweight sessions until you're back. Do you have bands at home?",
        fails: "proposal_intent",
        intent: null,
      },
    ],
  ),
  proposes(
    "proposal-four-days",
    "Let's change my plan for the next 2 months to 4 days a week.",
    "A new schedule for some weeks.",
    "Here's a proposal you can approve below: your week rebuilt for four sessions, reviewed after eight weeks. Tracend keeps your weekly volume and effort inside your limits. Which days work best for you?",
    {
      kind: "training_schedule",
      reason: "athlete_request",
      days_per_week: 4,
      weeks: 8,
    },
    { kind: "intent", intent: "training_schedule", has: { daysPerWeek: 4, weeks: 8 } },
    [{
      reply:
        "Here's a proposal you can approve below: five sessions a week for two months. Which days work best for you?",
      fails: "proposal_intent",
      intent: {
        kind: "training_schedule",
        reason: "athlete_request",
        days_per_week: 5,
        weeks: 8,
      },
    }],
  ),
  proposes(
    "proposal-diet-break",
    "Take a diet break.",
    "A diet break: maintenance calories for a short spell, the goal kept.",
    "Here's a proposal you can approve below: a short diet break at maintenance calories, with your fat-loss goal kept. It rests you from the deficit without losing progress, and Tracend works out the calories for you.",
    { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    { kind: "intent", intent: "goal_or_phase", has: { phase: "diet_break" } },
    [{
      reply:
        "Here's a proposal you can approve below: a short diet break at maintenance calories, with your goal kept.",
      fails: "proposal_intent",
      intent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "cut" },
    }],
  ),
  proposes(
    "proposal-lighter-tomorrow",
    "Tomorrow I'm tired, go lighter.",
    "A lighter next session, within one load step.",
    "Here's a proposal you can approve below: your next session a little lighter, with fewer sets and a lower effort. Your regular plan carries on after it. How are you feeling about the rest of the week?",
    {
      kind: "next_session_adjustment",
      reason: "fatigue",
      direction: "lighter",
      session: "next",
    },
    { kind: "intent", intent: "next_session_adjustment", has: { direction: "lighter" } },
    [{
      reply:
        "Here's a proposal you can approve below: your next session a little heavier. How are you feeling?",
      fails: "proposal_intent",
      intent: {
        kind: "next_session_adjustment",
        reason: "fatigue",
        direction: "heavier",
        session: "next",
      },
    }],
  ),
  {
    id: "proposal-not-asked",
    category: "proposals",
    description:
      "A question about what a diet break is asks for no change: answer, propose nothing.",
    athlete: plain,
    question: "What is a diet break, and when would someone need one?",
    expect: { screen: "none" },
    good: [
      "A diet break is a planned stretch, often a week or two, at maintenance calories in the middle of a fat-loss phase. People use one when hunger, energy or training quality has been slipping after a long deficit. Want me to look at whether you are near that point?",
    ],
    bad: [{
      reply:
        "A diet break is a short stretch at maintenance calories. Here's a proposal you can approve below.",
      fails: "proposal_intent",
      intent: { kind: "goal_or_phase", reason: "diet_fatigue", phase: "diet_break" },
    }],
  },
];
