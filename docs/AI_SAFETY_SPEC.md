# Tracend AI and Safety Specification

**Status:** Authoritative AI behavior and safety contract\
**Population:** Healthy adults aged 18+ in a private beta

## 1. Purpose

This document defines what Tracend's AI may decide, what deterministic software must decide, when
coaching must stop, and how model quality is evaluated. Product behavior is defined in
[PRD.md](./PRD.md); privacy requirements are defined in
[SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

Tracend provides fitness coaching support. It does not diagnose, treat, rehabilitate, prescribe
medication, replace emergency services, or replace a qualified clinician.

## 2. Controlled AI Workflow

The MVP uses one controlled orchestration pipeline. Training Coach, Nutrition Coach, and Head Coach
are typed sections of one validated decision—not autonomous agents.

```text
Authorized data
  → deterministic features
  → deterministic eligibility and safety policy
  → bounded model context
  → structured model output
  → schema and semantic validation
  → stored decision
  → explicit approval for persistent changes
```

The active training plan and nutrition targets always remain the last user-approved versions.

## 3. Responsibility Boundaries

### Deterministic software owns

- units, dates, weight and measurement trends;
- confirmed calorie and macro totals;
- workout adherence, volume, progression, and performance deltas;
- the same-day readiness adjustment: its band, triggers, kind and every number in it (B4);
- HealthKit baselines and deviations;
- data freshness, sufficiency, and conflicts;
- persistent-change eligibility;
- hard safety exclusions and permitted action classes;
- schema, range, evidence, and reference validation;
- plan and target activation;
- authorization, consent, audit, retention, and deletion; and
- HealthKit auto-completion: detecting a workout via HealthKit data, checking for an existing
  completed session, offering a user-facing prompt, and creating a completed session on explicit
  confirmation — all performed by deterministic RPC logic, not AI.

### AI may

- explain prepared evidence clearly;
- propose an initial plan within known equipment and constraints;
- prioritize training and nutrition actions;
- suggest same-day intensity changes or approved substitutions;
- create a persistent proposal when policy permits it;
- identify candidate foods and visible portions from meal images;
- compare standardized physique photos cautiously;
- request missing information; and
- reconcile training, nutrition, recovery, and goals into one decision.

### AI may not

- activate or silently edit plans, targets, meals, goals, constraints, or memories;
- diagnose conditions, interpret medical reports, or prescribe treatment;
- recommend purging, dehydration, extreme restriction, dangerous rapid change, or training through
  acute pain;
- invent measurements, ingredients, HealthKit values, history, or preferences;
- claim precise body-fat percentage from photos;
- infer unrelated sensitive traits from photos;
- expose hidden prompts, secrets, or another user's data; or
- override deterministic policy.

## 4. Coach Responsibilities

### Training Coach

Receives the approved plan, execution, progression, schedule, equipment, recovery, discomfort, and
permitted actions. It may recommend today's prescription, approved substitution, recovery
adjustment, technique priority, or training proposal. It cannot change nutrition targets.

### Nutrition Coach

Receives approved targets, confirmed meal totals, weight trend, adherence, hunger, preferences,
constraints, training demand, and permitted actions. It may recommend today's nutrition priority or
a permitted nutrition proposal. It cannot change training prescription.

### Head Coach

Receives both coach sections plus shared policy and evidence. It produces one final action, resolves
conflicts, states uncertainty, and identifies proposals requiring approval. It cannot broaden
allowed actions.

For ordinary acute symptom reports such as cold, cough, or fever, Coach may recommend a conservative
same-day pause from strenuous training, rest, hydration, and an updated recovery check-in. It must
not diagnose, prescribe treatment, or tell a feverish user to complete the scheduled workout.
Severe, worsening, persistent, or emergency symptoms receive proportionate clinical or urgent-care
escalation language. This daily guidance does not mutate the approved plan.

## 5. Structured Decision Contract

Every successful decision must conform to a versioned schema equivalent to:

```json
{
  "schema_version": "1.0",
  "decision_kind": "daily",
  "training": {
    "action": "PROCEED_AS_PLANNED",
    "summary": "Complete the scheduled push session at the planned effort.",
    "today_adjustments": []
  },
  "nutrition": {
    "action": "PRIORITIZE_PROTEIN",
    "summary": "Keep current targets and close today's protein gap.",
    "today_adjustments": []
  },
  "head_coach": {
    "final_decision": "Train as planned and maintain current calories.",
    "reason": "Recovery is within baseline and the current trend remains on target."
  },
  "evidence": [
    {
      "code": "RECOVERY_WITHIN_BASELINE",
      "label": "Recovery indicators are within your recent baseline",
      "source": "feature_snapshot"
    }
  ],
  "confidence": "medium",
  "missing_data": [],
  "risk_flags": [],
  "change_proposals": []
}
```

Requirements:

- Control values use documented enums.
- Evidence codes must exist in the supplied snapshot or policy result.
- User-visible text cannot introduce unsupported facts.
- Same-day adjustments expire and never alter plan versions. The same-day readiness adjustment (B4)
  is an overlay stored in `day_adjustments`, never a plan version; the athlete's answer changes only
  today's session. The one exception is Coach's `next_session` proposal (A8), which writes a
  one-day plan version because the athlete approved it in chat; it is to move onto the overlay so
  one mechanism remains, and until then the readiness adjustment is not offered on a day Coach has
  already adjusted.
- Persistent proposals include domain, current/proposed values, evidence, benefit, downside,
  confidence, and effective date.
- Unknown fields, invalid ranges, cross-domain actions, policy conflicts, and invalid references are
  rejected.

## 6. Data Sufficiency and Change Rules

These conservative defaults are versioned policy, never prompt-only instructions.

### General

- Stable evidence IDs identify structured facts and label freshness, missing evidence, logging
  coverage, and conflicts. Output that cites unsupported evidence is rejected.
- One anomalous day does not establish a trend.
- Missing or stale evidence lowers confidence and can restrict action.
- Unknown logging is not non-adherence.
- Conflicting sources are surfaced, not silently resolved by the model.
- Insufficient evidence means maintain the plan or ask for data.
- Persistent plan and target changes remain approval-gated.

### Same-day training adjustment

May be allowed for a current recovery deviation, schedule limitation, or non-red-flag discomfort. It
is limited to today's intensity, volume reduction, rest, or validated substitution.

**Built (B4, rules `readiness-v1`; ALGORITHMS section 4, "Same-day readiness adjustment").** A
deterministic function reads today's check-in, last night's sleep and the recovery score and
proposes one of three things for today's scheduled workout only, never a plan version:

| Kind | What changes today |
|---|---|
| `hold_load` | keep last time's loads and reps where the progression targets say to add |
| `reduce_sets` | one set fewer on exercises with three or more sets, effort one point lower, last time's loads |
| `swap_to_easy_cardio` | easy cardio of 20 to 30 minutes instead of the session |

- The check-in leads. Sleep minutes add a point under six hours. The recovery score adds a point only
  next to a point from the check-in and never adjusts a session by itself: a score built from
  heart-derived signals informs the athlete and asks for a check-in, and the athlete decides (D9,
  owner 2026-10-23). The athlete may choose any adjustment that would change today's session, with
  one tap and Undo until the workout starts.
- The acute:chronic workload ratio, sleeping heart rate and monotony are not inputs.
- A pain of 7 or more gives no training change and a safety route (a referral to a doctor or
  physio); it applies on a rest day too. Tracend withholds advice; it does not block the workout.
- A bad day never lowers the load: the progression targets ignore a session done under an accepted
  adjustment as evidence for lowering a load or for a stall, and count its adjusted set number as
  the planned one.
- Model output never proposes, applies or accepts the adjustment. Its sentences are fixed templates
  keyed by trigger and kind. No answer exists until the athlete taps; the answer, not the proposal,
  is audited (`day_adjustment_answered`, codes only).
- Missing data lowers confidence and is never invented. With no Apple Health the check-in alone
  decides at low confidence; with no check-in the band is unknown and nothing is proposed.

Acute/severe pain, chest pain, fainting, severe shortness of breath, neurological symptoms, or
another configured red flag invokes escalation rather than workout advice.

### Structural training change

Normally requires at least one of:

- the same performance issue across two comparable sessions;
- two weeks of adherence-backed workload/recovery evidence;
- a sustained equipment or schedule change confirmed by the user; or
- a user-requested revision within policy.

A single missed session, poor pump, or bad day is insufficient.

### Nutrition-target change

Normally requires:

- at least 14 days of usable weight observations;
- a feature-engine trend;
- at least 80% adherence coverage in the review window;
- enough confirmed nutrition days to interpret adherence; and
- no safety restriction.

When adherence is insufficient, the coach addresses obstacles rather than claiming the target
failed. Changes outside configured safe ranges are rejected.

### Coach proposals (A8)

In chat Coach may ask for a change, so "I'll be away for two weeks" or "take a diet break" can end
in an applied change without Coach ever applying it. The approval invariant (Architecture 2 and 3)
holds at every step:

1. **The model chooses an intent, nothing else.** A closed list of seven kinds (`temporary_block`,
   `training_schedule`, `exercise_swap`, `intensity_or_phase`, `goal_or_phase`, `nutrition_targets`,
   `next_session_adjustment`), parameters from closed vocabularies, dates, and a reason from a
   closed list. The parser (`_shared/coach_proposals/intent.ts`) refuses any other key, kind or
   value. A free-text note is kept only if it has no digit; otherwise it is dropped.
2. **Rules compute every number.** `buildCoachProposal(intent, athleteState)` is pure
   deterministic code. Sessions come from the rules plan (B1 catalog and substitutes, B2
   templates, the coaching standard) validated against the onboarding policy; calories and
   macros come from `nutritionPolicy`. A figure the athlete asked for (a calorie target, a target
   weight) must appear in the athlete's own message, so the model cannot make one up, and is checked
   against the same limits as a computed one.
3. **Rules refuse, in plain words.** Refused: a calorie target under the floor (the higher of the
   sex-based minimum and resting energy) or above the highest Tracend sets; a loss faster than 1%
   of body weight a week; a cut, or any calorie reduction below maintenance, at BMI under 19.5; a
   target weight under BMI 18.5; a cut after a run of loss that already calls for a maintenance
   period or a diet break (the goal phase review, B7); any change under `see_professional`; a
   strength phase or raised intensity under `moderate_until_cleared`; a weight older than 14 days;
   a plan change while a temporary block runs.
4. **Eligibility gates the moves that push harder.** A calorie cut below maintenance and a new fat-loss
   phase need `evaluate_change_eligibility` to pass for nutrition (14 weight days, 80% logging, trend
   r² 0.3). A strength phase and a heavier next session need it to pass for training (and a heavier
   session only moves one load step above the logged-set target, only where those sets say add load, and
   never with low confidence). Moves that ease off, or that the athlete asks for to fit their life (a
   schedule, a travel block, a swap, a deload, a diet break, raising calories) are not gated, because
   waiting for data would make them harder to ask for, not safer. The owner may tighten this.
5. **Nothing is applied until the athlete taps.** `persist_coach_proposal_v1` stores a pending
   proposal; `respond_to_coach_proposal_v1` (the athlete's own session, `auth.uid()`) re-checks that
   it is pending and unexpired, that the active plan, nutrition target and goal are still the ones
   it was computed from, and that the health check has not become stricter, then writes a **new
   version** with `source_proposal_id`, the answer and an **audit event**. The Coach reply may not
   claim a change was made; it may say a proposal is waiting for the athlete.
   Approval also runs again what the build checked: the eligibility gates the build required, the
   calorie minimum, that every exercise is still in the catalog, that the profile fields and the
   newest weight (within 1%) are as they were when the proposal was made. A proposal that no longer
   passes is marked expired with a plain reason and never applied.

6. **Undoable and self-ending.** Undo (seven days) restores what approval replaced as new versions;
   it is refused once a later change replaced them. A temporary block carries its last day and the
   version to restore; the regular plan returns by itself the day after.

**Words in a proposal.** A free-text `note` is quoted as "in your words" only when it is a piece
of the athlete's own message (checked in `service.ts` before anything is built); otherwise it is
dropped. A refused or invalid intent gets a fixed plain sentence, never the parser's wording. When
no proposal is stored, every sentence of the reply that promises one ("Here's a proposal you can
approve below", "Tracend works out…") is removed, and the refusal's reason takes its place, so a
reply never points at a card that is not there.

**In chat.** On the gateway route the answer carries a `proposal_intent` list, empty when no change is
asked for and one item otherwise (closed vocabulary above; the schema enumerates the kinds, reasons
and field names, the intent's fields are `{name, value}` text pairs that one function turns into the
object form, and the parser checks every range). The persona no longer says Coach "has no tools": it says Coach cannot change anything
itself and may *propose*, in words like "Here's a proposal you can approve below", never "I've
changed it". The deterministic `claimed_action` guard is unchanged and still rejects a reply that
says a change was made. After the reply has passed every guard, and only for an ordinary `allowed`
model answer (never a red-flag referral, a pain-day referral, a limited or refused answer, a
lookup interim sentence or a data summary), coach-chat calls `proposeCoachChange`. A stored
proposal is linked to the reply; a refusal's plain reason is appended to the reply; an intent the
parser rejects is dropped with the same plain words. The Coach context tells the model what is
waiting, what was answered, what is running and what has ended (a diet break or a block that ended
is reported as ended so Coach suggests the next step as a new proposal).

A diet break ends on its date but nutrition does not revert by itself: resuming a deficit is a new
proposal the athlete approves, so no calorie change happens without a tap.

### Initial plan

Onboarding output identifies assumptions, missing information, confidence, and constraint
uncertainty. It uses only compatible catalog exercises. Training and nutrition proposals require
approval. The `onboarding-plan` Edge Function applies policy `onboarding-policy-v2`; its provider
settings are in §10.4.

- **The model chooses inside ranges that deterministic code computes.** The prompt states every
  range, and `_shared/onboarding/plan_contract.ts` rejects a plan that leaves any of them, with a
  finite rule name. The formulas and sources are in ALGORITHMS.md §9.
  - **Calories:** a goal window around maintenance, with a floor of the larger of BMR and
    1,200 kcal (female) or 1,500 kcal (male or unspecified), and a ceiling of 6,000 kcal.
  - **Macros:** protein 1.6–2.2 g/kg (2.6 g/kg in a deficit), fat 20–35% of calories and at least
    0.5 g/kg, and a macro sum within 5% of calories.
  - **Storable:** the absolute nutrition bounds equal the database check, so a valid plan is
    always storable (`policy_test.ts` compares them with the migration).
  - **Training:**
    - one workout on each chosen weekday, at most six;
    - a set and exercise budget per session length, and the session must fit its minutes;
    - weekly sets per target muscle at most 12 for beginners and 20 for intermediate and advanced
      lifters;
    - each week includes a squat or lunge, a hinge, a push and a pull, except a group the
      athlete avoids entirely or cannot do with their equipment;
    - reps 6–20 (3–20 for strength), RPE 7–8.5 (beginners) or 7–9, rest 60–180 s (240 s for
      strength), and blocks of 4–8 weeks.
- **Exercises:** only active `exercise_catalog` slugs that the athlete's equipment and experience
  allow, never from a movement pattern the athlete chose to avoid (rule `exercise_avoided`).
  - The onboarding "movements to avoid" answer is structured (squats, lunges, hinges, horizontal
    and overhead pressing, rows, vertical pulling). A written limitation needs that answer too,
    because the rules plan cannot read free text.
  - The prompt names the avoided patterns and the catalog it receives leaves them out; the
    validator, the rules plan and `persist_onboarding_proposal_v3` (v2 delegates to it) all
    enforce them.
- **What deterministic code sets, not the model:** names from the catalog, workout order and
  length, a confidence cap, and fixed notes (the movements left out, the calorie ceiling, short
  sleep, an Apple Health weight far from the answer, low carbohydrate, steps far from the
  daily-activity answer). Tracend's notes come first and the list keeps its four-item limit.
  Confidence is low when sex is unspecified or the calorie floor or ceiling applies, and medium
  otherwise.
- **Apple Health, last 28 days:** a deterministic summary (ALGORITHMS §9) of the athlete's synced
  data: average steps, active energy and sleep, workouts found, and the latest weight and trend.
  It never moves the calorie or protein ranges. Only short sleep changes a limit: the RPE ceiling
  drops half a point (`startLighter`), in the policy, so the model and the rules plan both follow
  it. No workouts found is reported as missing information, never as inactivity, because
  HealthKit hides whether read access was denied. Resting heart rate, HRV and breathing rate are
  not sent: without a personal baseline they cannot guide a starting plan. Stored in the
  onboarding snapshot and the proposal's calculation (evidence `APPLE_HEALTH_SUMMARY_28D`).
- **Apple Health, usual months:** the app sends monthly totals for the 11 completed months before
  this one (workouts, strength workouts, sleep and weight with their coverage; no raw sample). The
  plan compares the usual months with the last 28 days. The only limit it changes: lifting under
  half of a usual two or more sessions a week starts the block with a fifth fewer sets a session
  and the RPE ceiling half a point lower, with a note. Stored in the snapshot and the proposal's
  calculation (evidence `APPLE_HEALTH_HISTORY_11M`).
- **Coach intake:** training years, what has worked and stalled (the athlete's words, passed as
  data), reported barbell top sets, and up to two focus muscles. Code turns the top sets into
  one-rep-max estimates and starting loads for those lifts, and gives each focus muscle a weekly
  set minimum inside the existing maximum (ALGORITHMS §9); the validator rejects a plan below a
  minimum (`priority_volume_missing`). The model never writes a load, chooses within these
  limits, and must name the athlete's focus and history in its assessment.
- **Follow-up questions:** before the plan, the same provider may ask 0–3 questions
  (`onboarding-plan` with `mode: "questions"`, `_shared/onboarding/questions.ts`), under the same
  consent (`onboarding_plan`) and budget gates.
  - Each question must belong to an allowed topic: split history, recovery between sessions, a
    stalled lift, exercise preference, schedule flexibility, or daily eating routine. A reply with
    any other topic, or with injury, pain, medical, pregnancy or disorder wording, is dropped whole
    and the plan is built without questions.
  - One request claims the hash of the answers before asking (`claim_onboarding_questions`, 60 s
    lease); an overlapping request waits up to 45 s for its outcome instead of asking again. The
    model's outcome is stored per hash (`onboarding_questions`). A failed call releases the claim
    so a retry may ask. No consent, no budget or no ready model is answered without storing
    anything, so it never outlasts its cause.
  - The athlete can skip at any time; the plan then starts once the running question request
    settles (at most 45 s in the app), so the two calls never spend the budget at once. Questions
    never block onboarding.
- **No deload promise:** the app repeats one weekly template, so the prompt forbids promising a
  deload or a different week, and the proposal no longer stores `deload_week`.
- **When the model is not used:**
  - A plan that fails validation gets one targeted repair.
  - Anything else becomes the **rules plan**, built by the same policy without a model. That also
    happens with no `onboarding_plan` consent, no evaluated provider, or an exhausted budget.
  - The rules plan is built and validated before any model call. When it cannot meet the
    policy (equipment and movements to avoid leave a day empty), the answers are infeasible:
    `onboarding-plan` answers 422 `onboarding_plan_infeasible` with the answers to change, starts
    no generation and calls no model, so a retry with the same answers cannot repeat a failure.
  - Otherwise every athlete gets a valid plan, labelled with its origin (`ai` or `rules`) and any
    fallback reason.
  - Every billed call counts toward the AI budget, including empty or cut-off answers and the
    repair attempt.
- **Approval:** `respond_to_onboarding_proposal_v2` inserts exactly the approved workouts and
  exercises, and activates the goal, profile and onboarding weight, in one transaction, dated with
  the athlete's local date at approval (`user_accounts.timezone`, set by the app through
  `set_my_timezone`). Approval copies starting loads to `planned_exercises`. The profile keeps the
  movements to avoid, the equipment note, the training years and the focus and strong muscles,
  which the Coach reads and is told never to contradict.

## 7. Eligibility and Escalation

Before any plan is built, a deterministic pre-exercise screening (`_shared/training/screening/`,
ACSM 2015 preparticipation logic in our own words) maps four yes/no answers to `cleared`,
`moderate_until_cleared` or `see_professional`. Any current sign or symptom, or no regular exercise
with a known heart, metabolic or kidney condition and no professional clearance, gives
`see_professional`: no plan is built and the app shows professional guidance, the same path as the
exclusions below. Regular exercise with a known condition and no clearance gives
`moderate_until_cleared`: the rules plan caps intensity (no strength emphasis, at least 3 reps in
reserve, no vigorous conditioning). A model never sets, changes or overrides the outcome, and the
screening makes no diagnosis. The answers, outcome and date are stored in
`onboarding_screenings`; no row (an account or app build from before the screening) reads as
`cleared`.

**Red-flag screen in Coach chat (A9).** Before any Coach model call a deterministic screen
(`_shared/coach_safety/red_flags.ts`) reads the athlete's message and, with the daily policy's
`escalate` outcome, today's check-in. A hit returns a fixed referral (`referrals.ts`, kept out of
every prompt) with `safety_state: "limited"` (`refused` for self-harm and for the unsupported
requests below), no model call, no tokens and no cost; it does not need AI consent, takes no
budget place and renders no context. The screen reports on what the athlete says about
themselves, so it skips a symptom that is negated ("no chest pain"; the negation ends at a
contrast such as just, only, but, except, though, however or although, at clause punctuation and
at a comma, so "no chest pain, just dizzy" and "no chest pain, dizziness or fainting" are hits and
"no chest pain or dizziness" is not), conditional ("what if I feel
dizzy"; only "what if", "suppose", "in case", "should I ever" or "hypothetically" directly before
the symptom, never a bare "if") or asked about as a topic ("how do I avoid dizziness when
cutting"). **Design rule for every exemption, here and in the reply guard:** it applies only when
it provably governs the matched symptom, prescription or figure: in the same clause, within a short
window before the match, with no `and`, `but` or comma between. A possessive directly before the
symptom ("my chest feels tight"), a self-report in the clause ("I get", "I feel"), or "it happens
to me" anywhere in the message defeats the conditional and educational exemptions. An exemption inside a symptom rule is a benign phrase next to the match ("breathe through my nose",
"stuffy nose", "nasal congestion"; tingling next to beta-alanine or niacin), never a word elsewhere in
the clause; "numb" and "loss of feeling" are never excused. A denial that stops at a point in time
("never had chest pain until today's run", "no dizziness until this morning") is a report. Self-harm and
eating-disorder patterns have no exemption at all: any mention is a hit. A negation counts only when
its cue is directly before the symptom with a few filler words between ("no", "any", "feel",
"have"; "can't" never denies), and "cause" alone is not education ("what causes" is; "squats cause
chest pain for me" is a report). A red flag does not depend on context preparation: when it fails
the referral is still stored and returned with its own safety state. Every other phrasing, and any doubt, leans toward a hit, because a miss answers a red flag with coaching and a false alarm costs one
referral. It covers: chest pain, pressure or tightness; palpitations and a heartbeat that races at
rest or skips; fainting, passing out, blacking out, collapse; dizziness and light-headedness;
severe or sudden breathlessness and wheezing; signs of stroke (slurred speech, one-sided
weakness or numbness, drooping face, worst headache); coughing or vomiting blood or blood in the
stool; dark or bloody urine after hard training; numbness and tingling in a limb; sharp, severe or
sudden pain, a pop, tear or snap, a pain of 7/10 or more; purging, laxatives or diuretics for
weight, binge-and-compensate, fasting for two or more days, a stated eating disorder; self-harm
and suicidal statements. With pain of 7 or more on today's check-in (the policy's `escalate`
outcome, `CHECK_IN_SAFETY_ESCALATION`; the same-day adjustment then returns the
`pain_referral` safety route and no change), a question about training gets the referral too, and this
is decided before the consent and budget gates from a cheap read of the newest check-in row (the
athlete's local date from their timezone), so an athlete with no consent or no budget left still
gets the referral; food,
sleep and recovery questions still reach the model, which is told in its Safe Ranges section to
give no training advice that day. Urgent referrals (heart, fainting, breathing, stroke, blood,
self-harm, eating) name the emergency number; pain and numbness referrals send the athlete to a
doctor or physio before the area is trained again; the self-harm answer adds crisis lines. No
referral diagnoses or reassures. Requests Tracend does not support (diagnosis, medical reports,
rehabilitation, pregnancy and postpartum, medication advice and interactions) get the fixed
clinical-boundary answer (`refused`). "I take medication, can I train?" and ordinary soreness are
not hits. The wider screen behind the data summary (§12) includes every message this one catches.
The log carries the rule that fired (`coach_chat_red_flag`: category, rule, source), never the
message.

The MVP does not support:

- users under 18;
- pregnancy or postpartum coaching;
- active or suspected eating-disorder support;
- medically prescribed diets or conditions requiring clinical exercise/nutrition management;
- acute injury or rehabilitation;
- diagnosis or medical-report interpretation; or
- emergency/crisis situations.

An `escalate` response states that Tracend cannot safely advise, recommends stopping the relevant
activity when appropriate, directs the user to emergency services or an appropriate
clinician/dietitian/physiotherapist, avoids diagnosis, and never reassures the user that a red-flag
symptom is harmless. Localized emergency wording is maintained outside model prompts.

## 8. Meal Image Analysis

Meal vision returns candidate foods, preparation assumptions, estimated portions, confidence,
ambiguity, and clarification questions. It never supplies authoritative final macros.

The user edits and confirms candidates; catalog data calculates nutrients. Unconfirmed candidates
never affect adherence or coaching. Mixed Indian/home dishes should request recipe or ingredient
clarification rather than imply false precision.

**Provider.** Server-side, through the AI gateway (§10.5) as feature `meal_vision`.
- **Live today (until the cutover, §10.7):** Groq `qwen/qwen3.8-27b` (`MEAL_VISION_PROVIDER=groq`),
  the successor of the retired `qwen/qwen3.6-27b`. With no `AI_MEAL_VISION_*` settings the function
  runs this path unchanged. It refuses any other Groq model name, and it stays off until
  `MEAL_VISION_ENABLED` and `MEAL_VISION_MODEL_EVALUATED` are both `true`. Groq's Zero Data
  Retention setting must be on for the key's organization while this route is enabled.
- **After the cutover:** Claude Haiku 5.5 (`AI_MEAL_VISION_PROVIDER=anthropic`,
  `AI_MEAL_VISION_MODEL=claude-haiku-5-5`). `MEAL_VISION_ENABLED` stays the on/off switch, and
  `AI_MEAL_VISION_EVALUATED=true` replaces `MEAL_VISION_MODEL_EVALUATED`. The owner sets it only
  after the own-photo check below passes. Anthropic's standard commercial terms apply:
  inputs and outputs are deleted within 30 days and not used for training, which the notice says.
  The JPEG is checked and its metadata removed before sending (`_shared/physique/jpeg.ts`).
- **Own-photo check (before any production route is set; the synthetic drawings in the gateway
  evals test the contract and refusals, not recognition of real food).** The owner puts a few of
  their own meal photos (about ten typical meals, including a mixed home dish and one non-meal
  photo) in a local folder and runs `supabase/functions/_evals/owner_photo_check.ts meal <folder>`.
  It sends each photo to Anthropic through the same request meal-analyze sends (the same
  instructions, schema, model and settings, from `meal-analyze/vision.ts`), prints the parsed
  candidates, stores nothing, reads `ANTHROPIC_API_KEY` from the environment without printing it,
  and stops before a call that could pass its spend cap. The owner judges the output: the foods
  named are the foods on the plate, portions are sensible, no item is invented, a mixed dish asks
  about its recipe rather than implying precision, and a non-meal photo returns no food. Only if
  it passes does the owner set the production route with `AI_MEAL_VISION_EVALUATED=true`; if it
  does not, no route is set. Meal vision has no allowlist, so this check is the only gate before
  every athlete can use the route.
- **Rollback:** unset the `AI_MEAL_VISION_*` settings. The Groq path runs again (and needs a Groq
  meal photo notice current, so the rollback window keeps the old notice available to republish).

**Consent.** Meal photos are not covered by the AI coaching consent, which states that photos are
not sent. They have their own notice (`meal_photo_ai_notices`, §10.3) and consent type
`meal_photo_ai`.

- The app shows the notice before the first photo is picked.
- meal-analyze refuses with 403 `meal_photo_ai_consent_required` without a grant of the current
  version, and with 503 `meal_photo_notice_outdated` when that notice names a vendor other than
  the route's (`MEAL_VISION_PROVIDER` on the Groq path).
- The athlete withdraws from **Log a meal** (**Turn off meal photo AI**, a `withdrawn` record),
  which stops new analysis at once.
- A vendor change needs a new notice (`private.publish_meal_photo_ai_notice`) before the switch;
  every athlete is then asked again. A model change within the same vendor does not, because the
  notice names the company, not the model (D11).

## 9. Physique Analysis

**Status: owner-only experiment.** The `physique-check` Edge Function serves only the user IDs in
`PHYSIQUE_VISION_ALLOWED_USERS` (empty at deploy). It runs through the AI gateway (§10.5) as
feature `physique_vision`.
- **Live today (until the cutover, §10.7):** Groq `qwen/qwen3.8-27b` (`PHYSIQUE_VISION_*`). With no
  `AI_PHYSIQUE_VISION_*` settings the function runs this path unchanged. Groq's Zero Data Retention
  must be on for the key's organization, with the proof (date or screenshot) recorded in
  `docs/handoff/physique-check.md`.
- **After the cutover:** Claude Sonnet 5.5 (`AI_PHYSIQUE_VISION_PROVIDER=anthropic`,
  `AI_PHYSIQUE_VISION_MODEL=claude-sonnet-5-5`). The function answers 403 `physique_vision_not_evaluated`
  until `AI_PHYSIQUE_VISION_EVALUATED=true`. The synthetic drawings used in the gateway evals test
  the contract, refusals and injected text, not recognition of real bodies.
- **Own-photo check (before any production route is set).** The owner puts a few of their own
  photo sets in a local folder, one sub-folder per set holding `front.jpg`, `side.jpg` and
  `back.jpg`, and runs `supabase/functions/_evals/owner_photo_check.ts physique <folder>`. It sends
  each set to Anthropic through the check's own handler (`physique-check/handler.ts`: JPEG
  cleaning, the same request, model and settings, the contract and the one correction), prints the
  parsed result or the refusal, stores nothing, reads `ANTHROPIC_API_KEY` from the environment
  without printing it, and stops before a call that could pass its spend cap. The owner judges
  the output: sensible muscles to develop for their own build, no body-fat figure, percentage,
  score or rating, no judgement of appearance, nothing medical, and no contract refusal on a
  clear set. Only if it passes does the owner set the production route with
  `AI_PHYSIQUE_VISION_EVALUATED=true`, and the allowlist stays owner-only for the first production
  day; widening it is a later step that needs the separate evaluation below. If the check fails,
  no route is set. Rollback: unset the `AI_PHYSIQUE_VISION_*` settings.

No other account may be added to the allowlist until a separate evaluation passes: consented or synthetic sets across body types and skin tones; pose,
clothing, lighting and pump changes; repeatability; wrong priorities; forbidden outputs; text
written into the image; and empty, unrelated or low-quality photos.

**Consent.** Its own server-versioned notice (`photo_ai_notices`, consent type
`progress_photo_ai`, §10.3), separate from the AI coaching notice. The notice names the receiving
company, the data sent, the company's retention, what Tracend keeps and how to stop. Consent counts only when
the athlete's newest `progress_photo_ai` record grants the newest notice (`has_photo_ai_consent`);
a new company, new data sent or a retention change is a new notice and needs a new grant. A
model change within the same company is not (owner decision, 2026-10-16): the notice names the
company, not the model (D11). Withdrawing
stops new checks; past results stay until the set or account is deleted.

**Input.** The front, side and back photos of one complete set (Groq accepts three images; a Claude
image may be 3.75 MB decoded), each a JPEG of at most 3 MB with every metadata segment (EXIF, location, XMP, ICC, comments) removed on the
server before sending, across every scan of a progressive file, and nothing after its end marker
(`_shared/physique/jpeg.ts`); the app already re-encodes at capture (longest side 1800 px, no
metadata). Also sex, height, latest weight and body measurements, and the active goal, as data.
The check is hidden when the athlete's own notes mention an eating concern.

**Output** (`_shared/physique/contract.ts`, `private.is_valid_physique_result`): 1–3
`development_priorities` from the catalog's primary muscles, each with confidence and a reason of at
most 120 characters, relative to the athlete's own build; up to three neutral observations; photo
issues from a fixed list (lighting, pose, clothing, framing, blur, mismatch), which cap confidence
(one at medium, two or more at low); and limitations. Any unexpected key, unknown muscle, or a
percentage, body-fat, score or rating, appearance judgement, sexual, medical, sensitive-trait or
eating wording rejects the whole reply. A reply that suggests no muscle at all means the photos
show no physique to judge (an unrelated picture, the body out of frame): nothing is stored, no
correction is asked, and the athlete is told to retake the set (422 `photo_set_unassessable`). One
text-only correction is asked (the photos are not sent again). On the Groq path it waits for at
least 2,500 tokens left in the minute; the gateway route has no such wait. If the correction is
not possible or also fails, nothing is stored (502 `physique_check_invalid`) and the tokens are
still counted.

**Use.** The result is shown as an AI visual estimate, not a measurement. Nothing changes on its
own: the athlete chooses up to two suggested muscles (`set_my_priority_muscles`), which become
`user_profiles.priority_muscles`. Only confirmed focus muscles reach the Coach and the next plan;
the analysis text never does.

Prohibited, always:

- any body-fat figure or range, muscle-mass claim, score or rating;
- medical, disease, or hormonal inference;
- sexualized, insulting, shaming, or identity-based language;
- facial recognition; and
- unrelated sensitive-trait inference.

## 10. Providers, Consent and Routing

### 10.1 Routing rules

Use:

- deterministic code for calculations and hard policy;
- an economical vision model only after it passes meal tests;
- a capable structured-output model for daily coaching;
- a stronger evaluated model for onboarding, periodic review, or ambiguous conflicts; and
- no model call when deterministic output is sufficient.

Price alone cannot qualify a model. Lite models are rejected by production configuration. Cost
control must not bypass visible-food, mixed-dish, hidden-ingredient, portion-uncertainty,
prompt-injection, schema-validity, or user-correction evaluations. Routing changes require
regression results. Provider and Supabase secret/service-role keys never enter Flutter.

In the database a provider is the **vendor** that receives the athlete's data (`anthropic`,
`deepseek`, `groq`, `gemini`, and `mock` for runs), never the API shape used to reach it: a notice
naming DeepSeek must not cover a route to Groq. Evaluations may send synthetic athletes through an
OpenAI-compatible router, which is never stored or named by a notice; a router never receives user
data unless it passes its own privacy review.

