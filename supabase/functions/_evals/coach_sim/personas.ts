// The simulated athletes: who they are, how they write, and months of records behind them. The
// primary persona is the owner's brief (a 6-year lifter, about 30, upper/lower, a bench plateau,
// cutting while keeping strength, an Indian diet with eggs and chicken); three others vary the
// diet, the age and sex, and the training history. Names, ids and numbers are invented.
import { confirmedFact } from "../coach_bank/athletes.ts";
import type { Athlete } from "../coach_bank/types.ts";
import {
  addDays,
  athleteFile,
  buildRecords,
  dataIndexPayload,
  e1rm,
  type Food,
  goalPhasePayload,
  type LiftSpec,
  type MealType,
  nutritionStatePayload,
  planOn,
  planStatePayload,
  type ProfileFacts,
  type Records,
  type RecordsExtras,
  type RecordsSpec,
  type SessionSpec,
  targetOn,
} from "./records.ts";
import type { CoachFact } from "../../_shared/coach_memory/facts.ts";

export const simulationToday = "2026-10-16";

export const personaIds = ["primary", "vegetarian", "woman_40s", "returning"] as const;
export type PersonaId = typeof personaIds[number];

export type Persona = Readonly<{
  id: PersonaId;
  name: string;
  /** ISO country code: which regional library sources the athlete's search sees. */
  region: string;
  /** One line for the report. */
  summary: string;
  /** How they write, for the athlete model. */
  voice: string;
  /** What they know about themselves and may say, for the athlete model. */
  background: string;
  profile: ProfileFacts;
  records: Records;
  extras: RecordsExtras;
  facts: readonly CoachFact[];
  /** A fresh athlete file and its contributors (the simulator adds the library search). */
  athlete: () => Athlete;
}>;

const lift = (
  name: string,
  slug: string,
  sets: number,
  reps: readonly [number, number],
  startKg: number | null,
  gainPerWeek: number,
  plateau?: LiftSpec["plateau"],
): LiftSpec => ({
  name,
  slug,
  sets,
  repMin: reps[0],
  repMax: reps[1],
  restSeconds: reps[1] <= 6 ? 180 : reps[1] <= 10 ? 120 : 75,
  targetRpe: 8,
  startKg,
  gainPerWeek,
  ...(plateau ? { plateau } : {}),
});

const food = (name: string, calories: number, protein: number): Food => ({
  name,
  calories,
  protein,
});

type Menu = Readonly<Record<MealType, readonly (readonly Food[])[]>>;

function persona(
  id: PersonaId,
  text: Readonly<
    { name: string; region: string; summary: string; voice: string; background: string }
  >,
  spec: RecordsSpec,
  profile: ProfileFacts,
  extras: RecordsExtras,
  facts: readonly CoachFact[],
  goalTarget: Readonly<Record<string, unknown>>,
): Persona {
  const records = buildRecords(spec, id);
  return {
    id,
    ...text,
    profile,
    records,
    extras,
    facts,
    athlete: () => ({
      context: athleteFile(records, profile),
      contributors: {
        screening: "cleared",
        goalPhase: goalPhasePayload(records, {
          goalType: profile.goal.goalType,
          activatedOn: profile.goal.activatedOn,
          heightCm: profile.heightCm,
        }, goalTarget),
        trainingPlan: planStatePayload(records, profile.equipment),
        nutritionState: nutritionStatePayload(records),
        dataIndex: dataIndexPayload(records, extras),
        memory: { facts, notes: [], remember: true },
      },
    }),
  };
}

// ---- primary: Arjun, 30, six years of lifting -------------------------------------------------

