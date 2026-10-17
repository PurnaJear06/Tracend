// The red-flag screen that runs before any Coach model call (AI_SAFETY_SPEC §7 and §11). A hit
// returns a fixed referral (referrals.ts); the model never sees the message and nothing is
// charged. The screen reads what the athlete reports about themselves, so it skips a symptom that
// is negated ("no chest pain"), hypothetical ("what if I feel dizzy") or asked about as a topic
// ("how do I avoid dizziness when cutting"). A miss answers a red flag with coaching, so every
// uncertain phrasing leans toward a hit; a false alarm costs one referral. The wider screen
// behind the labelled data summary (coach_chat_fallback.ts) includes everything found here.

export type RedFlagCategory =
  | "self_harm"
  | "chest"
  | "collapse"
  | "breathing"
  | "stroke"
  | "bleeding"
  | "eating"
  | "dark_urine"
  | "dizziness"
  | "injury_pain"
  | "numbness"
  | "check_in_pain"
  | "scope";

export type RedFlagHit = Readonly<{
  category: RedFlagCategory;
  /** A finite rule name, safe to log. */
  rule: string;
  source: "message" | "check_in";
}>;

type Rule = Readonly<{
  id: string;
  category: RedFlagCategory;
  pattern: RegExp;
  /** The rule does not apply to a clause this matches (for example a harmless supplement). */
  unless?: RegExp;
}>;

const rule = (
  id: string,
  category: RedFlagCategory,
  source: string,
  unless?: RegExp,
): Rule => ({ id, category, pattern: new RegExp(source, "g"), unless });

