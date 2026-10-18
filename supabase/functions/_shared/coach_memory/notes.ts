// The Coach's notes (store 3, episodic). A note is small and structured: the topics and concerns of
// a conversation, the commitments the athlete made, and the advice Coach gave with what became of
// it. Notes are built by rules, after the reply, from the athlete's own message, the evidence and
// lookups the turn used, and the proposals the athlete answered. They never copy the Coach's own
// prose, so a wrong claim of the Coach's cannot return as memory, and no model is called to write
// them. Each links to the messages it came from.
import { contentWords, dateOf, flatten, normalizeText, stem } from "./text.ts";
import {
  maxCommitmentChars,
  maxNoteAdvice,
  maxNoteCommitments,
  maxNoteConcerns,
  maxNoteSummaryChars,
  maxNoteTopics,
  type NoteConcern,
  noteConcernLabels,
  noteConcerns,
  type NoteTopic,
  noteTopicLabels,
  noteTopics,
} from "./vocabulary.ts";

export type NoteAdvice = Readonly<{
  /** The proposal kind (training_schedule, nutrition_targets, ...). */
  code: string;
  summary: string;
  outcome: ProposalOutcome;
  /** Set when the advice can be checked against logged sessions. */
  kind?: "train_days";
  target?: number;
}>;

export type NoteCommitment = Readonly<{
  text: string;
  kind: "train_days" | "other";
  target?: number;
}>;

export type CoachNoteDraft = Readonly<{
  entryKind: "conversation" | "advice";
  threadId: string | null;
  noteDate: string;
  summary: string;
  topics: readonly NoteTopic[];
  concerns: readonly NoteConcern[];
  advice: readonly NoteAdvice[];
  commitments: readonly NoteCommitment[];
  messageIds: readonly string[];
  proposalId: string | null;
}>;

export type FollowThrough = Readonly<{
  status: "followed" | "partly" | "not_followed";
  checkedOn: string;
  detail: string;
}>;

/** A stored note as the Coach contributor reads it. */
export type CoachNote = Readonly<{
  id: string;
  entryKind: "conversation" | "advice";
  noteDate: string;
  summary: string;
  topics: readonly string[];
  concerns: readonly string[];
  followThrough: FollowThrough | null;
}>;

type Json = Record<string, unknown>;
const rec = (value: unknown): Json =>
  value && typeof value === "object" && !Array.isArray(value) ? value as Json : {};
const strings = (value: unknown): string[] =>
  Array.isArray(value) ? value.filter((item): item is string => typeof item === "string") : [];

export function parseNotes(raw: unknown): CoachNote[] {
  if (!Array.isArray(raw)) return [];
  const notes: CoachNote[] = [];
  for (const item of raw) {
    const row = rec(item);
    const noteDate = dateOf(row.note_date);
    if (
      typeof row.id !== "string" ||
      (row.entry_kind !== "conversation" && row.entry_kind !== "advice") ||
      typeof row.summary !== "string" || noteDate === ""
    ) continue;
    const through = rec(row.follow_through);
    const status = through.status;
    notes.push({
      id: row.id,
      entryKind: row.entry_kind,
      noteDate,
      summary: row.summary,
      topics: strings(row.topics),
      concerns: strings(row.concerns),
      followThrough: status === "followed" || status === "partly" || status === "not_followed"
        ? {
          status,
          checkedOn: dateOf(through.checked_on),
          detail: typeof through.detail === "string" ? through.detail : "",
        }
        : null,
    });
  }
  return notes;
}

// Reading the athlete's message ---------------------------------------------------------------

const topicWords: Readonly<Record<NoteTopic, string>> = {
  training:
    "workout train training exercise lift lifting gym session rep squat bench deadlift run running cardio strength muscle hypertrophy",
  nutrition:
    "eat food meal calorie protein carb diet breakfast lunch dinner snack macro fasting nutrition",
  recovery: "recover recovery rest deload hrv readiness overtraining",
  sleep: "sleep slept insomnia nap bedtime",
  weight: "weight scale weigh bodyweight kg lb",
  goal: "goal target deadline bulk",
  plan: "plan program routine",
  pain_injury: "pain injury injured hurt strain sprain ache",
  motivation: "motivation motivated unmotivated discipline consistency consistent lazy",
  schedule: "schedule weekend travel trip vacation busy shift",
  supplements: "supplement creatine whey caffeine preworkout vitamin",
  equipment: "equipment dumbbell barbell band machine",
};

