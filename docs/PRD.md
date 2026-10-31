# Tracend Product Requirements Document

**Status:** Authoritative MVP requirements\
**Product:** Tracend\
**Release:** Private iOS TestFlight beta (owner-only today)

## 1. Product Goal

Tracend gives a healthy adult a personalized training and nutrition plan, observes real execution
and recovery, and produces clear daily and periodic coaching decisions. It behaves like a careful
personal trainer: plans remain stable until evidence supports a change, and persistent changes
require user approval.

The product intent and anti-goals are defined in [VISION.md](./VISION.md). AI decision constraints
are defined in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md). Screen behavior and visual rules are
defined in [UX_FLOWS.md](./UX_FLOWS.md) and [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md).

Current work runs under the coaching platform program
([plan](./plans/coaching-platform-2026-10/README.md)). Its owner decisions D1–D11 are product
rules. **Planned (Phase N)** notes mark work on its board that is not built yet. Section 11 lists
requirements that are still open.

## 2. Supported Audience

The MVP supports:

- adults aged 18 and over;
- configurable fat-loss, muscle-gain, recomposition, strength, and aesthetic-emphasis goals;
- beginner through experienced gym users;
- iPhone users, with optional Apple Watch or other HealthKit-connected sources;
- metric units by default, with user-selectable imperial display; and
- English-language coaching.

The MVP excludes users who disclose pregnancy, an active eating disorder, a condition requiring
medical nutrition, a serious or acute injury, or a need for clinical rehabilitation. The app must
explain the boundary and direct the user to an appropriate qualified professional.

**Pre-exercise screening (B6).** Before the first plan, four plain questions follow the
preparticipation logic of the ACSM 2015 guidance, in Tracend's own words: whether the athlete
exercises regularly now, whether they know of a heart, metabolic or kidney condition, whether they
notice signs or symptoms of one right now, and (only with a known condition and no symptom)
whether a professional has cleared them to exercise. Any current symptom, or no regular exercise
with a known condition and no clearance, means no plan until a health professional has cleared the
athlete; regular exercise with a known condition and no clearance builds a plan capped at moderate
effort (no strength emphasis, at least 3 reps in reserve, no vigorous conditioning); everything
else is cleared. The answers, the outcome and the date are stored and exported. Tracend never
diagnoses or names a condition. Accounts and app builds that never answered read as cleared.

**Regional modules (Phase 4, E4; D5; built):** a global audience, with regional nutrition and
body-measure modules in the research library for India (ICMR-NIN food guidelines, WHO and Indian
BMI points), the United States (Dietary Guidelines for Americans, the NIH BMI and waist guide), the
United Kingdom (Eatwell Guide, Government Dietary Recommendations, NHS BMI and waist guidance) and
Australia (Australian Dietary Guidelines, protein reference values, activity guidelines). The
athlete may choose a country in Account (optional); Coach then shows that country's sources next
to the ones that apply everywhere, and with no country the app behaves as before. A country
changes which guidelines Coach can cite, never a plan number: rules still set calories, protein and
safe ranges. NICE's obesity guideline is not in the library yet (its text could not be read), and
Australia's NHMRC review of the 2013 dietary guidelines may change that module.

**Planned (Phase 4, B5; D6):** knee, back and shoulder training modifications: swaps, range limits,
a pain check and referral warning signs. No diagnosis and no rehab programs.

## 3. Product Roles

### User

Owns the data, confirms observations, approves plans and changes, and performs workouts and logging.

### Training Coach

Explains workout prescription, progression, recovery adjustments, exercise substitutions, and
training priorities. It cannot change nutrition targets.

### Nutrition Coach

Explains nutrition targets, adherence, meal patterns, and proposed nutrition adjustments. It cannot
change training plans.

### Head Coach

Reconciles training, nutrition, recovery, goals, and safety into one final decision.