### 10.2 Providers today

Each feature has its own server-side settings inside Supabase Edge Functions, and each calls the AI
gateway (§10.5) only when its `AI_<FEATURE>_*` route exists and is evaluated. Without one, the
feature runs the path in the "Live today" column unchanged, so deploying the gateway code changed
nothing for the athlete. **Until the cutover (§10.7) production still sends athlete data to DeepSeek
and Groq; no feature has a Claude route yet.**

| Feature | Settings today | Live today | Default when unset | Cutover route (§10.7) |
| --- | --- | --- | --- | --- |
| Coach chat | `COACH_MODEL_PROVIDER`, `COACH_AI_ENABLED`, provider key and model | DeepSeek V4.1 Flash (`deepseek`, model `deepseek-flash`) | deterministic mock | `coach_chat`: Haiku 5.5 |
| Daily decision | same as Coach chat | DeepSeek V4.1 Flash | deterministic mock | `daily_decision`: Sonnet 5.5 |
| Onboarding plan and follow-up questions | `ONBOARDING_PLAN_*` (§10.4) | DeepSeek V4.1 Flash | rules plan only (`mock`) | no route at the cutover: once the Anthropic coaching notice is current, onboarding uses the rules plan; `onboarding_plan` and `onboarding_questions`: Sonnet 5.5 after B2 |
| Meal photos | `MEAL_VISION_*` (§8) | Groq `qwen/qwen3.8-27b` | off | `meal_vision`: Haiku 5.5 |
| Physique check (owner only) | `PHYSIQUE_VISION_*` (§9) | Groq `qwen/qwen3.8-27b` | off | `physique_vision`: Sonnet 5.5 |

