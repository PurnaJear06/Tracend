// Reads an athlete's message for statements about themselves that Coach could remember: what they
// like and dislike, allergies, injuries, equipment, schedule limits, and how they want Coach to talk
// to them. This is closed-vocabulary matching, not language understanding: a statement is a claim
// only when its words fit one of the patterns below, and everything else is left alone. A claim is
// never stored. It becomes a suggestion the athlete can confirm (suggestions.ts).
import { contentWords, normalizeText, stem } from "./text.ts";
import type { FactKind } from "./vocabulary.ts";

export const weekdayNames = [
  "monday",
  "tuesday",
  "wednesday",
  "thursday",
  "friday",
  "saturday",
  "sunday",
] as const;

/** Day groups the athlete may name; each stands for the weekdays it covers. */
const dayGroups: Readonly<Record<string, readonly string[]>> = {
  weekend: ["saturday", "sunday"],
  weekday: ["monday", "tuesday", "wednesday", "thursday", "friday"],
};

export const styleCodes = ["direct", "gentle", "brief", "detailed"] as const;
export type StyleCode = typeof styleCodes[number];

export type ClaimTarget = "food" | "exercise" | "unknown";

export type StatementClaim =
  | Readonly<{ type: "like" | "dislike"; target: ClaimTarget; subject: string }>
  | Readonly<{ type: "allergy"; subject: string }>
  | Readonly<{ type: "injury" | "injury_resolved"; subject: string }>
  | Readonly<{ type: "equipment_has" | "equipment_lacks"; subject: string }>
  | Readonly<{ type: "schedule_days"; days: number }>
  | Readonly<{ type: "schedule_minutes"; minutes: number }>
  | Readonly<{ type: "schedule_unavailable"; weekdays: readonly string[] }>
  | Readonly<{ type: "style"; style: StyleCode }>;

export const maxClaimsPerMessage = 3;

// Closed lexicons -----------------------------------------------------------------------------

const bodyParts = [
  "knee",
  "shoulder",
  "lower back",
  "upper back",
  "back",
  "elbow",
  "wrist",
  "ankle",
  "hip",
  "neck",
  "hamstring",
  "quad",
  "quadricep",
  "calf",
  "shin",
  "foot",
  "heel",
  "achilles",
  "groin",
  "rib",
  "finger",
  "thumb",
  "hand",
  "glute",
  "rotator cuff",
  "forearm",
  "bicep",
  "tricep",
  "chest",
  "jaw",
];

const exerciseWords = new Set(
  (
    "squat deadlift bench press row curl lunge pullup pull-up chinup chin-up dip plank burpee " +
    "pushup push-up run running jog jogging cardio swim swimming cycling hiit crunch situp " +
    "sit-up thrust pulldown pull push lift lifting yoga pilates stretching treadmill " +
    "elliptical rowing skipping jump jumping kettlebell snatch clean fly raise extension " +
    "workout exercise gym leg"
  ).split(" "),
);

const foodWords = new Set(
  (
    "rice chicken egg fish paneer tofu milk cheese bread pasta oat oatmeal beef pork lamb " +
    "mutton mushroom broccoli spinach salad vegetable veggie fruit banana apple nut peanut " +
    "almond shake yogurt yoghurt curd dal lentil bean potato tomato onion garlic sugar " +
    "chocolate pizza burger fries soda coffee tea juice alcohol butter meat seafood shrimp " +
    "prawn cauliflower cabbage carrot avocado soy oil sweet dessert cake sandwich soup curry " +
    "roti chapati idli dosa sushi noodle cereal granola smoothie protein whey creatine " +
    "breakfast lunch dinner snack food meal"
  ).split(" "),
);

