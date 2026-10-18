// Coach repeating itself across turns (AI_SAFETY_SPEC §12): the same closing question, or the same
// sentence, as in the athlete's previous reply. Read deterministically from the two replies:
//   - the closing question is the reply's last sentence when it ends with "?"; it repeats when
//     its content words are nearly the same as the previous reply's closing question;
//   - any other sentence repeats when it is long enough to say something and nearly all its
//     content words are in one sentence of the previous reply.
// "Nearly" is the Dice coefficient of the two sets of content words (twice the shared words over
// the words in both sets), after dropping function words and figures and trimming word endings.
// Safety wording is never a repeat: an emergency or red-flag line always bears repeating, and a
// referral line (see a doctor, get it checked, get clearance) bears repeating when the turn needs
// one (the health check is not cleared, today's pain is high, or the question or the previous
// exchange may be about a health risk), and then every caution or limit stands too. A stop rule
// for pain or another symptom always stands. The athlete asking the same thing again also gets
// the same answer again.

/** Closing questions are short; this many content words each, and at least this similar. */
export const closingQuestionSimilarity = 0.7;
export const closingQuestionMinWords = 3;
/** A longer sentence says something of its own; a repeat of one must be nearly word for word. */
export const sentenceSimilarity = 0.8;
export const sentenceMinWords = 6;
/** A question asked again, as similar as two questions of the athlete are. */
export const askedAgainSimilarity = 0.7;

const stopWords = new Set(
  ("the and for you your yours with that this these those have has had are was were been being but " +
    "not can could will would should shall may might from they them then than also just into out " +
    "its over more most some any all our get got let what when where which while who whom how why " +
    "too very about after before again once there here does did doing want like need make sure " +
    "ill ive youre youll dont wont cant").split(" "),
);

/** The content words of a sentence: letters only, no function words, endings trimmed. */
export function contentWords(sentence: string): Set<string> {
  return new Set(
    sentence.toLowerCase().replaceAll("’", "'").replace(/[^\p{L}\s]+/gu, " ").split(/\s+/)
      .filter((word) => word.length > 2 && !stopWords.has(word))
      .map((word) => word.replace(/(?:ing|ed|es|s)$/, "")).filter((word) => word.length > 2),
  );
}

export function similarity(a: ReadonlySet<string>, b: ReadonlySet<string>): number {
  if (a.size === 0 || b.size === 0) return 0;
  let shared = 0;
  for (const word of a) if (b.has(word)) shared += 1;
  return 2 * shared / (a.size + b.size);
}

const bulletMarker = /^\s*(?:[-*•]|\d+[.)])\s+/;

/** Sentences of a reply, one per line break or sentence end, list markers removed. */
export function replySentences(text: string): string[] {
  return text.split(/(?<=[.!?])\s+|\n+/).map((sentence) =>
    sentence.replace(bulletMarker, "").trim()
  )
    .filter(Boolean);
}

/** The reply's last sentence when it is a question. */
export function closingQuestion(text: string): string | null {
  const last = replySentences(text).at(-1);
  return last !== undefined && /\?["')\]*_]*$/.test(last) ? last : null;
}

const urgentWording =
  /\b(?:emergency|urgent(?:ly)?|ambulance|911|999|112|988|chest (?:pain|tightness|pressure)|faint\w*|stroke|suicid\w*|self[- ]?harm|crisis)\b/i;
const referralWording =
  /\b(?:doctor|physician|physio(?:therapist)?|clinician|gp|dietitian|nutritionist|medical|professional|looked (?:at|over)|checked (?:out|over)|seen|cleared?|clearance|screening|health check)\b/i;
// A stop rule for pain or another symptom ("stop if it hurts", "skip it when the knee pinches",
// "sharp pain means rest and see a physio"): always safety wording, whatever the turn.
const symptom = String
  .raw`(?:pain\w*|hurt\w*|pinch\w*|sharp|swell\w*|swollen|dizz\w*|light-?headed|numb\w*|tingl\w*|injur\w*|sore\w*|ach(?:e|es|ed|ing)|flare\w*|throb\w*|tender|twing\w*)`;
const stopWord = String
  .raw`(?:stop|skip|avoid|rest|back off|ease off|pull back|end (?:the|your|this) session|leave\b[^.!?]{0,30}\bout|call it a day|pause|switch to|lay off|drop the weight|pain-?free|don'?t|do not|never|doctor|physio\w*)`;
const symptomStopRule = new RegExp(
  String.raw`\b${stopWord}\b[^.!?]*\b${symptom}\b|\b${symptom}\b[^.!?]*\b${stopWord}\b`,
  "i",
);
// Any caution or limit; protected when the turn needs referral wording.
const cautionWording =
  /\b(?:stop|avoid\w*|skip\w*|don'?t|do not|never|limit\w*|careful|caution|pain\w*|hurt\w*|sharp|swell\w*|dizz\w*|numb\w*|injur\w*)\b/i;

/** Whether a sentence is safety wording that must stay (see the file header). */
export function isSafetyWording(sentence: string, referralNeeded: boolean): boolean {
  return urgentWording.test(sentence) || symptomStopRule.test(sentence) ||
    /\bpain-?free\b/i.test(sentence) ||
    (referralNeeded && (referralWording.test(sentence) || cautionWording.test(sentence)));
}

export type RepeatInputs = Readonly<{
  /** The athlete's previous reply from Coach in this conversation. */
  previousReply: string;
  /** The athlete's previous message, and the one being answered. */
  previousQuestion?: string;
  question?: string;
  /** The turn needs referral wording (health check not cleared, pain, a health-risk question). */
  referralNeeded: boolean;
}>;

export type Repeats = Readonly<{
  /** The reply's closing question, when it repeats the previous one. */
  closing: string | null;
  /** Other sentences that repeat one of the previous reply, in order. */
  sentences: readonly string[];
}>;

const none: Repeats = { closing: null, sentences: [] };

/** What a reply repeats from the athlete's previous reply. */
export function repeatsOf(reply: string, inputs: RepeatInputs): Repeats {
  if (inputs.previousReply.trim() === "") return none;
  if (inputs.previousQuestion && inputs.question) {
    const again = similarity(contentWords(inputs.question), contentWords(inputs.previousQuestion));
    if (again >= askedAgainSimilarity) return none;
  }
  const earlier = replySentences(inputs.previousReply);
  const closing = closingQuestion(reply);
  const earlierClosing = closingQuestion(inputs.previousReply);
  let repeatedClosing: string | null = null;
  if (
    closing !== null && earlierClosing !== null && !isSafetyWording(closing, inputs.referralNeeded)
  ) {
    const words = contentWords(closing);
    const earlierWords = contentWords(earlierClosing);
    if (
      words.size >= closingQuestionMinWords && earlierWords.size >= closingQuestionMinWords &&
      similarity(words, earlierWords) >= closingQuestionSimilarity
    ) repeatedClosing = closing;
  }
  const earlierSets = earlier.map(contentWords).filter((words) => words.size >= sentenceMinWords);
  const sentences = replySentences(reply).filter((sentence) => {
    if (sentence === closing || isSafetyWording(sentence, inputs.referralNeeded)) return false;
    const words = contentWords(sentence);
    return words.size >= sentenceMinWords &&
      earlierSets.some((other) => similarity(words, other) >= sentenceSimilarity);
  });
  return { closing: repeatedClosing, sentences };
}