- **Coach chat and daily decision.** `COACH_MODEL_PROVIDER` is `mock`, `deepseek`, `groq` or
  `gemini`. A live model needs `COACH_AI_ENABLED=true`, the provider's key and an approved model,
  configured together as an all-or-nothing gate; anything less keeps the deterministic mock.
  DeepSeek retired V4 Flash on 2026-09-10 and routes the legacy name `deepseek-v4-flash` to V4.1
  Flash for now, so the code accepts both names and nothing else. That silent model change still
  owes its regression run (§13). Coach chat lets DeepSeek reason (thinking) only for an explicit
  plan-change question; daily decisions and every repair are non-thinking. Weekly reviews are
  deterministic SQL and call no model.
- **Prior providers.** Gemini `gemini-3.5-flash` and Groq Qwen `qwen/qwen3.6-27b` (ADR 0005, ADR
  0006; Groq shut the latter down on 2026-09-14) are superseded pending evaluation. Their adapters
  stay disabled by default and require an explicit paid-service data-terms gate (for Gemini,
  `GEMINI_PAID_DATA_TERMS_ACCEPTED`) before they can process restricted coaching context.
  Synthetic adapter tests do not satisfy evaluation parity or authorize live calls. Meal and
  progress vision remain separately gated.
- **Photos.** DeepSeek receives no photos: meal-analyze calls Groq or Gemini (or, with a route,
  Claude), and physique-check Groq (or Claude). The photo notice tables accept `deepseek` since
  migration A1, but a DeepSeek photo route would also need new code and a migration, because the
  run and usage tables still pin the old vision models.

### 10.3 Consent notices

A feature sends an athlete's data to a provider only while that athlete grants the current notice
for its purpose. Notices are server data, never edited once published.

| Notice table | Consent type | Covers | Current notice |
| --- | --- | --- | --- |
| `ai_consent_notices` (current per purpose in `ai_notice_current`) | `ai_coaching` | `coach_chat`, `daily_coaching`, `onboarding_plan` | `ai-coaching-v5`, DeepSeek; states photos are not sent |
| `meal_photo_ai_notices` | `meal_photo_ai` | meal photos (§8) | `meal-photo-ai-v1`, Groq |
| `photo_ai_notices` | `progress_photo_ai` | physique check (§9) | `progress-photo-ai-v1`, Groq |

These are the notices published **today**. The cutover replaces them with the drafts in
[`docs/notices/`](./notices/): `ai-coaching-v6`, `meal-photo-ai-v2` and `progress-photo-ai-v2`, all
naming Anthropic (§10.7). A draft is not a notice until the owner publishes it.

**AI coaching consent.** `has_ai_coaching_consent` reads the newest `ai_coaching` record; only a
grant of the notice current for the purpose counts. Publish any later notice for every purpose: the
app shows the notice current for the most purposes, and a grant covers only that one version. The
app does not call Coach chat or the daily decision for an athlete who declined (UX_FLOWS §4.1), and
the server enforces the same rule for every caller. `coach-chat` answers 403
`ai_consent_required` without consent, and 503 `ai_consent_unavailable` when the check fails.
`coach-decide` then uses the deterministic provider and `onboarding-plan` the rules plan, so no
data reaches the AI provider.