Training Coach, Nutrition Coach, and Head Coach are parts of one daily decision produced by the
controlled workflow in [ARCHITECTURE.md](./ARCHITECTURE.md). They are not independent autonomous
actors, and the app does not show them as separate coach personas.

## 4. Primary User Journeys

### 4.1 Account and consent

1. User signs in with Apple for an external private beta. During owner-only development, the
   email/password Supabase Auth mode in ADR 0002 may be used until Apple Developer Program
   capabilities are available.
2. User confirms they are 18 or older.
3. User reads and accepts the private-beta terms and privacy notice.
4. User separately chooses whether to connect HealthKit and whether to upload meal or progress
   photos.
5. The app remains usable with reduced capability when optional permissions are denied.

Today the app signs in with email and password only; Sign in with Apple is not built. Sign-ups are
invite-only, and production Auth sign-ups are switched off. The public website
(https://tracend.pages.dev) runs a double opt-in waitlist. Joining it grants no app access; the
owner invites confirmed signups.

The website hosts the privacy policy and terms pages. The onboarding checkboxes do not link to
them yet. That is acceptable for the owner-only beta and blocks any wider release
(SECURITY_PRIVACY.md §15).

AI processing has its own consent, separate from the terms: one notice for AI coaching (Coach chat,
daily decisions and the onboarding plan), one for meal photos and one for the physique check. Each
can be declined; manual use continues.

### 4.2 Beginner onboarding

The user provides:

- goal and target direction;
- experience level;
- training days, session duration, schedule, and equipment;
- exercise preferences, dislikes, and movements to avoid;
- dietary pattern, allergies, dislikes, meal schedule, and budget considerations;
- height, weight, optional measurements, and desired unit system;
- known limitations, medications or conditions only to determine whether the MVP is appropriate;
- optional recent HealthKit history; and
- optional standardized physique photos.

Tracend produces an assessment summary, a proposed training block, nutrition targets, assumptions,
confidence, and missing information. Nothing becomes active until the user reviews and approves it.

With AI coaching consent, the plan is proposed by a model and validated by deterministic code; up to
three follow-up questions may come first. Without consent, or when the model fails, a rules plan
ranked by the athlete's equipment and experience is proposed instead.

### 4.3 Experienced-user onboarding

The experienced user provides the beginner information plus:

- current or recent plan;
- training years and recent exercise performance, such as barbell top sets that set starting loads;
- current calorie and macro targets if known;
- observed strong and weak areas, including up to two focus muscles;
- recent progress, plateaus, adherence, and concerns; and
- optional historical files or HealthKit summaries supported by the MVP import flow.

Tracend preserves valid current practices where possible, identifies gaps or conflicts, and proposes
either continuation or a revised plan. The user approves the result.

### 4.4 Daily coaching loop

1. The user sees today's scheduled workout and current nutrition targets.
2. The user optionally completes a short check-in: sleep quality, energy, soreness, hunger, mood,
   pain, availability, and notes.
3. The system combines the check-in with HealthKit summaries and recent execution.
4. Tracend returns one daily decision with training, nutrition, and head-coach parts. The app shows
   each part where it is used: the training note on Today's session card, the head-coach decision
   on Train's readiness line, and the nutrition note on Nutrition.
5. Daily recommendations may adjust today's execution, but persistent target or plan changes enter a
   separate approval flow.

**Same-day readiness adjustment (Phase 4, B4; server built in B4-1, app in B4-2):** from today's
check-in, last night's sleep and the recovery score, Tracend proposes holding last time's loads, one
set fewer, or easy cardio for today's session only. The athlete accepts or declines with one tap
(Undo until the workout starts), recorded with an audit event; the plan never changes. A poor check-in
leads; the recovery score alone never adjusts a session, it informs the athlete and the athlete may
choose an adjustment themselves. Pain of 7 or more gives a referral and no training change.

**Pain check and joint rules (Phase 4, B5; server built in B5-1, app in B5-2):** an athlete with pain
says where it is, how strong, when it hurts and whether any of ten red flags applies. The database
works out the outcome: a red flag or a pain of 7 or more gives a referral (the emergency number when
urgent) and no training change, applies on a rest day too, and holds the joint until the athlete says a
clinician cleared it; 4 to 6 limits the joint for a week, 1 to 3 puts it on watch. A limited or held
joint changes today's session (a gentler exercise for the same movement, a shorter pain-free range with
the load held, or leaving the exercise out) through the same one-tap adjustment. Tracend never names a
condition, never prescribes rehab, and never blocks the workout: it withholds advice.

