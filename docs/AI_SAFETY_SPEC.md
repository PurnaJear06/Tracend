# Tracend AI and Safety Specification

## Coach Context v2 and Qwen Reasoning

Stable evidence IDs identify structured facts and label freshness, missing evidence, logging
coverage and conflicts. Ordinary chat uses non-reasoning structured output. Weekly review may use
Qwen reasoning followed by validated formatting. Unsupported evidence rejects the output; unknown
logging is not non-adherence; persistent plan and target changes remain approval-gated.

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
- HealthKit baselines and deviations;
- data freshness, sufficiency, and conflicts;
- persistent-change eligibility;
- hard safety exclusions and permitted action classes;
- schema, range, evidence, and reference validation;
- plan and target activation; and
- authorization, consent, audit, retention, and deletion.
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
- Same-day adjustments expire and never alter plan versions.
- Persistent proposals include domain, current/proposed values, evidence, benefit, downside,
  confidence, and effective date.
- Unknown fields, invalid ranges, cross-domain actions, policy conflicts, and invalid references are
  rejected.

## 6. Data Sufficiency and Change Rules

These conservative defaults are versioned policy, never prompt-only instructions.

### General

- One anomalous day does not establish a trend.
- Missing or stale evidence lowers confidence and can restrict action.
- Conflicting sources are surfaced, not silently resolved by the model.
- Insufficient evidence means maintain the plan or ask for data.

### Same-day training adjustment

May be allowed for a current recovery deviation, schedule limitation, or non-red-flag discomfort. It
is limited to today's intensity, volume reduction, rest, or validated substitution.

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

### Initial plan

Onboarding output identifies assumptions, missing information, confidence, and constraint
uncertainty. It uses only compatible catalog exercises. Training and nutrition proposals require
approval.

Since 2026-10 (`onboarding-plan`, policy `onboarding-policy-v1`):

- **The model chooses inside ranges that deterministic code computes.** The prompt states every
  range, and `_shared/onboarding/plan_contract.ts` rejects a plan that leaves any of them, with one
  of 29 finite rule names. The formulas and sources are in ALGORITHMS.md §9.
  - **Calories:** a goal window around maintenance, with a floor of the larger of BMR and
    1,200 kcal (female) or 1,500 kcal (male or unspecified), and a ceiling of 6,000 kcal.
  - **Macros:** protein 1.6–2.2 g/kg (2.6 g/kg in a deficit), fat 20–35% of calories and at least
    0.5 g/kg, and a macro sum within 5% of calories.
  - **Storable:** the absolute nutrition bounds equal the database check, so a valid plan is
    always storable (`policy_test.ts` compares them with the migration).
  - **Training:**
    - one workout on each chosen weekday, at most six;
    - a set and exercise budget per session length, and the session must fit its minutes;
    - weekly sets per target muscle at most 12 for beginners and 20 for intermediates;
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
- **Apple Health** (2026-10): the plan uses a deterministic 28-day summary (ALGORITHMS §9) of the
  athlete's synced data: average steps, active energy and sleep, workouts found, and the latest
  weight and trend. It never moves the calorie or protein ranges. Only short sleep changes a
  limit: the RPE ceiling drops half a point (`startLighter`), in the policy, so the model and the
  rules plan both follow it. No workouts found is reported as missing information, never as
  inactivity, because HealthKit hides whether read access was denied. Resting heart rate, HRV and
  breathing rate are not sent: without a personal baseline they cannot guide a starting plan. The
  summary reaches the model only with `onboarding_plan` consent, as a data block, and is stored in
  the onboarding snapshot and the proposal's calculation (evidence `APPLE_HEALTH_SUMMARY_28D`).
- **Usual months** (2026-10): the app sends monthly totals for the 11 completed months before this
  one (workouts, strength workouts, sleep and weight with their coverage; no raw sample). The plan
  compares the usual months with the last 28 days. The only limit it changes: lifting under half of
  a usual two or more sessions a week starts the block with a fifth fewer sets a session and the RPE
  ceiling half a point lower, with a note. Stored in the snapshot and the proposal's calculation
  (evidence `APPLE_HEALTH_HISTORY_11M`).
