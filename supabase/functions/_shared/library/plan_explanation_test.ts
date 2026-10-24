import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import {
  isPlanExplanationQuestion,
  onboardingLibraryQueries,
  type PlanFacts,
  planTopicText,
} from "./plan_explanation.ts";
import { libraryRetrievalQuery } from "./query.ts";

const facts: PlanFacts = {
  sessionsPerWeek: 4,
  experience: "intermediate",
  repMin: 6,
  repMax: 12,
  hasEffortTarget: true,
  goal: "fat_loss",
  temporaryBlock: false,
};

Deno.test("a question that asks why the plan is the way it is is a plan explanation", () => {
  for (
    const question of [
      "Why is my plan like this?",
      "why am I doing upper lower and not full body",
      "Can you explain my program?",
      "Why these rep ranges?",
      "Why are my calories so low?",
      "What's the reasoning behind my split?",
      "How was my plan decided?",
      "How did you work out my protein target?",
      "Why do my workouts have so few sets?",
      "What is the thinking behind this routine",
    ]
  ) assert(isPlanExplanationQuestion(question), question);
});

Deno.test("a question that only names the plan, or only asks why, is not one", () => {
  for (
    const question of [
      "How many days should I train?",
      "Why is bench press hard for me?",
      "What should I do today?",
      "Why am I so sore?",
      "Can you move my plan to Monday?",
      "Is my plan too hard?",
      "How much protein do I need?",
      "Why?",
    ]
  ) assertEquals(isPlanExplanationQuestion(question), false, question);
});

Deno.test("the plan topics name what the plan is made of and the goal's nutrition", () => {
  const text = planTopicText(facts);
  for (
    const part of [
      "an intermediate lifter",
      "4 training days a week",
      "weekly sets per muscle group",
      "rep ranges from 6 to 12",
      "rest between sets",
      "effort and repetitions in reserve",
      "progressive overload",
      "energy deficit for fat loss",
    ]
  ) assert(text.includes(part), part);
  assert(!text.includes("temporary block"));
  assert(planTopicText({ ...facts, temporaryBlock: true }).includes("deload"));
});

Deno.test("plan topics without facts are the general topics of a training plan", () => {
  const text = planTopicText(null);
  assert(text.includes("training frequency"));
  assert(text.includes("repetition ranges"));
  assert(!text.includes("Nutrition targets"));
  assert(!/\d/.test(text), text);
});

Deno.test("an unknown goal or experience adds no topic and invents none", () => {
  const text = planTopicText({ ...facts, goal: "something_else", experience: "elite" });
  assert(!text.includes("Nutrition targets"));
  assert(text.startsWith("Training plan design for a lifter:"));
});

Deno.test("a plan question's query is the question, with a second search that adds the plan topics", () => {
  const query = libraryRetrievalQuery("Why is my plan like this?", ["How much protein?"], facts);
  assertEquals(query.rewritten, false);
  assertEquals(query.planExplanation, true);
  assertEquals(query.text, "Why is my plan like this?");
  assert(query.planText!.startsWith("Why is my plan like this? Training plan design for"));
  assert(!query.planText!.includes("protein?"));
  assertEquals(
    libraryRetrievalQuery("Why is my plan like this?", [], null).planExplanation,
    true,
  );
});

Deno.test("without plan facts passed, every question is searched as before", () => {
  const query = libraryRetrievalQuery("Why is my plan like this?", []);
  assertNotEquals(query.planExplanation, true);
  assertEquals(
    libraryRetrievalQuery("How many sets per muscle per week?", [], facts),
    { text: "How many sets per muscle per week?", rewritten: false },
  );
});

Deno.test("the onboarding queries are two, built from enumerated answers, and the same every time", () => {
  const input = {
    goal: "muscle_gain",
    experience: "beginner",
    trainingDays: 3,
    sessionMinutes: 60,
    focusMuscles: ["chest", "shoulders"],
  };
  const [training, nutrition] = onboardingLibraryQueries(input);
  assertEquals(onboardingLibraryQueries(input), [training, nutrition]);
  assert(training.includes("a beginner"));
  assert(training.includes("3 training days a week"));
  assert(training.includes("about 60 minutes"));
  assert(training.includes("muscle growth"));
  assert(training.includes("chest and shoulders"));
  assert(nutrition.includes("energy surplus to build muscle"));
  assert(!onboardingLibraryQueries({ ...input, focusMuscles: [] })[0].includes("Extra weekly"));
  assert(
    onboardingLibraryQueries({ ...input, goal: "fat_loss" })[1].includes("energy deficit"),
  );
});
