// The athlete model: plays a persona and writes its next chat message from the conversation so far,
// the scenario's goal and the beat for this message. Its words are the only thing it decides; the
// records, the Coach and the grading are fixed code.
import type { Turn } from "../coach_bank/types.ts";
import { excerpt, type WireError } from "./diagnostics.ts";
import { jsonObjectIn, type RouterChat } from "./router_client.ts";
import type { Persona } from "./personas.ts";
import type { Scenario } from "./scenarios.ts";

export type AthleteMessage = Readonly<{ message: string; done: boolean }>;

/** The most characters of one athlete message, like a long phone message. */
export const athleteMessageMaxChars = 600;

const system =
  "You role-play an athlete who is chatting with the AI coach in their fitness app. Stay in character the whole time. " +
  "Write only the athlete's next message: one to three sentences, plain text, typed on a phone, in the athlete's own voice. " +
  "Never write the coach's part, never describe what you are doing, and never mention that this is a role-play or a test. " +
  "Stick to the facts in your background; when you are unsure of a number, be vague rather than invent one. " +
  "React to what the coach just said: if it asked you something, answer it; if it was vague or generic, say so the way a real lifter would. " +
  'Return a JSON object: {"message": "<your next message>", "done": <true only when your goal is fully met and you would stop chatting>}.';

export function athletePrompt(
  persona: Persona,
  scenario: Scenario,
  transcript: readonly Turn[],
  messageNumber: number,
  totalMessages: number,
): { system: string; user: string } {
  const beat = scenario.beats[messageNumber - 2];
  const thread = transcript.map((turn) =>
    `${turn.role === "user" ? persona.name : "Coach"}: ${turn.content}`
  ).join("\n\n");
  return {
    system,
    user: [
      `You are ${persona.name}. ${persona.summary}`,
      `Background (what you know about yourself): ${persona.background}`,
      `How you write: ${persona.voice}`,
      `What you want from this conversation: ${scenario.goal}`,
      `The conversation so far:\n<conversation>\n${thread}\n</conversation>`,
      `This is your message ${messageNumber} of at most ${totalMessages}.`,
      beat ? `For this message: ${beat}` : "Bring the conversation to a natural close.",
    ].join("\n\n"),
  };
}

/**
 * The athlete's message from the model's answer (a speaker label such as "Arjun:" removed), or
 * null when it gave none.
 */
export function parseAthleteMessage(text: string, name = "athlete"): AthleteMessage | null {
  const json = jsonObjectIn(text);
  const raw = json ? json.message : text;
  if (typeof raw !== "string") return null;
  const label = new RegExp(`^\\s*(?:${name}|athlete)\\s*:\\s*`, "i");
  const message = raw.replace(label, "").replace(/\s+/g, " ").trim().slice(
    0,
    athleteMessageMaxChars,
  );
  if (message === "") return null;
  return { message, done: json?.done === true };
}

export type AthleteTurnResult = Readonly<{
  message: AthleteMessage | null;
  costUsd: number;
  failure?: string;
  /** The wire error of the last failed call, for the error log. */
  error?: WireError;
}>;

/** Output tokens of the first ask and of the one retry after an empty answer. */
export const athleteMaxTokens = 400;
export const athleteRetryMaxTokens = 1_200;

/**
 * The athlete's next message through the router. An empty answer (a reasoning model that spent
 * its output on thinking, or a blank reply) is asked for once more with a larger budget; a second
 * one ends the conversation with the reason.
 */
export async function nextAthleteMessage(
  chat: RouterChat,
  model: string,
  persona: Persona,
  scenario: Scenario,
  transcript: readonly Turn[],
  messageNumber: number,
  totalMessages: number,
): Promise<AthleteTurnResult> {
  const prompt = athletePrompt(persona, scenario, transcript, messageNumber, totalMessages);
  let costUsd = 0;
  let last: AthleteTurnResult = { message: null, costUsd: 0 };
  for (const maxTokens of [athleteMaxTokens, athleteRetryMaxTokens]) {
    const result = await chat({ model, ...prompt, maxTokens, json: true, source: "athlete" });
    costUsd += result.costUsd;
    if (!result.ok) {
      const empty = result.kind === "empty" || result.kind === "no_choices" ||
        result.kind === "truncated";
      last = {
        message: null,
        costUsd,
        failure: empty
          ? `empty answer (${result.body})`
          : `${result.reason}${result.body ? `: ${result.body}` : ""}`,
        error: result,
      };
      if (empty) continue;
      return last;
    }
    const message = parseAthleteMessage(result.text, persona.name);
    if (message) return { message, costUsd };
    last = {
      message: null,
      costUsd,
      failure: "empty answer (no message in the reply)",
      error: { status: 200, kind: "empty", body: excerpt(result.text) },
    };
  }
  return {
    ...last,
    failure: `${last.failure}; asked twice, so the conversation ends here`,
  };
}
