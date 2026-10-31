// Investigate-first cases: a question that is really several questions. For each one the bank
// names the kinds of record (Coverage Brief domains) the answer turns on; the turn passes when
// every one is either in the baseline for the period it needs or was looked up (`domain_coverage`),
// and, for a trivial or narrow question, when it fetched no more than a few lookups (`over_fetch`).
//
// "Should I train legs today?" needs the plan, recovery, sleep, soreness and pain, and the recent
// sessions at set level; the athlete file holds summaries of them, so the model has to ask for the
// detail. The good requests are what a Coach that investigates first sends in its first round.
// Synthetic athletes only; the replies carry no figures, so the numbers check has nothing to ground.
import { splitPlanPayload } from "../../_shared/coach_context/contributors/plan_fixtures.ts";
import { athlete, baseContext, ownerToday, withCheckIn } from "./athletes.ts";
import { domainProblem } from "./graders.ts";
import type { Athlete, BankCase, DataRequest, DomainNeed } from "./types.ts";

const today = ownerToday; // 2026-10-14, a Wednesday

const need = (domain: string, extra: Omit<DomainNeed, "domain"> = {}): DomainNeed => ({
  domain,
  ...extra,
});
const ask = (lookup: string, from: string, to: string, filter?: string): DataRequest => ({
  lookup,
  from,
  to,
  ...(filter ? { filter } : {}),
});

const checkIn = {
  sleep_quality: 3,
  energy: 3,
  mood: 4,
  soreness: 3,
  hunger: 3,
  pain_severity: 0,
  available_to_train: true,
};

/** The rich athlete on a Wednesday with a plan loaded: a session today and another tomorrow. */
const planned = (): Athlete =>
  athlete(withCheckIn(baseContext("rich", today), checkIn), {
    trainingPlan: splitPlanPayload(3, ["w-chest-a", "w-legs-a"]),
  });

/** The rich athlete with no plan payload: the file's summaries only. */
const summaryOnly = (): Athlete => athlete(withCheckIn(baseContext("rich", today), checkIn));

type Spec = Readonly<{
  id: string;
  description: string;
  question: string;
  athlete?: () => Athlete;
  needs: readonly DomainNeed[];
  requests: readonly DataRequest[];
  reply: string;
  /** A request list that leaves out a kind the question needs. */
  incomplete?: readonly DataRequest[];
  maxRequests?: number;
  noLookup?: boolean;
}>;

/** Distinct lookups over the last week, as many as asked for: the shape of over-fetching. */
const sweepOf = (count: number): DataRequest[] =>
  [
    "recovery",
    "check_ins",
    "body",
    "goals",
    "weekly_reviews",
    "meals",
    "workouts",
    "health_history",
    "past_messages",
  ]
    .slice(0, count).map((lookup) =>
      ask(lookup, "2026-10-07", today, lookup === "past_messages" ? "training" : undefined)
    );

/** Mistakes in a case's own data, found when the cases are built; the module refuses to load with any. */
const authoring: string[] = [];

function investigation(spec: Spec): BankCase {
  const incomplete = spec.incomplete ?? [];
  const given = (spec.athlete ?? planned)();
  const missing = (requests: readonly DataRequest[]) =>
    domainProblem(spec.needs, given.context, given.contributors, requests);
  // The baseline alone may not cover the question: then the turn must look something up, and a
  // list that leaves a kind out must fail. A list that covers everything would not be a bad example.
  const needsALookup = missing([]) !== null;
  if (missing(spec.requests) !== null) {
    authoring.push(`${spec.id}: the good requests do not cover ${missing(spec.requests)}`);
  }
  if (needsALookup && missing(incomplete) === null) {
    authoring.push(`${spec.id}: the incomplete requests cover every kind the question needs`);
  }
  if (!needsALookup && spec.incomplete !== undefined) {
    authoring.push(`${spec.id}: the baseline covers the question, so there is no incomplete list`);
  }
  return {
    id: spec.id,
    category: "investigation",
    description: spec.description,
    athlete: spec.athlete ?? planned,
    question: spec.question,
    expect: {
      screen: "none",
      ...(spec.noLookup ? { lookup: { kind: "none" as const } } : {}),
      checks: {
        domains: spec.needs,
        ...(spec.maxRequests === undefined ? {} : { maxRequests: spec.maxRequests }),
      },
    },
    goodRequests: spec.requests,
    good: [spec.reply],
    bad: [
      ...(needsALookup
        ? [{ reply: spec.reply, requests: incomplete, fails: "domain_coverage" }]
        : []),
      ...(spec.maxRequests === undefined ? [] : [{
        reply: spec.reply,
        requests: sweepOf(spec.maxRequests + 1),
        fails: "over_fetch",
      }]),
    ],
  };
}

