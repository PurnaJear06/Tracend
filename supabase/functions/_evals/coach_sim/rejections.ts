// Why the reply guard sent an attempt to repair. Production keeps only the rule name (and a path)
// of a rejected attempt, so a data summary or a repaired reply says "numbers_not_grounded" and not
// which figure. The router wrapper hands the simulator the text of every answer; this reads each
// one with the same check the gateway ran (`coachReplyCheckFor`, with the rows the Coach looked
// up) and keeps the rules, the figures it named and the start of what the Coach wrote.
import type { CoachChatAnswerCheck } from "../../_shared/contracts/coach_chat_v1.ts";
import { jsonObjectIn } from "./wire.ts";

export type Rejection = Readonly<{
  rules: readonly string[];
  /** The figures the numbers check named, when it did. */
  detail?: string;
  /** The start of the text the athlete would have read. */
  answer: string;
}>;

const clip = (text: string, max: number) =>
  text.length <= max ? text : `${text.slice(0, max)} [cut]`;

const strings = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];

/**
 * The attempts among `texts` that the reply check refuses, in order. A text with no JSON object is
 * a syntax failure; a lookup round (data_requests filled in) is not an answer and is left out; a
 * library evidence item that names a source the Coach was not shown breaks citation_not_retrieved.
 */
export function inspectAnswers(
  texts: readonly string[],
  check: CoachChatAnswerCheck,
  shown: ReadonlySet<string>,
): Rejection[] {
  const found: Rejection[] = [];
  for (const text of texts) {
    const json = jsonObjectIn(text);
    if (!json) {
      found.push({ rules: ["json_syntax"], answer: clip(text, 600) });
      continue;
    }
    if (Array.isArray(json.data_requests) && json.data_requests.length > 0) continue;
    const answer = typeof json.answer === "string" ? json.answer : "";
    const evidence = Array.isArray(json.evidence) ? json.evidence : [];
    const cited = evidence.flatMap((item) => {
      const entry = item as { code?: unknown; source?: unknown };
      return entry?.source === "library" && typeof entry.code === "string" ? [entry.code] : [];
    });
    const unshown = cited.filter((code) => !shown.has(code));
    // The strings the app shows: the answer, the chips, the notes on missing data, the evidence
    // labels and the reasoning chain (the contract's visibleText).
    const visible = [
      answer,
      ...strings(json.suggested_follow_ups),
      ...strings(json.missing_data),
      ...evidence.flatMap((item) => strings([(item as { label?: unknown })?.label])),
      ...(Array.isArray(json.reasoning_chain) ? json.reasoning_chain : []).flatMap((step) =>
        strings([(step as { step?: unknown })?.step, (step as { value?: unknown })?.value])
      ),
    ].join("\n");
    const result = check(visible, cited);
    const broken = typeof result === "string" ? { rule: result } : result;
    const rules: string[] = [...(broken ? (broken.rules ?? [broken.rule]) : [])];
    if (unshown.length > 0 && !rules.includes("citation_not_retrieved")) {
      rules.push("citation_not_retrieved");
    }
    if (rules.length === 0) continue;
    found.push({
      rules,
      ...(broken && "detail" in broken && broken.detail ? { detail: broken.detail } : {}),
      answer: clip(answer, 900),
    });
  }
  return found;
}