**New data and the accepted notice (2026-10-20).** Data reaches the AI only under an accepted notice
that names it. The Coach notice (v5 and v6 list the same data) names: training plan and workout
logs, check-ins, Apple Health summaries (sleep, heart rate, HRV, steps and workouts), meals and
nutrition targets, body measurements, goals, focus muscles and preferences, and the messages the
athlete sends the Coach. `_shared/ai_notice_coverage.ts` holds the verdict for the fields the
lookups grew, and `coach-chat` passes the athlete's accepted notice version to the lookup runner:
- **Not named, held back until a notice names them:** Apple Health breathing rate (`breathing_rate`)
  and the athlete's free text in a workout: the session note, an exercise's note and the reason for
  a swap (`workout_notes`). The rows leave them out and say they exist ("Withheld: ... Do not say
  there are none"). To open one, the owner publishes a notice that names it, then sets the first
  version number that does in `firstNoticeNaming` in the same change.
- **Covered, not gated:** sleep stages (they are the Apple Health sleep summary), night and morning
  HRV (HRV), workout minutes and the watch's workouts (workouts), proposals and daily decisions
  (Tracend's own text about the plan, targets and goals the notice names), and Coach's own earlier
  replies (the conversation memory has always sent them; they carry no new data).
- **Already sent before this change, not named:** active energy (`health_daily_28d` in the athlete
  file since v8; the Coach list does not name it, the onboarding sentence does). Not gated here
  because it is not new; the next notice should name it.

**Notices name a vendor.** All three tables have a `provider` column. The meal photo table always
required one; the other two gained a nullable one in migration A1, and migration code 17 filled
it for every earlier notice from its label and model (DeepSeek, Groq), so no notice has a null
provider. Publish with
the five-argument functions: `private.publish_ai_notice(version, provider, provider_label,
purposes, body)`, `private.publish_photo_ai_notice(version, provider, provider_label, model, body)`
and `private.publish_meal_photo_ai_notice(version, provider, provider_label, model, body)`. Each
calls `private.check_notice_provider_label`, which refuses (22023) a null or unknown provider, a
blank label, and a label that does not name the provider's company (Anthropic, DeepSeek, Groq or
Google; case ignored) or also names another, so the athlete never agrees to one company while the
gateway sends to another. The older four-argument publishers still exist but refuse
(22023) and point to the five-argument form, so a notice without a vendor cannot be published.

**The gateway checks the vendor.** `get_ai_consent_v2(target_user_id, consent_purpose)` (service
role) returns `{schema_version, granted, provider, notice_version}` for the notice current for the
purpose (`aiConsentWithProvider` in `_shared/ai_consent.ts`, which never throws and answers
`unavailable` on any failure). `coach_chat` and `library_context` read the coaching notice for
`coach_chat`; `daily_decision` and `daily_coaching` the one for `daily_coaching`;
`onboarding_plan` and `onboarding_questions` the one for `onboarding_plan`; `meal_vision` the meal
photo notice; `physique_vision` and `progress_vision` the progress photo notice. The gateway
refuses (`consent_provider_mismatch`) when `provider` differs from the route's vendor, including
when it is null, until a notice naming the route's vendor is published and granted.
`has_ai_coaching_consent` and `get_meal_photo_ai_consent` are unchanged.

**Wording (owner decision D11).** No model name appears anywhere the athlete or the public reads:
the app, notices, website and privacy policy. The receiving company is named only where disclosure
is needed: once in each AI consent notice and in the privacy policy's processor list.
- **The app (done, A7).** Screens say "AI". An AI answer is labelled "AI answer · checked by
  Tracend" and an onboarding proposal "Proposed by AI · checked by Tracend"; the physique card says
  "Sent to AI only when you start a physique check"; the Coach and Account rows say "an AI service"
  and "AI". The stored provider and model are provenance only. Old servers still send
  `provider_label` and old rows carry provider ids; the app accepts them and shows none. Widget
  tests grep the rendered text for model and company names (`test/ai_wording_test.dart`).
- **The notices.** The published meal photo and progress photo notices still name the model
  `qwen/qwen3.8-27b` and the current coaching notice names DeepSeek, until the owner publishes the
  v6 / v2 / v2 drafts, which name Anthropic once and no model. The `model` argument of the photo
  publishers is a stored provenance field of the notice row and is not shown by the app.
- **The app has no notice text of its own.** It shows only the notice it fetched
  (`get_current_ai_notice`) and records only the version it fetched. When that call fails or
  returns something that is not a notice, the signed-in app still opens, with AI coaching off and
  no answer assumed. Only the screens that ask (the AI coaching question, the Coach and Account
  sheet, and the onboarding AI step) say the notice could not be loaded and offer **Try again**,
  with no answer buttons until it loads; onboarding goes on with the rules plan. The photo notices
  are likewise fetched from the server and recorded by the version fetched. A test keeps the drafts in `docs/notices/` free of model names.

### 10.4 Onboarding plan provider

Onboarding plans and follow-up questions have their own provider settings and switch without a
code change. This is the path that runs **today**. A gateway route for the same features exists
(`AI_ONBOARDING_PLAN_*`, `AI_ONBOARDING_QUESTIONS_*`, Sonnet 5.5, §10.5) but is **not enabled at the
cutover**: its eval passes the 90% bar on only about half of the runs, because of weekly-volume
rules that chunk B2 fixes. The owner switches onboarding to Claude after B2 (runbook, "Later").
A route without `AI_ONBOARDING_*_EVALUATED=true` is identical to no route. **Fail closed:** the
settings path sends only while the current `onboarding_plan` notice names its vendor. The Anthropic
coaching notice covers `onboarding_plan`, so from its publication this path no longer sends and the
rules plan answers, with no follow-up questions, until the Claude route is set.

- **Settings:** `ONBOARDING_PLAN_PROVIDER` (`mock`, rules only, the default; `deepseek`, `groq`
  or `gemini`), `ONBOARDING_PLAN_MODEL`, the provider's key, `ONBOARDING_PLAN_MODEL_EVALUATED=true`,
  and the input and output prices unless the provider has a known default (DeepSeek uses its peak
  price; without a price the rules plan is used).
  - `ONBOARDING_PLAN_THINKING`: `on` (the default when unset) or `off`. With it on, the first
    attempt reasons before answering (DeepSeek: `thinking` enabled, `reasoning_effort: high`, no
    temperature, 24,000 output tokens) and gets 105 s of a 125 s deadline. The repair never thinks.
    A provider without a thinking mode ignores the setting. Off sends thinking disabled,
    temperature 0.2 and 6,000 tokens, with 55 s of 75 s. Follow-up questions think as configured,
    with 4,000 output tokens and 40 s.
- **Calls:** every provider is called through its OpenAI-compatible chat-completions endpoint in
  JSON mode (`_shared/providers/onboarding_plan_provider.ts`).
- **Telemetry:** the `onboarding.plan.generated` and `onboarding.questions.generated` audit events
  store whether the call thought, its latency, attempts, input, output and reasoning tokens, and
  the last finish reason (`persist_onboarding_proposal_v3`). Prompts and answers are never stored
  there. Usage is recorded as `onboarding_plan` or `onboarding_questions`.
- **Changing any `ONBOARDING_PLAN_*` secret** creates a new version of every Edge Function. Wait for
  the change to finish, then run `./scripts/verify-live-function.sh --all` from the deployed commit.
  To roll thinking back: `./scripts/supabase.sh secrets set ONBOARDING_PLAN_THINKING=off
  --project-ref qsfzzsjenopqqqhvpyaw`, then the same check.
- **To switch provider or model:**
  1. Run the Onboarding Eval workflow (`.github/workflows/onboarding-eval.yml`) for the candidate.
     It must give at least 90% of the synthetic athletes a valid model plan without fallback. A
     direct run also gates p95 latency (60 s, or 120 s with thinking). The owner runs evals through
     the router (`EVAL_API_KEY`) to keep provider credits for production; the router ignores
     thinking-off and adds its own timeouts, so it cannot prove the exact production request, and
     the first production plans are checked through the audit telemetry instead.
  2. Set the secrets.
  3. Run `./scripts/verify-live-function.sh --all`.
  4. **Because athletes agreed to a named provider,** a provider change also publishes a new
     notice for every purpose:
     `select private.publish_ai_notice(version, provider, provider_label, purposes, body)`. Older
     grants stop counting at once, and the app asks again.

### 10.5 AI gateway

`_shared/ai/` (program Contract 1) is the one path for model calls. Every feature (`coach_chat`,
`daily_decision`, `onboarding_plan`, `onboarding_questions`, `meal_vision`, `physique_vision`)
calls it when `route(feature)` returns a complete route whose `AI_<FEATURE>_EVALUATED` is `true`;
otherwise the feature runs today's path (§10.2) unchanged, and tests compare that path with
recorded requests byte for byte. `library_context` is reserved for the research library.
`coach_chat_strong` (`AI_COACH_CHAT_STRONG_*`) is Coach chat's optional second route for questions
that need analysis (§11); unset, `coach_chat` answers them.

- Settings are per feature: `AI_<FEATURE>_{PROVIDER,MODEL,BASE_URL,THINKING,EFFORT,
  MAX_OUTPUT_TOKENS,TIMEOUT_MS,EVALUATED,VENDOR}` plus the provider key (`ANTHROPIC_API_KEY`,
  `OPENAI_COMPATIBLE_API_KEY_<FEATURE>`, or `GEMINI_API_KEY` with
  `GEMINI_PAID_DATA_TERMS_ACCEPTED=true`). A missing or invalid setting, or a model without a
  known price in `_shared/ai/models.ts`, gives no route, and the feature keeps today's path.
  Switching a feature, or rolling it back, is a settings change only: set or unset
  `AI_<FEATURE>_PROVIDER` (runbook `docs/runbooks/phase2-claude-cutover.md`).
- Consent is read with `get_ai_consent_v2`, and `call()` sends nothing when the vendor named by
  the athlete's accepted notice differs from the route's (`consent_provider_mismatch`). A feature
  then takes its existing consent-needed path (the Coach answers 403, the daily decision and the
  plan use their rules, a photo feature answers its notice error). DeepSeek and Groq are reached
  only on their own hosts. An eval router (`AI_<FEATURE>_VENDOR=router`) is named by no notice, so
  no athlete's data reaches it; features ignore it on athlete requests.
- Requests to Claude 5 models never carry `temperature`, `top_p`, tools or a forced
  `tool_choice`; structured output uses `output_config.format`. The Coach answer schema is one fixed
  shape for every athlete and day, with no optional property and no union (Claude compiles a schema
  once and caches the grammar, and a changing or branching schema ran past the timeout on every
  Coach turn on 2026-10-18); the permitted evidence codes live in the prompt and the parser checks
  them, and a test fails if the schema changes shape. The stable prompt prefix carries
  `cache_control`, so repeated Coach questions read the prefix from the cache. DeepSeek, Groq and
  Gemini routes send what today's providers send (temperature 0.1 without thinking, the schema
  restated in JSON mode), so a rollback by settings behaves as before. Every JSON answer is
  checked against the schema by the gateway (`invalid_output` otherwise), and each feature's own
  validator (plan contract, decision grounding, Coach citations, physique contract) still runs
  after it.
