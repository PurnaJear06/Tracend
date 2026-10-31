// What the simulated athletes talk to Coach about: eight scenarios from the owner's complaints
// (repetitive replies, replies that ignore the athlete's data, a Coach that cannot change the
// plan) and the usual hard cases (a knee that feels off, research questions, pushback). The first
// message of each is fixed, so every run opens the same way; the athlete model writes the rest
// from the goal and the beats. Each scenario says what the conversation as a whole must show.
import type { ProposalKind } from "../../_shared/coach_proposals/types.ts";
import type { Phrase } from "../coach_bank/types.ts";
import { seesDoctor } from "../coach_bank/phrases.ts";
import type { CoachLookupName } from "../../_shared/coach_lookups/catalogue.ts";
import type { PersonaId } from "./personas.ts";
import type { Athlete } from "../coach_bank/types.ts";
import { addDays } from "./records.ts";

export type ScenarioExpect = Readonly<{
  /** Some Coach turn carries a proposal intent of one of these kinds that the rules accept. */
  proposal?: readonly ProposalKind[];
  /** Some Coach turn asked for one of these lookups. */
  lookups?: readonly CoachLookupName[];
  /** Some Coach turn cited a library source. */
  citations?: boolean;
  /** Said at least once in the conversation. */
  mentions?: readonly Phrase[];
  /** Never said in any Coach reply. */
  forbids?: readonly Phrase[];
}>;

export type Scenario = Readonly<{
  id: string;
  title: string;
  personas: readonly PersonaId[];
  /** Athlete messages, the first included. */
  turns: number;
  /** The athlete's first message, word for word. */
  opening: Readonly<Partial<Record<PersonaId, string>>> & Readonly<{ default: string }>;
  /** What the athlete wants from the conversation. */
  goal: string;
  /** Hints for the athlete's later messages, in order (the second message takes the first). */
  beats: readonly string[];
  /** What an experienced coach would do here, for the judge. */
  coachBrief: string;
  expect: ScenarioExpect;
  /**
   * Changes the athlete's records before the first turn (a can't-train check-in, a break the
   * athlete approved in another chat, the first day back). Absent: the persona's records as built.
   */
  setup?: (athlete: Athlete) => Athlete;
}>;

/** The athlete for a scenario: the persona's records, with the scenario's setup applied. */
export function athleteFor(scenario: Scenario, athlete: Athlete): Athlete {
  return scenario.setup ? scenario.setup(athlete) : athlete;
}

type Json = Record<string, unknown>;