const month = "2026-09-14";
const twoMonths = "2026-08-14";
const week = "2026-10-07";
const sleepWindow = "2026-09-01";
const ahead = "2026-10-21";

export const investigationCases: readonly BankCase[] = [
  investigation({
    id: "inv-train-legs-today",
    description:
      "'Should I train legs today?' is a plan, recovery, sleep, soreness and recent-sessions question; the sessions need their sets.",
    question: "Should I train legs today?",
    needs: [
      need("plan_ahead"),
      need("recovery"),
      need("check_ins"),
      need("training", { detail: true }),
    ],
    requests: [
      ask("workouts", month, today, "squat"),
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("check_ins", week, today),
    ],
    incomplete: [ask("plan_history", today, ahead, "schedule")],
    reply:
      "Today's plan is a pull session, and legs come later in the week. Your last leg work was a few days back, so you are not short on rest. Keep to the plan today and let the legs recover for their own day.",
  }),
  investigation({
    id: "inv-check-my-training",
    description:
      "'Check my training' names no domain; the sweep covers the plan, the sessions and how recovery is going.",
    question: "Can you check my training?",
    needs: [
      need("plan_ahead"),
      need("training", { detail: true }),
      need("recovery"),
      need("check_ins"),
    ],
    requests: [
      ask("workouts", month, today),
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("check_ins", week, today),
    ],
    incomplete: [ask("plan_history", today, ahead, "schedule")],
    reply:
      "You have been training steadily, and the plan for the rest of the week is balanced. Recovery looks fine for the work you are doing. Keep today's pull session as planned, then see how the legs feel before the next one.",
  }),
  investigation({
    id: "inv-week-looking",
    description:
      "'How is my week looking?' reaches the days ahead and the week's food and recovery.",
    question: "How is my week looking?",
    needs: [need("plan_ahead"), need("training"), need("recovery"), need("nutrition")],
    requests: [
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("meals", week, today),
    ],
    maxRequests: 6,
    reply:
      "Two sessions are done and the rest of the week is laid out with a rest day between the chest days. Food has been steady and recovery is holding up. The main thing is to keep tomorrow's session honest and not stack extra work on top.",
  }),
  investigation({
    id: "inv-overdoing",
    description:
      "'Am I overdoing it?' needs the sessions at set level, recovery over more than the file's window, check-ins and the watch's workouts.",
    question: "Am I overdoing it?",
    needs: [
      need("training", { detail: true }),
      need("recovery", { since: sleepWindow }),
      need("check_ins"),
      need("watch_workouts", { since: month }),
    ],
    requests: [
      ask("workouts", month, today),
      ask("recovery", sleepWindow, today),
      ask("check_ins", week, today),
      ask("health_history", month, today, "workouts"),
    ],
    incomplete: [ask("workouts", month, today), ask("check_ins", week, today)],
    reply:
      "Your training load has been consistent rather than excessive, and nothing in your recovery or the extra watch workouts says you are running ahead of yourself. Keep the planned rest days and watch how you feel after the next two sessions.",
  }),
  investigation({
    id: "inv-weight-flat",
    description:
      "'Why is my weight flat?' reaches weight, food, training and the goal and proposals behind it.",
    question: "Why is my weight flat?",
    needs: [
      need("body", { since: "2026-08-01" }),
      need("nutrition", { since: month }),
      need("training"),
      need("goals"),
      need("proposals", { detail: true }),
    ],
    requests: [
      ask("body", "2026-08-01", today),
      ask("meals", month, today),
      ask("goals", "2026-07-01", today),
      ask("plan_history", "2026-08-01", today, "proposals"),
    ],
    incomplete: [ask("body", "2026-08-01", today), ask("meals", month, today)],
    reply:
      "Over the weeks I looked at, your weight has barely moved while your logged food and training stayed steady, so your intake is close to what you burn. A plateau like this is normal; the next step is a small adjustment to food, which I can put forward for you to approve.",
  }),
  investigation({
    id: "inv-bench-stalled",
    description:
      "A stalled lift needs the lift's history, recovery over weeks, food and check-ins.",
    question: "My bench has stalled. Why?",
    needs: [
      need("training", { detail: true }),
      need("recovery", { since: sleepWindow }),
      need("nutrition", { since: month }),
      need("check_ins"),
    ],
    requests: [
      ask("exercise_history", twoMonths, today, "bench press"),
      ask("recovery", sleepWindow, today),
      ask("meals", month, today),
      ask("check_ins", week, today),
    ],
    incomplete: [ask("exercise_history", twoMonths, today, "bench press")],
    reply:
      "Your bench has been flat across the sessions I looked at while your sleep and food were steady, so this looks like a plain plateau rather than fatigue. Hold the load, aim for one more rep on each set, and give it two weeks before changing anything.",
  }),
  investigation({
    id: "inv-sleeping-badly",
    description:
      "Poor sleep reaches the watch's sleep over weeks, how the athlete felt, training timing and food.",
    question: "I have been sleeping badly. What should I change?",
    needs: [
      need("recovery", { since: sleepWindow }),
      need("check_ins", { since: month }),
      need("training"),
      need("nutrition"),
    ],
    requests: [
      ask("recovery", sleepWindow, today),
      ask("check_ins", month, today),
      ask("meals", week, today),
    ],
    incomplete: [ask("recovery", sleepWindow, today)],
    reply:
      "Your sleep has been shorter on the nights after late meals and hard sessions. Move your last meal earlier, keep a steady bedtime, and finish training a bit earlier in the evening. Check back with me in a week and we will see if it moved.",
  }),
  investigation({
    id: "inv-tired-lately",
    description: "'Tired all the time' reaches recovery, check-ins, food and weight over weeks.",
    question: "I feel tired all the time lately.",
    needs: [
      need("recovery", { since: sleepWindow }),
      need("check_ins", { since: month }),
      need("nutrition"),
      need("body"),
    ],
    requests: [
      ask("recovery", sleepWindow, today),
      ask("check_ins", month, today),
      ask("meals", week, today),
    ],
    incomplete: [ask("check_ins", month, today)],
    reply:
      "Your sleep and recovery have both slipped over the last few weeks, and your food has been on the lighter side while you keep training. That combination explains the tiredness. Eat a little more around training and protect your sleep before adding anything.",
  }),
  investigation({
    id: "inv-skip-today",
    description:
      "'Can I skip today?' needs today's session, recovery, how the athlete feels and the week's other sessions.",
    question: "Can I skip today's session?",
    needs: [need("plan_ahead"), need("recovery"), need("check_ins"), need("training")],
    requests: [
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("check_ins", week, today),
    ],
    maxRequests: 6,
    reply:
      "You could, but today is a pull session that sits between two chest days, so skipping it leaves a gap in the week. If you are only a bit tired, do it lighter and shorter rather than skipping it.",
  }),
  investigation({
    id: "inv-deload",
    description:
      "'Do I need a deload?' needs the sessions over a long span, recovery over weeks, check-ins and the plan's history.",
    question: "Do I need a deload?",
    needs: [
      need("training", { since: twoMonths, detail: true }),
      need("recovery", { since: sleepWindow }),
      need("check_ins"),
      need("plan_versions"),
    ],
    requests: [
      ask("workouts", twoMonths, today),
      ask("recovery", sleepWindow, today),
      ask("check_ins", week, today),
      ask("plan_history", twoMonths, today),
    ],
    incomplete: [ask("workouts", twoMonths, today), ask("recovery", sleepWindow, today)],
    reply:
      "Not yet. You are several weeks into this block with steady sessions and no sign in your recovery that you are running down. Plan a lighter week when the weights start to slip or you feel flat, and I will tell you if I see that.",
  }),
  investigation({
    id: "inv-travel-next-week",
    description:
      "Planning a trip needs the plan beyond the next seven days and any change already proposed.",
    question: "I am travelling next week. How should I plan my training?",
    needs: [
      need("plan_ahead", { detail: true, until: "2026-10-26" }),
      need("proposals", { detail: true }),
      need("training"),
    ],
    requests: [
      ask("plan_history", "2026-10-19", "2026-10-26", "schedule"),
      ask("plan_history", month, today, "proposals"),
    ],
    incomplete: [ask("plan_history", month, today, "proposals")],
    reply:
      "Next week you have a full set of sessions, and the simplest plan is to keep two of them as short home sessions and drop the rest. I can put a temporary change forward for you to approve once you tell me what kit you will have.",
  }),
  investigation({
    id: "inv-eating-enough-training",
    description:
      "'Am I eating enough on training days?' needs the meals by day and the training days they line up with.",
    question: "Am I eating enough on training days?",
    needs: [need("nutrition", { detail: true }), need("training", { detail: true }), need("body")],
    requests: [
      ask("meals", month, today),
      ask("workouts", month, today),
    ],
    incomplete: [ask("meals", month, today)],
    reply:
      "On the days you trained, your logged food ran lighter than on rest days, and several of those days look only partly logged. Add a proper meal around your session, and log the rest of the day so I can judge it properly.",
  }),
  investigation({
    id: "inv-protein-enough",
    description:
      "'Is my protein enough?' needs the foods behind the totals, weight and training and the goal.",
    question: "Is my protein enough?",
    needs: [need("nutrition", { detail: true }), need("body"), need("training"), need("goals")],
    requests: [ask("meals", month, today), ask("goals", "2026-07-01", today)],
    incomplete: [ask("goals", "2026-07-01", today)],
    reply:
      "Judging from the foods you logged, your protein is close to your target on most days and lower on the days with a missing meal. Spread it over each meal, and log those days fully so I can see it.",
  }),
  investigation({
    id: "inv-quads-sore-legs",
    description:
      "Sore quads and a leg day: soreness, the last leg sessions at set level, recovery and the plan.",
    question: "My quads are still sore from Monday. Can I train legs tomorrow?",
    needs: [
      need("check_ins"),
      need("training", { detail: true }),
      need("recovery"),
      need("plan_ahead"),
    ],
    requests: [
      ask("workouts", month, today, "squat"),
      ask("check_ins", week, today),
      ask("recovery", week, today),
      ask("plan_history", today, ahead, "schedule"),
    ],
    incomplete: [ask("check_ins", week, today), ask("recovery", week, today)],
    reply:
      "Tomorrow is a chest session, so your legs get another day. If the soreness is gone by the weekend, train them then; if not, keep the work light and shorter.",
  }),
  investigation({
    id: "inv-month-review",
    description:
      "'How has my month been?' reaches the sessions, weight, food and recovery over the month and the reviews.",
    question: "How has my month been?",
    needs: [
      need("training", { since: month, detail: true }),
      need("body", { since: month }),
      need("nutrition", { since: month }),
      need("recovery", { since: month }),
      need("reviews"),
    ],
    requests: [
      ask("workouts", month, today),
      ask("body", month, today),
      ask("meals", month, today),
      ask("recovery", month, today),
      ask("weekly_reviews", month, today),
    ],
    incomplete: [ask("workouts", month, today), ask("body", month, today)],
    reply:
      "It has been a steady month: you trained consistently, your weight moved a little and your recovery held up. The weak spot is food logging, which has a few thin days. Fix that and the next month will be easier to judge.",
  }),
  investigation({
    id: "inv-last-week-review",
    description:
      "'Review last week' reaches last week's sessions at set level, food, recovery and the weekly review.",
    question: "Can you review last week for me?",
    needs: [
      need("training", { detail: true }),
      need("nutrition"),
      need("recovery"),
      need("reviews"),
    ],
    requests: [
      ask("workouts", week, today),
      ask("weekly_reviews", month, today),
      ask("meals", week, today),
      ask("recovery", week, today),
    ],
    incomplete: [ask("workouts", week, today)],
    reply:
      "Last week you completed most of your planned sessions and your food and recovery were steady. The one miss was the legs session, which is the one to protect this week. Otherwise I would change nothing.",
  }),
  investigation({
    id: "inv-runs-and-lifting",
    description:
      "'Did my running hurt my lifting?' needs the watch's workouts from before the file's window, the lifts and recovery.",
    question: "I ran a lot last month. Did that hurt my lifting?",
    needs: [
      need("watch_workouts", { since: month }),
      need("training", { since: month, detail: true }),
      need("recovery", { since: month }),
    ],
    requests: [
      ask("health_history", month, today, "workouts"),
      ask("workouts", month, today),
      ask("recovery", month, today),
    ],
    incomplete: [ask("workouts", month, today), ask("recovery", month, today)],
    reply:
      "In the weeks you ran more, your leg lifts held steady but your recovery was lower on the days after longer runs. So the running cost you freshness more than strength. Keep the runs easy on the day before leg work.",
  }),
  investigation({
    id: "inv-why-plan-changed",
    description:
      "'Why did you change my plan?' needs the plan versions with why, the proposals and the daily decisions.",
    question: "Why did you change my plan?",
    needs: [
      need("plan_versions"),
      need("proposals", { detail: true }),
      need("decisions"),
      need("conversation"),
    ],
    requests: [
      ask("plan_history", twoMonths, today),
      ask("plan_history", twoMonths, today, "proposals"),
      ask("weekly_reviews", month, today, "decisions"),
    ],
    incomplete: [ask("plan_history", twoMonths, today)],
    reply:
      "The plan changed when you approved the proposal for it, and the reason recorded was to fit your training days. Nothing changes without your approval. If you want the older version back, say so and I will put that forward.",
  }),
  investigation({
    id: "inv-declined-proposal",
    description:
      "'What did I decline?' is answered from the proposal history, not the last three the file holds.",
    question: "What did I decline last time you suggested something?",
    needs: [need("proposals", { detail: true }), need("conversation")],
    requests: [
      ask("plan_history", twoMonths, today, "proposals"),
      ask("past_messages", twoMonths, today, "decline suggestion"),
    ],
    incomplete: [ask("past_messages", twoMonths, today, "decline suggestion")],
    reply:
      "You declined the proposal to lower your calories, and I should not push it again unless your weight stays flat. The other changes you accepted are still in your plan.",
  }),
  investigation({
    id: "inv-yesterday-call",
    description: "'What was the call yesterday?' is the daily decisions history.",
    question: "What was your call on my training yesterday?",
    needs: [need("decisions"), need("training")],
    requests: [
      ask("weekly_reviews", week, today, "decisions"),
      ask("workouts", week, today),
    ],
    incomplete: [ask("workouts", week, today)],
    reply:
      "Yesterday's call was to keep the session as planned, and you did it. Nothing in what I can see said to change it.",
  }),
  investigation({
    id: "inv-earlier-advice",
    description:
      "'What did you tell me last time?' needs Coach's own earlier replies, which are not records.",
    question: "What did you tell me about my lower back last time?",
    needs: [need("conversation", { detail: true }), need("training")],
    requests: [
      ask("past_messages", twoMonths, today, "lower back"),
      ask("workouts", month, today),
    ],
    incomplete: [ask("workouts", month, today)],
    reply:
      "Earlier I suggested keeping hinges light while it settled. I would not lean on that alone; looking at your recent sessions, you have been lifting normally, so tell me how it feels now.",
  }),
  investigation({
    id: "inv-tomorrow",
    description:
      "'What's tomorrow?' reaches the plan, the muscles two days share, recovery and how the athlete feels.",
    question: "What does tomorrow look like?",
    needs: [need("plan_ahead"), need("recovery"), need("check_ins"), need("training")],
    requests: [
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("check_ins", week, today),
    ],
    maxRequests: 6,
    reply:
      "Tomorrow is a chest and delts session. You trained pull today, so the muscles are fresh, and your recovery is fine for it. Go in as planned.",
  }),
  investigation({
    id: "inv-next-week",
    description: "'What does next week look like?' goes past the next seven days.",
    question: "What does next week look like?",
    needs: [
      need("plan_ahead", { detail: true, until: "2026-10-26" }),
      need("proposals", { detail: true }),
      need("recovery"),
    ],
    requests: [
      ask("plan_history", "2026-10-19", "2026-10-26", "schedule"),
      ask("plan_history", month, today, "proposals"),
      ask("recovery", week, today),
    ],
    incomplete: [ask("plan_history", "2026-10-19", "2026-10-26", "schedule")],
    reply:
      "Next week repeats this one: chest on Monday, legs on Tuesday, pull on Wednesday, and the others later. No change is waiting for your approval, so it stands as it is.",
  }),
  investigation({
    id: "inv-fasted-training",
    description:
      "'Can I train fasted tomorrow?' needs tomorrow's session, the food pattern and recovery.",
    question: "Can I train fasted tomorrow morning?",
    needs: [
      need("plan_ahead"),
      need("nutrition", { detail: true }),
      need("recovery"),
      need("training"),
    ],
    requests: [
      ask("plan_history", today, ahead, "schedule"),
      ask("meals", week, today),
      ask("recovery", week, today),
    ],
    incomplete: [ask("plan_history", today, ahead, "schedule"), ask("recovery", week, today)],
    reply:
      "Tomorrow is a heavy chest session, and on the mornings you ate before training your logged sessions went better. Have something small with carbs and protein beforehand rather than going fasted.",
  }),
  investigation({
    id: "inv-gaining-muscle",
    description:
      "'Am I gaining muscle?' needs weight and waist over months, the lifts' history and food.",
    question: "Am I gaining muscle?",
    needs: [
      need("body", { since: "2026-08-01" }),
      need("training", { since: twoMonths, detail: true }),
      need("nutrition", { since: month }),
    ],
    requests: [
      ask("body", "2026-08-01", today),
      ask("workouts", twoMonths, today),
      ask("meals", month, today),
    ],
    incomplete: [ask("body", "2026-08-01", today)],
    reply:
      "Your main lifts have gone up over the last two months while your waist stayed about the same, which fits slow muscle gain. Weight alone cannot tell us, so keep the lifts and the waist as the signals.",
  }),
  investigation({
    id: "inv-resting-hr-trend",
    description:
      "'Is my resting heart rate trending up?' needs the watch's days beyond the file's window and how the athlete feels.",
    question: "Is my resting heart rate trending up?",
    needs: [need("recovery", { since: sleepWindow }), need("check_ins"), need("training")],
    requests: [
      ask("recovery", sleepWindow, today),
      ask("check_ins", week, today),
    ],
    incomplete: [ask("check_ins", week, today)],
    reply:
      "Over the weeks of watch data, your resting heart rate has moved within its usual band, not upward. If you start to feel flat with it creeping up, tell me and we will ease the load.",
  }),
  investigation({
    id: "inv-keep-missing",
    description:
      "'Why do I keep missing sessions?' needs the plan's days, the sessions logged over months and how the athlete felt.",
    question: "Why do I keep missing sessions?",
    needs: [
      need("plan_ahead"),
      need("training", { since: twoMonths, detail: true }),
      need("check_ins", { since: month }),
      need("recovery"),
    ],
    requests: [
      ask("plan_history", twoMonths, today, "schedule"),
      ask("workouts", twoMonths, today),
      ask("check_ins", month, today),
    ],
    incomplete: [ask("workouts", twoMonths, today)],
    reply:
      "The sessions you miss are mostly the late-week ones, and they follow low-energy check-ins. Moving one of those sessions earlier in the week, or shortening it, would fit your pattern better. I can put that forward for you to approve.",
  }),
  investigation({
    id: "inv-squat-pr",
    description:
      "'Can I hit a PR today?' needs the lift's history, recovery, how the athlete feels and what today is.",
    question: "Can I hit a squat PR this week?",
    needs: [
      need("training", { since: twoMonths, detail: true }),
      need("recovery"),
      need("check_ins"),
      need("plan_ahead"),
    ],
    requests: [
      ask("exercise_history", twoMonths, today, "squat"),
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("check_ins", week, today),
    ],
    incomplete: [ask("plan_history", today, ahead, "schedule")],
    reply:
      "Your squat has been climbing for a few weeks, and legs are not until later in the week, so you can attempt it then if you feel fresh. Warm up well, and stop at a rep you could still repeat.",
  }),
  investigation({
    id: "inv-pre-workout-meal",
    description:
      "'What should I eat before training?' needs today's session, the food so far and the foods that suited the athlete.",
    question: "What should I eat before training today?",
    needs: [need("plan_ahead"), need("nutrition", { detail: true }), need("training")],
    requests: [
      ask("plan_history", today, ahead, "schedule"),
      ask("meals", week, today),
    ],
    incomplete: [ask("plan_history", today, ahead, "schedule")],
    reply:
      "Today is a pull session, so aim for a meal with carbs and some protein an hour or two before, such as oats with curd or a banana and some milk. Keep it light if you train early.",
  }),
  investigation({
    id: "inv-add-cardio",
    description:
      "'Can I add cardio?' needs the plan's room, recovery, the sessions and the watch's workouts.",
    question: "Can I add some cardio this week?",
    needs: [
      need("plan_ahead"),
      need("recovery"),
      need("training", { detail: true }),
      need("watch_workouts", { since: month }),
    ],
    requests: [
      ask("plan_history", today, ahead, "schedule"),
      ask("recovery", week, today),
      ask("workouts", month, today),
      ask("health_history", month, today, "workouts"),
    ],
    incomplete: [ask("plan_history", today, ahead, "schedule"), ask("recovery", week, today)],
    reply:
      "Yes, on the rest days between your sessions, and keep it easy so it does not eat into your lifting. The day before legs is the one to leave free.",
  }),
  investigation({
    id: "inv-sleep-and-lifts",
    description: "'Do my lifts drop when I sleep less?' needs sleep and the lifts over two months.",
    question: "Do my lifts drop when I sleep less?",
    needs: [
      need("recovery", { since: twoMonths }),
      need("training", { since: twoMonths, detail: true }),
      need("check_ins", { since: month }),
    ],
    requests: [
      ask("recovery", twoMonths, today),
      ask("workouts", twoMonths, today),
      ask("check_ins", month, today),
    ],
    incomplete: [ask("recovery", twoMonths, today)],
    reply:
      "A little. On the days after your shortest nights you finished fewer reps on the big lifts, though the effect was small. A steadier bedtime will help more than any change to the plan.",
  }),
  investigation({
    id: "inv-meals-last-week",
    description: "A narrow question about one week of meals fetches that and little else.",
    question: "What did I eat last Wednesday?",
    needs: [need("nutrition", { detail: true, since: "2026-10-07", until: "2026-10-07" })],
    requests: [ask("meals", "2026-10-07", "2026-10-07")],
    incomplete: [],
    maxRequests: 2,
    reply: "On Wednesday you logged breakfast and lunch only, so the day is incomplete.",
  }),
  investigation({
    id: "inv-weight-on-date",
    description: "A narrow question about one weigh-in fetches the body lookup and little else.",
    question: "What did I weigh on the first of October?",
    needs: [need("body", { since: "2026-10-01", until: "2026-10-01", detail: true })],
    requests: [ask("body", "2026-10-01", "2026-10-01")],
    incomplete: [],
    maxRequests: 2,
    reply:
      "I have the weigh-in recorded for that date in your readings; it was close to the rest of that week.",
  }),
  investigation({
    id: "inv-todays-session",
    description:
      "The baseline already holds today's session; asking for more than a few lookups is over-fetching.",
    question: "What is my session today?",
    needs: [need("plan_ahead")],
    requests: [],
    maxRequests: 3,
    reply:
      "Today is your pull session: rows and pulldowns first, then the curls and rear delts. Your plan has the sets and loads for each.",
  }),
  investigation({
    id: "inv-greeting",
    description: "A greeting needs no record: no lookups.",
    question: "hi coach",
    athlete: summaryOnly,
    needs: [],
    requests: [],
    noLookup: true,
    maxRequests: 0,
    reply: "Hi! Good to see you. What would you like to work on today?",
  }),
  investigation({
    id: "inv-thanks",
    description: "Thanks needs no record: no lookups.",
    question: "thanks, that helps",
    athlete: summaryOnly,
    needs: [],
    requests: [],
    noLookup: true,
    maxRequests: 0,
    reply: "Glad it helped. Tell me how the session goes.",
  }),
  investigation({
    id: "inv-general-breathing",
    description: "A general-knowledge question uses no record of the athlete: no lookups.",
    question: "How should I breathe during a squat?",
    athlete: summaryOnly,
    needs: [],
    requests: [],
    noLookup: true,
    maxRequests: 0,
    reply:
      "Breathe in at the top, brace your trunk, hold through the way down and up past the hardest point, then breathe out at the top before the next rep.",
  }),
  investigation({
    id: "inv-app-howto",
    description: "A question about the app uses no record of the athlete: no lookups.",
    question: "Where can I see my past check-ins in the app?",
    athlete: summaryOnly,
    needs: [],
    requests: [],
    noLookup: true,
    maxRequests: 0,
    reply:
      "Open your history from the check-in screen in the app; every day you filled in is listed there. I can also read them for you if you ask about a period.",
  }),
];

if (authoring.length > 0) throw new Error(authoring.join("\n"));