**Deloads and cardio dosing (Phase 4, B5; server built in B5-3 and B5-4):** when two lifts are heading
down, the athlete has felt run down on four of the last seven days, or a block of training is done and
was trained, Tracend can suggest a lighter week: the same sessions on the same days with half the sets,
loads held and effort at 7 or lower, then the regular plan returns by itself. It is a suggestion, never
applied: the athlete approves it (or asks Coach for one at any time) and can undo it for seven days.
Nothing is suggested on a day with a safety route, under a health check that says to see a professional,
within 28 days of the last deload or with too little training behind it. Separately, the week's cardio is
shown against the health guideline (150 minutes of moderate cardio, up to 300 for fat loss and
recomposition) from Apple Health workouts, with the honest note when the intensity is unknown or Apple
Health data is missing; hard cardio is offered only to a cleared athlete on a good day with no painful
joint. Heart rate informs the easy ceiling and the wording; it never applies or picks anything.

Direct Coach questions use the active approved plan plus bounded longitudinal context: the active
goal and profile, recent check-ins, normalized HealthKit summaries, completed workouts, confirmed
nutrition totals, measurements, the latest weekly and daily decisions, and the current thread.
A symptom report may produce a conservative same-day rest or reduced-training instruction without
diagnosing or silently changing the active plan. The Coach screen shows a deterministic
context-status summary with source availability, record counts, and latest dates, so the user can
tell missing app data from generic model wording.

**Planned (Phase 3, E3):** Coach answers draw on the research library (section 5.8).

### 4.5 Workout execution

The active plan supplies ordered exercises, warm-up guidance, working sets, rep ranges, target load
or effort, rest guidance, and substitutions.

For each exercise, the user can record:

- completed/skipped status;
- set number, repetitions, load, and reps left (reps in reserve, 0 to 5+; older sets carry RPE);
- when each set started and ended, and the rest taken before it (recorded by the app);
- optional technique or pump rating;
- pain flag and note;
- substitution and reason; and
- session-level duration, energy, and notes.

Untouched exercises remain `unknown`; they are never inferred as skipped. Logging distinguishes
prescribed, substituted, and extra work. The app resumes a server-backed in-progress session, and
the user may edit it. Completed sessions are immutable through normal UI; corrections create
audited amendments.

Between sets a rest timer runs. The workout also shows as a Live Activity on the Lock Screen and
Dynamic Island from the moment it opens: the set in progress (exercise, "Set 2 of 4", and its kg and
reps only if the athlete turned on Lock Screen numbers) with a **Log set** button that logs the
set at the values the logger pre-fills, then the rest countdown with **+30s** and **Skip**, then
the next set. Changing reps or load needs the app. An optional local alert says "Rest timer
finished" when rest ends while the phone is locked. It is off by default ("Rest timer alerts" in
Account › Notifications); off or denied, the rest timer stays in the app.

When Apple Health records a workout on a day the user has a scheduled Tracend workout but no
completed session, Train offers a **mark complete from HealthKit** prompt. The user explicitly
confirms; the completed session records HealthKit evidence and an audit trail. Apple Health
workout matches stay separate from Tracend's set-level evidence, and a duration conflict needs the
user's confirmation. HealthKit data never silently changes adherence.

### 4.6 Meal photo and nutrition confirmation