const arjunWeek: readonly SessionSpec[] = [
  {
    id: "w-lower-a",
    name: "Lower A",
    weekday: 1,
    minutes: 70,
    lifts: [
      lift("Barbell back squat", "barbell-back-squat", 4, [4, 6], 132.5, 0.5),
      lift("Romanian deadlift", "romanian-deadlift", 3, [6, 8], 100, 0.5),
      lift("Leg press", "leg-press", 3, [10, 12], 180, 1),
      lift("Standing calf raise", "standing-calf-raise", 3, [10, 15], 60, 0.4),
    ],
  },
  {
    id: "w-upper-a",
    name: "Upper A",
    weekday: 2,
    minutes: 70,
    lifts: [
      lift("Barbell bench press", "barbell-bench-press", 4, [4, 6], 92.5, 0.4, {
        from: "2026-08-20",
        kg: 100,
      }),
      lift("Barbell row", "barbell-row", 4, [6, 8], 82.5, 0.4),
      lift("Weighted pull-up", "weighted-pull-up", 3, [5, 8], 10, 0.25),
      lift("Incline dumbbell press", "incline-dumbbell-press", 3, [8, 10], 30, 0.15),
      lift("Cable triceps pressdown", "cable-triceps-pressdown", 3, [10, 12], 35, 0.2),
    ],
  },
  {
    id: "w-lower-b",
    name: "Lower B",
    weekday: 4,
    minutes: 65,
    lifts: [
      lift("Conventional deadlift", "conventional-deadlift", 3, [3, 5], 167.5, 0.5),
      lift("Bulgarian split squat", "bulgarian-split-squat", 3, [8, 10], 22, 0.15),
      lift("Lying leg curl", "lying-leg-curl", 3, [10, 12], 40, 0.25),
      lift("Hanging leg raise", "hanging-leg-raise", 3, [10, 15], null, 0),
    ],
  },
  {
    id: "w-upper-b",
    name: "Upper B",
    weekday: 5,
    minutes: 65,
    lifts: [
      lift("Barbell overhead press", "barbell-overhead-press", 4, [5, 7], 55, 0.25),
      lift("Close-grip bench press", "close-grip-bench-press", 3, [6, 8], 77.5, 0.3, {
        from: "2026-09-03",
        kg: 85,
      }),
      lift("Chest-supported dumbbell row", "chest-supported-dumbbell-row", 3, [8, 10], 30, 0.15),
      lift("Dumbbell lateral raise", "dumbbell-lateral-raise", 3, [12, 15], 10, 0.05),
      lift("EZ-bar curl", "ez-bar-curl", 3, [8, 12], 32.5, 0.15),
    ],
  },
];

const indianNonVeg: Menu = {
  breakfast: [
    [food("Masala omelette (4 eggs)", 380, 26), food("Brown bread toast (2 slices)", 160, 6)],
    [food("Egg bhurji (3 eggs)", 300, 20), food("Roti (2)", 240, 7)],
    [food("Poha with peanuts", 350, 9), food("Boiled eggs (2)", 140, 12)],
    [food("Oats with milk and whey", 420, 38)],
  ],
  lunch: [
    [
      food("Chicken curry (200 g chicken)", 420, 46),
      food("Rice (1.5 cups)", 300, 6),
      food("Dal", 150, 9),
    ],
    [food("Chicken tikka (250 g)", 400, 55), food("Roti (2)", 240, 7), food("Salad", 60, 2)],
    [food("Rajma", 250, 13), food("Rice (1.5 cups)", 300, 6), food("Curd (dahi)", 100, 6)],
  ],
  dinner: [
    [food("Tandoori chicken (250 g)", 420, 58), food("Roti (2)", 240, 7), food("Dal", 150, 9)],
    [food("Egg curry (3 eggs)", 330, 20), food("Rice (1.5 cups)", 300, 6)],
    [
      food("Grilled chicken (200 g)", 330, 50),
      food("Mixed vegetable sabzi", 150, 4),
      food("Roti (2)", 240, 7),
    ],
  ],
  snack: [
    [food("Whey protein with milk", 250, 32)],
    [food("Greek yogurt with banana", 220, 16)],
    [food("Roasted chana", 180, 10)],
  ],
};

