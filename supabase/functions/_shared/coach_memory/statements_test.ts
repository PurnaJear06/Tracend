import { assertEquals } from "jsr:@std/assert@1.0.14";
import {
  claimToFact,
  clausesOf,
  daysPerWeekIn,
  extractClaims,
  maxClaimsPerMessage,
  minutesIn,
  objectPhrase,
  styleOpposite,
  stylesOf,
  weekdaysIn,
} from "./statements.ts";

const claims = (text: string) => extractClaims(text);

Deno.test("dislikes are filed under food, exercise or other by what they name", () => {
  assertEquals(claims("I don't like squats"), [
    { type: "dislike", target: "exercise", subject: "squats" },
  ]);
  assertEquals(claims("I hate mushrooms"), [
    { type: "dislike", target: "food", subject: "mushrooms" },
  ]);
  assertEquals(claims("I really dislike doing cardio"), [
    { type: "dislike", target: "exercise", subject: "cardio" },
  ]);
  assertEquals(claims("I can't stand early mornings"), [
    { type: "dislike", target: "unknown", subject: "early mornings" },
  ]);
  assertEquals(claims("I never eat red meat"), [
    { type: "dislike", target: "food", subject: "red meat" },
  ]);
  assertEquals(claims("I don't drink milk."), [
    { type: "dislike", target: "food", subject: "milk" },
  ]);
});

Deno.test("an eating verb makes a food even when the word is not in the food list", () => {
  assertEquals(claims("I don't eat jackfruit"), [
    { type: "dislike", target: "food", subject: "jackfruit" },
  ]);
});

Deno.test("likes and preferences", () => {
  assertEquals(claims("I love pizza"), [{ type: "like", target: "food", subject: "pizza" }]);
  assertEquals(claims("I prefer chicken over beef"), [
    { type: "like", target: "food", subject: "chicken" },
  ]);
  assertEquals(claims("I really enjoy deadlifts"), [
    { type: "like", target: "exercise", subject: "deadlifts" },
  ]);
  assertEquals(claims("I like rowing instead of running"), [
    { type: "like", target: "exercise", subject: "rowing" },
  ]);
});

Deno.test("two statements in one message give two claims, in order", () => {
  assertEquals(claims("I hate mushrooms and I love running"), [
    { type: "dislike", target: "food", subject: "mushrooms" },
    { type: "like", target: "exercise", subject: "running" },
  ]);
  assertEquals(claims("I love pizza but I hate burpees"), [
    { type: "like", target: "food", subject: "pizza" },
    { type: "dislike", target: "exercise", subject: "burpees" },
  ]);
});

Deno.test("no more than three claims come from one message", () => {
  const found = claims("I love pizza. I hate burpees. I love rice. I hate lunges. I love fish.");
  assertEquals(found.length, maxClaimsPerMessage);
});

Deno.test("allergies and intolerances", () => {
  assertEquals(claims("I'm allergic to peanuts"), [{ type: "allergy", subject: "peanuts" }]);
  assertEquals(claims("I have a shellfish allergy"), [{ type: "allergy", subject: "shellfish" }]);
  assertEquals(claims("I'm lactose intolerant"), [{ type: "allergy", subject: "lactose" }]);
  assertEquals(claims("I am celiac"), [{ type: "allergy", subject: "gluten" }]);
  assertEquals(claims("I'm sensitive to caffeine"), [{ type: "allergy", subject: "caffeine" }]);
});

Deno.test("injuries name the body part and its side", () => {
  assertEquals(claims("my left knee hurts when I squat"), [
    { type: "injury", subject: "left knee" },
  ]);
  assertEquals(claims("I hurt my right shoulder last week"), [
    { type: "injury", subject: "right shoulder" },
  ]);
  assertEquals(claims("I have a bad lower back"), [{ type: "injury", subject: "lower back" }]);
  assertEquals(claims("I have knee pain"), [{ type: "injury", subject: "knee" }]);
  assertEquals(claims("I have a pain in my wrist"), [{ type: "injury", subject: "wrist" }]);
  assertEquals(claims("I strained my hamstring"), [{ type: "injury", subject: "hamstring" }]);
  assertEquals(claims("my elbow aches"), [{ type: "injury", subject: "elbow" }]);
  // Plain soreness is not an injury.
  assertEquals(claims("my quads are sore"), []);
  assertEquals(claims("I have a sore back"), []);
});