// Listed from the most urgent; a message that matches several gets the first rule here.
const rules: readonly Rule[] = [
  rule(
    "self_harm",
    "self_harm",
    String
      .raw`\bsuicid\w*|\bkill(?:ing)? myself\b|\bend(?:ing)? (?:my own life|my life|it all)\b|\bwant(?:ed)? to die\b|\bwanna die\b|\bwish i (?:was|were) dead\b|\bbetter off (?:dead|without me)\b|\bself[- ]?harm\w*|\b(?:want|going|plan(?:ning)?|thinking (?:of|about)|urge|feel like|need) (?:to )?(?:hurt|hurting|harm|harming|cut|cutting) myself\b|\b(?:hurt|harm)(?:ing)? myself (?:on purpose|deliberately|intentionally)\b|\btake my own life\b|\bnot worth living\b|\bno reason to (?:live|go on)\b|\bdon'?t want to (?:be here|live|exist|wake up)\b`,
  ),
  rule(
    "chest_symptom",
    "chest",
    String
      .raw`\bchest (?:pains?|pressure|tightness|tight|discomfort|heaviness|squeezing|burning|hurts?)\b|\bchest (?:is |was |feels? |felt |gets? |got )(?:\w+ ){0,2}?(?:tight|heavy|squeezed|squeezing|pressure|painful|crushed)\b|\b(?:pain|pressure|tightness|discomfort|heaviness|squeezing) (?:in|across|around|on) (?:my |the )?chest\b|\bhurts? in (?:my )?chest\b|\bheart attack\b|\bangina\b|\bseene (?:me|mein) dard\b`,
  ),
  rule(
    "heart_rhythm",
    "chest",
    String
      .raw`\bpalpitations?\b|\bheart (?:is |was |keeps |kept )?(?:fluttering|skipping|skipped|missing)\b|\bskipp(?:ed|ing) (?:a )?(?:heart)?beats?\b|\birregular (?:heart ?beat|heart rhythm|pulse)\b|\b(?:pulse|heart ?beat|heart rhythm) (?:is |was |feels? |felt )?(?:irregular|uneven|erratic)\b|\bheart (?:is |was )?(?:racing|pounding)\b.{0,40}\b(?:at rest|resting|sitting|lying|in bed|won'?t slow|not slowing|doesn'?t slow|for (?:hours|minutes|an hour)|since)\b|\b(?:at rest|resting|sitting|lying|in bed)\b.{0,40}\bheart (?:is |was )?(?:racing|pounding)\b`,
  ),
  rule(
    "faint",
    "collapse",
    String
      .raw`\bfaint(?:ed|ing|s)?\b|\bpass(?:ed|ing)? out\b|\bblack(?:ed|ing)? out\b|\bgr[ae]y(?:ed|ing)? out\b|\b(?:i|he|she|they|friend|someone) (?:just |nearly |almost )?collapsed\b|\bunconscious\b|\blost consciousness\b|\bknocked out\b|\bbehosh\b|\bvision (?:went|goes|going|turned|turns) (?:black|dark|grey|gray|white)\b`,
  ),
  rule(
    "breathing",
    "breathing",
    String
      .raw`\bcan'?t breathe\b|\bcannot breathe\b|\bcan'?t catch my breath\b|\b(?:trouble|difficulty|struggling|struggle|hard|harder) (?:to )?breath(?:e|ing)\b|\bgasping\b|\bwheez(?:e|ing)\b|\b(?:severe|extreme|sudden|serious|terrible|awful|unusual)(?:ly)? (?:shortness of breath|short of breath|breathlessness|out of breath)\b|\b(?:short of breath|shortness of breath|breathless\w*)\b.{0,40}\b(?:at rest|resting|sitting|lying|in bed|sleeping|doing nothing|walking|stairs|won'?t go away|not going away)\b|\bpain (?:when|while|on|with) (?:i )?(?:breathe|breathing|breath|inhale|inhaling|deep breath\w*)\b|\bpainful (?:to )?breath\w*`,
    /\bnose\b|\bnasal\b|\bcongest\w*|\bblocked\b|\bstuffy\b/,
  ),
  rule(
    "stroke_signs",
    "stroke",
    String
      .raw`\bslurr(?:ed|ing)\b|\bspeech (?:is |was |got )?(?:slurred|garbled)\b|\b(?:can'?t|cannot|trouble|difficulty) (?:speak|speaking|talk|talking|get (?:my )?words out|find (?:my )?words)\b|\bface (?:is |was |feels? )?(?:droop\w*|numb|sagging)\b|\bdroop\w* face\b|\b(?:had|having|have|suffered|think i'?m having|might be having) (?:a )?(?:mild |minor )?stroke\b|\bsudden (?:confusion|loss of vision|vision loss|blindness|weakness)\b|\bworst headache\b|\bthunderclap\b|\b(?:one|left|right) side\b.{0,30}\b(?:numb\w*|weak\w*|tingl\w*|paraly\w*|droop\w*)|\b(?:numb\w*|weak\w*|tingl\w*|paraly\w*)\b.{0,30}\b(?:one|left|right) side\b|\bhalf (?:of )?(?:my )?(?:body|face)\b.{0,30}\b(?:numb|weak|paraly)\w*`,
  ),
  rule(
    "blood",
    "bleeding",
    String
      .raw`\bcough(?:ing|ed|s)? (?:up )?blood\b|\bblood in (?:my )?(?:cough|sputum|spit|phlegm|vomit|stool|poop|faeces|feces)\b|\b(?:vomit(?:ing|ed)?|throwing up|threw up|spitting|spat) (?:up )?blood\b|\bblack,? tarry stool\b|\bbloody (?:stool|vomit|cough)\b`,
  ),
  rule(
    "purging",
    "eating",
    String
      .raw`\bpurg(?:e|ed|es|ing)\b|\bmak(?:e|ing|made) myself (?:throw up|vomit|sick|puke)\b|\binduc(?:e|ed|ing) vomiting\b|\bthrow(?:ing)? up (?:my )?(?:food|meals?|everything)\b|\bvomit(?:ing|ed)? (?:after|every) (?:eat|meal|food)\w*|\blaxatives?\b.{0,40}\b(?:lose|loss|weight|water|burn|drop|weigh|cut)\b|\b(?:lose|drop|cut) (?:water )?weight\b.{0,40}\blaxatives?\b|\bdiuretics?\b.{0,30}\b(?:lose|drop|cut|weigh|weight|water)\b|\bbulimi\w*|\banorexi\w*|\beating disorder\b|\bstarv(?:e|ing) myself\b|\bpunish(?:ing)? myself\b.{0,30}\b(?:eat|food|ate|meal)\b|\bstopped eating (?:completely|altogether|entirely|at all)\b|\bnot eating (?:at all|anything)\b`,
  ),
  rule(
    "binge_compensation",
    "eating",
    String
      .raw`\bbing(?:e|ed|eing)\b.{0,60}\b(?:purg|vomit|throw up|laxativ|fast|starv|skip|punish|guilt|out of control|can'?t stop|cannot stop|every (?:night|day|week)|secret|hid)|\b(?:purg|vomit|throw up|laxativ|fast|starv|skip|punish|guilt|out of control|secret|hid)\w*\b.{0,60}\bbing(?:e|ed|eing)\b`,
  ),
  rule(
    "extended_fast",
    "eating",
    String
      .raw`\b(?:fast(?:ed|ing)?|(?:haven'?t|have not|hasn'?t|didn'?t|did not|not) eat(?:en)?|no food|(?:ate|eaten|eating) (?:nothing|no food|almost nothing)|without (?:food|eating)|skipp(?:ed|ing) (?:all )?(?:food|meals))\b.{0,30}\b(?:for|in|over)\s+(?:the (?:last|past) )?(?:[2-9]|\d{2,}|two|three|four|five|six|seven|several|a few|many|multiple)\s+(?:consecutive |whole |full )?days?\b|\b(?:[2-9]|\d{2,}|two|three|four|five|six|seven)[- ]days?[- ](?:water )?fast\b|\bfast(?:ed|ing)? (?:for )?(?:4[8-9]|[5-9]\d|\d{3})\s*(?:h|hrs|hours)\b`,
  ),
  rule(
    "dark_urine",
    "dark_urine",
    String
      .raw`\b(?:dark|brown|cola|coca[- ]?cola|tea|bloody|red|pink)(?: brown)?(?:[- ]colou?red)? urine\b|\burine (?:is |was |looks? |turned |went )?(?:dark|brown|red|pink|cola|bloody)\b|\bblood in (?:my )?urine\b|\brhabdo\w*`,
  ),
  rule(
    "dizziness",
    "dizziness",
    String
      .raw`\bdizz(?:y|iness)\b|\blight-?headed(?:ness)?\b|\bwoozy\b|\bvertigo\b|\bhead (?:is |was )?spinning\b|\broom (?:is |was )?spinning\b|\bfeel(?:ing)? faint\b|\bchakkar\b`,
  ),
  rule(
    "severe_pain",
    "injury_pain",
    String
      .raw`\b(?:sharp|severe|sudden|stabbing|shooting|excruciating|intense|searing|tearing|piercing|unbearable|agonising|agonizing)(?: \w+){0,2} pains?\b|\bpains?\b.{0,25}\b(?:sharp|severe|sudden|stabbing|shooting|excruciating|unbearable|agonis\w+|agoniz\w+)\b|\b(?:heard|felt|got|had) (?:a )?(?:loud )?(?:pop|snap|crack|tear|rip)(?:ping)?\b|\b(?:something|it) (?:just )?(?:popped|snapped|tore|ripped|gave way)\b|\b(?:pulled|tore|torn|ruptured|snapped|dislocated|fractured|broke|broken) (?:a |my )?(?:\w+ ){0,3}(?:muscle|tendon|ligament|acl|mcl|hamstring|quad|bicep|tricep|pec|shoulder|knee|rotator cuff|achilles|meniscus|disc|rib|bone|wrist|ankle|elbow)\b|\b(?:[7-9]|10)\s*(?:/|out of)\s*10\b.{0,20}\bpain\b|\bpain\b.{0,20}\b(?:[7-9]|10)\s*(?:/|out of)\s*10\b|\bcan'?t (?:put weight on|bear weight|move my|lift my arm)\b`,
  ),
  rule(
    "numbness",
    "numbness",
    String
      .raw`\bnumb(?:ness)?\b|\btingling\b|\bpins and needles\b|\bloss of (?:feeling|sensation)\b|\bcan'?t feel my (?:arm|arms|leg|legs|hand|hands|foot|feet|fingers|toes)\b`,
    /beta[- ]?alanine|pre[- ]?workout|supplement|caffeine|niacin|creatine/,
  ),
  // Not red flags: requests Tracend does not support (AI_SAFETY_SPEC §7). They get the scope
  // answer, not an urgent referral.
  rule(
    "diagnosis_request",
    "scope",
    String
      .raw`\bdiagnose\b|\bdiagnosing\b|\bwhat(?:'s| is) wrong with me\b|\bdo i have (?:a |an )?(?:disease|disorder|condition|syndrome|hernia|tear|fracture|cancer|diabetes|arrhythmia|infection)\b`,
  ),
  rule(
    "medical_report",
    "scope",
    String
      .raw`\bmedical (?:report|records?)\b|\b(?:blood tests?|blood work|lab|mri|x-?ray|ecg|ekg|ct scan|ultrasound|echo(?:cardiogram)?)\s+(?:results?|report)\b|\b(?:interpret|read|analy[sz]e|explain)\b.{0,20}\b(?:my )?(?:mri|x-?ray|ecg|ekg|scan|blood tests?|lab results?|medical report)\b`,
  ),
  rule("rehab", "scope", String.raw`\brehab(?:ilitat\w*)?\b`),
  rule(
    "pregnancy",
    "scope",
    String
      .raw`\bpregnan\w*|\bpostpartum\b|\bpost-partum\b|\bbreastfeed\w*|\btrimester\b|\bexpecting a baby\b`,
  ),
  rule(
    "medication_advice",
    "scope",
    String
      .raw`\b(?:interact\w*|mix(?:ing)?|combin\w+)\b.{0,40}\b(?:medication|medications|meds|medicine|pills?|prescription)\b|\b(?:take|taking|use|using)\b.{0,40}\b(?:with|alongside)\s+(?:my |your |the |a )?(?:[\w-]+ ){0,3}(?:medication|medications|meds|medicine|prescription)\b|\b(?:should|can|could|may|do) i (?:take|start|stop|quit|skip|increase|decrease|double|miss|swap|switch) (?:my |the |some |any |a |an )?(?:\w+ ){0,2}(?:medication|medications|meds|medicine|pills?|tablets?|insulin|antidepressants?|steroids?|statins?|beta[- ]?blockers?|inhalers?|ozempic|semaglutide|metformin|prescription|ibuprofen|painkillers?)\b|\bwhat (?:dose|dosage)\b|\bprescribe\b|\b(?:stop|stopping|quit|quitting|come off|coming off|go off) (?:taking )?(?:my )?(?:medication|meds|pills|insulin|antidepressants?)\b`,
  ),
];