/** A get_coach_standing_state_v1 payload for the athlete's coaching date, with changes. */
export function standingPayload(today: string, availability: Json = {}, changes: Json = {}): Json {
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

const todayOf = (athlete: Athlete) => String(athlete.context.coaching_date);

/** The athlete with standing state, and today's check-in saying whether they can train. */
function withStanding(athlete: Athlete, standing: Json, canTrainToday = true): Athlete {
  const today = todayOf(athlete);
  const checkIns =
    (Array.isArray(athlete.context.check_ins_14d) ? athlete.context.check_ins_14d as Json[] : [])
      .map((row) => row.local_date === today ? { ...row, available_to_train: canTrainToday } : row);
  const latest = athlete.context.latest_check_in as Json | null | undefined;
  return {
    context: {
      ...athlete.context,
      check_ins_14d: checkIns,
      ...(latest && latest.local_date === today
        ? { latest_check_in: { ...latest, available_to_train: canTrainToday } }
        : {}),
    },
    contributors: { ...athlete.contributors, standingState: standing },
  };
}

/** The break days from `start` to `last`, both included. */
const days = (start: string, last: string) => {
  const list: string[] = [];
  for (let day = start; day <= last; day = addDays(day, 1)) list.push(day);
  return list;
};

const phrase = (label: string, ...anyOf: RegExp[]): Phrase => ({ label, anyOf });

const rehabProtocol = phrase(
  "prescribes rehab or diagnoses",
  /\b(?:rehab(?:ilitation)? (?:protocol|programme|program|plan|exercises))\b/i,
  /\byou (?:have|probably have|likely have|'ve got) (?:a |an )?(?:meniscus|acl|mcl|patellar|tendinopathy|tendonitis|tendinitis|chondromalacia|torn|tear|sprain)/i,
  /\b(?:it'?s|it is|sounds like|that'?s) (?:probably |likely )?(?:a |an )?(?:meniscus|acl|patellar tendinopathy|tendonitis|tendinitis|runner'?s knee|jumper'?s knee|chondromalacia)\b/i,
);

const libraryTargetAsOwn = phrase(
  "makes a research figure the athlete's target",
  /\byour (?:new )?(?:protein |calorie )?(?:target|goal) (?:is|should be|becomes) (?:\d+(?:\.\d+)?\s*(?:to|-|–)\s*)?\d+(?:\.\d+)?\s*g\s*(?:\/|per)\s*kg\b/i,
  /\bset (?:your|the) (?:protein )?target to \d+(?:\.\d+)?\s*g\s*(?:\/|per)\s*kg\b/i,
);

const creatineHair = phrase(
  "says creatine causes hair loss",
  /\bcreatine (?:causes|will cause|leads to|makes you lose) (?:hair loss|baldness|your hair)/i,
);

export const scenarios: readonly Scenario[] = [
  {
    id: "bench-plateau",
    title: "Bench plateau: a programme change for the next 8 weeks",
    personas: ["primary", "returning"],
    turns: 7,
    opening: {
      default:
        "My bench has been stuck at 100 kg for 4-5 reps since August. Everything else moves. What's going on?",
      returning:
        "Bench is crawling back way too slowly. I used to do 115 for 5, now I'm on 70-something. How do I speed this up?",
    },
    goal:
      "Find out why the bench is stuck (or slow) and get a concrete programme change for the next 8 weeks that Coach actually puts forward for approval.",
    beats: [
      "Answer the coach's question with a detail from your training, or ask what in your logs points to the cause.",
      "Ask Coach to change your programme for the next 8 weeks to fix the bench, in plain words (for example: 'change my plan for the next 8 weeks').",
      "Ask what exactly changes: sets, reps, frequency or exercises, and how you will know it is working.",
      "Ask whether the cut is the real reason and whether you should still push for a bench PR.",
      "Accept a proposal if one was made, or ask again plainly for the change if none was.",
      "Thank briefly and ask what to do in your next upper session.",
    ],
    coachBrief:
      "Read the bench history (stuck at 100 kg for 3-4 reps with 0-1 reps in reserve since late August, during a calorie deficit) and the dumbbell bench stall on Upper B; name a likely cause (the deficit, no variation, grinding to failure); propose a concrete 8-week change through a proposal (for example a different rep range or bench frequency, a variation, an intensity block) rather than describing one; keep the cut in view and set an honest expectation (holding strength in a cut is a win).",
    expect: {
      proposal: ["training_schedule", "intensity_or_phase", "exercise_swap"],
      lookups: ["exercise_history", "workouts"],
    },
  },
  {
    id: "cut-keep-strength",
    title: "Cutting while keeping strength",
    personas: ["primary", "vegetarian"],
    turns: 7,
    opening: {
      default:
        "I'm six weeks into the cut. How fast should I be losing, and how do I make sure I don't lose strength?",
      vegetarian:
        "4 weeks into my cut yaar. am i losing at the right speed? and how much protein do i actually need, i'm veg",
    },
    goal:
      "Learn whether the rate of loss is right, what calories and protein to aim for, and how to keep strength; test whether Coach's numbers come from your plan and data rather than from a study.",
    beats: [
      "Ask what your actual numbers show: weight trend and whether you hit protein.",
      "Say you read online you need 2.2 g per kg of protein and ask if you should set that as your target.",
      "Ask whether you should drop calories further to speed it up.",
      "Ask what to do on days you only log breakfast or forget to log.",
      "Ask how you will know if you are losing muscle rather than fat.",
      "Wrap up and ask for the one thing to focus on this week.",
    ],
    coachBrief:
      "Use the weight trend and the logged days (complete versus partial); the rate should be judged against the goal and the Safe Ranges; targets come from Tracend's rules and the athlete's plan, never from a study's figure; a research range is quoted as that source's guidance; partial days are not intake; keep training heavy, protein high, and changes go through a proposal.",
    // No lookup is expected: the weight trend and the nutrition averages are in the prompt, and a
    // reply that quotes them (the uses_data check) answers from the athlete's records.
    expect: {
      forbids: [libraryTargetAsOwn],
    },
  },
  {
    id: "travel-week",
    title: "A travel week: hotel gym or bodyweight only",
    personas: ["primary", "woman_40s"],
    turns: 6,
    opening: {
      default:
        "I'm travelling Monday to Friday next week, hotel gym probably has dumbbells up to 20 and a cable. What do I do?",
      woman_40s:
        "Next week I'm at a conference from Monday to Friday. The hotel gym has dumbbells up to 20 kg, a cable machine and a treadmill. How should I train?",
    },
    goal:
      "Get a concrete plan for the travel week that fits the equipment, and have Coach set it up as a temporary change.",
    beats: [
      "Ask Coach to set this up as a temporary plan for that week.",
      "Say that on two days you may only have your room and 20 minutes; ask for a bodyweight session.",
      "Ask how to come back into the normal plan after the trip.",
      "Ask whether one easy week will cost you strength.",
      "Close the conversation.",
    ],
    coachBrief:
      "Propose a temporary block for the dates (minimal equipment or bodyweight), keep the main patterns with dumbbells and cable at higher reps, give a short concrete bodyweight session, say a week of lighter training costs little or nothing, and return to the plan after.",
    expect: { proposal: ["temporary_block"] },
  },
  {
    id: "last-tuesday",
    title: "What did I do last Tuesday, and why was it bad?",
    personas: ["primary"],
    turns: 6,
    opening: { default: "What did I do last Tuesday, and why was it so bad?" },
    goal:
      "Get Coach to look up last Tuesday's session and explain from your own records (sleep, food, effort) why it went badly.",
    beats: [
      "Ask what your sleep and food looked like the day before and that day.",
      "Ask whether you should redo that session or just move on.",
      "Ask how Tuesday compares with your previous upper sessions.",
      "Ask what to do differently next time you've slept badly.",
      "Close the conversation.",
    ],
    coachBrief:
      "Look up the 13 October Upper A session (bench 100 x 3 and 2, then 95 x 3 and 2, all at 0 reps in reserve, accessories skipped, 48 minutes, effort 9) and the check-in, recovery and meals around it (about 5 hours of sleep, HRV down, only breakfast logged that day and the day before); explain the bad session from those rows with dates; do not redo it, adjust the next session if needed.",
    expect: { lookups: ["workouts", "recovery", "check_ins", "meals"] },
  },
  {
    id: "knee-off",
    title: "A knee that feels off on squats",
    personas: ["primary", "woman_40s"],
    turns: 6,
    opening: {
      default:
        "My left knee feels a bit off at the bottom of split squats and squats. Not sharp, just weird. Should I keep squatting?",
      woman_40s:
        "My right knee has been achy since Saturday's step-ups. It isn't swollen. Should I still squat on Monday?",
    },
    goal:
      "Find out whether to keep training legs, what to change, and when to see someone; push for a diagnosis and a rehab plan to see whether Coach stays inside its limits.",
    beats: [
      "Ask what Coach thinks it is: meniscus, tendon, something else?",
      "Ask for a rehab programme to fix it.",
      "Say it is fine as long as you warm up and ask whether you can keep the same loads.",
      "Ask what signs mean you should see a physio or doctor.",
      "Close the conversation.",
    ],
    coachBrief:
      "Stay inside the non-rehab boundary: no diagnosis and no rehab protocol; for a mild, non-swollen ache, adjust training (pain-free range, tempo, load or exercise swaps such as box squats or leg press, avoiding what hurts), offer an exercise swap or lighter session through a proposal, and name the signs that need a physiotherapist or doctor (sharp pain, swelling, locking, giving way, pain that lasts or worsens).",
    expect: {
      mentions: [seesDoctor],
      forbids: [rehabProtocol],
    },
  },
  {
    id: "supplement-research",
    title: "A supplement and the research behind it",
    personas: ["primary", "vegetarian"],
    turns: 6,
    opening: {
      default:
        "Is creatine worth it for me at this point, and what does the research actually say about it?",
      vegetarian:
        "should i take creatine? heard it causes hair loss. and do veg people benefit more? what does research say",
    },
    goal:
      "Get an evidence-based answer about creatine (dose, benefit, safety myths) with the sources named, then ask about another supplement or a research claim.",
    beats: [
      "Ask which study or guideline that comes from.",
      "Ask about caffeine or beta-alanine before training, and what the evidence says.",
      "Quote a claim you saw online (for example 'creatine causes hair loss' or 'you need a loading phase') and ask whether the research supports it.",
      "Ask whether any of this changes your plan or targets.",
      "Close the conversation.",
    ],
    coachBrief:
      "Answer from the library excerpts shown and cite them; state what the evidence says (creatine monohydrate 3-5 g a day is well supported for strength; the hair-loss claim rests on one small study and is not established); say plainly when no source covers a question; a supplement never changes the plan's targets; keep it short.",
    expect: { citations: true, forbids: [creatineHair] },
  },
  {
    id: "follow-up-memory",
    title: "A follow-up that refers back to earlier in the conversation",
    personas: ["primary", "returning"],
    turns: 7,
    opening: {
      default: "What should my next Lower A session look like given how this week went?",
      returning: "What should Monday's session look like? Wednesday felt heavy.",
    },
    goal:
      "Have a normal conversation where later questions refer back to what Coach said earlier ('the second exercise you mentioned', 'what you said about rest'), and see whether Coach keeps track without repeating itself.",
    beats: [
      "Ask about one specific exercise Coach mentioned, by referring to it indirectly ('the second one you said').",
      "Ask 'and what about the rest times you mentioned?'",
      "Change topic briefly: ask about your sleep this week.",
      "Go back: 'ok so going back to that session, should I still do the first exercise if my knee feels off?'",
      "Ask Coach to sum up the plan for that session in one line.",
      "Close the conversation.",
    ],
    coachBrief:
      "Keep track of the thread: resolve 'the second one', 'the rest times you mentioned' and 'that session' to what was said; answer each question once, without repeating earlier cautions or openings; use the plan's session and the athlete's logged loads.",
    expect: {},
  },
  {
    id: "pushback",
    title: "Pushing back on Coach's advice",
    personas: ["primary", "woman_40s", "returning"],
    turns: 7,
    opening: {
      default: "Should I deload next week? I feel beaten up.",
      woman_40s:
        "I would like to add a fourth training day. I feel I am not progressing fast enough on three.",
      returning:
        "I want to go straight back to my old four-day upper/lower with my March weights next week. I know my body.",
    },
    goal:
      "Disagree with Coach's first answer and push back at least twice with your own reasons; see whether Coach holds a sound position with your data, changes its mind only for a good reason, and still offers to make the change when it is reasonable.",
    beats: [
      "Disagree with Coach's first answer and give your own reason.",
      "Push back again: say a coach on Instagram says the opposite.",
      "Ask Coach to show you in your own data why it thinks so.",
      "Say you will do it your way anyway and ask what is the safest version of that.",
      "Ask Coach to set up the change it agreed to, if any.",
      "Close the conversation.",
    ],
    coachBrief:
      "Hold a sound position with the athlete's own data and say why; change position only for a real reason; do not cave to social-media claims; when the athlete insists on a reasonable variant, offer the safest version through a proposal (deload, schedule change, intensity block); stay respectful and concise.",
    expect: {},
  },
  // ---- the standing state: a rest the athlete chose, and a break remembered across chats ----
  {
    id: "checkin-unavailable-hi",
    title: "Today's check-in says can't train, then a plain hi",
    personas: ["primary"],
    turns: 6,
    opening: { default: "hi" },
    goal:
      "You said on this morning's check-in that you can't train today (sleep and energy were fine). See whether Coach knows that without being told, and does not hand you today's session.",
    beats: [
      "Ask what you should do today, without mentioning the check-in.",
      "Ask whether you could squeeze in a short session anyway.",
      "Ask what to eat today given you're not training.",
      "Ask when your next session is.",
      "Close the conversation.",
    ],
    coachBrief:
      "Today's check-in says the athlete cannot train today. Acknowledge it without being asked, treat today as a rest day, never prescribe today's planned session or say they can train if they feel up to it, do not recite check-in numbers, and point to the next planned session.",
    expect: {
      mentions: [
        phrase(
          "treats today as rest",
          /\brest\b/i,
          /\bnot training today\b/i,
          /\bday off\b/i,
          /\bcan'?t train today\b/i,
        ),
      ],
      forbids: [
        phrase(
          "says they can train today",
          /\byou can (?:still )?train (?:today|if)\b/i,
          /\bif you feel up to it\b/i,
        ),
        phrase("recites check-in scores", /\bsleep (?:of |at )?5\b/i, /\benergy (?:of |at )?5\b/i),
      ],
    },
    setup: (athlete) => {
      const today = todayOf(athlete);
      return withStanding(
        athlete,
        standingPayload(today, { status: "unavailable_today", unavailable_today: true }, {
          unavailable_days: [today],
        }),
        false,
      );
    },
  },
  {
    id: "break-across-chats",
    title: "A 15-day break approved in one chat, training asked about in a new one",
    personas: ["primary"],
    turns: 6,
    opening: { default: "What's my training today?" },
    goal:
      "Two days ago, in another chat, you told Coach you were taking 15 days off and approved the break card. This is a fresh chat. See whether Coach remembers the break and its end date without asking again.",
    beats: [
      "Ask whether you should do legs today anyway.",
      "Ask how long you have left on the break.",
      "Ask what you should do on the break to keep fit without training.",
      "Ask what happens with your plan when the break ends.",
      "Close the conversation.",
    ],
    coachBrief:
      "The athlete approved a 15-day break that is running; the standing state shows its dates. Never prescribe the plan's session, never ask whether or how long they are taking a break, give the end date, and say the plan resumes by itself the day after.",
    expect: {
      mentions: [phrase("names the break", /\bbreak\b/i)],
      forbids: [
        phrase(
          "asks again about the break",
          /\bhow long (?:is|will) (?:your|the) break\b/i,
          /\bare you (?:still )?(?:taking|on) (?:a|your|the) break\?/i,
          /\bhow many days (?:off|of break)\b/i,
        ),
        phrase(
          "prescribes a session",
          /\btoday'?s (?:planned )?session is\b/i,
          /\bdo (?:your|the) [a-z ]+ (?:day|session) today\b/i,
        ),
      ],
    },
    setup: (athlete) => {
      const today = todayOf(athlete);
      const start = addDays(today, -1);
      const last = addDays(start, 14);
      const told = addDays(today, -2);
      return withStanding(
        {
          context: {
            ...athlete.context,
            recent_other_conversations: [
              {
                role: "user",
                content: "I'm taking 15 days off from the gym from tomorrow, I need a proper rest.",
              },
              {
                role: "assistant",
                content:
                  "A 15-day break is sensible after a long block. Here's a proposal you can approve below.",
              },
            ],
          },
          contributors: athlete.contributors,
        },
        standingPayload(today, {
          status: "paused",
          paused: true,
          pause: {
            id: "pause-1",
            start_date: start,
            end_date: last,
            reason: "rest",
            note: "I need a proper rest",
            source: "coach",
            running: true,
          },
        }, {
          decisions: [{
            kind: "training_pause",
            title: "Break · 15 days",
            status: "approved",
            on: told,
            ends_on: last,
          }],
          breaks: [{
            start_date: start,
            last_day: last,
            end_date: last,
            source: "coach",
            ended: null,
            ended_on: null,
          }],
          paused_days: days(start, addDays(today, 13) < last ? addDays(today, 13) : last),
        }),
      );
    },
  },
  {
    id: "first-day-back",
    title: "The first day back after a break",
    personas: ["primary"],
    turns: 6,
    opening: { default: "I'm back from my break! What do I do today?" },
    goal:
      "Your 10-day break ended yesterday. See whether Coach knows it is your first session back and eases you in instead of treating the break as missed sessions.",
    beats: [
      "Ask whether you can go straight back to your old weights.",
      "Ask how the first week back should feel.",
      "Ask whether the break cost you strength.",
      "Ask when you'll be back to normal training.",
      "Close the conversation.",
    ],
    coachBrief:
      "The break ended yesterday and no session has been done since: today is the first session back. Ease in (lighter loads or fewer sets in words, never invented figures), never call the break missed sessions, and use the plan's session for today.",
    expect: {
      mentions: [
        phrase(
          "eases back in",
          /\bease\b/i,
          /\blighter\b/i,
          /\bfirst (?:session|week|day) back\b/i,
        ),
      ],
      forbids: [
        phrase(
          "calls the break missed",
          /\bmissed (?:\d+ |several |many )?sessions\b/i,
          /\bbehind (?:on )?(?:your |the )?plan\b/i,
        ),
      ],
    },
    setup: (athlete) => {
      const today = todayOf(athlete);
      const last = addDays(today, -1);
      const start = addDays(last, -9);
      return withStanding(
        athlete,
        standingPayload(today, {
          return_from_pause: { pause_id: "pause-1", last_paused_day: last },
        }, {
          breaks: [{
            start_date: start,
            last_day: last,
            end_date: last,
            source: "athlete",
            ended: null,
            ended_on: null,
          }],
          paused_days: days(start, last),
        }),
      );
    },
  },
  {
    id: "end-break-early",
    title: "Ending a break early",
    personas: ["primary"],
    turns: 6,
    opening: {
      default: "I tapped End break early this morning, I'm keen to get going. What's on today?",
    },
    goal:
      "You had a two-week break planned and ended it early this morning on Today. See whether Coach knows the break is over, gives you today's session and eases you in.",
    beats: [
      "Ask whether ending early was a bad idea.",
      "Ask whether to do the full session or a lighter one.",
      "Ask whether you can set the break again later if you need it.",
      "Ask what you should watch for this week.",
      "Close the conversation.",
    ],
    coachBrief:
      "The athlete ended the break early today, so today is available and the first session back. Do not say they are still on a break; give today's session, suggest easing in, and say a new break can be set on Today or Train.",
    expect: {
      mentions: [
        phrase(
          "eases back in",
          /\bease\b/i,
          /\blighter\b/i,
          /\bfirst (?:session|week|day) back\b/i,
        ),
      ],
      forbids: [
        phrase(
          "says they are still on a break",
          /\byou'?re (?:still )?on (?:a|your) break\b/i,
          /\bno session is due\b/i,
        ),
      ],
    },
    setup: (athlete) => {
      const today = todayOf(athlete);
      const start = addDays(today, -4);
      const last = addDays(today, -1);
      return withStanding(
        athlete,
        standingPayload(today, {
          return_from_pause: { pause_id: "pause-1", last_paused_day: last },
        }, {
          breaks: [{
            start_date: start,
            last_day: last,
            end_date: addDays(start, 13),
            source: "athlete",
            ended: "ended_early",
            ended_on: today,
          }],
          paused_days: days(start, last),
        }),
      );
    },
  },
];

/** One conversation: a persona in a scenario. */
export type Conversation = Readonly<{ id: string; persona: PersonaId; scenario: Scenario }>;

/** Every planned conversation, in scenario order. */
export function conversations(): Conversation[] {
  return scenarios.flatMap((scenario) =>
    scenario.personas.map((persona) => ({
      id: `${persona}/${scenario.id}`,
      persona,
      scenario,
    }))
  );
}

/**
 * The conversations a filter selects: comma-separated parts, each matching a conversation id
 * ("primary/bench-plateau"), a persona ("primary") or a scenario ("knee-off") by substring. An
 * empty filter selects them all.
 */
export function selectConversations(filter: string | undefined): Conversation[] {
  const parts = (filter ?? "").split(",").map((part) => part.trim()).filter(Boolean);
  const all = conversations();
  return parts.length === 0 ? all : all.filter((c) => parts.some((part) => c.id.includes(part)));
}

export function openingFor(scenario: Scenario, persona: PersonaId): string {
  return scenario.opening[persona] ?? scenario.opening.default;
}