Deno.test("a healed injury is a resolution, not a new injury", () => {
  const resolved = (text: string, subject: string) =>
    assertEquals(claims(text), [{ type: "injury_resolved", subject }], text);
  resolved("my knee is fine now", "knee");
  // "Better" is not healed.
  assertEquals(claims("my left knee feels better"), []);
  resolved("my shoulder doesn't hurt anymore", "shoulder");
  resolved("no more back pain", "back");
  resolved("my ankle injury has healed", "ankle");
  resolved("I recovered from my elbow tendinitis", "elbow");
  resolved("my wrist pain is gone", "wrist");
});

Deno.test("equipment: what the athlete has, lacks, or where they train", () => {
  assertEquals(claims("I joined a gym"), [{ type: "equipment_has", subject: "gym" }]);
  assertEquals(claims("I only have dumbbells at home"), [
    { type: "equipment_has", subject: "dumbbells" },
  ]);
  assertEquals(claims("I don't have a barbell"), [{ type: "equipment_lacks", subject: "barbell" }]);
  assertEquals(claims("I have no access to a gym"), [{ type: "equipment_lacks", subject: "gym" }]);
  assertEquals(claims("I quit my gym"), [{ type: "equipment_lacks", subject: "gym" }]);
  assertEquals(claims("I work out at home"), [{ type: "equipment_has", subject: "home gym" }]);
  assertEquals(claims("I train at the gym"), [{ type: "equipment_has", subject: "gym" }]);
  assertEquals(claims("I bought a pull-up bar"), [{
    type: "equipment_has",
    subject: "pull-up bar",
  }]);
});

Deno.test("schedule limits: days, minutes and days that are out", () => {
  assertEquals(claims("I can only train 3 days a week"), [{ type: "schedule_days", days: 3 }]);
  assertEquals(claims("I can work out four times per week"), [{ type: "schedule_days", days: 4 }]);
  assertEquals(claims("I have 30 minutes"), [{ type: "schedule_minutes", minutes: 30 }]);
  assertEquals(claims("I only have 45 minutes per session"), [
    { type: "schedule_minutes", minutes: 45 },
  ]);
  assertEquals(claims("I can't train on Saturdays"), [
    { type: "schedule_unavailable", weekdays: ["saturday"] },
  ]);
  assertEquals(claims("I don't have time on weekends"), [
    { type: "schedule_unavailable", weekdays: ["saturday", "sunday"] },
  ]);
  assertEquals(claims("I can't work out during the week days"), []);
});

Deno.test("the audit's example is a schedule limit, not a food", () => {
  const found = claims("I don't have time on weekends");
  assertEquals(found.map((claim) => claim.type), ["schedule_unavailable"]);
  assertEquals(claimToFact(found[0]).kind, "schedule_constraint");
});

Deno.test("a style request counts only when it is meant to last", () => {
  assertEquals(claims("always keep it short please"), [{ type: "style", style: "brief" }]);
  assertEquals(claims("from now on be direct with me"), [{ type: "style", style: "direct" }]);
  assertEquals(claims("in general I want more detail"), [{ type: "style", style: "detailed" }]);
  assertEquals(claims("I prefer gentle coaching"), [{ type: "style", style: "gentle" }]);
  assertEquals(claims("be direct"), []);
  assertEquals(claims("keep it short"), []);
});

Deno.test("questions, hypotheticals and the past make no claim", () => {
  const none = [
    "do I hate squats?",
    "what if I hate squats?",
    "I used to hate burpees",
    "should I avoid milk because I don't eat dairy?",
    "if I hurt my knee, what then?",
    "I'd like to lose weight",
    "I like to run",
    "I like it when you are direct",
    "how do I fix my knee pain?",
    "hello",
    "",
  ];
  for (const text of none) assertEquals(claims(text), [], text);
});

Deno.test("clausesOf drops questions and splits at but, however and 'and I'", () => {
  assertEquals(clausesOf("I love pizza! Is it bad? I hate rice"), ["i love pizza", "i hate rice"]);
  assertEquals(clausesOf("My knee hurts but I trained anyway"), [
    "my knee hurts",
    "i trained anyway",
  ]);
});

Deno.test("objectPhrase keeps up to five words and refuses pronouns and long clauses", () => {
  assertEquals(
    objectPhrase("the early morning sessions because I'm tired"),
    "early morning sessions",
  );
  assertEquals(objectPhrase("it"), null);
  assertEquals(objectPhrase("one two three four five six"), null);
  assertEquals(objectPhrase(""), null);
});