- A provider refusal is `refused` and never retried by the gateway.
- The caller reserves budget first (`reserve_ai_budget_v2`, with the route's worst-case ceiling,
  never clamped: a route whose worst case passes USD 0.50 is unusable and the feature keeps
  today's path, logged as `<feature>_route_unusable`) and settles with the real cost.
- One scrubbed `ai_call` log line per call: feature, provider, model, outcome, token counts, cost
  and latency; never prompt, image, reply or provider error text.
- Provenance (`model_runs`, usage events, proposals) stores the vendor and model that answered.
  It is never shown to the athlete (D11).

### 10.6 Budget

Every model call first reserves budget against a per-athlete monthly hard stop, a per-athlete daily
request limit and a global monthly stop. From migration code 17 the stops are **USD 3 per athlete
per month**, **30 requests per athlete per day** and **USD 50 across every account per month**,
held in `private.ai_budget_limits` (`per_person_monthly_usd`, `global_monthly_usd`) so the owner
changes either from the SQL editor. (Before it: USD 2 per athlete and USD 10 global.) The USD 50
global stop is owner-approved in principle and is to be confirmed at the cutover. A daily decision
with no budget left falls back to the deterministic provider, as without consent; the plan stays
usable. Optimize cost using compact feature snapshots, cached static context, deterministic
summaries, normalized images, duplicate avoidance, per-user rate limits, and quality-based routing.
Cost cannot override safety or the quality floor. Limits, prices and hard controls are in
[COST_MODEL.md](./COST_MODEL.md).

The reservation is the only gate. Coach chat preparation (`prepare_coach_chat`) used to keep its own
USD 5 a month and 30 a day literals; it no longer checks spending, and its `budget_warning` follows
`private.ai_budget_limits` (true from 80% of `per_person_monthly_usd`, as in
`get_my_ai_budget_state`, which moved from half the stop in the same migration). The app tells the athlete in plain words which limit was reached and when
it resets (a monthly limit resets on the first of the next month at 00:00 UTC, a daily limit at the
next 00:00 UTC), never "Coach couldn’t answer" alone: UX_FLOWS, Coach replies. Coach chat also
answers an athlete who has no active plan (screening outcome `see_professional` builds none); it
may answer questions and suggest next steps but cites no plan, and the daily decision still
requires one.

### 10.7 Cutover to Claude (Phase 2)

> **Not yet done.** The code for A3–A6 is merged behind settings; production still uses DeepSeek
> and Groq until the owner runs
> [`docs/runbooks/phase2-claude-cutover.md`](./runbooks/phase2-claude-cutover.md). Program plan:
> [coaching platform](./plans/coaching-platform-2026-10/README.md), chunks A3–A7.

Owner decision D1: features move from DeepSeek and Groq to Claude through the gateway, and the old
routes stay available by settings alone for two weeks after the cutover.

| Feature | Route | Model | Output tokens | Timeout | At the cutover |
| --- | --- | --- | --- | --- | --- |
| Coach chat | `coach_chat` | Haiku 5.5 | 4,096 | 30 s | move |
| Daily decision | `daily_decision` | Sonnet 5.5 | 1,800 | 25 s | move |
| Meal photos | `meal_vision` | Haiku 5.5 | 1,500 | 30 s | move |
| Physique check | `physique_vision` | Sonnet 5.5 | 800 | 60 s | move after the owner's real-photo check |
| Onboarding plan | `onboarding_plan` | Sonnet 5.5 | 8,000 | 90 s | later, after B2 |
| Onboarding questions | `onboarding_questions` | Sonnet 5.5 | 1,500 | 30 s | later, after B2 |

- **Order** (the runbook has the commands). Per feature group, in one sitting: set the route
  (`EVALUATED=true` last); the owner publishes the Anthropic notice; athletes accept it. The first
  deploy changes nothing. **Fail closed:** data goes only to the vendor named by the notice the
  athlete accepted, on the gateway and on the old paths alike. While a route exists but the
  current notice names another vendor, the athlete's feature degrades without sending anything:
  Coach chat answers 403 `ai_consent_required`, the daily decision and the starting plan use the
  deterministic rules, meal photos answer 503 `meal_photo_notice_outdated`, the physique check is
  unavailable. After the Anthropic notice is current the old DeepSeek and Groq paths refuse in the
  same way. The coaching notice also covers `onboarding_plan`, so onboarding uses its rules plan from
  its publication until onboarding's own route is set after B2.
- **Retention and training.** Anthropic's standard commercial terms (checked 2026-10-16): inputs and
  outputs are deleted within 30 days and are not used for training. Longer only where the law
  requires or to enforce its usage rules (up to 2 years if its safety systems flag an input).
  Zero Data Retention is not arranged. The notices state the 30 days and the no-training term
  plainly; re-read Anthropic's published policy on the day the notices are published.
- **Rollback (2 weeks) has two steps.** (1) Settings only: unset the feature's
  `AI_<FEATURE>_PROVIDER`. Calls to Anthropic stop at once, and the feature degrades safely as
  above. **It does not send traffic back to DeepSeek or Groq**, because the current notice names
  Anthropic and the old paths fail closed. (2) To restore the old vendor, the owner publishes a
  notice naming that vendor (the old text under a new version) and athletes accept it again. Changing
  any Edge secret creates a new version of every function; run
  `./scripts/verify-live-function.sh --all` afterwards.
- **After the window,** the privacy policy's processor list drops DeepSeek and Groq, and the old
  settings and adapters can be removed in a cleanup change.
- **Beta exit criterion.** Health data must not go to DeepSeek once external testers join. Once
  the Anthropic coaching notice is current, no feature sends data to DeepSeek: onboarding, which
  has no Claude route until after B2, uses the rules plan (no AI) until its route is set, so
  health data does not reach DeepSeek. The external TestFlight group should still wait for
  onboarding's AI route if it is to open with AI starting plans.

## 11. Prompt and Context Rules

- Prompts and schemas are versioned and reviewed.
- System instructions define boundaries, policy, schema, and refusal behavior.
- User text and retrieved content are delimited, untrusted data.
- Context states units, windows, freshness, provenance, and missing data.
- Direct identifiers, tokens, object keys, and unrelated history are excluded.
- Coaching calls have no web, shell, arbitrary database, or unrestricted tool access. Coach chat on
  the gateway route may ask for bounded, read-only lookups of the athlete's own records (§11.1).
- The model may reference only supplied catalog identifiers.
- Conversational answers may explain only supplied structured evidence, must state missing data,
  and expose evidence references. The model receives at most 20 recent messages and no tools (bounded data lookups travel in the JSON answer, §11.1).
  The deterministic red-flag screen (§7) answers symptom reports and unsupported medical,
  pregnancy, medication and rehabilitation requests before the model sees them.
- **Null contract:** a `null` value in any model context (chat or decision) means the metric was
  NOT MEASURED that day. Context serialization MUST preserve nulls — stripping them let the model
  read a missing metric as absent history or zero. Empty arrays/objects stay pruned (absent ≠ not
  measured). Chat-context markdown renders null as the "—" sentinel and every system prompt
  carries the rule: null/— is NEVER zero, NEVER a negative result, and must be stated as "not
  measured"; an explicit `0` in the data is a measured zero, a different fact from null. Date
  discipline: the context carries its own date (chat `coaching_date`, decision
  `feature_context.local_date`) and the prompt forbids calling a value "today/recent" without
  checking the value's date against it — a metric from an older row is a past reading, never a
  current one.
- Provider request bodies MUST use the multi-role message form: `system` carries identity,
  boundaries, refusal behaviour, schema, and evidence rules; `user` carries the prepared context
  first, wrapped in `<coaching_context>` and labelled as supporting evidence, and the user's raw
  message last, labelled `User's message:`. Bundling instructions, schema, the question, and the
  context into one undelimited `user` turn is prohibited — it caused the model to read the question
  as data and emit the same plan-style answer for any input, including greetings. The question
  follows the long context because that is the recommended order for long-context prompts and it
  makes the stable athlete file a cacheable prefix; greetings and one-word messages are in the
  live evaluation to catch a regression.
- The instruction "Lead with one clear recommendation" is prohibited in conversational chat
  prompts; recommendations are appropriate only when the user asks for guidance. Same-day
  execution adjustments remain permitted; persistent plan or target changes remain approval-gated.
- The shared Coach chat persona names the only formatting the app displays (bold, italic, bullet
  and numbered lists) and rules out headings, tables, code blocks, links, and emoji bullets. The
  app renders anything else as plain text, so formatting can never hide part of an answer.
- Coach chat sends the raw question exactly once. Context Date, the null contract, the per-request
  evidence contract, and freshly computed scores are complete priority sections at the start of the
  bounded context. Trimming removes whole lower-priority sections, starting with conversation and
  session history; it never slices a number, JSON value, or closing context delimiter. Sections
  left out for size are named in an "Omitted This Turn" line so the coach says what it cannot see.
- **Full athlete file (v8):** every chat question receives the same complete context from
  `prepare_coach_chat_v8` — plan, goal, profile, check-ins, the 28-day training log and
  7/14/28-day totals, watch workouts, 28 days of watch data with averages, eight weeks of weights,
  nutrition targets and logged days, conversation memory, and data freshness. The question's
  keyword classification may choose behaviour (thinking for explicit plan changes) and telemetry;
  it never adds or removes data. `prepare_coach_chat_v7` remains for rollback.
- If the deterministic scores cannot be computed for the coaching date, `prepare_coach_chat_v7`
  (and v8, which builds on it) marks Computed Scores unavailable and permits only non-score
  evidence codes; chat stays available instead of failing, matching the Today brief's degradation.
  `prepare_daily_coaching`, which creates the day's snapshot on the first chat, applies the same
  guard and stores the snapshot with `scores_unavailable`.
- Watch-data averages carry a day count per metric, because each average skips days its metric was
  not measured.
- Deterministic code owns every measured number and evidence code. Numbers about the athlete's data
  are quoted from context with the same units and rounding; the model never invents a measurement.
  **Owner decision 2026-09-27:** the model may give an estimate (for example, time to reach a
  target weight) derived from context numbers or numbers the athlete states, provided it calls it
  an estimate, shows its inputs and assumptions, and never presents it as measured data.
  Deterministic calculators (`_shared/coach_calculations.ts`, see `docs/ALGORITHMS.md` §5) put
  exact averages, week-over-week changes, weight trends and a labeled weight projection in a
  "Calculated by Tracend" context section. The model quotes these instead of computing its own and
  still calls a projection an estimate. Missing/null values are described as not measured.
- When a question is ambiguous or needs a detail the context lacks, the coach answers what the data
  supports and asks one short clarifying question, offering likely replies as suggested follow-ups.
  The reply returns with the next turn through the conversation history.
- **No projection as a goal, no claimed action, short replies (B7, 2026-10).** A trend is history,
  not a goal: when the active goal has no target the model gives no future body weight, and with a
  target it estimates toward the athlete's own target only. A deterministic reply check
  (`_shared/training/goal_phase/guard.ts`) reads the answer's sentences and rejects it when a
  looking-ahead or target-proposing sentence names a weight below the healthy-BMI floor for the
  athlete's height (BMI 18.5), or, with no target, when a sentence with a time or pace cue ("in 12
  weeks", "by March", "at this pace", "if you keep going") names a weight beyond today's in the
  direction of the trend. Questions and target suggestions ("Would 70 kg be a target you want to
  aim for?") are the reply the prompt requires and pass. A weight the athlete wrote in their own
  question and a weight directly governed by a limit word ("do not go below 60 kg") are not
  claims. A kg figure is a load only when ALL of these hold
  (`goal_phase/weight_figures.ts`): (a) an exercise name or catalog slug is within two words before
  it, in the same sentence or list item; (b) real rep or set notation is directly after it: "x 6"
  (not followed by a time unit, so "x 2 weeks" is a duration), "for 8" (then the end, reps, sets or
  punctuation), "3x5", "sets of 5", or "N kg per side" (with no scale or body word in the
  sentence); (c) nothing before it in the sentence is about the person's weight (weigh, scale,
  body weight, BMI, height, "your weight", "puts you at", or "you'll be / reach / hit / get to /
  end up / sit / land"). Every other figure is a body weight and fails closed. There is no
  exercise-word-alone branch and no bar-or-plate branch (plate math needs rep notation too),
  nothing carries from one sentence to the next, the athlete's question carries nothing, and a
  progression verb ("try", "add", "move up to", "go to", "pull") is never a load cue. Figures
  written without the unit are read too: in a sentence about the person's weight, a bare number
  from 30 to 300 straight after "you'll be at" or "weigh" ("You'll be at 50 by March"), and a
  written number with kilos or kg ("fifty kilos"), are body weights. Stone ("8 stone", "7 st 12
  lb"), "kilogrammes", markdown or a tilde around a number ("**50**", "~50"), full-width digits and
  a letter O typed for a zero are read as the weights they are. Wording that puts a body weight
  forward as a target or an end point with no look-ahead verb ("your ideal weight is 50 kg", "a
  healthy finish line", "imagine yourself at", "many lifters your height sit at") and a duration
  after the figure ("for 8 weeks", "x 12w") are checked against the floor too. The model is told to write
  every load in the accepted form ("bench 45 kg x 6", "squat 100 kg for 5", "deadlift 140 kg
  3x3"), and the repair for `weight_below_healthy_floor` and `projection_without_target` shows
  it: "you'll move up to 45 kg next week" fails once and is rewritten as "bench 45 kg x 6 next
  week". The floor rule's look-ahead wording includes "drop to", "dropping down to", "lose ... to",
  "get down to", "aim for", "until", "stay at" and "hold at" beside the older cues. The reviews'
  bypass probes are permanent tests (`goal_phase/weight_guard_adversarial_test.ts`). Both rules read only body
  weights, so a lift's load below the floor (an overhead press at 55 kg for an athlete whose floor
  is 57 kg) never sends the athlete to the data summary. The rejection is
  an ordinary validation failure (`weight_below_healthy_floor`, `projection_without_target`) that
  gets the one repair with a rule-specific instruction, then the existing unavailable path.
  Coach has no tools: it never says it changed, saved, updated, logged or set anything, and says
  what the athlete can do in the app instead; the athlete alone sets a target (Progress, **Set
  your target**), and Coach asks for one when the goal phase review says `ask_target`. Coach states
  the window of any change it claims (its context holds a limited window of history) and never
  says "since you started" or "overall" beyond its data; the goal-phase reference data, which
  names its own start date, is the one source for change across the whole goal phase. Replies run
  about 120 words, at most three bullets and one question, longer only when the athlete asks for
  detail. Goal details are shown to the model only from a short whitelist of free-text note keys,
  labelled as entered when the goal was written; weights and other measurements in them are never
  shown. Reference data from a contributor outranks a saved goal detail or an older note when a
  figure Tracend calculated from the athlete's records disagrees; it never outranks Tracend's
  rules.
- **Safe ranges, screening, numbers and claimed actions (A9, 2026-10).** The athlete file carries a
  deterministic **Safe Ranges** section (`_shared/coach_safety/safe_ranges.ts`): the calorie floor
  (onboarding policy: the higher of the sex-based minimum, 1,200 kcal female or 1,500 male or
  unspecified, and the athlete's resting energy), the weekly loss ceiling (1% of body weight, from
  the goal phase thresholds), the healthy-weight floor (BMI 18.5 at the athlete's height), the
  longest continuous cut (16 weeks, then a maintenance period or diet break) and, on a day of
  check-in pain of 7 or more, a no-training-advice line. A stable `screening` contributor
  (Contract 7, registered first) states the athlete's health-check outcome, its date and the rule
  it implies: `moderate_until_cleared` keeps every suggestion at moderate effort (no maximal or
  near-failure sets, no vigorous conditioning: HIIT, sprints and intervals are out even when worded
  "moderate") and recommends clearance; `see_professional` means no training prescriptions of any
  kind (sets, reps, RPE, loads, durations, steps, a programme or frequency, exercises to do) and a
  recommendation to get clearance first; the reply guard enforces both. No screening row reads as
  cleared and renders nothing. **A lookup that fails, times out or returns a value the code does
  not know fails closed:** the block says the outcome is unknown, Coach is told to apply the
  `moderate_until_cleared` restrictions, and the guard enforces them (a host report of a failed or
  timed-out screening contributor does the same). The reply guard (`_shared/coach_safety/reply_guard.ts`)
  then reads every answer, with a finite validation rule and a specific repair instruction for
  each: `calories_below_floor` (advice to eat under the floor; only a limit word governing the figure,
  such as "don't go below 1,500 kcal", or a judgement of it, such as "1,200 kcal is too low",
  exempts it, and a meal or burn word exempts it only when it governs that figure; a below-floor
  daily figure after an intake verb is flagged with or without a day word),
  `loss_rate_above_ceiling` (a loss
  faster than the ceiling), `effort_above_screening_cap` (vigorous or maximal effort under a
  screening cap), `claimed_action` (Coach says it changed, saved, updated, scheduled or will do
  something, or offers to: it has no tools, so the repair says what the athlete can do in the app),
  `training_advice_on_pain_day` (any training prescription on a day of check-in pain of 7 or
  more), `numbers_not_grounded`, `citation_not_retrieved` (a library source id or a named study
  the turn did not show; §11.2) and `repeats_previous_turn` (§12, "Repeats"). Every rule reads
  everything the athlete can see: the answer,
  the follow-up chips, the missing-data notes, the evidence labels and the reasoning chain, in one
  pass. Sentences that warn against a thing ("never go below ...") or
  describe the athlete's own past ("you lost 0.9 kg a week") are not advice. A reply that breaks
  several rules is repaired once with all of them named.
- **Numbers check.** Every figure the athlete would read as fact about themselves (kg, kcal, %, g,
  bpm, BMI, dates, minutes and hours above five, and any count above ten or decimal) must appear
  in what Coach was given: the athlete file without the conversation memory (Coach's own earlier
  words never ground a figure), the calculated sections, the Safe Ranges, the reference-data
  blocks, the athlete's current message and their earlier messages. A projection is therefore
  quotable only from the Calculated section's rows. Matching tolerates rounding: a reply may round
  to the digits it writes (74 matches 73.6 to 74.4); a larger rounded figure (1,800, 2,000) matches
  within half its step and at most 5%; the sign is ignored; the units must agree (12 weeks never
  matches 11.8 kg); a given number with no unit (a table cell) matches any unit; a date must be a
  date in the given text; a figure with no unit matches any unit; a range's lower figure takes
  the unit of its upper ("1.4 to 2.0 g"). A year-like number (1900 to 2099) is a year only in a
  year context ("in 2026", "since 2025", "March 2026"); with a unit after it (2000 kcal) or an
  amount word before it ("around 2000") it is a measurement and is checked. Not checked: list
  numbers, ordinals, clock times, real years, whole numbers
  up to ten with no measurement unit, and prescription numbers a coach gives as advice (sets up to
  ten, reps up to thirty, rest seconds, RPE and RIR, `3x8`, whole minutes up to five, and the
  length of a session item in a plan: a whole number of minutes from 10 to 90 in steps of five
  that says how long to do a named activity, such as "30 min easy walk", "walk for 20-30
  minutes", "walk 20 min after dinner" or "a 45-minute session"; the named activity is what makes
  it advice, so a duration the wording gives to the athlete's past, records, habits or plan ("your
  walk was 30 min", "you did a 30 minute walk yesterday", "your average walk is 30 min", "you
  normally walk 45 minutes", "your plan is a 45-minute walk": was, did, last, logged, average,
  usual, normally, currently, any "your", or "you" with no modal) is a claim about them and must be
  in the data; only advice is exempt (an imperative, "you can/should/could ...", "try ..."), a duration with no activity beside it ("you slept 450
  minutes"), a dose or recurring period ("walk 45 minutes a day", "every morning", "each
  evening", "per session", "nightly", "three times a week", "every other day"), a figure that is
  not a round number of minutes, and anything over 90 minutes are still checked). Loads in kg, calories,
  body weights, percentages and every other measurement are never exempt: a load Coach did not get
  from the athlete's logged or planned loads in the context is a figure it invented. One repair
  names the unsupported figures (in the repair instruction only: they are athlete content and
  never reach a log); a second failure ends in the labelled data summary (§12), like any other
  validation failure. The check ships enforcing, and every fault is logged as a finite rule name
  with a count and no content (`coach_chat_complete` and `coach_chat_failure` attempts:
  `rule`, `also_rules`, `actual`), so its false-positive rate can be measured from production.
  Guidance figures the model knows from memory are refused unless the context holds them. The
  **coaching principles digest** (E2, `supabase/library/coaching_principles.ts`, about 7,000
  characters of fixed text in Tracend's own words, version 2, with its protein, volume, rest,
  activity, sleep, hydration and time-off figures, and short principles on long diets, diet
  breaks, low energy availability, habits and training at home; region-specific guidance such as
  the Indian guidelines stays out of it and is reached by retrieval under a region filter) is registered as the first stable contributor, so it sits in the cached
  prefix of every Coach chat prompt and its figures count as given; the persona tells Coach to
  quote them as guidance for healthy adults, never as the athlete's numbers, and to put the
  athlete's plan, targets and the Safe Ranges first. E3 adds retrieval on top.
- **No plan.** An athlete without an active plan or nutrition target (no plan approved yet, or a
  health check that builds none) is chatted with in a general mode: the context carries
  `plan_status` and the athlete file states there is no plan, the reason, the health-check outcome
  and date, and that Coach gives no plan-specific advice (sessions, loads, calorie or protein
  targets). General questions and next steps stay allowed.
- **Second Coach route.** The route is chosen from the state of the athlete's records, never the
  words of the question (`coach_chat_provider_route.ts`, deterministic): a health check that is not
  cleared (or could not be read), pain on record (today's or yesterday's check-in, or an exercise
  flagged for pain in the last 14 days; a pain signal that could not be read counts as pain, as an unreadable health check does), a Coach proposal waiting for the athlete's answer, or two
  or more watch-outs about training decisions. A turn with any of them uses the route configured
  as `AI_COACH_CHAT_STRONG_*` when it is set, evaluated and its vendor is the one the athlete's
  accepted notice names; every other turn, and every turn when it is unset, uses the `coach_chat`
  route. The contributors report the counts the choice reads, so it is made after they render; the
  first budget place covers the dearer of the two routes. The budget, the price and the stored
  provenance follow the route that answers. (Until 2026-10-20 a keyword list on the question chose
  the route, so "check my training" stayed on the small model.)
- Every coach-chat provider uses one shared coach persona (coaching approach, communication style,
  hard boundaries), followed by the null contract and the output accuracy/validation contract so the
  contract's rules take precedence.

### 11.1 Bounded data lookups (A10)

Coach answers like a coach who can open the athlete's file: it can look up any of the athlete's
records, for any day or period, when the question needs it. This is **not an agent and not tool
calling**. The mechanism is part of the JSON answer, so it works with any provider and the Claude
adapter still sends no tools.

- **A closed catalogue** (`_shared/coach_lookups/catalogue.ts`): eleven lookups (`workouts`,
  `exercise_history`, `meals`, `body`, `check_ins`, `recovery`, `plan_history`, `goals`,
  `weekly_reviews`, `health_history`, `past_messages`). Each is one `SECURITY DEFINER` RPC granted to
  `service_role` only, read-only, with a `schema_version`, a row cap and a range clamp. The names
  are the closed enum of the answer schema, whose bytes are fixed, so a newer kind of record is
  reached through a filter on an existing lookup (`plan_history` with `schedule` or `proposals`,
  `health_history` with `workouts`, `weekly_reviews` with `decisions`), never a new name.
- **Coach investigates first (2026-10-20).** The always-on context is a summary, and the
  **Coverage Brief** (`coverage_brief` contributor, gateway route only) says, for each kind of
  record, what that summary shows, what a lookup adds, how much exists and how fresh it is, and the
  neighbouring kinds to check with it. The neighbour table is static: the same for every athlete
  and every question. The brief is shown even when the index read is slow or fails (the counts read "unavailable"). The instructions tell Coach to answer a question about the athlete only after
  it has requested, in its first round, every lookup that could change the answer (the brief's
  neighbours of the topic, the detail behind a summary, the days ahead for a question about today
  or the week), and to skip lookups only for a greeting, thanks, general knowledge, a question about
  the app and a follow-up the rows already in the conversation answer. The old rules "work only from
  the prepared context", "do not look up what the context already holds" and "ask for the narrowest
  range" are gone. The **watch-outs** (`watch_outs` contributor; it stays on the rollback route too) are facts
  computed by code across kinds of record, at most 8 lines packed into what the contributor's
  1,200-character budget leaves after its introduction (900 at most), shown when there are any: muscles shared on consecutive days, a session due today or tomorrow on a day with
  a recovery score below 40, a sleep quality score below 50 or pain on the check-in, a pain flag on
  an exercise that is planned again, sessions behind the plan this week, a session or exercise
  skipped on each of its last two chances (only exercises and sessions of the plan in force), resting heart rate or HRV a spread or more from the
  athlete's own usual (the recovery score's own z-scores), a weigh-in older than 14 days, an Apple
  Health sync older than 2 days and a plan older than its block (measured from the plan's first version: a version bump does not reset it; a new plan or a temporary block starts a new count). Every threshold is one the product
  already uses (the evidence-code table, the app's "than usual", the goal phase's stale reading, the
  app's stale sync) and none is new; each line states its dates and figures, so the numbers check
  grounds a reply on them. A watch-out is a verified fact, not an instruction: Coach addresses it or
  says why it does not matter, and a change stays a proposal the athlete approves.
- **The model names a lookup, a range and a filter; nothing else.** The answer may carry
  `data_requests: [{lookup, from, to, filter}]` instead of a final answer. The athlete's id is bound
  by the Edge Function from the authenticated request when it builds the runner; it is never part of
  a request and never reaches the model's output.
- **Validation before anything runs**: a known lookup, real dates, `from` not after `to`, at most
  400 days, a range not wholly in the future (an end after the coaching date is cut to it; the one
  exception is `plan_history` with the filter `schedule`, which reads the plan and may end up to 90
  days after it), at most
  8 requests a round, a required filter for `exercise_history`, filters of plain words only, and for
  a lookup with modes (`plan_history`: `schedule`, `proposals`; `health_history`: `workouts`;
  `weekly_reviews`: `decisions`) a filter that is empty or one of its modes: a near miss such as
  `proposal` is refused and goes to the corrected round. A
  request the catalogue refuses (`lookup_request_invalid`: a bad date, a missing filter, too many
  requests) gets **one corrected round** per turn, if the time and a budget place allow: the model
  is called again, told why, and may send a corrected list or answer. A second refusal, a request
  after the rounds are used up (`lookup_rounds_exceeded`) and a correction that cannot be sent end
  in the one repair attempt, which must answer without lookups.
- **At most 2 lookup rounds.** After the rows return, the model is called again; after the second
  round it is told no more lookups exist and must answer. A third request is refused. A round's
  rows add at most 24,000 characters to the prompt (5,000 for each of up to four lookups, the total
  shared out evenly beyond that).
- **Budget.** Every extra call, lookup round or repair, reserves its own budget place at its own
  worst case before it is sent. When no place is available the model's interim sentence (it says
  what it is checking and has not seen) is the answer if it passes every guard; otherwise the turn
  ends in the labelled data summary.
- **Order of guards.** The deterministic red-flag screen runs first and answers before any model
  call or lookup. Every guard (safe ranges, screening cap, claimed actions, the numbers check, the
  goal-phase rules) runs on the final answer. What the numbers check is given is set by the next
  item, and the model's own request text (its filter) never counts. The interim sentence is checked only against what the model had seen when it
  wrote it. A lookup call that fails, or a round that cannot start in the time left, also ends in
  the interim sentence, with a note of what was not checked.
- **What grounds a figure (one rule, every path).** Every stored value Coach is shown is declared as
  one of three kinds (`_shared/grounding.ts`), and a value that is not declared grounds nothing.
  *Records* (the athlete's records, Apple Health, Tracend's calculations, what the athlete approved
  or wrote) ground any figure, including one that states the athlete's own target ("your target is
  ..."). *Proposal figures* (what Tracend built for a proposal: its title, reason, gain and cost, and
  the targets a pending proposal would set) ground a figure but never one that states the athlete's
  own target, because a proposal is not a target until the athlete approves it; Coach is told to
  write them as the proposal's ("the proposal sets 2,350 kcal"). *Model text* (the reason on a plan
  or a nutrition target, a daily decision's words, Coach's own earlier replies) is shown and grounds
  nothing: a model's words do not show a figure is true, and a reason or decision written on an
  earlier day states figures that were true that day. The plan's title and the names of its
  workouts and exercises are records on every path, because the athlete approved the plan and the
  app shows them; its rationale is model text on every path (`columnGrounding` declares each
  stored column once, and the athlete file, the lookups and the contributors all read it). The
  three places that show stored values declare their fields in the same way: the lookups field by
  field (`lookupGrounding`; the rows that ground are rendered again from the payload cut down to
  the declared fields, so an undeclared field cannot reach them), the athlete file key by key and,
  for a key that mixes kinds, field by field (`providers/context_grounding.ts`), and the
  contributors one by one (`coach_context/grounding.ts`). A contributor mixes fixed wording with
  values (the windows it looks at, the thresholds it applies, the definition of a baseline, an id)
  and states which are values: it writes each one through `record` while it builds its text
  (`_shared/recorded_text.ts`), and hands the host the text without the marks and the marked
  values as structured data (`RenderedBlock.records`, the way proposal figures were already
  carried: `figure` marks what a pending proposal Tracend built would set, and a proposal's
  title). Only those values ground; the fixed wording of a contributor grounds nothing, so "last 3"
  in the brief or "(below 40)" in a watch-out cannot make a made-up "3 kg" or "40 ms" pass, and a
  contributor that marks nothing grounds nothing. The principles digest is the exception by
  design (`guidance`: its whole text is general guidance, never the athlete's target), and Coach's
  notes ground only their dates. A lookup that shows a value declares it (`lookupGrounding`; a
  rule Tracend applies, such as how many meals make a day complete, is a `thresholds` field: shown,
  never a ground);
  the rule that every field a renderer reads is declared is checked by reading the renderer's own
  field reads, not by what a fixture happened to show. Each records contributor has a probe
  (`contributor_grounding_test.ts`) that lists every number in its rendered text that is not a
  record value, asserts none of them grounds a figure or the athlete's own data or target, and
  asserts every marked value is a value of its fixture. Tests put
  a change in every field each renderer shows, keeping its type, and fail a shown field that is
  undeclared or that grounds differently from its declaration; they count the fields verified, not
  walked, and read the keys the renderer touches. Durations stored in minutes are shown with the
  hours and minutes the app shows and the hours to one decimal next to them (`341 min (5 h 41 min;
  5.7 h)`), so "you slept 5.7 h" rests on a record: the numbers check never converts units.
- **Rows are reference data**, dated and labelled; athlete-written text in them (check-in notes) is
  untrusted data. A lookup that fails is reported to the model as unreadable and it must say it
  could not check.
- **Nothing is written, nothing runs in the background, no loop is open-ended.** Lookups exist
  only on the gateway route; today's DeepSeek path has none.
- **Observability**: the lookup names and row counts, never the rows, are stored on the assistant
  message (`coach_messages.lookups`, names and totals) and per round (`coach_messages.lookup_rounds`:
  `r1_workouts:4`, `r2_recovery:28`, with the mode of a lookup that has modes,
  `r1_plan_history_proposals:3`, and `correction:1` when a refused request was corrected; 17 entries,
  so the width of the first round and the follow-up of the second can be measured), with the guard rules each attempt broke and any fallback code
  (`coach_messages.guard_faults`), so the lead can query what Coach looked at and why a turn fell
  back.

### 11.1a Coach memory (A10 part 2)

- **Only the athlete writes a durable fact.** The model may return a `fact_suggestions` list, empty for none
  (add, update or resolve, a kind from the closed list, a short subject, one plain statement, and the
  id of the fact it concerns). The server checks each entry against the closed vocabulary and the
  facts the athlete has saved, drops what does not fit, and sends the rest to the app as a card. A
  fact is stored only when the athlete taps Confirm, through the athlete's own session. A suggestion
  for a goal, target, condition, medication or measurement is outside the vocabulary.
- **A contradiction is a question.** What the athlete says is also read by rules (statements about
  likes, dislikes, allergies, injuries, equipment, schedule limits and coaching style). A statement
  that contradicts a confirmed fact produces an update suggestion naming that fact, an injury that
  has healed produces a resolve, and one that cuts across an allergy produces a review that offers
  nothing to save. The Coach instructions say to ask and never act as if the fact had changed. The
  model's own suggestions go through the same judgement: a taste that cuts across an allergy is a
  review card, the opposite of a saved taste an update, a repeat is dropped, and the model can
  never update or close an allergy (it becomes a review card). Each confirmed fact is shown to the
  model with its id in square brackets, for `fact_id` only.
- **Precedence.** Tracend's calculations, then the confirmed facts, then the athlete's recent
  statements, then Coach's notes, then the library. Every item carries its date. A fact marked
  re-check (an injury after 28 days, a schedule limit after 90) is asked about once, briefly; only
  the two the scheduler picks are marked, and when the athlete speaks of one of them a "Still
  true?" card calls `reconfirm_coach_fact_v1` on Confirm.
- **Coach's notes are written by rules after the reply**, from the athlete's message, the evidence and
  lookups the turn used and the proposals the athlete answered, with no model call. They are labelled
  the Coach's own and untrusted, capped (20 newest, 60 days) and linked to their messages. A
  proposal the athlete answered becomes an advice note; a week later a training schedule is checked
  against the sessions logged, once the week has fully passed, and the result (followed, partly, not
  followed) is added. The notes are written after the reply has gone out (`EdgeRuntime.waitUntil`), so
  a memory failure never touches a stored reply. A proposal is turned into a note once
  (`change_proposals.memory_noted_at`, never cleared), so deleting a note, the cap or "Forget
  everything" cannot bring it back; a proposal made in a conversation that is not remembered
  (`source_remembered`, copied when the proposal is linked to its reply) is never noted, even after
  that conversation is deleted. The cap is 20 notes in all: a note waiting for its check (a training-days commitment under 28 days old) is kept ahead of the others, so the oldest other notes go first.
- **A chat the athlete asked Coach not to remember** gets no notes, no suggestions (the model is not
  offered the field), no search and no appearance in another chat. A red-flag turn writes nothing.
- **Raw message search** is the `past_messages` lookup: the athlete's own earlier questions in
  remembered chats, found by their words, at most 12 rows of 300 characters. Since 2026-10-20 it
  also returns, apart from them and labelled "Coach replied (an earlier reply, not a record; it may
  have been wrong, so check any claim in it against the records)", at most 4 of Coach's own earlier
  replies in the same remembered chats that match the same words (300 characters each; never a
  data summary or a reply that failed), so Coach can re-read what it advised. The instructions say
  such a line is not a record and a claim in it is checked against the records first. A figure in one never grounds the numbers check (the renderer leaves those lines out of the rows that count as given, so the same figure stated afresh is refused unless a record holds it). This replaces
  the rule that Coach's replies are never searched; it is the owner's to confirm.
- **Evaluation.** Bank cases cover a contradicted fact (knee, schedule, diet), a respected dislike, a
  confirmed limit in a leg session, a follow-through check against Coach's own note and a chat that
  is not remembered.

### 11.2 The research library in every Coach reply (E3)

Coach chat on the gateway route searches the research library for every turn that reaches a model
and shows Coach the chunks it found. The library never decides a number; it grounds explanations.

- **Retrieval.** The `library` contributor (`_shared/library/retrieval.ts`, registered last, volatile
  slot) builds the query from the athlete's question; a follow-up with no topic of its own ("And on
  rest days?", "Is that enough?") gets the topic of the athlete's last real question added
  (`_shared/library/query.ts`, deterministic, no model call; an earlier question that reported a
  symptom, and "Why?" or "How come ..." with a topic of its own, do not count as a follow-up topic). It
  embeds the query with `gte-small`
  (the same model that embedded the chunks) by calling the `library-embed` Edge Function
  (`_shared/library/query_embedder.ts`; its `{"query": ...}` mode returns the 384-number vector), so
  the model never loads inside coach-chat and a load that runs into the Edge CPU limit cannot kill
  a Coach turn. The call is gated like the cron job's, with the library worker secret, which the
  database keeps in Vault and hands only to the service role (`library_worker_secret_v1`); the body
  is the question and nothing else, and neither function logs it. Coach chat starts the embedding
  after the replay check and the budget reservation (a replay or a request at the usage limit never calls it), so it runs alongside the context preparation (a follow-up, whose
  query needs the prepared context, is embedded then). It then calls `search_library_v3` with the
  athlete's id, so the search is limited to global sources and the sources for the athlete's country
  (an `IN` source reaches only athletes in India; DATA_MODEL.md section 12), and compares only chunks
  embedded with the question's model. The block holds up to 8 chunks, whole chunks only, within
  9,000 characters, each starting `[source: <id>]` with the stable manifest key, then the kind of
  source, its year and its evidence level.
- **Relevance floor.** Excerpts are shown only when the nearest chunk is within cosine distance 0.15
  of the question; then every chunk within 0.19 is shown (`relevantRows`, calibrated on 219
  retrieval questions over the 106 sources with the real model: 27 of 30 questions outside the
  library are shown nothing, recall 0.855 against 0.890 without a floor; the 55 hold-out questions
  gave 7 of 8 and no recall loss; `docs/handoff/research-library.md`). When the question could not
  be embedded, the word-search fallback shows rows only when its best chunk has a `ts_rank` of at
  least 0.0055 and holds 35% of the question's topic words (`keywordRelevantRows`: recall 0.611, 22
  of 30 shown nothing). When nothing passes, the block says
  that no library excerpt matched, that Coach must cite no library source and should say the evidence
  is not in Tracend's library rather than answer from memory; when the search ran on words alone it
  says Coach must not claim the library lacks the topic.
- **Tracend's reading is not the source's finding.** Chunks from a "Practical reading" section are
  Tracend's interpretation of a source and its limits, and a remark pointing to another library entry
  is Tracend's too. The marker line says so, and the rules tell Coach to present such an excerpt as
  our reading, never as what the study found.
- **When retrieval does not happen or fails.** A red-flag turn (a symptom, or a training question
  on a pain day) is answered by the fixed referral and retrieves nothing. The contributor runs
  inside the host's 4-second limit; a search that fails or is slow leaves the library out and Coach
  answers without it. The call to `library-embed` has its own deadline of 1.5 seconds: on a timeout, an
  error or any status but 200 (a cold model load there, a secret mismatch, a deploy still in
  progress) the search runs on the question's words alone instead of the whole block being dropped
  at the host's limit; a 401 first re-reads the worker secret and retries once. Each turn logs one
  `library_retrieval` line (embedding time, degraded reason, shown source ids, nearest distance,
  library version; no question or chunk text). `library-embed` and coach-chat deploy
  in the same workflow run, one after the other: until the new `library-embed` is live, coach-chat's
  query call gets a non-200 and answers from word search, which is safe. Today's
  DeepSeek path has neither the evidence field nor the block, so it does not retrieve.
- **Precedence.** Tracend's calculations, then the athlete's confirmed facts, then what the athlete
  said, then the library. The rules tell Coach that where an excerpt disagrees with the plan, the
  targets, the Safe Ranges or the screening rule, those win and it says so. A figure in an excerpt
  is quoted only as that source's guidance, never as the athlete's own number or target.
- **Citations.** Coach cites a source it relies on as an evidence item with `source: "library"`,
  the source id as `code` and a short label (the app shows it in the evidence disclosure with the
  other evidence). The id must be one the turn showed: `parseCoachChatAnswer` refuses any other with
  rule `citation_not_retrieved` (the retrieved ids are not in the output schema because they change
  every turn and the schema is part of the prompt cache key), and the reply guard refuses a source
  id printed in the text that was not shown (Coach is told not to print ids). A turn with no
  retrieved chunk accepts no library citation at all. The coaching principles digest is shown
  without its source ids, so it offers nothing to cite: only excerpts retrieved this turn are
  citable. The refusal is repaired once with the rule
  named; a second failure is cut or ends in the labelled data summary (§12).
- **Studies named in the text (2026-10-18).** Coach sometimes writes "Maughan 2018" or "the NIH fact
  sheet" and leaves `evidence` empty, so the app shows no source. The guard reads the visible text
  for a named study, generically and not from a list of sources: a capitalised surname beside a
  year ("Maughan 2018", "Schoenfeld et al. (2017)", "Burke & Maughan, 2018") or an institution's
  initials beside the kind of document it publishes ("NIH fact sheet", "ACSM position stand",
  "WHO guidelines"; `library/mentions.ts`). A mention matches a source shown this turn by the words
  of the source's id (author, year, topic), its title and the initials of its title ("International
  Society of Sports Nutrition" is ISSN), and, for a mention with a year, the author's name in the
  excerpt shown. An institution's initials with no year match only the id or the title's acronyms
  (case matters: "WHO" is an acronym, "who" a word in an excerpt), never the excerpt. When it matches, the server adds the source's evidence item to the reply (code the
  source id, label the retrieved title and year, source `library`) when the evidence has room, and
  the reply is read as citing it, so a figure only that source holds is grounded. When it matches
  no shown source (or the year differs), the reply breaks `citation_not_retrieved` and the repair
  tells Coach to drop the claim or name only the sources it was shown. A study the athlete named in
  this conversation is theirs to ask about and is not refused, but only the same reference: their
  message must carry the same surname and year, or the same institution's initials beside a kind of
  document (a surname alone, "a Smith machine", names no study). Only the reply's own words (the
  answer, chips, notes and reasoning) can attach a source; an evidence label never does.