1. The user uploads or captures a meal photo: a plate, the front of a packaged product, or a
   product's printed nutrition table.
2. AI proposes visible foods, preparation assumptions, portion estimates, confidence, and questions.
   For a pack or a nutrition table it copies what is printed (product name and brand, net weight
   or volume, serving size, servings per pack, and the per 100 g or 100 ml and per-serving
   values, with the unit); it never names a
   product or a value from memory.
3. Deterministic code, never the model, checks a label's arithmetic (energy against protein,
   carbohydrate and fat; the per-serving column against the per 100 g column; servings times
   serving size against the net quantity), works out the portions (one serving, the whole pack,
   or, by weight only, any grams) from per-unit values, and sets the confidence from the source:
   **From label** when a label by weight passes its checks, **Label unclear** when it does not or is
   printed per ml (never shown as grams; only its printed serving and pack are offered),
   **Estimated** for a plate or the front of a pack (never high confidence). The model's
   assumptions and question are shown with each candidate.
4. The user adds, removes, edits, or confirms foods and portions; for a pack or label a portion
   chooser recalculates every value from the stored per-unit values. Nothing counts until the
   user confirms it.
5. **Not built: the hybrid food catalog.** The intended step, matching confirmed items to a food
   catalog and calculating macros from catalog values, does not exist. Until it does, the confirmed
   values are the ones the user confirms: a checked nutrition label read from the photo (the interim
   path for packaged foods) or the model's estimate, as edited. Barcode lookup (for example Open
   Food Facts) is a later step that would feed that catalog.
6. Only confirmed items count toward daily nutrition totals.
7. A confirmed home meal can be saved as a reusable personal food or recipe.

Confirmed daily logs remain available by date after the coaching day changes; midnight changes the
default day but never deletes or visually strands history.

The product must communicate that hidden ingredients and portions cannot be determined reliably from
an image alone.

### 4.7 Progress review

The user records weight and optional waist, chest, hip, arm, and thigh measurements. Weight and
activity trends use real dates, readable scales, and plain current/average/change explanations.
Same-day corrections are audited. A monthly flow guides consistent front, side, and back photos
using comparable pose, distance, lighting, clothing, and timing.

Progress review combines:

- smoothed weight and measurement trends;
- training performance and workload;
- adherence and missed sessions;
- nutrition adherence and hunger;
- sleep and recovery context;
- standardized photo comparison; and
- previous decisions and their outcomes.

Photo analysis may describe visible development, balance, and approximate body-fat range with
confidence. It must not claim precise composition, diagnose a condition, or infer sensitive traits
unrelated to coaching.

The physique check is live for allowlisted accounts (the owner only). From a complete photo set, AI
suggests one to three muscles to develop relative to the athlete's own build, and the athlete may
confirm up to two as focus muscles for the Coach and the next plan. Its output rules are in
AI_SAFETY_SPEC.md §9.

### 4.8 Change approval

A persistent proposal must show:

- what will change;
- current and proposed values;
- effective date;
- supporting evidence;
- confidence and missing data;
- expected benefit and downside;
- whether the change affects training, nutrition, or both; and
- accept, reject, or request-revision actions.

Rejected proposals do not alter the plan. Accepted proposals create a new version while retaining
the prior version and audit record.

## 5. Functional Requirements

### 5.1 Authentication and tenancy

- Use native Sign in with Apple through Supabase Auth for an external private beta. Owner-only
  development may use the email/password mode documented in ADR 0002; it is not an authentication
  bypass and does not change the canonical `auth.users.id` tenancy boundary.
- Every user-owned record must be scoped by authenticated user ID.
- Every exposed user-owned table and private Storage bucket must have tested RLS based on the
  Supabase authenticated user.
- Data API, RPC, and Edge Functions must never trust a client-supplied user ID for authorization.
- The mobile app never accepts, stores, or displays an AI-provider API key. Provider credentials are
  owner-managed server secrets.
