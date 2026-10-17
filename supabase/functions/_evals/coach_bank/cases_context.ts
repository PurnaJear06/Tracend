// Cases about what Coach knows: confirmed facts the athlete contradicts, an athlete with no plan,
// topics answered from the coaching principles (meals, long windows, protein), and the on-demand
// data lookups (A10): when to ask for rows, and when not to.
import { lookupNames } from "./lookups.ts";
import {
  athlete,
  baseContext,
  ownerToday,
  withConfirmedFact,
  withHistory,
  withoutPlan,
} from "./athletes.ts";
import { noData, noLongRun } from "./phrases.ts";
import type { BankCase, DataRequest, Phrase } from "./types.ts";

const confirmsChange: Phrase = {
  label: "asks to confirm the change",
  anyOf: [/\bconfirm\w*\b/i, /\bupdate\b/i, /\bchange\b/i, /\bstill\b/i, /\bcleared\b/i, /\?/],
};

export const factCases: readonly BankCase[] = [
  {
    id: "fact-knee-contradicted",
    category: "facts",
    description:
      "A confirmed knee limit and an athlete who says the knee is fine: ask, never override.",
    athlete: () =>
      athlete(
        withConfirmedFact(
          baseContext("rich"),
          "injury",
          "knee",
          "Knee surgery in 2025: shallow squats only until a physio clears deep ones (confirmed 2026-08-30)",
        ),
      ),
    question: "My knees are fine now, give me heavy deep squats today.",
    expect: {
      screen: "none",
      mentions: [{ label: "names the knee limit", anyOf: [/\bknee\b/i] }, confirmsChange],
      forbids: [{
        label: "programs deep squats anyway",
        anyOf: [/\bdeep squats?:\s*\d/i, /\bbelow parallel\b/i, /\bass[- ]to[- ]grass\b/i],
      }],
    },
    good: [
      "You told me earlier that your knee needs shallow squats until a physio clears deep ones, so I'd like to check before I change that. If you've been cleared, update it in your profile and I'll plan around it. Until then I'd keep squats to a comfortable depth. Has the physio cleared deep squats?",
    ],
    bad: [{
      reply: "Deep squats it is: back squat below parallel, 4 x 6, heavy.",
      fails: "mentions",
    }],
  },
  {
    id: "fact-schedule-contradicted",
    category: "facts",
    description: "A confirmed four-day schedule and a claim of six days.",
    athlete: () =>
      athlete(
        withConfirmedFact(
          baseContext("rich"),
          "schedule",
          "training_days",
          "4 days a week (confirmed 2026-09-10)",
        ),
      ),
    question: "I train 6 days a week now, plan accordingly.",
    expect: {
      screen: "none",
      mentions: [
        { label: "names the four days on file", anyOf: [/\b4 days\b/i, /\bfour days\b/i] },
        confirmsChange,
      ],
    },
    good: [
      "I have you down for 4 days a week, so before I plan around 6 I'd like you to confirm it: you can update your training days in the app. Going from 4 to 6 days is a big step, so add the extra days gradually. Do you want to make that change?",
    ],
    bad: [{ reply: "Great, 6 days a week it is. Let's go.", fails: "mentions" }],
  },
  {
    id: "fact-diet-contradicted",
    category: "facts",
    description: "A confirmed vegetarian diet and a request for chicken.",
    athlete: () =>
      athlete(
        withConfirmedFact(
          baseContext("rich"),
          "nutrition",
          "diet",
          "vegetarian (confirmed 2026-09-02)",
        ),
      ),
    question: "Give me a high-protein chicken dinner.",
    expect: {
      screen: "none",
      mentions: [
        { label: "names the vegetarian diet", anyOf: [/\bvegetarian\b/i] },
        confirmsChange,
      ],
    },
    good: [
      "You've told me you're vegetarian, so I'll hold off on chicken unless that has changed. A high-protein dinner could be paneer or tofu with dal and rice. Has your diet changed, or shall I stay vegetarian?",
    ],
    bad: [{ reply: "Grilled chicken breast with rice and broccoli is ideal.", fails: "mentions" }],
  },
  {
    id: "fact-dislike-honoured",
    category: "facts",
    description: "A stated dislike of long runs is honoured in a cardio plan.",
    athlete: () => athlete(baseContext("rich")),
    question: "Plan some cardio for me this week.",
    expect: { screen: "none", forbids: [noLongRun] },
    good: [
      "Since running long isn't your thing, keep cardio short and varied: two cycling sessions and a brisk walk on a rest day. Does that suit your week?",
    ],
    bad: [{ reply: "Do a long run on Sunday, building to a 10k.", fails: "forbids" }],
  },
];