const arjun = persona(
  "primary",
  {
    name: "Arjun",
    region: "IN",
    summary:
      "Male, 30, 178 cm, six years of lifting, upper/lower four days a week, bench stuck at 100 kg for eight weeks, six weeks into a cut (84.4 to about 81.6 kg), Indian diet with eggs and chicken.",
    voice:
      "Writes like a busy Bengaluru software engineer who has lifted for years: short, direct messages, lifting slang (top set, RPE, e1RM, deload), the odd Indian English phrase, no emoji. Knows his numbers roughly, not exactly. Impatient with generic advice and says so.",
    background:
      "Trains at 7 am before work, Monday, Tuesday, Thursday and Friday, upper/lower. Bench press has been stuck around 100 kg for 4-5 reps since late August; best ever was 100 x 6. Squat and deadlift still move. Started a cut in early September at about 84.5 kg and wants to reach about 79 kg without losing strength. Eats eggs, chicken, dal, roti and rice; no beef or pork. Logs most meals with photos, sometimes only breakfast. Last Tuesday's upper session went badly after a 5-hour night before a work deadline and a skipped lunch. His left knee has felt a bit off at the bottom of split squats this week, no sharp pain.",
  },
  {
    today: simulationToday,
    start: "2026-04-16",
    plans: [
      {
        from: "2026-04-13",
        title: "Upper lower strength",
        rationale: "Four upper/lower sessions to build strength on the main lifts.",
        blockWeeks: 6,
        week: arjunWeek,
      },
      {
        from: "2026-09-07",
        title: "Cut: upper lower, strength kept",
        rationale:
          "The same four sessions through the cut, so strength is kept while fat comes off.",
        blockWeeks: 8,
        week: arjunWeek,
      },
    ],
    missEvery: 11,
    weight: [["2026-04-16", 83.6], ["2026-09-06", 84.4], ["2026-10-16", 81.6]],
    weighInDays: [1, 3, 5, 6],
    waist: [86, 83.5],
    nutrition: {
      since: "2026-08-01",
      targets: [
        {
          from: "2026-04-13",
          calories: 2850,
          protein: 165,
          carbs: 340,
          fat: 85,
          rationale: "Maintenance while building strength.",
        },
        {
          from: "2026-09-07",
          calories: 2350,
          protein: 170,
          carbs: 245,
          fat: 70,
          rationale: "About 500 kcal under maintenance for a cut that keeps strength.",
        },
      ],
      menu: indianNonVeg,
      complete: 0.68,
      partial: 0.22,
    },
    sleep: { minutes: 405, spread: 45, hrvMs: 58, restingHr: 54 },
    steps: 8500,
    checkInsSince: "2026-07-01",
    events: [
      { date: "2026-10-12", sleepMinutes: 340, meals: "partial" },
      {
        date: "2026-10-13",
        sleepMinutes: 292,
        hrvMs: 41,
        meals: "partial",
        checkIn: {
          sleep_quality: 2,
          energy: 2,
          mood: 3,
          soreness: 3,
          note: "Slept about 5 hours, deadline at work. Skipped lunch.",
        },
        session: {
          effort: 9,
          energy: 2,
          minutes: 48,
          sets: {
            "barbell-bench-press": [
              { reps: 3, load_kg: 100, rir: 0 },
              { reps: 2, load_kg: 100, rir: 0 },
              { reps: 3, load_kg: 95, rir: 0 },
              { reps: 2, load_kg: 95, rir: 0 },
            ],
            "barbell-row": [
              { reps: 6, load_kg: 87.5, rir: 1 },
              { reps: 5, load_kg: 87.5, rir: 0 },
              { reps: 5, load_kg: 87.5, rir: 0 },
            ],
            "weighted-pull-up": [
              { reps: 4, load_kg: 15, rir: 0 },
              { reps: 3, load_kg: 15, rir: 0 },
            ],
            "incline-dumbbell-press": [],
            "cable-triceps-pressdown": [],
          },
        },
      },
      {
        date: "2026-10-15",
        checkIn: {
          pain_severity: 2,
          note: "Left knee feels a bit off at the bottom of split squats.",
        },
        session: { pain: ["bulgarian-split-squat"] },
      },
      { date: "2026-10-16", sleepMinutes: 410, checkIn: { pain_severity: 1, energy: 3 } },
    ],
  },
  {
    sex: "male",
    age: 30,
    heightCm: 178,
    experience: "advanced",
    trainingYears: "over_5",
    sessionMinutes: 70,
    equipment: ["barbell", "dumbbells", "bench", "rack", "cables", "machines", "pull_up_bar"],
    nutritionNotes: "Eats eggs and chicken; no beef or pork. Mostly home-cooked Indian food.",
    limitations: null,
    goal: {
      goalType: "fat_loss",
      description: "Cut to about 79 kg while keeping strength",
      activatedOn: "2026-09-06",
    },
  },
  {
    goals: [{
      goal_type: "fat_loss",
      status: "active",
      created_on: "2026-09-06",
      target: { weight_kg: 79, set_at: "2026-09-06" },
    }],
    screenings: [{ screened_on: "2026-04-12", outcome: "cleared" }],
    healthHistory: ["2025-10", "2025-11", "2025-12", "2026-01", "2026-02", "2026-03"].map((
      month,
      index,
    ) => ({
      month,
      workouts: 15 + (index % 3),
      strength_workouts: 14 + (index % 3),
      workout_minutes: 1050 + index * 20,
      sleep_minutes_avg: 400 + (index % 2) * 10,
      sleep_nights: 28,
      weight_kg_avg: 83 + index * 0.1,
      weight_days: 12,
    })),
  },
  [
    confirmedFact("food_dislike", "beef and pork", "Doesn't eat beef or pork."),
    confirmedFact("schedule_constraint", "morning training", "Trains at 7 am before work."),
  ],
  { weight_kg: 79, set_at: "2026-09-06" },
);