- Account provides profile and goal review, connection status, notification and privacy controls,
  sanitized user-scoped AI usage, export, deletion, and sign out. It is one inset-grouped settings
  page: Plan (Profile and goals), Health (Apple Health status in plain words), Appearance (System,
  Dark or Light), Notifications (the two reminders and Rest timer alerts), AI coach (AI coaching,
  this month's usage against the warning and stop limits, Coach conversations) and Privacy (Export
  data, Consent history, Delete account). There is no in-app haptics toggle; the iOS setting
  governs haptics.

### 5.2 HealthKit

Request only data needed for enabled features:

- steps;
- active energy;
- sleep;
- workouts;
- weight;
- resting heart rate;
- heart-rate variability; and
- respiratory rate.

Permissions must be requested by type with plain-language purpose descriptions. Sync stores
normalized daily summaries and source references needed for idempotency, not an unnecessary copy of
every raw sample. Denied, partial, stale, or unavailable data must be visible in plain language and
must not prevent manual use.

**Planned (Phases 2–4, C2–C4):** per-set workout heart rate (summaries only; raw samples never
leave the phone), a heart-rate profile, and sleeping heart rate in shadow mode (D10). Heart rate
never sets the load (D9). C4 adds a dismissible suggestion on the workout screen to start a Watch
workout when none of the last three workouts had Watch heart rate, and load signals for the training
engine (confidence and rest), which Coach shows as fixed sentences in the plan context.

### 5.3 Plans and progression

- Plans are versioned and have draft, proposed, active, superseded, or archived status.
- Exactly one training-plan version and one nutrition-target version may be active per user at a
  time.
- AI cannot activate a version directly.
- Exercise substitutions must preserve the intended movement or muscle objective unless the change
  proposal explicitly changes it.
- A single poor workout must not trigger structural reprogramming.

**Planned (Phases 2–4, B1–B6):** coach-grade rule data, templates by goal, days and experience,
progression from the sets actually logged, deloads, cardio dosing, and a screening gate. Deloads
and cardio dosing are built on the server (B5-3, B5-4) and shown on Train (a lighter-week card, a Cardio this week row).

### 5.4 Coaching decisions

- Each decision references an immutable computed feature snapshot.
- The response must conform to the schema in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md).
- The UI must distinguish observation, recommendation, and proposed persistent change.
- Decisions must show evidence in user-readable language.
- A failure to obtain AI output must not corrupt plans or block logging.

### 5.5 Notifications

The MVP may provide local or push reminders for scheduled workouts, check-ins, meal confirmation,
weekly review, and pending proposals. Notifications must not reveal sensitive health or physique
details on the lock screen. The rest-timer alert and Live Activity are described in section 4.5.

**Widgets (Phase 3, D2).** Today and Lock Screen widgets show today's session, recovery, the first
exercises with their targets, calories and protein against the plan, and the check-in state, from a
snapshot the app writes when Today loads. Lock Screen numbers are off until the athlete turns them
on in Account (SECURITY_PRIVACY §10). Notifications themselves still reveal nothing sensitive.

### 5.6 Feedback and auditability

Users can rate a decision as useful, unclear, incorrect, or unsafe and add a note. Model runs,
feature snapshots, proposals, approvals, rejections, corrections, exports, and deletions produce
audit events without storing secrets or unnecessary raw prompt content.

### 5.7 Production daily experience

- Today is assembled deterministically from the approved workout, the meal schedule, the check-in,
  HealthKit freshness, and the latest validated decision. It never substitutes fixtures for missing
  data. It reads in this order: the recovery verdict and score with its drivers, plan progress,
  Sleep, Load and Fuel tiles, today's session with the coach's note and **Open in Train**, and the
  week. Until today's check-in is saved, a check-in bar takes the tab bar's place; **Not today**
  always lets the athlete through. Details: UX_FLOWS.md §5.
- Train exposes the complete active weekly split, prescription detail, recent completed sessions,
  adherence, and comparable-set progression.