- **Coach intake** (2026-10): training years, what has worked and stalled, reported barbell top
  sets, and up to two focus muscles. Code turns the top sets into one-rep-max estimates and starting
  loads for those lifts, and gives each focus muscle a weekly set minimum inside the existing
  maximum (ALGORITHMS §9); the validator rejects a plan below a minimum (`priority_volume_missing`).
  The model never writes a load. Approval copies starting loads to `planned_exercises` and keeps
  training years and muscles on the profile, which the Coach reads.
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
  `set_my_timezone`). The profile keeps the movements to avoid, the equipment note, the training
  years and the focus and strong muscles, which the Coach reads and is told never to contradict.

## 7. Eligibility and Escalation

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

Provider (2026-09-29): server-side Groq `qwen/qwen3.8-27b`, successor of the retired
`qwen/qwen3.6-27b`. The function refuses any other Groq model name, and it stays off until
`MEAL_VISION_ENABLED` and `MEAL_VISION_MODEL_EVALUATED` are both `true`; the owner sets the second
only after checking the model on their own meal photos. Groq's Zero Data Retention setting must be
on for the key's organization before the route is enabled. Meal photos are not covered by the AI
coaching consent (which covers DeepSeek and states that photos are not sent). They have their own
notice and consent (2026-10-09): `meal_photo_ai_notices` (current `meal-photo-ai-v1`, Groq,
`qwen/qwen3.8-27b`) and consent type `meal_photo_ai`. The app shows the notice before the first
photo is picked, and meal-analyze refuses (403 `meal_photo_ai_consent_required`) without a grant of
the current version, and (503 `meal_photo_notice_outdated`) when that notice names a provider other
than `MEAL_VISION_PROVIDER`. The athlete withdraws from **Log a meal** (**Turn off meal photo
AI**, a `withdrawn` record), which stops new analysis at once. A provider or model change needs a new notice
(`private.publish_meal_photo_ai_notice`) before the switch; every athlete is then asked again.

## 9. Physique Analysis

**Status (2026-10): owner-only experiment.** The `physique-check` Edge Function serves only the
user IDs in `PHYSIQUE_VISION_ALLOWED_USERS` (empty at deploy). Before the owner adds their own ID,
Groq's Zero Data Retention must be on for the key's organization and the proof (date or screenshot)
recorded in `docs/handoff/physique-check.md`. No other account may be added until a separate
evaluation passes: consented or synthetic sets across body types and skin tones; pose, clothing,
lighting and pump changes; repeatability; wrong priorities; forbidden outputs; text written into the
image; and empty, unrelated or low-quality photos.

**Consent.** Its own server-versioned notice (`photo_ai_notices`, consent type `progress_photo_ai`),
separate from the DeepSeek coaching notices, which stay true: DeepSeek never receives photos. The
notice names Groq, the model, the data sent, Zero Data Retention, what Tracend keeps and how to stop.
Consent counts only when the athlete's newest `progress_photo_ai` record grants the newest notice
(`has_photo_ai_consent`); a new provider, model, data sent or retention is a new notice and needs a
new grant. Withdrawing stops new checks; past results stay until the set or account is deleted.

**Input.** The front, side and back photos of one complete set (Groq accepts three images), each a
JPEG of at most 3 MB with every metadata segment (EXIF, location, XMP, ICC, comments) removed on the
server before sending, across every scan of a progressive file, and nothing after its end marker
(`_shared/physique/jpeg.ts`); the app already re-encodes at capture (longest
side 1800 px, no metadata). Also sex, height, latest weight and body measurements, and the active
goal, as data. The check is hidden when the athlete's own notes mention an eating concern.

**Output** (`_shared/physique/contract.ts`, `private.is_valid_physique_result`): 1–3
`development_priorities` from the catalog's primary muscles, each with confidence and a reason of at
most 120 characters, relative to the athlete's own build; up to three neutral observations; photo
issues from a fixed list (lighting, pose, clothing, framing, blur, mismatch), which cap confidence
(one at medium, two or more at low); and limitations. Any unexpected key, unknown muscle, or a
percentage, body-fat, score or rating, appearance judgement, sexual, medical, sensitive-trait or
eating wording rejects the whole reply. A reply that suggests no muscle at all means the photos
show no physique to judge (an unrelated picture, the body out of frame): nothing is stored, no
correction is asked, and the athlete is told to retake the set (422 `photo_set_unassessable`). One
text-only correction is asked (the photos are not sent
again) when Groq reports at least 2,500 tokens left in the minute; otherwise, or if the correction
also fails, nothing is stored (502 `physique_check_invalid`) and the tokens are still counted.

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