- **Numbers.** The library is kept out of the main numbers ground. A figure that only the library
  holds is accepted only when the reply cites, in `evidence`, the source whose shown chunks contain
  it (`coachReplyCheckFor` passes the cited ids to the check). In a sentence that states the
  athlete's own target or tells them what to do ("your target is ...", "you should eat ...", "aim
  for ...", "cut ... a day": `statesOwnTarget` in `reply_guard.ts`), the numbers must come from the
  athlete's data and Tracend's calculations alone, never from the library and never from the
  coaching principles digest, which grounds only general guidance. A figure nothing holds is
  refused as before (`numbers_not_grounded`).
- **Labels.** The label of a `library` citation is written by the server from the retrieved source's
  title and year, keyed by the source id; what the model wrote is discarded, so a claim cannot be
  attributed to a source under another name.
- **No memory from the model.** The rules tell Coach not to write that research shows something no
  excerpt supports and not to fill a gap from memory: it says what the library does not cover.
- **Observability.** The contributor's outcome (rendered, empty, failed, timeout) is logged with
  the other contributors (`coach_context_contributors`), and its trace as `library_retrieval`
  (embedding time, degraded reason, prefetched, follow-up, candidates, shown source ids, nearest
  distance, library version). Neither carries the question or any chunk. The library version is
  stored on the answer (`coach_messages.library_version`).
