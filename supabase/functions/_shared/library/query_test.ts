import { assertEquals } from "jsr:@std/assert@1.0.14";
import { screenMessage } from "../coach_safety/red_flags.ts";
import {
  isFollowUp,
  libraryRetrievalQuery,
  maxQuestionChars,
  maxTopicChars,
  previousQuestionsOf,
  topicTerms,
} from "./query.ts";

Deno.test("topic terms drop stop words and keep short numbers and units", () => {
  assertEquals(topicTerms("How much protein should I eat per day to build muscle?"), [
    "protein",
    "eat",
    "per",
    "day",
    "build",
    "muscle",
  ]);
  assertEquals(topicTerms("Is 5x5 better than 3 sets?"), ["5x5", "sets"]);
});

Deno.test("a question with a topic of its own is not a follow-up", () => {
  for (
    const question of [
      "How much protein should I eat per day to build muscle?",
      "Can I train fasted?",
      "Do I need creatine?",
      "Is it better to train each muscle once or twice a week?",
    ]
  ) assertEquals(isFollowUp(question), false, question);
});

Deno.test("a short question that points back is a follow-up", () => {
  for (
    const question of [
      "And on rest days?",
      "What about for fat loss?",
      "Is that enough?",
      "Why?",
      "How often?",
      "Does it matter for women?",
      "What if I can't?",
    ]
  ) assertEquals(isFollowUp(question), true, question);
});

Deno.test("a question searches as it stands when nothing needs borrowing", () => {
  const query = libraryRetrievalQuery("How many sets per muscle per week?", [
    "What is reps in reserve?",
  ]);
  assertEquals(query, { text: "How many sets per muscle per week?", rewritten: false });
});

Deno.test("a follow-up borrows the topic of the last real question", () => {
  const query = libraryRetrievalQuery("And on rest days?", [
    "Is that enough?",
    "How much protein should I eat per day to build muscle?",
    "Hi",
  ]);
  assertEquals(query, {
    text: "And on rest days? How much protein should I eat per day to build muscle?",
    rewritten: true,
  });
});

Deno.test("a follow-up with nothing before it, or only follow-ups, uses what exists", () => {
  assertEquals(libraryRetrievalQuery("Why?", []), { text: "Why?", rewritten: false });
  assertEquals(libraryRetrievalQuery("Why?", ["", "  "]), { text: "Why?", rewritten: false });
  assertEquals(libraryRetrievalQuery("Why?", ["Is that enough?", "What about it?"]), {
    text: "Why? Is that enough?",
    rewritten: true,
  });
});

Deno.test("the rewrite is deterministic and bounded", () => {
  const long = "protein ".repeat(200);
  const first = libraryRetrievalQuery("And then?", [long]);
  assertEquals(libraryRetrievalQuery("And then?", [long]), first);
  assertEquals(first.text.length <= maxQuestionChars + maxTopicChars + 1, true);
  assertEquals(libraryRetrievalQuery("x".repeat(900), []).text.length, maxQuestionChars);
});

Deno.test("earlier questions come from the athlete's messages, newest first", () => {
  const context = {
    recent_messages: [
      { role: "user", content: "How much protein do I need?" },
      { role: "assistant", content: "About 1.6 g per kg." },
      { role: "user", content: "And for cutting?" },
      { role: "user", content: "Is sleep important?" },
      { role: "assistant", content: "Yes." },
    ],
  };
  assertEquals(previousQuestionsOf(context, "And on rest days?"), [
    "Is sleep important?",
    "And for cutting?",
    "How much protein do I need?",
  ]);
  assertEquals(previousQuestionsOf(context, "And on rest days?", 1), ["Is sleep important?"]);
  assertEquals(previousQuestionsOf(context, "Is sleep important?"), [
    "And for cutting?",
    "How much protein do I need?",
  ]);
  assertEquals(previousQuestionsOf({}, "Hello"), []);
  assertEquals(previousQuestionsOf({ recent_messages: "nope" }, "Hello"), []);
});

Deno.test("a question that reported a symptom never lends its words to a follow-up", () => {
  const symptom = "I get chest pain when I squat heavy";
  assertEquals(screenMessage(symptom) !== null, true);
  const query = libraryRetrievalQuery("And on rest days?", [
    symptom,
    "How much protein should I eat per day to build muscle?",
  ]);
  assertEquals(
    query.text,
    "And on rest days? How much protein should I eat per day to build muscle?",
  );
  // With nothing else to borrow, the follow-up is searched as it stands.
  assertEquals(libraryRetrievalQuery("And on rest days?", [symptom]), {
    text: "And on rest days?",
    rewritten: false,
  });
  // The fallback to a follow-up of its own skips it too.
  assertEquals(
    libraryRetrievalQuery("Why?", [symptom, "Is that enough?"]).text,
    "Why? Is that enough?",
  );
});

Deno.test("a question that starts with why or how come has a topic of its own", () => {
  for (
    const question of [
      "Why does creatine make me retain water?",
      "How come my squat stalls every week?",
      "Why should I rest between sets?",
    ]
  ) assertEquals(isFollowUp(question), false, question);
  // Alone, with nothing else said, it still depends on the question before.
  assertEquals(isFollowUp("Why?"), true);
  assertEquals(isFollowUp("And why?"), true);
});