const equipmentItems: ReadonlyArray<readonly [string, string]> = [
  ["gym membership", "gym"],
  ["home gym", "home gym"],
  ["gym", "gym"],
  ["barbell", "barbell"],
  ["dumbbell", "dumbbells"],
  ["kettlebell", "kettlebells"],
  ["resistance band", "bands"],
  ["band", "bands"],
  ["pull-up bar", "pull-up bar"],
  ["pullup bar", "pull-up bar"],
  ["bench", "bench"],
  ["squat rack", "squat rack"],
  ["power rack", "squat rack"],
  ["rack", "squat rack"],
  ["cable", "cable machine"],
  ["treadmill", "treadmill"],
  ["exercise bike", "bike"],
  ["bike", "bike"],
  ["rowing machine", "rower"],
  ["weights", "weights"],
  ["equipment", "equipment"],
];

const styleRules: ReadonlyArray<readonly [StyleCode, readonly RegExp[]]> = [
  ["direct", [
    /\b(?:be|stay|get)(?: a bit| a little| more)? (?:direct|blunt|honest|straight|strict|tough)\b/,
    /\btell me (?:it )?(?:straight|directly|bluntly|like it is)\b/,
    /\b(?:don't|do not|no need to) sugar ?coat\b/,
    /\bno sugar ?coating\b/,
    /\bpush me (?:harder|more)\b/,
    /\btalk to me straight\b/,
    /\bi (?:prefer|like|want) (?:direct|blunt|honest|straight)(?: feedback| answers| coaching)?\b/,
  ]],
  ["gentle", [
    /\b(?:be|go)(?: a bit| a little| more)? (?:gentle|gentler|nicer|kinder|softer|encouraging|supportive)\b/,
    /\b(?:easy|gentle) on me\b/,
    /\bdon't be (?:so |too )?(?:harsh|blunt|strict|pushy|tough)\b/,
    /\bless (?:pushy|harsh|blunt)\b/,
    /\bi (?:prefer|like|want) (?:gentle|encouraging|supportive|positive)(?: feedback| coaching| tone)?\b/,
  ]],
  ["brief", [
    /\b(?:keep|make) (?:it|your (?:answers|replies|responses)|answers|replies|responses)(?: very| really| a bit)? (?:short|brief|concise|quick|simple)\b/,
    /\b(?:short|brief|concise|shorter|briefer)(?: answers| replies| responses)\b/,
    /\btl;?dr\b/,
    /\b(?:fewer|less) (?:words|text|detail)\b/,
    /\bbe (?:brief|concise|short)\b/,
    /\bget to the point\b/,
  ]],
  ["detailed", [
    /\b(?:more|full|extra|lots of) detail\b/,
    /\bgo (?:into|in) (?:more )?(?:detail|depth)\b/,
    /\bexplain (?:more|everything|in detail|in depth|why|the why)\b/,
    /\bdetailed (?:answers|replies|explanations|responses)\b/,
    /\blonger (?:answers|replies|explanations|responses)\b/,
    /\bbe (?:more )?(?:detailed|thorough)\b/,
    /\bi (?:like|want|prefer) (?:detail|detailed|thorough)\b/,
  ]],
];

/** A style request is a preference only when it is meant to last. */
const durableMarker =
  /\b(?:always|from now on|going forward|in general|generally|usually|in future|next time|every time|i prefer|i like|i want you to|please keep)\b/;

/** Words in a fact that point to one style, for comparing a saved style with a new one. */
const styleWords: Readonly<Record<StyleCode, readonly string[]>> = {
  direct: ["direct", "blunt", "honest", "straight", "strict", "tough"],
  gentle: ["gentle", "gentler", "kind", "nice", "soft", "supportive", "encouraging", "easy"],
  brief: ["short", "brief", "concise", "quick", "tldr", "tl;dr"],
  detailed: ["detail", "detailed", "thorough", "depth", "long", "explain"],
};

export const styleOpposite: Readonly<Record<StyleCode, StyleCode>> = {
  direct: "gentle",
  gentle: "direct",
  brief: "detailed",
  detailed: "brief",
};

/** The styles a saved fact's words point to; a style and its opposite together cancel out. */
export function stylesOf(text: string): StyleCode[] {
  const words = contentWords(text);
  const found = styleCodes.filter((code) =>
    styleWords[code].some((word) => words.includes(stem(word)))
  );
  return found.filter((code) => !found.includes(styleOpposite[code]));
}

// Clauses -----------------------------------------------------------------------------------------

const hypothetical =
  /\b(?:used to|if i|when i was|what if|would i|should i|do i|can i|could i|is it|are there|why do|why does|how do|how can)\b/;

/** The statements of a message: sentences, split again at "but" and "and I". Questions are dropped. */
export function clausesOf(text: string): string[] {
  const clauses: string[] = [];
  for (const match of text.matchAll(/([^.!?;\n]+)([.!?;\n]*)/g)) {
    if (match[2].includes("?")) continue;
    const clause = normalizeText(match[1]);
    if (clause === "" || hypothetical.test(clause)) continue;
    for (
      const part of clause.split(/\s+(?:but|however|although)\s+|\s+and\s+(?=i(?:'m|'ve|'ll)?\b)/)
    ) {
      if (part.trim() !== "") clauses.push(part.trim());
    }
  }
  return clauses;
}

const objectStop =
  /\b(?:because|since|when|while|so|which|but|if|unless|as|though|although|after|before)\b|[,:(]/;
const objectLead =
  /^(?:(?:doing|training|eating|drinking|to do|to train|to eat|a lot of|too much|so much|any|some|a|an|the|my) )+/;

/** The noun phrase an object clause names: up to five words, or null. */
export function objectPhrase(raw: string): string | null {
  const cut = raw.split(objectStop)[0].replace(/[^a-z0-9' -]/g, " ").replace(/\s+/g, " ").trim();
  const trimmed = cut.replace(objectLead, "").trim();
  if (/^(?:it|that|this|them|you|how|being|to|when|the way)\b/.test(trimmed)) return null;
  const words = trimmed.replace(/'/g, "").split(" ").filter((word) =>
    word !== "" && contentWords(word).length > 0
  );
  return words.length >= 1 && words.length <= 5 ? words.join(" ") : null;
}

function targetOf(subject: string, verbIsFood: boolean): ClaimTarget {
  const words = contentWords(subject);
  const isExercise = words.some((word) => exerciseWords.has(word));
  const isFood = words.some((word) => foodWords.has(word));
  if (verbIsFood) return "food";
  if (isExercise) return "exercise";
  return isFood ? "food" : "unknown";
}

export function bodyPartIn(text: string): string | null {
  const normalized = normalizeText(text);
  for (const part of bodyParts) {
    const match = normalized.match(
      new RegExp(`\\b(?:(left|right) )?${part}s?\\b`),
    );
    if (match) return match[1] ? `${match[1]} ${part}` : part;
  }
  return null;
}

export function equipmentIn(text: string): string | null {
  const normalized = normalizeText(text);
  for (const [word, canonical] of equipmentItems) {
    if (new RegExp(`\\b${word}s?\\b`).test(normalized)) return canonical;
  }
  return null;
}

const numberWords: Readonly<Record<string, number>> = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
};

const daysPattern =
  /\b(\d|one|two|three|four|five|six|seven)(?: |-)?(?:days?|times|sessions|x)(?: a| per| each| every| \/)? ?week/;
const minutesPattern = /\b(\d{2,3}) ?(?:min|mins|minutes)\b/;

/** "4 days a week" or "four times per week" in a phrase, else null. */
export function daysPerWeekIn(text: string): number | null {
  const match = normalizeText(text).match(daysPattern);
  if (!match) return null;
  const days = numberWords[match[1]] ?? Number(match[1]);
  return days >= 1 && days <= 7 ? days : null;
}

/** "45 minutes" in a phrase, else null. */
export function minutesIn(text: string): number | null {
  const match = normalizeText(text).match(minutesPattern);
  if (!match) return null;
  const minutes = Number(match[1]);
  return minutes >= 10 && minutes <= 240 ? minutes : null;
}

/** The weekdays a phrase names, with "weekends" and "weekdays" expanded. */
export function weekdaysIn(text: string): string[] {
  const normalized = normalizeText(text);
  const found = new Set<string>();
  for (const day of weekdayNames) {
    if (new RegExp(`\\b${day}s?\\b`).test(normalized)) found.add(day);
  }
  for (const [group, days] of Object.entries(dayGroups)) {
    if (new RegExp(`\\b${group}s?\\b`).test(normalized)) days.forEach((day) => found.add(day));
  }
  return weekdayNames.filter((day) => found.has(day));
}

// Claim rules -------------------------------------------------------------------------------------

type Rule = (clause: string) => StatementClaim | null;

const part = "((?:left |right )?[a-z ]{3,24}?)";

const injuryRules: Rule[] = [
  (clause) => {
    const m = clause.match(
      /\bi(?:'ve| have)? (?:just |recently )?(?:injured|hurt|strained|sprained|pulled|tore|torn|twisted|rolled|broke|broken|dislocated|tweaked) (?:my |the )?([a-z ]{3,30})/,
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      new RegExp(
        `\\bmy ${part} (?:is |has been |keeps |feels |gets )?(?:hurting|hurts|sore|aching|aches|injured|painful|inflamed|swollen|bothering me|tweaked|killing me|giving me (?:pain|trouble|problems))`,
      ),
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      /\bi have (?:a |some )?(?:bad |sore |chronic |old |nagging )?([a-z ]{3,24}?) (?:pain|injury|issues?|problems?|strain|sprain|tendinitis)\b/,
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      /\bi have (?:a |some )?(?:pain|injury|issues?|problems?) (?:in|with|on) (?:my |the )?([a-z ]{3,24})/,
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      /\bi have (?:a |an )?(?:bad|sore|weak|dodgy|painful|injured|stiff) ([a-z ]{3,24})/,
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury", subject } : null;
  },
];

const resolvedRules: Rule[] = [
  (clause) => {
    const m = clause.match(
      new RegExp(
        `\\bmy ${part} (?:is |feels |has |seems )?(?:fine|healed|better|ok|okay|good|normal|recovered|back to normal|100%)(?: now| again)?\\b`,
      ),
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury_resolved", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      new RegExp(
        `\\bmy ${part} (?:doesn't|does not|no longer|stopped|isn't|is not|hasn't|has not)(?: been)? (?:hurt|hurting|bother|bothering|painful|sore)`,
      ),
    );
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury_resolved", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\bno more ([a-z ]{3,24}?) (?:pain|issues?|problems?)\b/);
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury_resolved", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\b([a-z ]{3,24}?) pain is gone\b/);
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury_resolved", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\b(?:recovered|healed) from my ([a-z ]{3,30})/);
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury_resolved", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\bmy ([a-z ]{3,24}?) injury (?:is |has )?(?:healed|gone|over)\b/);
    const subject = m && bodyPartIn(m[1]);
    return subject ? { type: "injury_resolved", subject } : null;
  },
];

const allergyRules: Rule[] = [
  (clause) => {
    const m = clause.match(
      /\bi(?:'m| am) (?:allergic|intolerant|sensitive) to ([a-z0-9' -]{2,40})/,
    );
    const subject = m && objectPhrase(m[1]);
    return subject ? { type: "allergy", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\bi have an? ([a-z ]{2,24}?) (?:allergy|intolerance)\b/);
    const subject = m && objectPhrase(m[1]);
    return subject ? { type: "allergy", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\bi(?:'m| am) (lactose|gluten|dairy|nut|egg) intolerant\b/);
    return m ? { type: "allergy", subject: m[1] } : null;
  },
  (clause) =>
    /\bi(?:'m| am) (?:celiac|coeliac)\b/.test(clause)
      ? { type: "allergy", subject: "gluten" }
      : null,
];

const equipmentRules: Rule[] = [
  (clause) => {
    const m = clause.match(
      /\bi (?:don't|do not|dont|no longer) (?:have|own) (?:a |an |any |access to |the )?([a-z -]{3,30})/,
    );
    const subject = m && equipmentIn(m[1]);
    return subject ? { type: "equipment_lacks", subject } : null;
  },
  (clause) => {
    const m = clause.match(/\bi have no (?:access to )?([a-z -]{3,30})/);
    const subject = m && equipmentIn(m[1]);
    return subject ? { type: "equipment_lacks", subject } : null;
  },
  (clause) =>
    /\bi (?:left|quit|cancelled|canceled|stopped going to) (?:my |the )?gym\b/.test(clause)
      ? { type: "equipment_lacks", subject: "gym" }
      : null,
  (clause) => {
    const m = clause.match(
      /\bi (?:now |also |just |only )?(?:have|got|bought|own|joined|started) (?:a |an |access to |some |the |my )?([a-z -]{3,30})/,
    );
    const subject = m && equipmentIn(m[1]);
    return subject ? { type: "equipment_has", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      /\bi (?:work ?out|train|exercise|lift) (?:only )?(?:at|in) (?:a |the |my )?(gym|home|garage)\b/,
    );
    if (!m) return null;
    return { type: "equipment_has", subject: m[1] === "gym" ? "gym" : "home gym" };
  },
];

const scheduleRules: Rule[] = [
  (clause) => {
    if (!/\bi (?:can|could|will|'ll|only|usually|normally|am able to)\b|\bi'll\b/.test(clause)) {
      return null;
    }
    if (!/\b(?:train|work ?out|exercise|lift|gym|come in|go)\b/.test(clause)) return null;
    const days = daysPerWeekIn(clause);
    return days === null ? null : { type: "schedule_days", days };
  },
  (clause) => {
    if (!/\bi (?:have|got|can do|can spare|get|only have|just have)\b/.test(clause)) return null;
    const minutes = minutesIn(clause);
    return minutes === null ? null : { type: "schedule_minutes", minutes };
  },
  (clause) => {
    const m = clause.match(
      /\bi (?:can't|cannot|can not|won't|am not able to|'m not able to) (?:train|work ?out|exercise|lift|go to the gym)(?: on| during)? (.+)/,
    ) ?? clause.match(
      /\bi (?:don't|do not|dont|have no) (?:have )?(?:any )?time (?:on|for|during)? ?(.+)/,
    );
    if (!m) return null;
    const weekdays = weekdaysIn(m[1]);
    return weekdays.length > 0 ? { type: "schedule_unavailable", weekdays } : null;
  },
];

const likeVerbs =
  "(?:love|like|enjoy|prefer|adore|am a fan of|'m a fan of|am a big fan of|'m a big fan of)";
const dislikeVerbs =
  "(?:hate|dislike|detest|can't stand|cannot stand|don't like|do not like|dont like|am not a fan of|'m not a fan of|never liked)";

const preferenceRules: Rule[] = [
  (clause) => {
    const m = clause.match(
      /\bi (?:really |absolutely |totally )?(?:don't|do not|dont|never|can't|cannot|won't) (eat|drink|touch|stomach|tolerate) ([a-z0-9' -]{2,60})/,
    );
    const subject = m && objectPhrase(m[2]);
    return subject ? { type: "dislike", target: "food", subject } : null;
  },
  (clause) => {
    const m = clause.match(
      new RegExp(`\\bi (?:really |absolutely |totally )?${dislikeVerbs} ([a-z0-9' -]{2,60})`),
    );
    const subject = m && objectPhrase(m[1]);
    return subject ? { type: "dislike", target: targetOf(subject, false), subject } : null;
  },
  (clause) => {
    const m = clause.match(
      new RegExp(
        `\\bi (?:really |absolutely |totally )?${likeVerbs} ([a-z0-9' -]{2,60}?)(?: over | instead of | rather than | more than | to |$)`,
      ),
    );
    const subject = m && objectPhrase(m[1]);
    return subject ? { type: "like", target: targetOf(subject, false), subject } : null;
  },
];

function styleClaim(clause: string): StatementClaim | null {
  if (!durableMarker.test(clause)) return null;
  for (const [style, patterns] of styleRules) {
    if (patterns.some((pattern) => pattern.test(clause))) return { type: "style", style };
  }
  return null;
}

// The first rule group that fits wins, so "I don't have a gym" is equipment before it could be a
// food and "I don't have time on weekends" is a schedule limit, not a dislike.
const ruleGroups: readonly (readonly Rule[])[] = [
  allergyRules,
  resolvedRules,
  injuryRules,
  equipmentRules,
  scheduleRules,
  [styleClaim],
  preferenceRules,
];

/** The claims in a message, at most three, in the order they were written. */
export function extractClaims(text: string): StatementClaim[] {
  const claims: StatementClaim[] = [];
  for (const clause of clausesOf(text)) {
    for (const group of ruleGroups) {
      const claim = group.map((rule) => rule(clause)).find((found) => found !== null);
      if (claim) {
        claims.push(claim);
        break;
      }
    }
    if (claims.length >= maxClaimsPerMessage) break;
  }
  return claims;
}

// What a claim would be saved as -----------------------------------------------------------------

export type ClaimFact = Readonly<{ kind: FactKind; subject: string; statement: string }>;

const sentence = (text: string) => text.charAt(0).toUpperCase() + text.slice(1);

const styleStatements: Readonly<Record<StyleCode, string>> = {
  direct: "Prefers direct, blunt feedback",
  gentle: "Prefers a gentle, encouraging tone",
  brief: "Prefers short answers",
  detailed: "Prefers detailed explanations",
};

const weekdayList = (days: readonly string[]) =>
  days.length === 2 && days[0] === "saturday" && days[1] === "sunday"
    ? "weekends"
    : days.map((day) => `${sentence(day)}s`).join(", ");

/** The fact a claim stands for: a kind from the closed list, a short subject and a statement. */
export function claimToFact(claim: StatementClaim): ClaimFact {
  switch (claim.type) {
    case "like":
    case "dislike": {
      const liked = claim.type === "like";
      const kind: FactKind = claim.target === "food"
        ? (liked ? "food_like" : "food_dislike")
        : claim.target === "exercise"
        ? (liked ? "exercise_like" : "exercise_dislike")
        : "other_preference";
      return {
        kind,
        subject: claim.subject,
        statement: `${liked ? "Likes" : "Dislikes"} ${claim.subject}`,
      };
    }
    case "allergy":
      return {
        kind: "allergy",
        subject: claim.subject,
        statement: `Allergy or intolerance: ${claim.subject}`,
      };
    case "injury":
    case "injury_resolved":
      return {
        kind: "injury_limitation",
        subject: claim.subject,
        statement: `${sentence(claim.subject)} pain or injury`,
      };
    case "equipment_has":
      return { kind: "equipment", subject: claim.subject, statement: `Has ${claim.subject}` };
    case "equipment_lacks":
      return { kind: "equipment", subject: claim.subject, statement: `No ${claim.subject}` };
    case "schedule_days":
      return {
        kind: "schedule_constraint",
        subject: "days per week",
        statement: `Can train ${claim.days} ${claim.days === 1 ? "day" : "days"} a week`,
      };
    case "schedule_minutes":
      return {
        kind: "schedule_constraint",
        subject: "minutes per session",
        statement: `Has about ${claim.minutes} minutes per session`,
      };
    case "schedule_unavailable": {
      const list = weekdayList(claim.weekdays);
      return {
        kind: "schedule_constraint",
        subject: `no training ${list.toLowerCase()}`,
        statement: `Cannot train on ${list}`,
      };
    }
    case "style":
      return {
        kind: "coaching_style",
        subject: claim.style,
        statement: styleStatements[claim.style],
      };
  }
}