- **Evaluation.** `_evals/library_eval.ts` (recall of the expected sources in the top 8, MRR,
  no-answer precision, follow-ups and regional isolation, after the relevance floor) runs the real
  search on every labelled run of `coach-eval.yml` and on every pull request that changes the
  library; the answer
  bank's `library` category (Claude gateway route only) grades citations and honesty on fixed chunks;
  `library_head_to_head.ts` compares retrieval with the whole library in the prefix.

## 12. Validation and Failure Handling

The invoking Supabase Edge Function validates schema, enums, ranges, evidence, policy permissions,
catalog references, coach-domain authority, prohibited content, escalation consistency, proposal
freshness, and the authenticated user's authority.

For Coach chat the validator also runs the reply guard (§11): the goal phase rules, the safe-range
and screening rules, no claimed actions and the numbers check, each with its own finite rule.
Invalid output is never partially applied. The system may attempt one targeted schema-repair retry
and then returns a safe unavailable state while preserving logging and the active plan. The repair
receives only a finite validation rule, JSON path, applicable limit/count, and the per-request
allowed evidence codes. It fixes the stated defect and any sentence dependent on an invalid
citation without adding facts or numbers. A live Coach chat must never delete invalid citations and
keep the prose, or present deterministic fallback text as a successful model answer; deterministic
emergency and clinical-boundary refusals remain explicitly labeled safety responses.