// ---- vegetarian: Rohan, 27, three years -------------------------------------------------------

const rohanWeek: readonly SessionSpec[] = [
  {
    id: "w-push",
    name: "Push",
    weekday: 1,
    minutes: 60,
    lifts: [
      lift("Barbell bench press", "barbell-bench-press", 3, [6, 8], 62.5, 0.4),
      lift(
        "Seated dumbbell shoulder press",
        "seated-dumbbell-shoulder-press",
        3,
        [8, 10],
        18,
        0.15,
      ),
      lift("Cable fly", "cable-fly", 3, [12, 15], 12.5, 0.1),
    ],
  },
  {
    id: "w-pull",
    name: "Pull",
    weekday: 2,
    minutes: 60,
    lifts: [
      lift("Lat pulldown", "lat-pulldown", 3, [8, 10], 50, 0.4),
      lift("Seated cable row", "seated-cable-row", 3, [8, 10], 50, 0.4),
      lift("Dumbbell curl", "dumbbell-curl", 3, [10, 12], 12, 0.1),
    ],
  },
  {
    id: "w-legs",
    name: "Legs",
    weekday: 3,
    minutes: 65,
    lifts: [
      lift("Barbell back squat", "barbell-back-squat", 3, [6, 8], 80, 0.6),
      lift("Romanian deadlift", "romanian-deadlift", 3, [8, 10], 70, 0.5),
      lift("Leg extension", "leg-extension", 3, [12, 15], 40, 0.3),
    ],
  },
  {
    id: "w-upper",
    name: "Upper",
    weekday: 5,
    minutes: 60,
    lifts: [
      lift("Incline barbell press", "incline-barbell-press", 3, [6, 8], 50, 0.3),
      lift("Pull-up", "pull-up", 3, [6, 10], null, 0),
      lift("Dumbbell lateral raise", "dumbbell-lateral-raise", 3, [12, 15], 8, 0.05),
    ],
  },
  {
    id: "w-lower",
    name: "Lower",
    weekday: 6,
    minutes: 60,
    lifts: [
      lift("Trap-bar deadlift", "trap-bar-deadlift", 3, [5, 7], 110, 0.6),
      lift("Walking lunge", "walking-lunge", 3, [10, 12], 14, 0.1),
      lift("Seated calf raise", "seated-calf-raise", 3, [12, 15], 40, 0.3),
    ],
  },
];

const indianVeg: Menu = {
  breakfast: [
    [food("Paneer bhurji (150 g paneer)", 430, 28), food("Roti (2)", 240, 7)],
    [food("Moong dal chilla (4)", 440, 24), food("Curd (dahi)", 100, 6)],
    [food("Oats with milk and peanut butter", 480, 18)],
  ],
  lunch: [
    [food("Rajma", 300, 15), food("Rice (1.5 cups)", 300, 6), food("Curd (dahi)", 100, 6)],
    [food("Chole", 320, 14), food("Roti (3)", 360, 10)],
    [food("Soya chunk curry (60 g dry)", 300, 31), food("Rice (1.5 cups)", 300, 6)],
  ],
  dinner: [
    [food("Palak paneer (120 g paneer)", 420, 24), food("Roti (2)", 240, 7)],
    [food("Dal tadka", 240, 13), food("Jeera rice", 320, 6), food("Curd (dahi)", 100, 6)],
    [food("Tofu stir fry (200 g)", 360, 30), food("Roti (2)", 240, 7)],
  ],
  snack: [
    [food("Whey protein with milk", 270, 34)],
    [food("Roasted chana", 180, 10)],
    [food("Milk (300 ml) and banana", 290, 11)],
  ],
};