## 10. Provider and Model Routing

Use:

- deterministic code for calculations and hard policy;
- an economical vision model only after it passes meal tests;
- a capable structured-output model for daily coaching;
- a stronger evaluated model for onboarding, periodic review, or ambiguous conflicts; and
- no model call when deterministic output is sufficient.

Providers sit behind `CoachModelProvider` inside Supabase Edge Functions. DeepSeek V4.1 Flash
(`COACH_MODEL_PROVIDER=deepseek`, model `deepseek-flash`) is the current active production provider
for Coach text and chat. DeepSeek retired V4 Flash on 2026-09-10 and routes the legacy name
`deepseek-v4-flash` to V4.1 Flash for now, so the code accepts both names and nothing else. That
silent model change still owes its regression run, the live evaluation below. The evaluation may
send its synthetic athletes through an OpenAI-compatible router; a router never receives user data
unless it passes its own privacy review.
Coach chat and the daily decision send an athlete's data to the provider only while their current
`ai_coaching` consent is granted (UX_FLOWS §4.1). The app does not call either function for an athlete
who declined, and the server enforces the same rule for every caller (2026-09-30):
`has_ai_coaching_consent` reads the newest `ai_coaching` record, and only a grant of the current
notice version counts. Since 2026-10 the notice is server data, current per purpose
(`ai_notice_current` for `coach_chat`, `daily_coaching` and `onboarding_plan`), and a grant counts
for a purpose only when it names the notice that is current for that purpose. `ai-coaching-v4`
(2026-10-02) is current for all three; it adds the onboarding Apple Health summary and movements
to avoid. Publish any later notice for every purpose: the app shows the notice current for the
most purposes, and a grant covers only that one version. `coach-chat` answers 403 `ai_consent_required` without it, and 503
`ai_consent_unavailable` when the check fails. `coach-decide` then uses the deterministic provider,
so no data reaches the AI provider.
Under ADR 0006, Groq Qwen was an owner-only, time-bounded test provider and has been superseded. The
mock remains the default. Progress-photo vision is an owner-only experiment (§9) behind its own
allowlist and notice. Provider and Supabase secret/service-role keys never enter Flutter. Price alone cannot
qualify a model.

**Onboarding plans** have their own provider settings and switch without a code change:

- **Settings:**
  - `ONBOARDING_PLAN_PROVIDER`: `mock` (rules only, the default), `deepseek`, `groq` or `gemini`.
  - `ONBOARDING_PLAN_MODEL`.
  - The provider's key.
  - `ONBOARDING_PLAN_MODEL_EVALUATED=true`.
  - The input and output prices, unless the provider has a known default. DeepSeek uses its peak
    price.
  - `ONBOARDING_PLAN_THINKING`: `on` (the default when unset) or `off`. With it on, the first
    attempt reasons before answering (DeepSeek: `thinking` enabled, `reasoning_effort: high`, no
    temperature, 24,000 output tokens) and gets 105 s of a 125 s deadline. The repair never thinks.
    A provider without a thinking mode ignores the setting. Off restores the request used before
    2026-10 (thinking disabled, temperature 0.2, 6,000 tokens, 55 s of 75 s).
- **Calls:** every provider is called through its OpenAI-compatible chat-completions endpoint in
  JSON mode (`_shared/providers/onboarding_plan_provider.ts`).
- **Telemetry:** the `onboarding.plan.generated` audit event stores whether the call thought, its
  latency, attempts, input, output and reasoning tokens, and the last finish reason
  (`persist_onboarding_proposal_v3`). Prompts and answers are never stored there.
