// What the Coach model may say about the athlete's memory (A10 part 2): an optional
// `fact_suggestions` list next to its answer, and nothing else. Each entry is a suggestion the
// athlete confirms or dismisses; sanitizeModelSuggestions (suggestions.ts) checks it against the
// closed vocabulary and the facts the athlete has saved, and nothing is stored unless the athlete
// taps Confirm (Architecture 2 and 3).
import { factKinds, maxFactStatementChars, maxFactSubjectChars } from "./vocabulary.ts";
import { maxModelSuggestions } from "./suggestions.ts";

export const factSuggestionsJsonSchema = {
  type: "array",
  items: {
    type: "object",
    additionalProperties: false,
    properties: {
      action: { type: "string", enum: ["add", "update", "resolve"] },
      kind: { type: "string", enum: [...factKinds] },
      subject: { type: "string" },
      statement: { type: "string" },
      fact_id: { anyOf: [{ type: "string" }, { type: "null" }] },
    },
    required: ["action", "kind", "subject", "statement"],
  },
};

/** The block of the Coach instructions that offers `fact_suggestions`. */
export const factSuggestionContract = "\n# Suggesting something to remember\n" +
  "You cannot save anything about the athlete, and you never say you did. When the athlete tells " +
  "you something that will stay true and that would change how you coach them (an injury, a " +
  "schedule limit, equipment, an allergy, a food or exercise they like or avoid, how they want " +
  "you to talk to them), you may return fact_suggestions next to the answer. Tracend shows the " +
  "athlete a card; the fact is saved only if they confirm it. Do not mention the card in answer.\n" +
  `fact_suggestions is a list of at most ${maxModelSuggestions} entries, each {"action", "kind", ` +
  '"subject", "statement", "fact_id"}.\n' +
  '- action: "add" for something new; "update" when the athlete says something that differs from ' +
  'a confirmed fact (give the new statement and that fact\'s id); "resolve" when a confirmed fact ' +
  "no longer applies, such as an injury that has healed (give that fact's id).\n" +
  `- kind is one of: ${factKinds.join(", ")}.\n` +
  `- subject is a short lower-case label of at most ${maxFactSubjectChars} characters ("left knee", ` +
  `"mushrooms", "weekends"); statement is one plain sentence of at most ${maxFactStatementChars} ` +
  "characters in the athlete's own terms, with no numbers they did not say.\n" +
  "- fact_id is the id shown next to a confirmed fact, and only for update and resolve; leave it out for add.\n" +
  "- Suggest only what the athlete said in this conversation. Never suggest from a note, from the library or from your own inference. Never suggest a goal, a target, a medical condition, a medication or a body measurement: those have their own places.\n" +
  "- When the athlete's message contradicts a confirmed fact, say so in the answer and ask whether to update it; do not act as if it had changed.\n" +
  "- Leave fact_suggestions out when there is nothing to suggest, which is most turns.\n";