const rohan = persona(
  "vegetarian",
  {
    name: "Rohan",
    region: "IN",
    summary:
      "Male, 27, 175 cm, three years of lifting, five days a week, lacto-vegetarian, four weeks into a cut (76 to about 74 kg), protein usually short of target.",
    voice:
      "Writes in casual Indian English with some Hinglish words (yaar, accha, thoda), lowercase, quick questions, reads fitness Instagram and quotes it. No emoji.",
    background:
      "Lifts five days a week (push, pull, legs, upper, lower). Lacto-vegetarian: paneer, dal, soya, tofu, curd and milk; no eggs, meat or fish. Started a cut in late September at about 76 kg. Finds it hard to reach 140 g of protein and wonders about creatine and whether vegetarians need it more. Has heard creatine causes hair loss.",
  },
  {
    today: simulationToday,
    start: "2026-05-01",
    plans: [{
      from: "2026-04-27",
      title: "Five-day push pull legs upper lower",
      rationale: "Five sessions to build muscle, kept through the cut.",
      blockWeeks: 6,
      week: rohanWeek,
    }],
    missEvery: 8,
    weight: [["2026-05-01", 74.8], ["2026-09-20", 76.1], ["2026-10-16", 74.1]],
    weighInDays: [1, 4, 7],
    waist: [82, 80.5],
    nutrition: {
      since: "2026-08-15",
      targets: [
        {
          from: "2026-04-27",
          calories: 2600,
          protein: 135,
          carbs: 330,
          fat: 75,
          rationale: "Maintenance with a small surplus on training days.",
        },
        {
          from: "2026-09-21",
          calories: 2150,
          protein: 140,
          carbs: 250,
          fat: 62,
          rationale: "About 450 kcal under maintenance for a moderate cut.",
        },
      ],
      menu: indianVeg,
      complete: 0.6,
      partial: 0.28,
    },
    sleep: { minutes: 430, spread: 50, hrvMs: 66, restingHr: 58 },
    steps: 7000,
    checkInsSince: "2026-08-01",
    events: [],
  },
  {
    sex: "male",
    age: 27,
    heightCm: 175,
    experience: "intermediate",
    trainingYears: "3_5",
    sessionMinutes: 60,
    equipment: ["barbell", "dumbbells", "bench", "rack", "cables", "machines", "pull_up_bar"],
    nutritionNotes: "Lacto-vegetarian: no eggs, meat or fish. Dairy is fine.",
    limitations: null,
    goal: {
      goalType: "fat_loss",
      description: "Lose about 3 kg and keep the muscle",
      activatedOn: "2026-09-20",
    },
  },
  {
    goals: [{
      goal_type: "fat_loss",
      status: "active",
      created_on: "2026-09-20",
      target: { weight_kg: null, set_at: null },
    }],
    screenings: [{ screened_on: "2026-04-26", outcome: "cleared" }],
    healthHistory: [],
  },
  [confirmedFact("food_dislike", "eggs meat fish", "Lacto-vegetarian: no eggs, meat or fish.")],
  {},
);

// ---- woman in her 40s: Meera, 44, two years ---------------------------------------------------

const meeraWeek: readonly SessionSpec[] = [
  {
    id: "w-full-a",
    name: "Full body A",
    weekday: 1,
    minutes: 55,
    lifts: [
      lift("Barbell back squat", "barbell-back-squat", 3, [6, 8], 40, 0.35),
      lift("Dumbbell bench press", "dumbbell-bench-press", 3, [8, 10], 12, 0.1),
      lift("Lat pulldown", "lat-pulldown", 3, [8, 10], 32.5, 0.2),
      lift("Plank", "plank", 3, [30, 45], null, 0),
    ],
  },
  {
    id: "w-full-b",
    name: "Full body B",
    weekday: 3,
    minutes: 55,
    lifts: [
      lift("Romanian deadlift", "romanian-deadlift", 3, [8, 10], 40, 0.35),
      lift("Seated dumbbell shoulder press", "seated-dumbbell-shoulder-press", 3, [8, 10], 8, 0.08),
      lift("Seated cable row", "seated-cable-row", 3, [10, 12], 30, 0.2),
      lift("Barbell hip thrust", "barbell-hip-thrust", 3, [8, 12], 60, 0.5),
    ],
  },
  {
    id: "w-full-c",
    name: "Full body C",
    weekday: 6,
    minutes: 50,
    lifts: [
      lift("Goblet squat", "goblet-squat", 3, [10, 12], 16, 0.12),
      lift("Incline dumbbell press", "incline-dumbbell-press", 3, [8, 10], 10, 0.08),
      lift("Assisted pull-up", "assisted-pull-up", 3, [6, 8], null, 0),
      lift("Step-up", "step-up", 3, [10, 12], 8, 0.08),
    ],
  },
];

