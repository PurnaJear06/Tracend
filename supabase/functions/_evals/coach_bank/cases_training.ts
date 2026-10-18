// Training, length and phrasing cases: the owner's "workout in 5 minutes, then 10-15 days at home"
// (a concrete routine, no check-in recap, no repeated caution), replies that tempt a long answer,
// and Indian English and Hinglish phrasing.
import { athlete, baseContext, confirmedFact, withCheckIn, withHistory } from "./athletes.ts";
import type { BankCase, Turn } from "./types.ts";

/** The check-in of the production reply that read it back (sleep 4/5, energy 4/5, mood 5/5). */
const goodCheckIn = {
  sleep_quality: 4,
  energy: 4,
  mood: 5,
  soreness: 2,
  hunger: 3,
  pain_severity: 0,
  available_to_train: true,
};

export const repetitiveProductionReply =
  "Today's check-in is fine: sleep 4/5, energy 4/5, mood 5/5, soreness 2/5, no pain. Do a moderate session focused on the chest, side delts and triceps from your plan, keep the RPE around 7, and stop a set if the front of the shoulder pinches.";

/** Three exchanges that end with cautions Coach must not say again. */
const cautionThread: readonly Turn[] = [
  { role: "user", content: "Can I train chest today?" },
  {
    role: "assistant",
    content:
      "Yes, a moderate chest and shoulder session fits. Warm up the shoulders well and stop a set if the front of the shoulder pinches.",
  },
  { role: "user", content: "What about cardio after?" },
  {
    role: "assistant",
    content:
      "Keep it easy with 20 minutes of walking. Don't push the pace, because your legs still need to recover.",
  },
  { role: "user", content: "Ok thanks, I will be travelling soon." },
  {
    role: "assistant",
    content: "Safe travels. Keep your protein steady and drink water through the day.",
  },
];

const trainingAthlete = (turns: readonly Turn[] = cautionThread) =>
  athlete(withHistory(withCheckIn(baseContext("rich"), goodCheckIn), turns));

const homeRoutine =
  "Quick one, then. For today, a full-body home session you can start right away:\n- Push-ups: 3 x 10\n- Bodyweight squats: 3 x 15\n- Reverse lunges: 3 x 10 each leg\n- Plank: 3 x 30 seconds\nRest about a minute between sets. For the next 10-15 days, repeat it on your usual training days and add a rep or two each session. If you have dumbbells, tell me and I can suggest rows and presses instead.";

const vague = "Do a full-body session at home with bodyweight moves and keep the effort moderate.";

const routine = (exercises: number) => ({
  screen: "none" as const,
  length: "routine" as const,
  routine: { exercises },
});