- **Follow-up questions** (2026-10): before the plan, the same provider may ask 0–3 questions
  (`onboarding-plan` with `mode: "questions"`, `_shared/onboarding/questions.ts`). Same consent
  (`onboarding_plan`) and budget gates; thinking as configured, 4,000 output tokens, 40 s. Each
  question must belong to an allowed topic (split history, recovery between sessions, a stalled
  lift, exercise preference, schedule flexibility, daily eating routine); a reply with any other
  topic, or injury, pain, medical, pregnancy or disorder wording, is dropped whole and the plan is
  built without questions. One request claims the hash of the answers before asking
  (`claim_onboarding_questions`, 60 s lease); an overlapping request waits up to 45 s for its
  outcome instead of asking again. The model's outcome is stored per hash (`onboarding_questions`);
  a failed call releases the claim so a retry may ask, and no consent, no budget or no ready model
  is answered without storing anything, so it never outlasts its cause. Usage is recorded as
  `onboarding_questions`, and the `onboarding.questions.generated` audit event carries the same
  telemetry as the plan. The athlete can skip at any time; the plan then starts once the running
  question request settles (at most 45 s in the app), so the two calls never spend the budget at
  once. Questions never block onboarding.
- **What the plan model receives since onboarding-policy-v2:** the athlete's training years, what
  has worked and stalled (their words, as data), reported barbell top sets with Tracend's
  one-rep-max estimates and ratios, focus and strong muscles, follow-up answers, and the Apple
  Health usual months next to the last 28 days. Starting loads, focus minimums and the
  return-from-a-break limits are set by code (ALGORITHMS §9); the model chooses within them and
  must name the athlete's focus and history in its assessment.
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
  4. **Because athletes agreed to a named provider,** a provider change also publishes a new notice
     for every purpose: `select private.publish_ai_notice(version, provider_label, purposes, body)`.
     Older grants stop counting at once, and the app asks again.

Live model activation requires all server-side secrets (`COACH_MODEL_PROVIDER`, `COACH_AI_ENABLED`,
provider API keys) configured together as an all-or-nothing gate. Coach-decide specifically defaults
to the deterministic mock; changing it to a live model requires the full secret configuration.
Prior providers: Gemini `gemini-3.5-flash` and Groq Qwen `qwen/qwen3.6-27b` (both superseded
pending evaluation). Lite models are rejected by production configuration. Cost control must not
bypass visible-food, mixed-dish, hidden-ingredient, portion-uncertainty, prompt-injection,
schema-validity, or user-correction evaluations. Routing changes require regression results.

Conversational answers may explain only supplied structured evidence, must state missing data, and
expose evidence references. The model receives at most 20 recent messages and no tools.
Deterministic pre-model rules refuse medical, emergency, pregnancy, eating-disorder, medication, and
rehabilitation requests.

Model adapters for prior providers remain disabled by default and require an explicit paid-service
data-terms gate before they can process restricted coaching context. Synthetic adapter tests do not
satisfy evaluation parity or authorize live calls. Meal and progress vision remain separately gated.

Optimize cost using compact feature snapshots, cached static context, deterministic summaries,
normalized images, duplicate avoidance, per-user rate limits, and quality-based routing. Cost cannot
override safety or the quality floor. Budget assumptions and hard controls are defined in
[COST_MODEL.md](./COST_MODEL.md).

## 11. Prompt and Context Rules

- Prompts and schemas are versioned and reviewed.
- System instructions define boundaries, policy, schema, and refusal behavior.
- User text and retrieved content are delimited, untrusted data.
- Context states units, windows, freshness, provenance, and missing data.
- Direct identifiers, tokens, object keys, and unrelated history are excluded.
- Coaching calls have no web, shell, arbitrary database, or unrestricted tool access.
- The model may reference only supplied catalog identifiers.
- **Null contract (2026-09-08, Pass 4):** a `null` value in any model context (chat or decision)
  means the metric was NOT MEASURED that day. Context serialization MUST preserve nulls —
  stripping them let the model read a missing metric as absent history or zero. Empty
  arrays/objects stay pruned (absent ≠ not measured). Chat-context markdown renders null as the
  "—" sentinel and every system prompt carries the rule: null/— is NEVER zero, NEVER a negative
  result, and must be stated as "not measured"; an explicit `0` in the data is a measured zero, a
  different fact from null. Date discipline: the context carries its own date (chat
  `coaching_date`, decision `feature_context.local_date`) and the prompt forbids calling a value
  "today/recent" without checking the value's date against it — a metric from an older row is a
  past reading, never a current one.