const mixedDiet: Menu = {
  breakfast: [
    [food("Greek yogurt with berries and granola", 380, 24)],
    [food("Scrambled eggs (3) on toast", 400, 24)],
    [food("Oats with milk and whey", 380, 30)],
  ],
  lunch: [
    [food("Chicken salad wrap", 520, 36)],
    [food("Lentil soup", 320, 18), food("Wholegrain bread (2 slices)", 220, 8)],
    [food("Quinoa bowl with chickpeas and feta", 560, 22)],
  ],
  dinner: [
    [
      food("Baked salmon (150 g)", 350, 34),
      food("Roast vegetables", 180, 4),
      food("Rice (1 cup)", 200, 4),
    ],
    [food("Chicken stir fry", 480, 38), food("Noodles", 220, 7)],
    [food("Dal", 220, 12), food("Roti (2)", 240, 7), food("Paneer tikka (100 g)", 280, 18)],
  ],
  snack: [
    [food("Apple with peanut butter", 250, 7)],
    [food("Protein shake", 160, 25)],
    [food("Cottage cheese with fruit", 200, 20)],
  ],
};

const meera = persona(
  "woman_40s",
  {
    name: "Meera",
    region: "GB",
    summary:
      "Female, 44, 163 cm, two years of lifting, three full-body sessions a week, stable around 64 kg, wants to get stronger and keep her joints happy, travels for work.",
    voice:
      "Writes in full, polite sentences like a senior manager who is new-ish to lifting but has read a lot; asks why before she agrees; mentions her age when she worries about recovery. No emoji, no slang.",
    background:
      "Started lifting two years ago after years of running. Trains Monday, Wednesday and Saturday. Weight steady around 64 kg. Squat is about 52 kg for 6. Travels for work about once a month; next week she is in a hotel with a small gym (dumbbells to 20 kg, a cable machine, a treadmill). Her right knee sometimes aches after long walks or step-ups, never swollen.",
  },
  {
    today: simulationToday,
    start: "2026-03-01",
    plans: [{
      from: "2026-02-23",
      title: "Three-day full body strength",
      rationale: "Three full-body sessions for strength and bone health.",
      blockWeeks: 6,
      week: meeraWeek,
    }],
    away: [{ from: "2026-07-13", to: "2026-07-19" }, { from: "2026-09-14", to: "2026-09-18" }],
    missEvery: 9,
    weight: [["2026-03-01", 64.8], ["2026-10-16", 64.1]],
    weighInDays: [1, 6],
    waist: [76, 74.5],
    nutrition: {
      since: "2026-08-01",
      targets: [{
        from: "2026-02-23",
        calories: 1950,
        protein: 110,
        carbs: 220,
        fat: 65,
        rationale: "Maintenance with protein for strength training.",
      }],
      menu: mixedDiet,
      complete: 0.55,
      partial: 0.3,
    },
    sleep: { minutes: 395, spread: 40, hrvMs: 38, restingHr: 61 },
    steps: 9500,
    checkInsSince: "2026-06-01",
    events: [{
      date: "2026-10-14",
      checkIn: { pain_severity: 2, note: "Right knee achy after the step-ups on Saturday." },
    }],
  },
  {
    sex: "female",
    age: 44,
    heightCm: 163,
    experience: "intermediate",
    trainingYears: "1_2",
    sessionMinutes: 55,
    equipment: ["barbell", "dumbbells", "bench", "rack", "cables", "machines"],
    nutritionNotes: "Eats most things; fish and chicken a few times a week.",
    limitations: "Right knee aches after long walks or step-ups sometimes.",
    goal: {
      goalType: "strength",
      description: "Get stronger, keep joints happy",
      activatedOn: "2026-02-22",
    },
  },
  {
    goals: [{
      goal_type: "strength",
      status: "active",
      created_on: "2026-02-22",
      target: { weight_kg: null, set_at: null },
    }],
    screenings: [{ screened_on: "2026-02-21", outcome: "cleared" }],
    healthHistory: [],
  },
  [
    confirmedFact(
      "injury_limitation",
      "right knee",
      "Right knee aches after long walks or step-ups sometimes.",
      "2026-09-01",
      "2026-12-01",
    ),
    confirmedFact("schedule_constraint", "work travel", "Travels for work about once a month."),
  ],
  {},
);

// ---- returning: Kabir, 34, back after six months off ------------------------------------------