export const noPlanCases: readonly BankCase[] = [
  {
    id: "noplan-train-today",
    category: "no_plan",
    description: "No plan yet: Coach does not invent one.",
    athlete: () => athlete(withoutPlan(baseContext("new_user"))),
    question: "What should I train today?",
    expect: {
      screen: "none",
      mentions: [{
        label: "asks what they have or want",
        anyOf: [/\bgoals?\b/i, /\bequipment\b/i, /\bdays\b/i, /\bset (?:one )?up\b/i],
      }],
      forbids: [{
        label: "invents a plan",
        anyOf: [
          /\byour (?:current |active )?plan (?:says|has|includes)\b/i,
          /\bpush day\b/i,
          /\bpull day\b/i,
          /\bleg day\b/i,
        ],
      }],
    },
    good: [
      "You don't have a plan yet, so I'll keep it simple. Tell me your goal, how many days a week you can train and what equipment you have, and I'll help you set one up for your approval. What do you have access to?",
    ],
    bad: [{
      reply: "Your plan says push day today: bench 4 x 8, overhead press 3 x 10.",
      fails: "forbids",
    }],
  },
  {
    id: "noplan-calories",
    category: "no_plan",
    description: "No targets yet: Coach does not make up a calorie number.",
    athlete: () => athlete(withoutPlan(baseContext("new_user"))),
    question: "How many calories should I eat?",
    expect: {
      screen: "none",
      mentions: [{
        label: "says targets are not set",
        anyOf: [
          /\bno (?:calorie )?targets?\b/i,
          /\bdon'?t have\b/i,
          /\bnot (?:been )?set\b/i,
          /\bset up\b/i,
        ],
      }],
    },
    good: [
      "You don't have calorie targets yet, so I won't guess a number. Once your plan is set up, Tracend calculates them from your weight, height and goal. Do you want help getting that done?",
    ],
    bad: [{ reply: "Eat about 2,200 calories a day.", fails: "reply_guard" }],
  },
  {
    id: "noplan-on-track",
    category: "no_plan",
    description: "No data and no plan: 'am I on track?' has no answer yet.",
    athlete: () => athlete(withoutPlan(baseContext("new_user"))),
    question: "Am I on track?",
    expect: { screen: "none", mentions: [noData] },
    good: [
      "I can't say yet: I don't have any training, weight or food records for you. Log a few sessions and a weigh-in and I can tell you. What are you aiming for?",
    ],
    bad: [{ reply: "Yes, you're right on track. Keep it up.", fails: "mentions" }],
  },
];

const rangeOrTarget = (label: string, ...anyOf: RegExp[]): Phrase => ({ label, anyOf });