- Provider request bodies MUST use the multi-role message form: `system` carries identity,
  boundaries, refusal behaviour, schema, and evidence rules; `user` carries the prepared context
  first, wrapped in `<coaching_context>` and labelled as supporting evidence, and the user's raw
  message last, labelled `User's message:`. Bundling instructions, schema, the question, and the
  context into one undelimited `user` turn is prohibited — it caused the model to read the question
  as data and emit the same plan-style answer for any input, including greetings. (Changed
  2026-09-27 from question-first: the question now follows the long context, which is the
  recommended order for long-context prompts, and the stable athlete file becomes a cacheable
  prefix; greetings and one-word messages are in the live evaluation to catch that regression.)
  The instruction "Lead with one clear recommendation" is prohibited in conversational chat
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
- **Full athlete file (2026-09-27, v8):** every chat question receives the same complete context
  from `prepare_coach_chat_v8` — plan, goal, profile, check-ins, the 28-day training log and
  7/14/28-day totals, watch workouts, 28 days of watch data with averages, eight weeks of weights,
  nutrition targets and logged days, conversation memory, and data freshness. The question's
  keyword classification may choose behaviour (thinking for explicit plan changes) and telemetry;
  it never adds or removes data. `prepare_coach_chat_v7` remains for rollback.
- If the deterministic scores cannot be computed for the coaching date, `prepare_coach_chat_v7`
  (and v8, which builds on it) marks Computed Scores unavailable and permits only non-score
  evidence codes; chat stays available instead of failing, matching the Today brief's degradation.
  `prepare_daily_coaching`, which creates the day's snapshot on the first chat, applies the same
  guard (2026-09-28) and stores the snapshot with `scores_unavailable`.
- Watch-data averages carry a day count per metric, because each average skips days its metric was
  not measured.
- Deterministic code owns every measured number and evidence code. Numbers about the athlete's data
  are quoted from context with the same units and rounding; the model never invents a measurement.
  **Owner decision 2026-09-27:** the model may give an estimate (for example, time to reach a
  target weight) derived from context numbers or numbers the athlete states, provided it calls it
  an estimate, shows its inputs and assumptions, and never presents it as measured data.
  Deterministic calculators (2026-09-30, `_shared/coach_calculations.ts`, see
  `docs/ALGORITHMS.md` §5) put exact averages, week-over-week changes, weight trends and a labeled
  weight projection in a "Calculated by Tracend" context section. The model quotes these instead of
  computing its own and still calls a projection an estimate. Other estimates follow the rule
  above. Missing/null values are described as not measured.
- When a question is ambiguous or needs a detail the context lacks, the coach answers what the data
  supports and asks one short clarifying question, offering likely replies as suggested follow-ups.
  The reply returns with the next turn through the conversation history.
- Every coach-chat provider uses one shared coach persona (coaching approach, communication style,
  hard boundaries), followed by the null contract and the output accuracy/validation contract so the
  contract's rules take precedence.

## 12. Validation and Failure Handling

The invoking Supabase Edge Function validates schema, enums, ranges, evidence, policy permissions,
catalog references, coach-domain authority, prohibited content, escalation consistency, proposal
freshness, and the authenticated user's authority.

Invalid output is never partially applied. The system may attempt one targeted schema-repair retry
and then returns a safe unavailable state while preserving logging and the active plan. The repair
receives only a finite validation rule, JSON path, applicable limit/count, and the per-request
allowed evidence codes. It fixes the stated defect and any sentence dependent on an invalid
citation without adding facts or numbers. A live Coach chat must never delete invalid citations and
keep the prose, or present deterministic fallback text as a successful model answer; deterministic
emergency and clinical-boundary refusals remain explicitly labeled safety responses.

**Labeled data summary (2026-09-27):** for app builds that send request schema 1.1, the safe
unavailable state is a deterministic data-summary reply instead of an error, so the athlete is
never left at a dead end. It opens by saying the coach could not produce a full answer, copies
every number verbatim from the prepared context (no estimates), cites only permitted evidence, and
carries `safety_state: "unavailable"`, `answer_source: "data_summary"`, and a sanitized
`diagnostic` (failure code and finite rule names). It is stored in the thread as an assistant
message flagged `data_summary` and is never presented as the model's answer: not to the athlete,
and not to the model, whose conversation memory leaves it out. Request schema 1.0 builds keep the
503.