Deno.test("number readers", () => {
  assertEquals(daysPerWeekIn("four times per week"), 4);
  assertEquals(daysPerWeekIn("3 days a week"), 3);
  assertEquals(daysPerWeekIn("9 days a week"), null);
  assertEquals(daysPerWeekIn("some days"), null);
  assertEquals(minutesIn("about 45 minutes"), 45);
  assertEquals(minutesIn("5 minutes"), null);
  assertEquals(minutesIn("300 minutes"), null);
  assertEquals(weekdaysIn("on weekends and fridays"), ["friday", "saturday", "sunday"]);
  assertEquals(weekdaysIn("weekdays"), ["monday", "tuesday", "wednesday", "thursday", "friday"]);
  assertEquals(weekdaysIn("never"), []);
});

Deno.test("stylesOf reads a saved style and drops a style cancelled by its opposite", () => {
  assertEquals(stylesOf("Prefers direct, blunt feedback"), ["direct"]);
  assertEquals(stylesOf("Prefers short answers"), ["brief"]);
  assertEquals(stylesOf("direct but gentle"), []);
  assertEquals(stylesOf("direct and short"), ["direct", "brief"]);
  assertEquals(styleOpposite.direct, "gentle");
  assertEquals(styleOpposite.detailed, "brief");
});

Deno.test("claimToFact gives every claim a closed kind, a lower-case subject and a statement", () => {
  const cases: [Parameters<typeof claimToFact>[0], string, string, string][] = [
    [{ type: "like", target: "food", subject: "pizza" }, "food_like", "pizza", "Likes pizza"],
    [{ type: "dislike", target: "food", subject: "milk" }, "food_dislike", "milk", "Dislikes milk"],
    [
      { type: "like", target: "exercise", subject: "rowing" },
      "exercise_like",
      "rowing",
      "Likes rowing",
    ],
    [
      { type: "dislike", target: "exercise", subject: "squats" },
      "exercise_dislike",
      "squats",
      "Dislikes squats",
    ],
    [
      { type: "dislike", target: "unknown", subject: "early mornings" },
      "other_preference",
      "early mornings",
      "Dislikes early mornings",
    ],
    [
      { type: "allergy", subject: "peanuts" },
      "allergy",
      "peanuts",
      "Allergy or intolerance: peanuts",
    ],
    [
      { type: "injury", subject: "left knee" },
      "injury_limitation",
      "left knee",
      "Left knee pain or injury",
    ],
    [
      { type: "injury_resolved", subject: "knee" },
      "injury_limitation",
      "knee",
      "Knee pain or injury",
    ],
    [{ type: "equipment_has", subject: "gym" }, "equipment", "gym", "Has gym"],
    [{ type: "equipment_lacks", subject: "barbell" }, "equipment", "barbell", "No barbell"],
    [
      { type: "schedule_days", days: 3 },
      "schedule_constraint",
      "days per week",
      "Can train 3 days a week",
    ],
    [
      { type: "schedule_days", days: 1 },
      "schedule_constraint",
      "days per week",
      "Can train 1 day a week",
    ],
    [
      { type: "schedule_minutes", minutes: 30 },
      "schedule_constraint",
      "minutes per session",
      "Has about 30 minutes per session",
    ],
    [
      { type: "schedule_unavailable", weekdays: ["saturday", "sunday"] },
      "schedule_constraint",
      "no training weekends",
      "Cannot train on weekends",
    ],
    [
      { type: "schedule_unavailable", weekdays: ["friday"] },
      "schedule_constraint",
      "no training fridays",
      "Cannot train on Fridays",
    ],
    [
      { type: "style", style: "direct" },
      "coaching_style",
      "direct",
      "Prefers direct, blunt feedback",
    ],
    [
      { type: "style", style: "gentle" },
      "coaching_style",
      "gentle",
      "Prefers a gentle, encouraging tone",
    ],
    [{ type: "style", style: "brief" }, "coaching_style", "brief", "Prefers short answers"],
    [
      { type: "style", style: "detailed" },
      "coaching_style",
      "detailed",
      "Prefers detailed explanations",
    ],
  ];
  for (const [claim, kind, subject, statement] of cases) {
    const fact = claimToFact(claim);
    assertEquals([fact.kind, fact.subject, fact.statement], [kind, subject, statement]);
    assertEquals(fact.subject, fact.subject.toLowerCase());
    assertEquals(fact.subject.length <= 60 && fact.statement.length <= 200, true);
  }
});