const kabirBefore: readonly SessionSpec[] = [
  {
    id: "w-old-upper",
    name: "Upper",
    weekday: 1,
    minutes: 75,
    lifts: [
      lift("Barbell bench press", "barbell-bench-press", 4, [5, 7], 105, 0.3),
      lift("Barbell row", "barbell-row", 4, [6, 8], 90, 0.3),
    ],
  },
  {
    id: "w-old-lower",
    name: "Lower",
    weekday: 2,
    minutes: 75,
    lifts: [
      lift("Barbell back squat", "barbell-back-squat", 4, [5, 7], 150, 0.4),
      lift("Conventional deadlift", "conventional-deadlift", 3, [3, 5], 190, 0.4),
    ],
  },
  {
    id: "w-old-upper-2",
    name: "Upper 2",
    weekday: 4,
    minutes: 70,
    lifts: [
      lift("Barbell overhead press", "barbell-overhead-press", 4, [5, 7], 65, 0.2),
      lift("Weighted pull-up", "weighted-pull-up", 3, [5, 8], 20, 0.2),
    ],
  },
  {
    id: "w-old-lower-2",
    name: "Lower 2",
    weekday: 5,
    minutes: 70,
    lifts: [
      lift("Front squat", "front-squat", 3, [5, 7], 110, 0.3),
      lift("Romanian deadlift", "romanian-deadlift", 3, [6, 8], 130, 0.3),
    ],
  },
];

const kabirReturn: readonly SessionSpec[] = [
  {
    id: "w-return-a",
    name: "Full body A",
    weekday: 1,
    minutes: 60,
    lifts: [
      lift("Barbell back squat", "barbell-back-squat", 3, [6, 8], 75, 3.5),
      lift("Barbell bench press", "barbell-bench-press", 3, [6, 8], 62.5, 2.5),
      lift("Barbell row", "barbell-row", 3, [8, 10], 60, 2),
    ],
  },
  {
    id: "w-return-b",
    name: "Full body B",
    weekday: 3,
    minutes: 60,
    lifts: [
      lift("Conventional deadlift", "conventional-deadlift", 3, [4, 6], 110, 5),
      lift("Barbell overhead press", "barbell-overhead-press", 3, [6, 8], 42.5, 1.25),
      lift("Lat pulldown", "lat-pulldown", 3, [8, 10], 55, 1.25),
    ],
  },
  {
    id: "w-return-c",
    name: "Full body C",
    weekday: 5,
    minutes: 60,
    lifts: [
      lift("Front squat", "front-squat", 3, [6, 8], 55, 2.5),
      lift("Incline dumbbell press", "incline-dumbbell-press", 3, [8, 10], 24, 1),
      lift("Seated cable row", "seated-cable-row", 3, [10, 12], 55, 1.25),
    ],
  },
];

const kabir = persona(
  "returning",
  {
    name: "Kabir",
    region: "IN",
    summary:
      "Male, 34, 181 cm, eight years of lifting before a six-month break (March to September), back for four weeks on three full-body days, 91 to 89.6 kg, wants his old numbers back fast.",
    voice:
      "Writes like a confident ex-competitive lifter and new father: a bit cocky about his old numbers, frustrated by starting light, short sentences, some swearing-free bluntness. No emoji.",
    background:
      "Lifted seriously for eight years: bench 115 x 5, squat 160 x 5, deadlift 200 x 3 in early March. Stopped from mid-March to late September for a new baby and a job change. Back since 21 September on three full-body sessions (Monday, Wednesday, Friday). Gained about 5 kg during the break. Sleeps badly some nights because of the baby. Wants to go back to his old four-day upper/lower and old weights within two months.",
  },
  {
    today: simulationToday,
    start: "2025-11-03",
    plans: [
      {
        from: "2025-11-03",
        title: "Upper lower strength",
        rationale: "Four upper/lower sessions for strength.",
        blockWeeks: 6,
        week: kabirBefore,
      },
      {
        from: "2026-09-21",
        progressFrom: "2026-09-21",
        title: "Return to training: full body",
        rationale:
          "Three full-body sessions at about two thirds of earlier loads, building back up.",
        blockWeeks: 6,
        week: kabirReturn,
      },
    ],
    away: [{ from: "2026-03-16", to: "2026-09-20" }],
    missEvery: 10,
    weight: [["2025-11-03", 86.2], ["2026-03-15", 86.6], ["2026-09-21", 91.2], [
      "2026-10-16",
      89.6,
    ]],
    weighInDays: [1, 5],
    waist: [88, 92],
    nutrition: {
      since: "2026-09-21",
      targets: [
        {
          from: "2025-11-03",
          calories: 3000,
          protein: 180,
          carbs: 350,
          fat: 90,
          rationale: "Maintenance for strength training.",
        },
        {
          from: "2026-09-21",
          calories: 2550,
          protein: 180,
          carbs: 270,
          fat: 75,
          rationale: "A modest deficit while training restarts.",
        },
      ],
      menu: indianNonVeg,
      complete: 0.5,
      partial: 0.3,
    },
    sleep: { minutes: 370, spread: 70, hrvMs: 48, restingHr: 60 },
    steps: 6500,
    checkInsSince: "2026-09-21",
    events: [],
  },
  {
    sex: "male",
    age: 34,
    heightCm: 181,
    experience: "advanced",
    trainingYears: "over_5",
    sessionMinutes: 60,
    equipment: ["barbell", "dumbbells", "bench", "rack", "cables", "machines", "pull_up_bar"],
    nutritionNotes: "Eats everything; chicken and eggs most days.",
    limitations: null,
    goal: {
      goalType: "strength",
      description: "Get back to old strength and lose the break weight",
      activatedOn: "2026-09-20",
    },
  },
  {
    goals: [{
      goal_type: "strength",
      status: "active",
      created_on: "2026-09-20",
      target: { weight_kg: 86, set_at: "2026-09-20" },
    }],
    screenings: [{ screened_on: "2026-09-19", outcome: "cleared" }],
    healthHistory: ["2025-05", "2025-06", "2025-07", "2025-08", "2025-09", "2025-10"].map((
      month,
      index,
    ) => ({
      month,
      workouts: 16 + (index % 2),
      strength_workouts: 16,
      workout_minutes: 1200,
      sleep_minutes_avg: 420,
      sleep_nights: 29,
      weight_kg_avg: 86 + (index % 2) * 0.3,
      weight_days: 8,
    })),
  },
  [confirmedFact("schedule_constraint", "new baby", "Has a new baby; some nights are short.")],
  { weight_kg: 86, set_at: "2026-09-20" },
);