/** Lower case, straight quotes, single spaces. */
export function normalizeMessage(text: string): string {
  return text.toLowerCase().replace(/[‘’ʼ`]/g, "'").replace(/\s+/g, " ").trim();
}

const clauseBreak = new RegExp(
  [
    String.raw`[.!?;:\n()\u2013\u2014]+`,
    String.raw`\s-+\s`,
    String.raw`,\s*(?=(?:i|i'm|im|i've|ive|my|it|so|now|also|though|but|and)\b)`,
    String.raw`\bbut\b|\bhowever\b|\balthough\b|\bthough\b|\bexcept\b`,
    String.raw`\band (?=(?:i|i'm|im|i've|ive|my|now|also|it|they|he|she)\b)`,
  ].join("|"),
);

function clausesOf(text: string): string[] {
  return text.split(clauseBreak).map((part) => part.trim()).filter(Boolean);
}

// Words that end a negation's reach: a conjunction or a contrast ("no chest pain, just dizzy").
const scopeBreakers = new Set([
  "and",
  "but",
  "then",
  "so",
  "because",
  "when",
  "while",
  "after",
  "during",
  "although",
  "which",
  "just",
  "only",
  "except",
  "though",
  "however",
  "instead",
  "besides",
  "apart",
  "yet",
  "still",
  "other",
  "rather",
]);
const uncertainWords = new Set(["sure", "certain", "know", "if", "whether", "idea", "unsure"]);
const negationCues = new Set([
  "no",
  "not",
  "never",
  "without",
  "none",
  "neither",
  "nor",
  "zero",
  "nothing",
  "denies",
]);
// Words that make the stretch after a comma a statement of its own, not another item of a list.
const statementWords = new Set([
  "i",
  "i'm",
  "im",
  "i've",
  "ive",
  "my",
  "me",
  "feel",
  "feels",
  "felt",
  "feeling",
  "get",
  "gets",
  "got",
  "getting",
  "have",
  "has",
  "had",
  "having",
  "am",
  "is",
  "are",
  "was",
  "were",
  "keep",
  "kept",
  "started",
  "noticed",
  "with",
  "since",
  "at",
  "on",
]);
// After a list, what follows the symptom says it is happening ("no chest pain, dizzy when I run").
const happeningAfter =
  /^\W*(?:when|while|after|during|since|every|whenever|at\b|on\b|today|yesterday|again|a lot|often|sometimes|all the time|lately|recently)/;

/**
 * True when a negation governs the symptom that follows `before`: "no chest pain or dizziness".
 * The reach ends at a conjunction or a contrast (just, only, but, except, though, however), at
 * clause punctuation (the clause is cut there), and at a comma unless what follows it is another
 * item of the list ("no chest pain, dizziness, or fainting"): a short run of words with no verb,
 * that is not followed by words saying it is happening.
 */
function negated(before: string, after: string): boolean {
  const tokens = before.split(" ").filter(Boolean);
  let uncertain = false;
  let crossedComma = false;
  let segmentWords = 0;
  let segmentStatement = false;
  for (let index = tokens.length - 1, steps = 0; index >= 0 && steps < 10; index--, steps++) {
    const raw = tokens[index];
    const token = raw.replace(/^[("']+|[,)"'?]+$/g, "");
    if (scopeBreakers.has(token)) return false;
    if (uncertainWords.has(token)) uncertain = true;
    if (negationCues.has(token) || token.endsWith("n't")) {
      if (uncertain) return false;
      return !(crossedComma && happeningAfter.test(after));
    }
    if (raw.endsWith(",")) {
      if (segmentWords > 3 || segmentStatement) return false;
      crossedComma = true;
      segmentWords = 0;
      segmentStatement = false;
    }
    if (token !== "or" && token !== "nor") segmentWords++;
    if (statementWords.has(token)) segmentStatement = true;
  }
  return false;
}

const conditionalCue =
  /\b(?:in case|what if|suppose|whenever|should i ever)\b|(?<!(?:sure|know|certain|wonder|wondering|idea|unsure) )\bif\b/;
const experienceCue =
  /\b(?:again|today|yesterday|last night|this morning|earlier|just now|just|already|recently|since|still|keeps?|kept|every time)\b/;
const educationCue =
  /\b(?:avoid|avoiding|prevent|preventing|prevention|minimi[sz]e|minimi[sz]ing|reduce|reducing|what causes|causes? of|what is|what are|what's|define|meaning of|signs? of|symptoms? of|difference between|common cause|explain|tell me about)\b|\b(?:does|do|can|could|will|would)\b.{0,40}\bcause\b/;
const ownershipCue =
  /\b(?:i|i'm|im|i've|ive|we)\s+(?:(?:just|also|still|really|always|sometimes|often|actually|almost|nearly|suddenly|keep|kept)\s+)*(?:felt|feel|feeling|get|getting|got|have|having|had|am|was|been|passed|fainted|blacked|collapsed|started|noticed|experienc\w+|suffer\w*|woke)\b/;

/** Whether the athlete is reporting the symptom, not denying it, supposing it or asking about it. */
function reported(clause: string, index: number, length: number): boolean {
  const before = clause.slice(0, index);
  if (negated(before, clause.slice(index + length))) return false;
  if (conditionalCue.test(before) && !experienceCue.test(clause)) return false;
  if (educationCue.test(clause) && !ownershipCue.test(clause)) return false;
  return true;
}

/** The most urgent red flag the athlete reports in this message, or null. */
export function screenMessage(question: string): RedFlagHit | null {
  const clauses = clausesOf(normalizeMessage(question));
  for (const candidate of rules) {
    for (const clause of clauses) {
      if (candidate.unless?.test(clause)) continue;
      for (const match of clause.matchAll(candidate.pattern)) {
        if (reported(clause, match.index, match[0].length)) {
          return { category: candidate.category, rule: candidate.id, source: "message" };
        }
      }
    }
  }
  return null;
}

/** Questions about training, where a day of high pain stops coaching. */
const trainingIntent =
  /\b(?:train|training|trained|workout|work out|working out|lift|lifting|lifted|exercise|exercising|session|gym|run|running|jog|cardio|hiit|sets?|reps?|squats?|deadlifts?|bench|press|pull-?ups?|push-?ups?|heavy|pr|max|leg day|chest day|back day|arm day|push day|pull day)\b|\bshould i (?:go|do|skip|push)\b/;

function num(value: unknown): number | null {
  return typeof value === "number" && Number.isFinite(value) ? value : null;
}

function obj(value: unknown): Record<string, unknown> {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : {};
}

/** The check-in pain level at which the daily policy escalates (check-in pain 7 or more). */
export const checkInPainEscalation = 7;

/**
 * Whether today's check-in put the athlete in the daily policy's escalate outcome (pain of 7 or
 * more): the policy's evidence code, or today's check-in pain in the prepared context.
 */
export function checkInEscalated(context: Record<string, unknown>): boolean {
  const evidence = Array.isArray(context.permitted_evidence) ? context.permitted_evidence : [];
  if (evidence.includes("CHECK_IN_SAFETY_ESCALATION")) return true;
  const checkIn = obj(context.latest_check_in);
  const pain = num(checkIn.pain_severity);
  return pain !== null && pain >= checkInPainEscalation &&
    typeof context.coaching_date === "string" && checkIn.local_date === context.coaching_date;
}

/**
 * With pain of 7 or more on today's check-in, a question about training gets the referral: no
 * session is planned or adjusted on a day the athlete reports this much pain. Food, sleep and
 * recovery questions still reach the model, which is told the pain in its Safe Ranges section.
 */
export function screenCheckIn(
  context: Record<string, unknown>,
  question: string,
): RedFlagHit | null {
  if (!checkInEscalated(context)) return null;
  if (!trainingIntent.test(normalizeMessage(question))) return null;
  return { category: "check_in_pain", rule: "check_in_pain", source: "check_in" };
}

/** The check-in columns the early screen reads. */
export type CheckInRow = Readonly<{ local_date?: unknown; pain_severity?: unknown }>;

/** A question about training, from the words alone (nothing is read). */
export function trainingQuestion(question: string): boolean {
  return trainingIntent.test(normalizeMessage(question));
}

/** The athlete's calendar date in their timezone (UTC when the timezone is unknown). */
export function localDateIn(timezone: string, instant: number = Date.now()): string {
  const format = (zone: string) =>
    new Intl.DateTimeFormat("en-CA", {
      timeZone: zone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    }).format(instant);
  try {
    return format(timezone);
  } catch {
    return format("UTC");
  }
}

/**
 * The same check-in screen from the newest check-in row, read before the consent and budget
 * gates: a day of pain of 7 or more must reach the athlete as the referral even when they have no
 * consent or budget left.
 */
export function screenCheckInRow(
  row: CheckInRow | null,
  localDate: string,
  question: string,
): RedFlagHit | null {
  if (row === null) return null;
  return screenCheckIn({ coaching_date: localDate, latest_check_in: row }, question);
}

/** The screen for a turn: the message first, then today's check-in. */
export function screenTurn(question: string, context: Record<string, unknown>): RedFlagHit | null {
  return screenMessage(question) ?? screenCheckIn(context, question);
}