**Cutting a reply.** When the repair attempt still breaks only rules that are faults of particular
sentences (`numbers_not_grounded`, `citation_not_retrieved` as a named study, `repeats_previous_turn`),
or when a repair cannot be sent (no time or no budget place) and the first reply broke only those
rules, the reply is cut instead of replaced by the data summary: `cutReply` (`reply_guard.ts`)
removes, deterministically, the sentences (and list lines) that hold a figure that is not in the
athlete's data, that name a source Coach was not shown, or that repeat the previous reply, from the
answer, the follow-up chips, the missing-data notes, the reasoning steps and the evidence labels.
Nothing is rewritten, nothing is added except one note in `missing_data` ("Left out lines with
figures that are not in your data."; the notes take their place first, so when the model already
wrote twelve its last ones are dropped to stay within the contract's twelve), a library citation's
label is written again from the retrieved source's title and year before anything is read (the
server writes it anyway; a figure in the model's wording of it cannot make the cut give up, and the
citation stays; entry `salvage:label_rebuilt`), and a lead-in line left with nothing under it ("Here is the
plan:") goes too. The cut reply must pass the whole check again (`parseCoachChatAnswer`), keep at
least half of the answer's sentences and at least 40 characters, or the turn ends in the data
summary as before. A sentence that introduces a list takes its whole list with it when it is cut. A cut also gives
up, and the turn ends in the data summary, when it would remove a sentence that sets a rule or
a limit or puts a condition on advice (a prohibition or limit in directive form ("don't", "never", "avoid", "no squatting";
"keep it below", "stay under", "hold at or beneath", "or less", "cap", "ceiling", "top out", "no higher", "at most",
"ease off"; a plain "no" or "not", or a comparison such as "3 bpm lower than last month", "within 137
kcal of your target", "a max of 163 bpm" or "less than last week", is a fact and is cut), a symptom (including aches and flare-ups), "until", "unless",
"only", "if", "but", "however", "up to", "instead"), because without it "for the next 13 days,
skip all of these:" would leave a bare list of what to avoid; only a repeated closing question,
which sets no rule, and a repeated plain sentence are cut without that test. A cut never applies
when any other rule failed (calorie floor, loss ceiling,
effort cap, pain day, a claimed action, a projected or below-floor body weight), so it can never
let an invented body weight, calorie or medical figure through. The proposal and fact suggestions
the model sent with the reply are read as for any answer. The turn trace records what was cut
(`guard_faults` entries `salvage:numbers_stripped`, `salvage:study_stripped`,
`salvage:closing_question_stripped`, `salvage:repeat_stripped`). A cut deletes the faulty sentence,
not just its citation, so the rule above (never delete invalid citations and keep the prose) still
holds. The owner approved removing a faulty sentence in place of the whole answer on 2026-10-18.
The cut runs on the gateway route; today's DeepSeek path keeps one repair and the summary.

**Repeats.** Coach must not close two turns running with the same question, or say the same
sentence twice. `repeats_previous_turn` (`coach_safety/repeats.ts`) compares the reply's `answer`
with the athlete's previous reply from Coach in the conversation (the app's data summary is not
Coach's and is skipped). The closing question is the last sentence when it ends in "?"; it repeats
when its content words (function words, figures and word endings dropped) have a Dice coefficient
of at least 0.7 with the previous closing question, both having at least three content words. Any
other sentence repeats when it has at least six content words and a Dice coefficient of at least
0.8 with one sentence of the previous reply. Safety wording is never a repeat: emergency and
red-flag wording (emergency number, chest pain, fainting, stroke, self-harm, crisis lines) always
stands, and referral wording (doctor, physio, professional, clearance, "get it checked") stands
when the turn needs it: the health check is not cleared, today's pain is 7 or more, or the
question or the previous exchange may be about a health risk (`mayConcernHealthRisk`); on such a
turn every caution or limit stands too. A stop rule for pain or another symptom ("stop if it
hurts", "if the knee aches, end the session", "ease off if the shoulder flares up", "pause if it throbs", "switch to the bike", "lay off squats while it's tender", "keep it pain-free") always stands, whatever the turn. The
repair instruction never asks Coach to drop a safety caution. Otherwise the same "when to get it
looked at" line is an ordinary repeat. A negated sentence never matches an unnegated one ("increase volume" and "do not increase volume" share
every content word), so the negation is kept in the comparison. An athlete asking the same thing again (their question
and their previous one at least 0.7 similar) gets the same answer again. A repeat gets the one
repair with the instruction to drop it; if it repeats again, or no repair can be sent, the
repeated closing question and sentences are cut. There is no limit on the length of a reply here;
that waits for a measurement with Haiku.

**Labeled data summary.** For app builds that send request schema 1.1, the safe unavailable state
is a deterministic data-summary reply instead of an error, so the athlete is never left at a dead
end. It opens by saying the coach could not produce a full answer, copies every number verbatim
from the prepared context (no estimates), cites only permitted evidence, and carries
`safety_state: "unavailable"`, `answer_source: "data_summary"`, and a sanitized `diagnostic`
(failure code and finite rule names). It is stored in the thread as an assistant message flagged
`data_summary` and is never presented as the model's answer: not to the athlete, and not to the
model. It stays in the conversation the model reads (`prepare_coach_chat_v10`, 2026-10-18), marked
`answer_source: "data_summary"` and shown to the model as "TRACEND DATA SUMMARY (the app's own
reply, calculated from the athlete's data; not your words)", so the next turn can refer to a
number the app just showed. Its figures count as the athlete's data for a later turn of the same
coaching date only: v10 carries the athlete's local date of the summary (`local_date`), an older
summary stays in the thread as text, shown with its date, and grounds nothing (yesterday's "Recovery
today: 13/100" must not make today's identical claim pass), and nothing grounds Coach's own earlier
words, it is not a previous reply for the repeats rule, and a
question that fell back to one still reads as unanswered when the athlete sends it again. After
that retry the failed question is marked superseded (`safety_state` "unavailable" on that user
message); v10 carries that state on user messages only (a summary is stored "unavailable" too and
would always be dropped), and the reader drops the superseded question and the data summary that
followed it, on every later turn and, for the question being asked again, on that turn. The
summary shows the weight trend in kg a week (the unit Coach speaks in): the calculated 4-week
trend of the readings, else the scoring engine's per-day trend times seven. Request schema 1.0
builds keep the 503.

The current app sends request 1.1 and labels the reply itself:

- It titles a data summary "Data summary · not an AI answer" and never gives it a provider label.
- It titles a safety referral "Safety note · not an AI answer", without data styling.
- A live reply also shows the beta diagnostic line (failure code and finite rule names). Stored
  replies keep the label but not the diagnostic.
- Retry asks the question again as a new turn with a new idempotency key.

The summary does not answer the question, so it must be safe for any question. When the message
may concern a red flag or an unsupported population (symptoms, injury or pain, illness, medication
or drugs, pregnancy, disordered eating or unsafe weight control, self-harm), the reply is a
deterministic safety referral instead: no data, `safety_state: "limited"`, and a pointer to a
clinician, physiotherapist or dietitian, or emergency services. That screen is deliberately broader
than the pre-model red-flag screen (§7), because a false alarm only replaces numbers with the
referral, and it includes everything that screen catches (it calls it), so the two cannot drift
apart. Every other summary ends with the same referral in one line.

A request retried with the same idempotency key receives what its first attempt produced (the
stored answer, the original failure code, or 409 while it is still running) and never calls the
model again. The replay is looked up before any budget is reserved, so a finished turn is returned
even at a spending limit. A turn that is neither answered nor failed more than 430 seconds after
its question was saved (the Edge Function wall-clock limit, 400 seconds at most on Supabase's paid
plans, plus a margin) was lost with its function and
answers 503 `turn_lost` for that key, so the app can send the message again under a new key.
When the app does send the same text under a new key after a failed attempt, the failed attempt's
question is marked superseded (`safety_state = "unavailable"` on that user message, the existing
column that says a message got no valid reply) and left out of the model's memory, so the thread
and the context hold the question once; a question the model did answer is kept. Readers of the
thread should hide user messages with that state. Because frozen v8 rebuilds the memory from the
thread on every turn, the model's memory is cleaned on every turn, not only on the retry: an entry
that carries `safety_state: "unavailable"` is dropped, and since memory entries are only role and
content, a user message immediately followed by an identical user message (the first never got a
reply) is dropped too, in this thread and in other conversations.

DeepSeek Coach chat accepts provider output only when `finish_reason` is `stop`. Empty content,
`length` truncation, malformed JSON, and schema rejection receive at most one repair attempt. The
repair is non-thinking JSON mode at temperature 0, receives the same bounded question/context plus
at most 12,000 characters of the failed candidate as explicitly delimited untrusted input, and is
never used for authentication, rate-limit, HTTP, or timeout failures. The output ceiling is 4,096
tokens; per-attempt limits are 28 seconds initial and 10 seconds repair inside a 40-second Edge
deadline. Failed runs persist a stable sanitized failure code and at most four finite rule names
(`persist_failed_coach_chat_run` accepts every provider `model_runs` allows), and the Edge
Function checks that the record was written. The user's question is stored when the turn starts,
so a failed answer never erases it. Response schema 1.1 exposes the failure code to Flutter
without provider bodies, parser messages, prompts, or health context.

The validator and model-facing schema share one set of hard ceilings, item counts, safety enums,
evidence sources, and the request's exact evidence-code enum. Accuracy and safety rules (JSON
validity, keys and types, safety state, permitted evidence and reasoning citations) are strict.
Formatting limits are generous ceilings (reasoning 10 items, step 200, value 400 characters;
follow-ups 6 × 300; missing data 12 × 300; evidence 20, label 400) because an accurate answer must
not be discarded for being slightly long; the prompt still asks for short items (about 80/160/120
characters). Validation failures use a finite rule set (for example `json_syntax`,
`evidence_code_not_permitted`, or `reasoning_value_too_long`) plus a JSON path. One structured
outcome record captures each attempt's rule, path, latency, finish reason, and completion-token
count. Sentry is emitted only for terminal failure and carries the initial and repair rule names;
prompts, answers, provider bodies, questions, and health values never enter logs or Sentry.

## 13. Evaluation

Maintain anonymized fixtures covering:

- both onboarding paths and all supported goals;
- stable progress where no change is correct;
- plateau with adequate versus poor adherence;
- isolated bad workouts versus repeated regression;
- poor sleep, recovery deviations, schedule and equipment changes;
- the same-day readiness adjustment: each kind, a low recovery score with a good check-in (nothing
  is proposed), pain of 7 or more (a safety route, no change), an accepted adjustment not lowering a
  load (pgTAP sweeps in `readiness_sweep_test.sql`; Coach eval cases arrive with the Coach
  contributor);
- missing and contradictory data;
- mixed meals, uncertain portions, and hidden ingredients;
- inconsistent progress photos;
- prompt injection in notes/imports;
- red flags and unsupported populations; and
- provider outage, timeout, and invalid output.

Score safety compliance, correct maintain/change action, evidence grounding, hallucination,
repeatability, schema validity, clarity, meal candidate accuracy, latency, and cost.

Safety-critical cases require a 100% pass rate. A cheaper model cannot ship below a quality
threshold. Prompt, policy, schema, or model changes require regression evaluation.

**Live Coach chat evaluation:** `supabase/functions/_evals/coach_chat_eval.ts` runs about 60
varied prompts (the real failures verbatim, mixed topics, typos and Hinglish, long messages,
projections, unmeasured metrics, plan changes, safety, follow-ups, greetings) against three
synthetic athletes through the production code path and the real model. Merge gates: at least
97% model answers, zero dead-ends, every safety prompt handled safely, zero unpermitted evidence,
p95 latency under 25 seconds. Estimate labelling, clarifying questions, and a projection sanity
range are reported. It runs on demand (add the `coach-eval` label to a pull request, or run the
`Coach Eval` workflow; `DEEPSEEK_API_KEY` repository secret) before any Coach chat change merges.
A run through an OpenAI-compatible router (`EVAL_BASE_URL`, `EVAL_API_KEY`) is a smoke test: its
attempts wait up to 120 s and its latency is reported but not gated. A cheap sample always runs
every safety prompt; a safety prompt that falls back passes only with the safety referral.

## 14. Observability and Review

Record provider/model/prompt/schema/policy versions, feature snapshot, latency, usage, estimated
cost, validation, retries, decision class, proposal outcome, and feedback. Keep raw sensitive
content out of general telemetry.

Unsafe feedback, unusual proposal rates, repeated failures, safety regression, or increased cost
without quality gain opens review. Changes remain versioned and tested.

## 15. RAG and Multi-Agent Policy

The MVP uses structured state and bounded summaries. Vector RAG over user data is added only after
the gates in [ARCHITECTURE.md](./ARCHITECTURE.md) pass. The research library of open sources and
in-house summaries (decision D3, ARCHITECTURE.md section 11) is the one retrieval source allowed
now; Coach chat retrieves from it on every turn (§11.2). Retrieval cannot override confirmed facts
or policy.

Bounded lookups of the athlete's own records (§11.1) are not an agent: a closed read-only
catalogue, a hard cap of two rounds, no writes and no background runs.

Separate model agents are added only if evaluation demonstrates a specific improvement over the
controlled single call. Safety and mutation approval always remain external to models.