- Coach supports owner-scoped saved conversations for training, nutrition, recovery, progress,
  evidence, and app-usage questions. At most the latest 20 messages (fewer when the context is too
  large) plus minimized structured evidence are sent to the provider.
- No model or provider name appears anywhere the athlete or the public reads (D11). The receiving
  company is named only in one line of each AI consent notice and in the privacy policy's processor
  list. The current build still shows provider names (for example under Coach replies and in the
  onboarding proposal) until chunk A7 (Phase 2).
- If no schema-valid AI reply is available after the bounded retry, the user sees a labelled data
  summary or safety note with Retry, never generic text presented as an AI answer.
- Nutrition presents the next scheduled meal before secondary macro totals. Planned food, AI
  candidates, and confirmed consumption remain distinct.
- Coach conversations persist until thread deletion or account deletion. Conversation replies cannot
  activate plans, targets, meals, or durable facts.

### 5.8 AI budgets and routing

- All model calls run server-side in Edge Functions, and each feature's provider and model are
  set on the server, never in the app. A live route requires the full all-or-nothing secret gate
  in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md) §10; without it the feature takes its deterministic
  path.
- Current production routes (until the Claude cutover below): Coach chat, daily decisions, and the
  onboarding plan and questions use DeepSeek V4.1 Flash (ADR 0011). Meal photos and the physique
  check use Groq `qwen/qwen3.8-27b`. Gemini (ADR 0005) is a gated alternative that requires
  paid-service privacy terms. Cost facts live in [COST_MODEL.md](./COST_MODEL.md).
- A provider-neutral AI gateway (`supabase/functions/_shared/ai/`, with Anthropic,
  OpenAI-compatible and Gemini adapters) serves every feature that has an `AI_<FEATURE>_*` route
  setting; with none, the feature runs the route above unchanged.
- **Cutover (Phase 2; D1, D2), code merged, not yet switched on:** the owner moves features to
  Claude by settings, one at a time: Coach chat and meal photos to Haiku 5.5, the daily decision
  and the physique check to Sonnet 5.5; onboarding follows after chunk B2 (until then, once the
  Anthropic notice is current, new athletes get the rules plan with no AI). The old code paths stay
  for two weeks after the cutover, but data goes only to the vendor named by the notice the
  athlete accepted: unsetting the settings stops Anthropic and the features degrade safely;
  restoring DeepSeek or Groq needs a notice naming that vendor. Health data must not go to DeepSeek
  once external testers join. Steps: `docs/runbooks/phase2-claude-cutover.md`.
- AI wording (D11): the app says "AI" and never names a model or company outside an AI consent
  notice; each notice names the receiving company once.
- Budgets, enforced in SQL before each call: per account, a USD 1.50 monthly warning, a USD 3
  monthly hard stop, and 30 AI requests a day across every AI feature; across all accounts, a
  USD 50 monthly stop (owner decision 2026-10-16; the global value is confirmed at cutover). Each
  call reserves its expected cost ceiling first, so parallel calls cannot cross a stop.
- Meal verification and photo interpretation use evaluated providers with bounded context,
  output, request budgets, and task-specific thinking. Lite models are not production routes.
- Progress-photo interpretation remains separately consented and separately evaluated. Manual use
  and the approved plan survive every provider failure.
- A research library (decision D3) holds open papers, guidelines and in-house summaries in our own
  words. Paid course material is never stored. The tables and hybrid search exist; 114 sources
  are ingested and shape every Coach reply (E3), regional modules choose the sources for the
  athlete's country (E4), and plan explanations cite them: Coach chat when the athlete asks why the
  plan is the way it is, and the onboarding plan, whose "Why this plan" lists the research behind it
  (E5). A plan with no source to cite says so and is less certain.

## 6. Evidence-Gated Change Policy

Defaults are defined in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md). Product behavior must follow these
principles:

- daily safety or recovery adjustments may affect only the current session/day;
- structural training changes normally require repeated evidence across at least two affected
  sessions or two weeks of trend data;
- nutrition-target changes normally require at least 14 days of weight data and adequate adherence;
- adherence below the configured sufficiency threshold must be addressed before concluding that the
  plan failed;
- acute pain or red-flag symptoms stop normal coaching and invoke safety guidance; and
- uncertainty results in maintaining the plan or requesting information, not speculative change.

## 7. MVP Scope

### Included

- private TestFlight distribution;
- multi-user account isolation;
- onboarding and plan approval;
- HealthKit daily-summary sync;
- workout prescription and set-level logging;
- daily check-ins;
- meal-photo proposal, food-catalog matching, and confirmation;
- nutrition totals and adherence;
- measurements and private progress photos;
- daily coaching decisions;
- evidence-backed change proposals;
- weekly progress review;
- feedback, export, and deletion; and
- AI quality, latency, and cost telemetry.

### Excluded

- Android and Health Connect;
- public App Store launch;
- minors, pregnancy, eating-disorder support, medical diets, and rehabilitation;
- medical-report analysis;
- exercise-video form correction or rep counting;
- subscriptions, payments, ads, trainer marketplace, and social features;
- autonomous multi-agent operation; and
- production vector RAG over user data unless a later evaluation justifies it (the research
  library of open sources, decision D3, is in scope).

## 8. Success Metrics

Private-beta success requires:

- at least 90% successful completion of the core onboarding-to-active-plan flow during dogfooding;
- at least 80% of completed planned workouts containing usable execution data;
- at least 80% of AI-analyzed meals either confirmed or explicitly discarded;
- all persistent AI changes containing evidence and explicit approval;
- zero cross-user data exposure;
- zero known plan mutations caused by invalid or failed AI output;
- schema-valid AI output in at least 99% of successful model calls after retry/fallback handling;
- safe behavior on the required safety evaluation suite;
- median user usefulness rating of at least 4/5 for reviewed daily decisions; and
- two weeks of stable owner dogfooding before inviting additional testers.

The external beta also waits until all four phases of the coaching platform program are merged and
device-checked (D7), with no fixed date. The D11 wording rule is a beta exit criterion.

Transformation outcomes are tracked but are not release gates or guarantees.

## 9. Acceptance Criteria

The MVP is acceptable when a tester can:

1. create an account and consent selectively;
2. complete either onboarding path and approve a plan;
3. sync available HealthKit summaries or continue manually;
4. perform and log a prescribed workout at set level;
5. photograph a meal, correct the proposal, and confirm calculated macros;
6. complete a check-in and receive one coherent coaching decision;
7. understand the evidence and missing data behind that decision;
8. review and accept or reject a persistent change;
9. complete a progress review using trends and standardized photos;
10. view decision and plan-version history; and
11. export or delete their account and associated data.

## 10. Dependencies

- [ARCHITECTURE.md](./ARCHITECTURE.md)
- [DATA_MODEL.md](./DATA_MODEL.md)
- [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md)
- [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md)
- [UX_FLOWS.md](./UX_FLOWS.md)
- [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md)
- [TESTING_STRATEGY.md](./TESTING_STRATEGY.md)
- [IMPLEMENTATION_ROADMAP.md](./IMPLEMENTATION_ROADMAP.md)
- [COST_MODEL.md](./COST_MODEL.md)
- [Coaching platform program](./plans/coaching-platform-2026-10/README.md)

## 11. Build Status

Live progress is in [PROGRESS_CONTEXT.md](./PROGRESS_CONTEXT.md). These requirements are not
built yet:

- Sign in with Apple (section 4.1);
- links from the onboarding terms and privacy checkboxes to the hosted pages (section 4.1);
- imperial display (the database stores the preference; the app shows metric only);
- a screen to review a persistent change proposal after onboarding (section 4.8); and
- decision feedback ratings (section 5.6).