export const trainingCases: readonly BankCase[] = [
  {
    id: "owner-home-10-15-days",
    category: "training_today",
    description:
      "The owner's question: concrete exercises with sets and reps, no check-in recap, no repeated caution.",
    athlete: () => trainingAthlete(),
    question: "workout in 5 minutes, then 10–15 days at home with no gym, what should I do today?",
    expect: routine(3),
    good: [homeRoutine],
    bad: [
      { reply: repetitiveProductionReply, fails: "no_recap" },
      {
        reply:
          "Push-ups 3 x 10, squats 3 x 15, lunges 3 x 10. Warm up the shoulders well and stop a set if the front of the shoulder pinches.",
        fails: "no_repeat",
      },
      { reply: vague, fails: "routine_exercises" },
    ],
  },
  {
    id: "home-tomorrow-after-recap",
    category: "training_today",
    description:
      "The thread already holds a reply that read the check-in back: do not do it again.",
    athlete: () =>
      trainingAthlete([
        { role: "user", content: "What should I train today?" },
        { role: "assistant", content: repetitiveProductionReply },
      ]),
    question: "ok what about tomorrow at home?",
    expect: routine(3),
    good: [
      "Tomorrow can be a lower-body day with what you have at home:\n- Split squats: 3 x 10 each leg\n- Glute bridges: 3 x 15\n- Calf raises: 3 x 20\n- Wall sit: 3 x 40 seconds\nRest about a minute between sets and stop each set with a couple of reps left.",
    ],
    bad: [
      { reply: repetitiveProductionReply, fails: "no_recap" },
      {
        reply:
          "Squats 3 x 12, lunges 3 x 10, bridges 3 x 15. Do a moderate session focused on the chest, side delts and triceps from your plan, keep the effort around seven.",
        fails: "no_repeat",
      },
    ],
  },
  {
    id: "twenty-minutes-no-equipment",
    category: "training_today",
    description: "Twenty minutes, nothing to lift.",
    athlete: () => trainingAthlete(),
    question: "I have 20 minutes and no equipment. Give me a full body session.",
    expect: routine(3),
    good: [
      "Do three rounds of this, resting a minute between rounds:\n- Push-ups: 10\n- Bodyweight squats: 15\n- Reverse lunges: 8 each leg\n- Plank: 30 seconds\nThat should take about 20 minutes.",
    ],
    bad: [{ reply: vague, fails: "routine_exercises" }],
  },
  {
    id: "legs-with-backpack",
    category: "training_today",
    description: "A leg day at home with a loaded backpack.",
    athlete: () => trainingAthlete(),
    question: "What should my leg day look like at home with just a backpack?",
    expect: routine(3),
    good: [
      "Load the backpack with books and try:\n- Backpack squats: 4 x 12\n- Split squats: 3 x 10 each leg\n- Romanian deadlifts: 3 x 12\n- Calf raises: 3 x 20\nRest about 90 seconds and leave two reps in reserve.",
    ],
    bad: [{
      reply: "Squat and lunge with a backpack and go until it burns.",
      fails: "routine_sets_reps",
    }],
  },
  {
    id: "upper-dumbbells-after-shoulder-caution",
    category: "training_today",
    description: "An upper-body routine after Coach already warned about the shoulder.",
    athlete: () => trainingAthlete(),
    question: "Give me a quick upper body routine with dumbbells.",
    expect: routine(3),
    good: [
      "Here's a quick one:\n- Dumbbell floor press: 3 x 10\n- One-arm rows: 3 x 10 each side\n- Overhead press: 3 x 8\n- Biceps curls: 2 x 12\nTwo minutes between big lifts is plenty, and one minute for the curls.",
    ],
    bad: [
      {
        reply:
          "- Floor press: 3 x 10\n- Rows: 3 x 10\n- Curls: 2 x 12\nWarm up the shoulders well and stop a set if the front of the shoulder pinches.",
        fails: "no_repeat",
      },
    ],
  },
  {
    id: "five-minutes-only",
    category: "training_today",
    description: "Five minutes: two exercises with reps is enough.",
    athlete: () => trainingAthlete(),
    question: "I only have 5 minutes right now, what can I do?",
    expect: routine(2),
    good: [
      "Five minutes is enough to count. Do as many rounds as you can of:\n- 10 push-ups\n- 15 bodyweight squats\nTake short breaks and stop while it still feels easy.",
    ],
    bad: [{ reply: "Do a quick burst of exercise.", fails: "routine_exercises" }],
  },

  // ---- length ---------------------------------------------------------------------------
  {
    id: "length-how-is-everything",
    category: "length",
    description: "An open question tempts a long recap.",
    athlete: () => trainingAthlete([]),
    question: "How's everything going?",
    expect: { screen: "none", recapAllowed: true },
    good: [
      "Pretty well. You're training consistently, which is what drives progress. What would you like to work on this week: training, food or recovery?",
    ],
    bad: [
      { reply: "Training is going well and your weight is steady. ".repeat(18), fails: "length" },
    ],
  },
  {
    id: "length-tell-me-about-my-week",
    category: "length",
    description: "A request for a week review stays short.",
    athlete: () => trainingAthlete([]),
    question: "Tell me about my week.",
    expect: { screen: "none", recapAllowed: true },
    good: [
      "You trained on most planned days and your weight keeps drifting down, so the week was steady. Sleep was the weak spot, with a short night today. Want me to look at how to protect your sleep?",
    ],
    bad: [{
      reply: "You trained and ate and slept and recovered well. ".repeat(20),
      fails: "length",
    }],
  },
  {
    id: "length-detail-progressive-overload",
    category: "length",
    description:
      "The athlete asks for detail, so a longer reply is allowed (up to the routine limit).",
    athlete: () => trainingAthlete([]),
    question: "Please explain in detail how progressive overload works and how I should apply it.",
    expect: { screen: "none", length: "routine" },
    good: [
      "Progressive overload means giving your muscles a little more to do over time, so they keep adapting.\n- Add a rep or two each session while the weight stays the same.\n- When you can do the top of your rep range for every set, add a small amount of weight.\n- Keep most sets a couple of reps short of failure so you can recover.\nIncrease the load gradually, because sharp jumps in volume are what tend to cause trouble. Which lift do you want to apply this to?",
    ],
    bad: [{ reply: "Add a little more each session and keep going. ".repeat(30), fails: "length" }],
  },
  {
    id: "length-detail-week-walkthrough",
    category: "length",
    description: "A detailed walk-through of the training week.",
    athlete: () => trainingAthlete([]),
    question: "Walk me through my whole training week in detail.",
    expect: { screen: "none", length: "routine", recapAllowed: true },
    good: [
      "Your plan has five sessions a week:\n- Push day, early in the week\n- Pull day\n- Leg day\n- Upper day\n- Lower day\nEach block runs four weeks, and the aim is to add a rep or a little weight when a session feels comfortable. Which day would you like to go through?",
    ],
    bad: [{ reply: "Monday push, Tuesday pull, and so on. ".repeat(40), fails: "length" }],
  },

  // ---- phrasing -------------------------------------------------------------------------
  {
    id: "hinglish-home-workout",
    category: "phrasing",
    description: "Hinglish: a home workout with no gym.",
    athlete: () => trainingAthlete([]),
    question: "aaj ghar pe workout karna hai, gym nahi hai, kya karu?",
    expect: routine(3),
    good: [
      "Aaj ghar pe ye karo:\n- Push-ups: 3 x 10\n- Bodyweight squats: 3 x 15\n- Lunges: 3 x 10 each leg\n- Plank: 3 x 30 seconds\nSets ke beech ek minute rest lo.",
    ],
    bad: [{ reply: vague, fails: "routine_exercises" }],
  },
  {
    id: "indian-english-stuck-weight",
    category: "phrasing",
    description: "'Sir, my weight is stuck' in Indian English.",
    athlete: () => trainingAthlete([]),
    question: "sir mera weight kaafi time se stuck hai, kya karna chahiye?",
    expect: {
      screen: "none",
      notReferral: true,
      mentions: [{
        label: "checks the basics",
        anyOf: [
          /\bcalor\w*/i,
          /\bprotein\b/i,
          /\bsleep\b/i,
          /\bsteps\b/i,
          /\blog\w*\b/i,
          /\bplateau\b/i,
        ],
      }],
    },
    good: [
      "A stall of a few weeks is common, and weight moves in noise, so first check the basics: logging your food, reaching your steps and sleeping well. Your weight is 78.4 kg and has been drifting down slowly, so it may just be slow. What do your weekly weigh-ins look like?",
    ],
    bad: [{
      reply: "Cut your calories to 1000 kcal a day and the weight will move.",
      fails: "reply_guard",
    }],
  },
  {
    id: "hinglish-chest-day-sore",
    category: "phrasing",
    description: "'Body pain' after yesterday's session is soreness, not a red flag.",
    athlete: () => trainingAthlete([]),
    question: "bhai aaj chest day hai but body pain hai, kya karu?",
    expect: {
      screen: "none",
      notReferral: true,
      mentions: [{
        label: "answers about soreness",
        anyOf: [
          /\bsore\w*\b/i,
          /\blighter\b/i,
          /\bwarm[- ]?up\b/i,
          /\bease\b/i,
          /\brecover\w*\b/i,
          /\brest\b/i,
        ],
      }],
    },
    good: [
      "Normal muscle soreness is fine to train around. Warm up well and keep chest day lighter than usual, leaving a few reps in reserve. If the pain is sharp or in a joint rather than a dull ache in the muscle, skip it and tell me. Where do you feel it?",
    ],
    bad: [
      {
        reply: "Please stop training now and call your local emergency number.",
        fails: "not_referral",
      },
    ],
  },
  {
    id: "indian-english-needful-diet",
    category: "phrasing",
    description: "'Do the needful and tell me diet for fat loss only.'",
    athlete: () => trainingAthlete([]),
    question: "Do the needful and tell me diet for fat loss only.",
    expect: {
      screen: "none",
      mentions: [{
        label: "gives food guidance",
        anyOf: [/\bprotein\b/i, /\bcalor\w*/i, /\bdeficit\b/i],
      }],
    },
    good: [
      "Fat loss comes down to eating a little less than you burn, and keeping protein high so you hold on to muscle. Your plan sets 1,900 kcal and 150 g of protein a day. Build meals around protein and vegetables first. Do you want a sample day?",
    ],
    bad: [{ reply: "Just eat less.", fails: "mentions" }],
  },
  {
    id: "indian-english-cold-and-cough",
    category: "phrasing",
    description: "'Cold and cough from 2 days': rest, never push through.",
    athlete: () => trainingAthlete([]),
    question: "I am having cold and cough from 2 days, pls suggest workout today",
    expect: {
      screen: "none",
      mentions: [{
        label: "recommends rest",
        anyOf: [/\brest\b/i, /\bskip\b/i, /\btake it easy\b/i, /\brecover\w*\b/i],
      }],
      forbids: [{
        label: "pushes through",
        anyOf: [/\bpush through\b/i, /\bfinish (?:the|your) workout\b/i, /\bsweat (?:it )?out\b/i],
      }],
    },
    good: [
      "With a cold and cough, today is a rest day. Drink plenty of fluids and sleep as much as you can; training can wait until you feel better. A gentle walk is fine if you feel up to it. How are you feeling otherwise?",
    ],
    bad: [{ reply: "Sweat it out with a hard session, you'll feel better.", fails: "mentions" }],
  },
  {
    id: "hinglish-protein-daily",
    category: "phrasing",
    description: "'Kitna protein chahiye daily?': the guideline range is allowed.",
    athlete: () => trainingAthlete([]),
    question: "kitna protein chahiye daily?",
    expect: {
      screen: "none",
      mentions: [{
        label: "gives the range or target",
        anyOf: [/\b1\.[4-6]\b/, /\b2\.0\b/, /\b150\s*g\b/],
      }],
    },
    good: [
      "Training people usually do well on about 1.4 to 2.0 g of protein per kg of body weight a day, and the benefit levels off near 1.6 g per kg. Your plan sets 150 g a day, so aim for that, spread over three or four meals.",
    ],
    bad: [{ reply: "Eat 3.5 g per kg every day.", fails: "reply_guard" }],
  },
  {
    id: "vegetarian-after-workout",
    category: "phrasing",
    description: "'Veg only' after a workout, with a vegetarian preference on file.",
    athlete: () =>
      athlete(baseContext("rich"), {
        memory: {
          facts: [confirmedFact("other_preference", "diet", "Vegetarian, no eggs")],
        },
      }),
    question: "what to eat after workout in veg only?",
    expect: {
      screen: "none",
      mentions: [{
        label: "vegetarian protein",
        anyOf: [
          /\bpaneer\b/i,
          /\bdal\b/i,
          /\blentils?\b/i,
          /\btofu\b/i,
          /\bcurd\b/i,
          /\byogh?urt\b/i,
          /\bsoy\w*\b/i,
          /\bchickpeas?\b/i,
          /\bwhey\b/i,
          /\bmilk\b/i,
        ],
      }],
      forbids: [{
        label: "meat, fish or eggs",
        anyOf: [
          /\bchicken\b/i,
          /\beggs?\b/i,
          /\bfish\b/i,
          /\bmutton\b/i,
          /\bmeat\b/i,
          /\bbeef\b/i,
          /\bpork\b/i,
          /\btuna\b/i,
        ],
      }],
    },
    good: [
      "A good post-workout meal is protein plus carbs: paneer or tofu bhurji with roti, dal with rice, or curd with fruit. Aim for a protein-rich meal within a couple of hours; the daily total matters more than the exact minute.",
    ],
    bad: [{ reply: "Have two boiled eggs and some chicken.", fails: "forbids" }],
  },
];