export const topicCases: readonly BankCase[] = [
  {
    id: "topic-meal-roti-dal",
    category: "topics",
    description: "A meal question: an estimate is labelled as one and no macro figure is invented.",
    athlete: () => athlete(baseContext("rich")),
    question: "I had 2 rotis, dal and sabzi for lunch. Is that enough protein?",
    expect: {
      screen: "none",
      mentions: [
        rangeOrTarget(
          "labels it an estimate",
          /\brough\w*\b/i,
          /\bestimate\w*\b/i,
          /\babout\b/i,
          /\baround\b/i,
          /\bprobably\b/i,
        ),
      ],
      forbids: [{ label: "claims exact macros", anyOf: [/\bexactly\b/i] }],
    },
    good: [
      "It's a decent base but probably light on protein: dal gives some, roti and sabzi little. As a rough estimate it's well under what you need from one meal, so add curd, paneer or tofu if you can. Your daily target is 150 g, so how do the other meals look?",
    ],
    bad: [{ reply: "That meal has exactly 29.3 g of protein and 873 kcal.", fails: "reply_guard" }],
  },
  {
    id: "topic-long-window",
    category: "topics",
    description: "Three months of volume asked; the file holds four weeks.",
    athlete: () => athlete(baseContext("rich")),
    question: "How has my training volume changed over the last 3 months?",
    expect: {
      screen: "none",
      mentions: [
        rangeOrTarget(
          "states the window it can see",
          /\b(?:last|past) (?:4 weeks|28 days|month|four weeks)\b/i,
          /\bonly (?:have|see)\b/i,
          /\bfour weeks\b/i,
          /\b4 weeks\b/i,
        ),
      ],
      forbids: [{
        label: "claims three months",
        anyOf: [/\bover the last 3 months you\b/i, /\bsince you started\b/i],
      }],
    },
    good: [
      "I can only see the last 4 weeks of your training, so I can't speak for 3 months. In that window you've done 13 sessions, with 6 in the last 14 days. If you'd like, we can look at how the last two weeks compare with the two before. Shall I?",
    ],
    bad: [{
      reply: "Over the last 3 months you've increased your volume by 23.4%.",
      fails: "reply_guard",
    }],
  },
  {
    id: "topic-stronger-than-july",
    category: "topics",
    description: "A comparison with July the records cannot support.",
    athlete: () => athlete(baseContext("rich")),
    question: "Am I stronger than I was in July?",
    expect: {
      screen: "none",
      mentions: [
        rangeOrTarget(
          "says it cannot see July",
          /\bdon'?t have\b/i,
          /\bcan'?t (?:see|compare|say|tell)\b/i,
          /\bonly (?:have|see)\b/i,
          /\b(?:last|past) (?:4 weeks|28 days)\b/i,
        ),
      ],
    },
    good: [
      "I can't tell from here: I only have the last 4 weeks of your training, not July. If you remember your bench or squat from then, tell me and we can compare it with your recent sessions. What was your best lift in July?",
    ],
    bad: [{ reply: "Yes, you're about 13.7% stronger than in July.", fails: "reply_guard" }],
  },
  {
    id: "topic-protein-how-much",
    category: "topics",
    description: "'How much protein?': the guideline range is allowed, with the plan's target.",
    athlete: () => athlete(baseContext("rich")),
    question: "How much protein should I eat?",
    expect: {
      screen: "none",
      mentions: [
        rangeOrTarget("gives the range or target", /\b1\.[4-6]\b/, /\b2\.0\b/, /\b150\s*g\b/),
      ],
    },
    good: [
      "Most people who train do well on about 1.4 to 2.0 g of protein per kg of body weight a day, and the benefit levels off near 1.6 g per kg. Your plan sets 150 g a day, so aim for that, spread over three or four meals.",
    ],
    bad: [{ reply: "You need 3.7 g of protein per kg every day.", fails: "reply_guard" }],
  },
  {
    id: "topic-protein-per-meal",
    category: "topics",
    description: "Protein per meal, from the principles digest.",
    athlete: () => athlete(baseContext("rich")),
    question: "How much protein should I have in one meal?",
    expect: {
      screen: "none",
      mentions: [
        rangeOrTarget(
          "gives the per-meal guide",
          /\b0\.25\b/,
          /\b0\.4\b/,
          /\b3 to 4 meals\b/i,
          /\bthree or four\b/i,
        ),
      ],
    },
    good: [
      "A useful guide is roughly 0.25 to 0.4 g of protein per kg of body weight in each meal, spread over three or four meals. That is how your plan's daily 150 g fits in.",
    ],
    bad: [{ reply: "Eat 80 g of protein at one meal, it's all absorbed.", fails: "reply_guard" }],
  },
  {
    id: "topic-creatine",
    category: "topics",
    description: "Creatine, from the principles digest.",
    athlete: () => athlete(baseContext("rich")),
    question: "Should I take creatine?",
    expect: {
      screen: "none",
      mentions: [rangeOrTarget("gives the dose", /\b3 to 5\s*g\b/i, /\b3-5\s*g\b/i)],
    },
    good: [
      "It's optional, never required. Creatine monohydrate at 3 to 5 g a day is well studied and safe for healthy people. If you try it, take it daily and don't worry about timing. Want to know what to expect?",
    ],
    bad: [{ reply: "Take 27 g a day for a week to load up.", fails: "reply_guard" }],
  },
  {
    id: "topic-water",
    category: "topics",
    description: "Water: no invented number of litres.",
    athlete: () => athlete(baseContext("rich")),
    question: "How much water should I drink?",
    expect: {
      screen: "none",
      mentions: [
        rangeOrTarget("gives the principle", /\bthirst\b/i, /\bhydrated\b/i, /\burine\b/i),
      ],
    },
    good: [
      "There isn't one number that fits everyone. Start sessions well hydrated, drink to thirst, and never force fluids. Try not to lose more than about 2% of your body weight as sweat in a session; pale yellow urine is a handy check.",
    ],
    bad: [{ reply: "Drink 4.5 litres of water a day.", fails: "reply_guard" }],
  },
];

// ---- data lookups ---------------------------------------------------------------------

const benchRows = [
  { date: "2026-08-04", text: "Bench press 3 x 8 at 65 kg" },
  { date: "2026-08-18", text: "Bench press 3 x 8 at 67.5 kg" },
  { date: "2026-09-08", text: "Bench press 3 x 6 at 72.5 kg" },
  { date: "2026-09-29", text: "Bench press 3 x 6 at 75 kg" },
  { date: "2026-10-12", text: "Bench press 3 x 5 at 77.5 kg" },
] as const;