From A2 (2026-09-29) the app sends request 1.1 and labels the reply itself:
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
than the pre-model boundary, because a false alarm only replaces numbers with the referral. Every
other summary ends with the same referral in one line.

A request retried with the same idempotency key receives what its first attempt produced (the
stored answer, the original failure code, or 409 while it is still running) and never calls the
model again.

DeepSeek Coach chat accepts provider output only when `finish_reason` is `stop`. Empty content,
`length` truncation, malformed JSON, and schema rejection receive at most one repair attempt. The
repair is non-thinking JSON mode at temperature 0, receives the same bounded question/context plus
at most 12,000 characters of the failed candidate as explicitly delimited untrusted input, and is
never used for authentication, rate-limit, HTTP, or timeout failures. The output ceiling is 4,096
tokens; per-attempt limits are 28 seconds initial and 10 seconds repair inside a 40-second Edge
deadline. Failed runs persist a stable sanitized failure code and at most four finite rule names
(`persist_failed_coach_chat_run` accepts every provider `model_runs` allows, including DeepSeek),
and the Edge Function checks that the record was written. The user's question is stored when the
turn starts, so a failed answer never erases it. Response schema 1.1 exposes the failure code to
Flutter without provider bodies, parser messages, prompts, or health context.

The validator and model-facing schema share one set of hard ceilings, item counts, safety enums,
evidence sources, and the request's exact evidence-code enum. Accuracy and safety rules (JSON
validity, keys and types, safety state, permitted evidence and reasoning citations) are strict.
Formatting limits are generous ceilings (reasoning 10 items, step 200, value 400 characters;
follow-ups 6 × 300; missing data 12 × 300; evidence 20, label 400) because an accurate answer must
not be discarded for being slightly long; the prompt still asks for short items (about 80/160/120
characters). Validation failures use a finite rule
set (for example `json_syntax`, `evidence_code_not_permitted`, or
`reasoning_value_too_long`) plus a JSON path. One structured outcome record captures each attempt's
rule, path, latency, finish reason, and completion-token count. Sentry is emitted only for terminal
failure and carries the initial and repair rule names; prompts, answers, provider bodies, questions,
and health values never enter logs or Sentry.

## 13. Evaluation

Maintain anonymized fixtures covering:

- both onboarding paths and all supported goals;
- stable progress where no change is correct;
- plateau with adequate versus poor adherence;
- isolated bad workouts versus repeated regression;
- poor sleep, recovery deviations, schedule and equipment changes;
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

**Live Coach chat evaluation (2026-09-27):** `supabase/functions/_evals/coach_chat_eval.ts` runs
about 60 varied prompts (the real failures verbatim, mixed topics, typos and Hinglish, long
messages, projections, unmeasured metrics, plan changes, safety, follow-ups, greetings) against
three synthetic athletes through the production code path and the real model. Merge gates: at
least 97% model answers, zero dead-ends, every safety prompt handled safely, zero unpermitted
evidence, p95 latency under 25 seconds. Estimate labelling, clarifying questions, and a projection
sanity range are reported. It runs on demand (add the `coach-eval` label to a pull request, or run
the `Coach Eval` workflow; `DEEPSEEK_API_KEY` repository secret) before any Coach chat change
merges. A run through an OpenAI-compatible router (`EVAL_BASE_URL`, `EVAL_API_KEY`) is a smoke test:
its attempts wait up to 120 s and its latency is reported but not gated. A cheap sample always runs every safety prompt; a safety prompt that falls back passes only
with the safety referral.

## 14. Observability and Review

Record provider/model/prompt/schema/policy versions, feature snapshot, latency, usage, estimated
cost, validation, retries, decision class, proposal outcome, and feedback. Keep raw sensitive
content out of general telemetry.

Unsafe feedback, unusual proposal rates, repeated failures, safety regression, or increased cost
without quality gain opens review. Changes remain versioned and tested.

## 15. RAG and Multi-Agent Policy

The MVP uses structured state and bounded summaries. Vector RAG is added only after the gates in
[ARCHITECTURE.md](./ARCHITECTURE.md) pass. Retrieval cannot override confirmed facts or policy.

Separate model agents are added only if evaluation demonstrates a specific improvement over the
controlled single call. Safety and mutation approval always remain external to models.