const topicStems: Readonly<Record<NoteTopic, ReadonlySet<string>>> = Object.fromEntries(
  noteTopics.map((topic) => [topic, new Set(topicWords[topic].split(" ").map(stem))]),
) as unknown as Record<NoteTopic, ReadonlySet<string>>;

/** The lookups that tell what a turn was about. */
const lookupTopics: Readonly<Record<string, readonly NoteTopic[]>> = {
  workouts: ["training"],
  exercise_history: ["training"],
  meals: ["nutrition"],
  body: ["weight"],
  check_ins: ["recovery"],
  recovery: ["recovery"],
  plan_history: ["plan"],
  goals: ["goal"],
};

const proposalTopics: Readonly<Record<string, readonly NoteTopic[]>> = {
  temporary_block: ["plan", "schedule"],
  training_schedule: ["plan", "schedule"],
  exercise_swap: ["plan", "training"],
  intensity_or_phase: ["plan", "training"],
  goal_or_phase: ["goal"],
  nutrition_targets: ["nutrition", "plan"],
  next_session_adjustment: ["training"],
};

/** The evidence codes a turn cited, read by the area their name belongs to. */
function evidenceTopics(codes: readonly string[]): NoteTopic[] {
  const found: NoteTopic[] = [];
  for (const code of codes) {
    const name = code.toLowerCase();
    if (/sleep/.test(name)) found.push("sleep");
    else if (/recover|readiness|hrv/.test(name)) found.push("recovery");
    else if (/nutrition|meal|calorie|protein/.test(name)) found.push("nutrition");
    else if (/weight|body/.test(name)) found.push("weight");
    else if (/goal|target/.test(name)) found.push("goal");
    else if (/workout|train|session|plan/.test(name)) found.push("training");
  }
  return found;
}