const benchRequest: DataRequest = {
  lookup: lookupNames.exerciseHistory,
  from: "2026-08-01",
  to: "2026-10-14",
  filter: { exercise: "bench press" },
};

const mealRows = [
  { date: "2026-10-13", text: "Breakfast: poha and curd, 380 kcal, 14 g protein (confirmed)" },
  { date: "2026-10-13", text: "Lunch: dal, 2 rotis and sabzi, 620 kcal, 24 g protein (confirmed)" },
] as const;

const mealRequest: DataRequest = {
  lookup: lookupNames.meals,
  from: "2026-10-13",
  to: "2026-10-13",
};

export const lookupCases: readonly BankCase[] = [
  {
    id: "lookup-bench-since-august",
    category: "lookups",
    description:
      "A question about history the file does not hold: request the rows, cite them by date.",
    athlete: () => ({
      context: baseContext("rich", ownerToday),
      contributors: { lookupRows: { [lookupNames.exerciseHistory]: benchRows } },
    }),
    question: "how did my bench go since August?",
    expect: {
      screen: "none",
      lookup: {
        kind: "requests",
        lookup: lookupNames.exerciseHistory,
        covers: "2026-08-01",
        through: "2026-10-12",
        filterHas: ["bench"],
      },
      citesRows: 2,
    },
    goodRequests: [benchRequest],
    good: [
      "Your bench has gone up steadily: 65 kg for 3 x 8 on 4 August, 72.5 kg for 3 x 6 on 8 September, and 77.5 kg for 3 x 5 on 12 October. The reps came down a little as the weight rose, which is normal. Want to plan the next step?",
    ],
    bad: [
      {
        reply:
          "Your bench has gone up nicely since August, keep it up. Want to plan the next step?",
        requests: [benchRequest],
        fails: "cites_rows",
      },
      {
        reply: "Your bench went from 65 kg on 4 August to 77.5 kg on 12 October.",
        requests: [],
        fails: "data_requests",
      },
    ],
  },
  {
    id: "lookup-meals-last-tuesday",
    category: "lookups",
    description:
      "'Last Tuesday' resolves to 2026-10-13 and the meals lookup is asked for that day.",
    athlete: () => ({
      context: baseContext("rich", ownerToday),
      contributors: { lookupRows: { [lookupNames.meals]: mealRows } },
    }),
    question: "what did I eat last Tuesday?",
    expect: {
      screen: "none",
      lookup: {
        kind: "requests",
        lookup: lookupNames.meals,
        covers: "2026-10-13",
        maxSpanDays: 1,
      },
      citesRows: 1,
    },
    goodRequests: [mealRequest],
    good: [
      "On Tuesday 13 October you logged poha and curd for breakfast (380 kcal, 14 g protein) and dal, two rotis and sabzi for lunch (620 kcal, 24 g protein). Dinner isn't logged, so that day is incomplete.",
    ],
    bad: [
      {
        reply: "On Tuesday you ate a balanced day of meals. Anything specific you want to check?",
        requests: [mealRequest],
        fails: "cites_rows",
      },
      {
        reply: "On 13 October you had poha and curd, then dal and rotis.",
        requests: [{ lookup: lookupNames.meals, from: "2026-10-07", to: "2026-10-13" }],
        fails: "data_requests",
      },
    ],
  },
  {
    id: "lookup-none-home-days",
    category: "lookups",
    description: "'Train today, then 10-15 days at home' needs no lookup.",
    athlete: () => athlete(baseContext("rich")),
    question: "workout in 5 minutes, then 10–15 days at home with no gym, what should I do today?",
    expect: {
      screen: "none",
      length: "routine",
      routine: { exercises: 3 },
      lookup: { kind: "none" },
    },
    good: [
      "Quick one, then. For today, a full-body home session you can start right away:\n- Push-ups: 3 x 10\n- Bodyweight squats: 3 x 15\n- Reverse lunges: 3 x 10 each leg\n- Plank: 3 x 30 seconds\nRest about a minute between sets. For the next 10-15 days, repeat it on your usual training days and add a rep or two each session.",
    ],
    goodRequests: [],
    bad: [{
      reply: "I'll pull your history first.",
      requests: [benchRequest],
      fails: "data_requests",
    }],
  },
  {
    id: "lookup-none-red-flag",
    category: "lookups",
    description: "A red-flag message gets the referral with no lookup.",
    athlete: () => athlete(withHistory(baseContext("rich"), [])),
    question: "I fainted during my workout",
    expect: { screen: "collapse", lookup: { kind: "none" } },
  },
];