export const personas: readonly Persona[] = [arjun, rohan, meera, kabir];

export function personaById(id: PersonaId): Persona {
  return personas.find((p) => p.id === id)!;
}

/**
 * What the persona's records show, in a few lines, for the judges: the main lifts' recent top sets,
 * body weight, nutrition and sleep. Computed from the records, so a judge can tell a reply that
 * used the athlete's data from one that did not.
 */
export function dataDigest(p: Persona): string {
  const { records } = p;
  const today = records.spec.today;
  const plan = planOn(records.spec, today);
  const lines: string[] = [
    `Profile: ${p.summary}`,
    `Plan: ${plan.title}, ${plan.week.map((s) => s.name).join(", ")}.`,
  ];
  for (const slug of plan.week.map((s) => s.lifts[0].slug)) {
    const done = records.sessions.flatMap((s) =>
      s.exercises.filter((e) => e.slug === slug && e.sets.length > 0).map((e) => ({
        date: s.local_date,
        top: e.sets[0],
        name: e.name,
      }))
    ).slice(-6);
    if (done.length === 0) continue;
    lines.push(
      `${done[0].name}, last ${done.length} sessions: ${
        done.map((d) =>
          `${d.date} ${d.top.load_kg ?? "bodyweight"} x ${d.top.reps}${
            d.top.load_kg ? ` (e1RM ${e1rm(d.top.load_kg, d.top.reps)})` : ""
          }`
        ).join("; ")
      }.`,
    );
  }
  const weights = records.weights;
  const monthAgo = weights.filter((w) => w.date <= addDays(today, -28)).at(-1);
  lines.push(
    `Body weight: ${weights[0].kg} kg on ${weights[0].date}, ${
      monthAgo ? `${monthAgo.kg} kg on ${monthAgo.date}, ` : ""
    }${weights.at(-1)!.kg} kg on ${weights.at(-1)!.date}.`,
  );
  const target = targetOn(records.spec, today);
  const recent = records.mealDays.filter((d) => d.local_date >= addDays(today, -14));
  const complete = recent.filter((d) => d.complete);
  const avg = (values: number[]) =>
    values.length ? Math.round(values.reduce((a, b) => a + b, 0) / values.length) : null;
  lines.push(
    `Nutrition (last 14 days): target ${target.calories} kcal and ${target.protein} g protein; ${complete.length} complete days averaging ${
      avg(complete.map((d) => d.calories))
    } kcal and ${avg(complete.map((d) => d.protein_g))} g protein; ${
      recent.length - complete.length
    } partial days; ${14 - recent.length} days not logged.`,
  );
  const sleep = records.recovery.filter((d) => d.local_date > addDays(today, -7))
    .map((d) => d.sleep_minutes).filter((m): m is number => m !== null);
  lines.push(`Sleep (last 7 nights with the watch): average ${avg(sleep)} minutes.`);
  const notes = records.checkIns.filter((c) => c.note && c.local_date >= addDays(today, -14));
  for (const note of notes) lines.push(`Check-in ${note.local_date}: "${note.note}"`);
  return lines.join("\n");
}