const concernPatterns: Readonly<Record<NoteConcern, RegExp>> = {
  pain: /\b(?:pain|painful|hurts?|hurting|aching|aches?|injured|injury)\b/,
  fatigue:
    /\b(?:tired|exhausted|fatigue|fatigued|drained|wiped out|burnt out|burned out|lethargic)\b/,
  soreness: /\b(?:sore|soreness|doms|stiff)\b/,
  poor_sleep:
    /\b(?:can't|cannot|cant|couldn't) sleep\b|\binsomnia\b|\b(?:bad|poor|terrible|little|no) sleep\b|\bslept (?:badly|poorly|terribly)\b|\bsleep(?:ing)? (?:is |has been |was )?(?:bad|poor|terrible|awful)\b/,
  plateau:
    /\b(?:plateau|plateaued|stuck|stalled|not progressing|no progress|not improving|not getting stronger)\b/,
  hunger: /\b(?:hungry|starving|cravings?|craving|always hungry)\b/,
  low_motivation:
    /\b(?:unmotivated|demotivated|no motivation|lost (?:my )?motivation|can't be bothered|feel lazy|giving up|give up)\b/,
  time_pressure:
    /\b(?:no time|not enough time|short on time|little time|time crunch|too busy|so busy)\b/,
  stress: /\b(?:stressed|stress|anxious|anxiety|overwhelmed)\b/,
};

const numberWords: Readonly<Record<string, number>> = {
  one: 1,
  two: 2,
  three: 3,
  four: 4,
  five: 5,
  six: 6,
  seven: 7,
};

const commitmentLead =
  /\bi(?:'ll| will| am going to|'m going to|'m gonna| plan to|'m planning to| promise to| commit to| am planning to)\s+(.{4,160})/;
const trainDays =
  /\b(\d|one|two|three|four|five|six|seven)(?: |-)?(?:days?|times|sessions|workouts)(?: a| per| each| every| this| next| in the)? week\b/;

function commitmentsIn(question: string): NoteCommitment[] {
  const found: NoteCommitment[] = [];
  for (const sentence of normalizeText(question).split(/[.!?;\n]+/)) {
    const lead = sentence.match(commitmentLead);
    if (!lead) continue;
    const text = flatten(lead[1], maxCommitmentChars);
    if (text === "") continue;
    const days = lead[1].match(trainDays);
    const count = days ? numberWords[days[1]] ?? Number(days[1]) : null;
    found.push(
      count !== null && count >= 1 && count <= 7 &&
        /\b(?:train|work ?out|lift|gym|exercise|go)\b/.test(lead[1])
        ? { text, kind: "train_days", target: count }
        : { text, kind: "other" },
    );
    if (found.length >= maxNoteCommitments) break;
  }
  return found;
}

// Building a conversation note -----------------------------------------------------------------

export type TurnForNote = Readonly<{
  question: string;
  /** The athlete's calendar day. */
  localDate: string;
  threadId: string;
  /** False for a conversation the athlete chose not to have remembered. */
  remember: boolean;
  /** A referral or a data summary is not the Coach's answer and is not noted. */
  outcome: "answered" | "referral" | "data_summary";
  evidenceCodes: readonly string[];
  lookups: readonly string[];
  /** The kind of the proposal Coach made this turn, if any. */
  proposalKind: string | null;
  /** The athlete's message and the reply, in that order. */
  messageIds: readonly string[];
}>;

function listWords(words: readonly string[]): string {
  if (words.length <= 1) return words.join("");
  return `${words.slice(0, -1).join(", ")} and ${words.at(-1)}`;
}

/**
 * The note for one answered turn, or null when there is nothing to note: the conversation is not
 * remembered, the turn was a referral or a data summary, or it touched no topic, concern or
 * commitment. Everything in it comes from the athlete's message and the turn's structured fields.
 */
export function buildConversationNote(turn: TurnForNote): CoachNoteDraft | null {
  if (!turn.remember || turn.outcome !== "answered") return null;
  const words = new Set(contentWords(turn.question));
  const fromMessage = noteTopics.filter((topic) =>
    [...words].some((word) => topicStems[topic].has(word))
  );
  const fromTurn = [
    ...turn.lookups.flatMap((name) => lookupTopics[name] ?? []),
    ...evidenceTopics(turn.evidenceCodes),
    ...(turn.proposalKind ? proposalTopics[turn.proposalKind] ?? [] : []),
  ];
  const topics = noteTopics.filter((topic) =>
    fromMessage.includes(topic) || fromTurn.includes(topic)
  )
    .slice(0, maxNoteTopics);
  const normalized = normalizeText(turn.question);
  const concerns = noteConcerns.filter((concern) => concernPatterns[concern].test(normalized))
    .slice(0, maxNoteConcerns);
  const commitments = commitmentsIn(turn.question);
  if (topics.length === 0 && concerns.length === 0 && commitments.length === 0) return null;

  const parts: string[] = [];
  if (topics.length) parts.push(`Asked about ${listWords(topics.map((t) => noteTopicLabels[t]))}.`);
  if (concerns.length) {
    parts.push(`Mentioned ${listWords(concerns.map((c) => noteConcernLabels[c]))}.`);
  }
  for (const commitment of commitments.slice(0, 2)) {
    parts.push(`Said they would: “${commitment.text}”.`);
  }
  return {
    entryKind: "conversation",
    threadId: turn.threadId,
    noteDate: turn.localDate,
    summary: flatten(parts.join(" "), maxNoteSummaryChars),
    topics,
    concerns,
    advice: [],
    commitments,
    messageIds: turn.messageIds,
    proposalId: null,
  };
}

// Advice and follow-through ----------------------------------------------------------------------

export const proposalOutcomes = ["accepted", "declined", "changed", "expired", "undone"] as const;
export type ProposalOutcome = typeof proposalOutcomes[number];

export type ResolvedProposal = Readonly<{
  id: string;
  kind: string;
  title: string;
  outcome: ProposalOutcome;
  /** The athlete's day the proposal was answered or lapsed. */
  answeredOn: string;
  /** Sessions a week a training schedule asks for. */
  daysPerWeek: number | null;
  sourceMessageId: string | null;
}>;

/** The answer of get_unnoted_coach_proposals_v1; a malformed row is left out. */
export function parseResolvedProposals(raw: unknown): ResolvedProposal[] {
  const rows = rec(raw).proposals;
  if (!Array.isArray(rows)) return [];
  const proposals: ResolvedProposal[] = [];
  for (const item of rows) {
    const row = rec(item);
    const answeredOn = dateOf(row.answered_on);
    if (
      typeof row.id !== "string" || typeof row.kind !== "string" || typeof row.title !== "string" ||
      !(proposalOutcomes as readonly string[]).includes(row.outcome as string) || answeredOn === ""
    ) continue;
    proposals.push({
      id: row.id,
      kind: row.kind,
      title: row.title,
      outcome: row.outcome as ProposalOutcome,
      answeredOn,
      daysPerWeek: typeof row.days_per_week === "number" ? row.days_per_week : null,
      sourceMessageId: typeof row.source_message_id === "string" ? row.source_message_id : null,
    });
  }
  return proposals;
}

const outcomeWords: Readonly<Record<ProposalOutcome, string>> = {
  accepted: "you approved it",
  declined: "you said not now",
  changed: "you asked for changes",
  expired: "it expired unanswered",
  undone: "you approved it, then undid it",
};

/** The "advice and follow-through" note for a proposal the athlete answered or let lapse. */
export function buildAdviceNote(proposal: ResolvedProposal): CoachNoteDraft {
  const title = flatten(proposal.title, 100);
  const checkable = proposal.kind === "training_schedule" && proposal.outcome === "accepted" &&
    proposal.daysPerWeek !== null && proposal.daysPerWeek >= 1 && proposal.daysPerWeek <= 7;
  const advice: NoteAdvice = {
    code: proposal.kind,
    summary: title,
    outcome: proposal.outcome,
    ...(checkable ? { kind: "train_days" as const, target: proposal.daysPerWeek! } : {}),
  };
  return {
    entryKind: "advice",
    threadId: null,
    noteDate: proposal.answeredOn,
    summary: flatten(
      `Coach proposed “${title}”; ${outcomeWords[proposal.outcome]} on ${proposal.answeredOn}.`,
      maxNoteSummaryChars,
    ),
    topics: (proposalTopics[proposal.kind] ?? []).slice(0, maxNoteTopics),
    concerns: [],
    advice: [advice].slice(0, maxNoteAdvice),
    commitments: [],
    messageIds: proposal.sourceMessageId ? [proposal.sourceMessageId] : [],
    proposalId: proposal.id,
  };
}

export type FollowThroughCheck = Readonly<{
  noteId: string;
  target: number;
  windowFrom: string;
  windowTo: string;
  sessionsCompleted: number;
}>;

/** The answer of get_coach_follow_through_inputs_v1; a malformed row is left out. */
export function parseFollowThroughChecks(raw: unknown): FollowThroughCheck[] {
  const rows = rec(raw).checks;
  if (!Array.isArray(rows)) return [];
  const checks: FollowThroughCheck[] = [];
  for (const item of rows) {
    const row = rec(item);
    const windowFrom = dateOf(row.window_from);
    const windowTo = dateOf(row.window_to);
    if (
      typeof row.note_id !== "string" || row.kind !== "train_days" ||
      typeof row.target !== "number" || row.target < 1 || row.target > 7 ||
      typeof row.sessions_completed !== "number" || windowFrom === "" || windowTo === ""
    ) continue;
    checks.push({
      noteId: row.note_id,
      target: row.target,
      windowFrom,
      windowTo,
      sessionsCompleted: row.sessions_completed,
    });
  }
  return checks;
}

/**
 * Whether a week of training matched what was said or agreed: all the sessions is followed, at
 * least half is partly, less is not followed. The count is the number of completed sessions the
 * database found in the week after the note.
 */
export function evaluateFollowThrough(check: FollowThroughCheck, checkedOn: string): FollowThrough {
  const done = check.sessionsCompleted;
  const status = done >= check.target
    ? "followed"
    : done * 2 >= check.target
    ? "partly"
    : "not_followed";
  return {
    status,
    checkedOn,
    detail: `${done} of ${check.target} sessions from ${check.windowFrom} to ${check.windowTo}`,
  };
}
