// Reading rejected attempts with the reply check the gateway runs. No model.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { coachReplyCheckFor } from "../../_shared/providers/coach_chat_provider.ts";
import { previousQuestionsOf } from "../../_shared/library/query.ts";
import { renderTurn } from "../coach_bank/harness.ts";
import { wordSearch } from "./library_search.ts";
import { personaById } from "./personas.ts";
import { inspectAnswers } from "./rejections.ts";

const answerJson = (answer: string, extra: Record<string, unknown> = {}) =>
  JSON.stringify({
    data_requests: [],
    proposal_intent: [],
    fact_suggestions: [],
    answer,
    evidence: [],
    missing_data: [],
    safety_state: "allowed",
    suggested_follow_ups: [],
    reasoning_chain: [],
    ...extra,
  });

Deno.test("a rejected attempt is read back with its rules and the figures the numbers check named", async () => {
  const persona = personaById("primary");
  const athlete = persona.athlete();
  const question = "How is the cut going?";
  const contributions = await renderTurn(
    athlete,
    question,
    previousQuestionsOf(athlete.context, question),
    {
      librarySearch: wordSearch(persona.region),
    },
  );
  const check = coachReplyCheckFor(athlete.context, question, contributions, []);
  const found = inspectAnswers(
    [
      "Sure! Here is the answer as prose, not JSON.",
      answerJson("You lost 7.3 kg in 4 weeks, so the cut is on track."),
      answerJson("Looking at it now.", {
        data_requests: [{ lookup: "body", from: "2026-09-01", to: "2026-10-16", filter: "" }],
      }),
      answerJson("Keep going and log your meals."),
    ],
    check,
    new Set(Object.keys(contributions.shown)),
  );
  assertEquals(found.length, 2, "the lookup round and the clean answer are not rejections");
  assertEquals(found[0].rules, ["json_syntax"]);
  assertEquals(found[1].rules, ["numbers_not_grounded"]);
  assertStringIncludes(found[1].detail ?? "", "7.3");
  assertStringIncludes(found[1].answer, "lost 7.3 kg");
});

Deno.test("a library citation of a source the Coach was not shown is refused", async () => {
  const persona = personaById("primary");
  const athlete = persona.athlete();
  const question = "Is creatine worth it?";
  const contributions = await renderTurn(athlete, question, [], {
    librarySearch: wordSearch(persona.region),
  });
  const check = coachReplyCheckFor(athlete.context, question, contributions, []);
  const found = inspectAnswers(
    [answerJson("It is well supported.", {
      evidence: [{ code: "not_a_shown_source_2099", label: "Nobody 2099", source: "library" }],
    })],
    check,
    new Set(Object.keys(contributions.shown)),
  );
  assertEquals(found.length, 1);
  assert(found[0].rules.includes("citation_not_retrieved"), found[0].rules.join());
});
