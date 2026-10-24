// Plan explanations that cite the library (chunk E5). When the athlete asks why their plan is the
// way it is, a question like "Why is my plan like this?" has no topic of its own for the library
// to search, so Coach chat adds what the plan is made of (frequency, weekly sets, rep ranges, rest,
// effort, progression and the goal's nutrition) to the search text. The onboarding plan prompt is
// given excerpts for the same topics, chosen from the athlete's answers. Everything here is
// deterministic and built from fixed wording and enumerated facts: no model call decides what the
// library is searched for, and nothing the athlete typed freely enters a query except the question
// they asked Coach. Retrieval is context: the plan's numbers still come from Tracend's rules.

/** The plan facts a search text is built from: enumerated or counted, never the athlete's words. */
export type PlanFacts = Readonly<{
  /** Training days in the plan's week, when the plan is known. */
  sessionsPerWeek: number | null;
  /** beginner, intermediate or advanced, when known. */
  experience: string | null;
  /** The lowest and the highest rep count the plan prescribes, when it prescribes any. */
  repMin: number | null;
  repMax: number | null;
  /** Whether the plan gives an effort target (RPE). */
  hasEffortTarget: boolean;
  /** fat_loss, muscle_gain, recomposition, strength or aesthetic, when the athlete has a goal. */
  goal: string | null;
  /** A temporary block (a deload or a short change) is in force. */
  temporaryBlock: boolean;
}>;

/** What each goal's nutrition targets rest on, in the words the library's entries use. */
const goalNutritionTopics: Readonly<Record<string, string>> = Object.freeze({
  fat_loss:
    "protein intake and a moderate energy deficit for fat loss while keeping muscle, how fast to lose weight",
  muscle_gain: "protein intake and a small energy surplus to build muscle",
  recomposition: "protein intake and energy balance for body recomposition",
  strength: "protein and energy intake to support strength training",
  aesthetic: "protein intake and energy balance to build muscle and stay lean",
});

/** What the goal asks of training, in the library's words. */
const goalTrainingTopics: Readonly<Record<string, string>> = Object.freeze({
  fat_loss: "keeping muscle and strength while losing fat",
  muscle_gain: "muscle growth (hypertrophy)",
  recomposition: "body recomposition",
  strength: "maximal strength and heavier loads",
  aesthetic: "muscle growth (hypertrophy) and symmetry",
});

const experienceTopics: Readonly<Record<string, string>> = Object.freeze({
  beginner: "a beginner",
  intermediate: "an intermediate lifter",
  advanced: "an advanced lifter",
});

const dayWord = (days: number) => `${days} training ${days === 1 ? "day" : "days"} a week`;

/** The text added to a plan question: what a training plan is made of, for this plan. */
export function planTopicText(plan: PlanFacts | null): string {
  const parts = [
    plan?.sessionsPerWeek ? dayWord(plan.sessionsPerWeek) : "training frequency",
    "weekly sets per muscle group",
    plan?.repMin && plan.repMax
      ? `rep ranges from ${plan.repMin} to ${plan.repMax}`
      : "repetition ranges",
    "rest between sets",
    plan?.hasEffortTarget ? "effort and repetitions in reserve" : "training close to failure",
    "progressive overload",
  ];
  const goal = plan?.goal ? goalNutritionTopics[plan.goal] : undefined;
  const experience = plan?.experience ? experienceTopics[plan.experience] : undefined;
  return [
    `Training plan design for ${experience ?? "a lifter"}: ${parts.join(", ")}.`,
    goal ? `Nutrition targets: ${goal}.` : null,
    plan?.temporaryBlock ? "A temporary block such as a deload week." : null,
  ].filter(Boolean).join(" ");
}

// A question about why the plan is the way it is: it names the plan (or a part of it) and asks for
// a reason. Both are needed, so "How many days should I train?" and "Why is bench hard?" are not
// plan explanations, and "Why is my plan like this?" and "How was my plan decided?" are.
const aboutThePlan = new RegExp(
  String.raw`\b(?:plan|program(?:me)?|routine|split|schedule|block|template|upper[ /-]?lower|` +
    String.raw`full[ -]?body|push[ /-]pull|ppl|` +
    String
      .raw`(?:my|these|this|the) (?:workouts?|sessions?|targets?|calories|macros?|numbers|protein|exercises|` +
    String.raw`rep ranges?|sets|rest times?|training days?))\b`,
  "i",
);
const asksWhy = new RegExp(
  String
    .raw`\b(?:why|reason(?:s|ing)?|rationale|explain|justify|how come|logic behind|thinking behind|` +
    String.raw`what(?:'s| is| was) the (?:point|logic|idea|thinking|basis)|based on what|` +
    String.raw`how (?:was|were|is|are|did)\b[^?.!]{0,40}\b(?:built|chosen|decided|made|designed|` +
    String.raw`work(?:ed)? out|calculated|picked|set|come up|put together))\b`,
  "i",
);

/** Whether the athlete is asking why their plan, or a part of it, is the way it is. */
export function isPlanExplanationQuestion(question: string): boolean {
  return aboutThePlan.test(question) && asksWhy.test(question);
}

// ---- the onboarding plan -------------------------------------------------------------------

/** The answers the onboarding searches are built from: enumerated, never the athlete's own words. */
export type OnboardingLibraryFacts = Readonly<{
  goal: string;
  experience: string;
  trainingDays: number;
  sessionMinutes: number;
  /** Focus muscles the athlete chose, from the catalog's fixed list. */
  focusMuscles: readonly string[];
}>;

/**
 * The two searches that give the onboarding plan prompt its excerpts: one for how the training is
 * built and one for what the nutrition targets rest on. They run apart because one question that
 * mixes two topics finds fewer of the right sources than two that each hold one.
 */
export function onboardingLibraryQueries(facts: OnboardingLibraryFacts): string[] {
  const goal = goalTrainingTopics[facts.goal];
  const experience = experienceTopics[facts.experience] ?? "a lifter";
  const focus = facts.focusMuscles.length
    ? ` Extra weekly volume for ${facts.focusMuscles.join(" and ")}.`
    : "";
  return [
    `Resistance training programme for ${experience} aiming at ${
      goal ?? "general strength and muscle"
    }: ${
      dayWord(facts.trainingDays)
    } of about ${facts.sessionMinutes} minutes, weekly sets per muscle group, ` +
    `training frequency, rep ranges, rest between sets, effort and repetitions in reserve, ` +
    `progressive overload.${focus}`,
    `Nutrition targets for a lifter: ${
      goalNutritionTopics[facts.goal] ?? "protein intake and energy balance for lifters"
    }.`,
  ];
}
