# Tracend Product Requirements Document

**Status:** Authoritative MVP requirements  
**Product:** Tracend  
**Release:** Private iOS TestFlight beta

## 1. Product Goal

Tracend gives a healthy adult a personalized training and nutrition plan, observes real execution and recovery, and produces clear daily and periodic coaching decisions. It behaves like a careful personal trainer: plans remain stable until evidence supports a change, and persistent changes require user approval.

The product intent and anti-goals are defined in [VISION.md](./VISION.md). AI decision constraints are defined in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md). Screen behavior and visual rules are defined in [UX_FLOWS.md](./UX_FLOWS.md) and [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md).

## 2. Supported Audience

The MVP supports:

- adults aged 18 and over;
- configurable fat-loss, muscle-gain, recomposition, strength, and aesthetic-emphasis goals;
- beginner through experienced gym users;
- iPhone users, with optional Apple Watch or other HealthKit-connected sources;
- metric units by default, with user-selectable imperial display; and
- English-language coaching.

The MVP excludes users who disclose pregnancy, an active eating disorder, a condition requiring medical nutrition, a serious or acute injury, or a need for clinical rehabilitation. The app must explain the boundary and direct the user to an appropriate qualified professional.

## 3. Product Roles

### User

Owns the data, confirms observations, approves plans and changes, and performs workouts and logging.

### Training Coach

Explains workout prescription, progression, recovery adjustments, exercise substitutions, and training priorities. It cannot change nutrition targets.

### Nutrition Coach

Explains nutrition targets, adherence, meal patterns, and proposed nutrition adjustments. It cannot change training plans.

### Head Coach

Reconciles training, nutrition, recovery, goals, and safety into one final decision. Training Coach, Nutrition Coach, and Head Coach are UI perspectives produced by the controlled workflow defined in [ARCHITECTURE.md](./ARCHITECTURE.md), not independent autonomous actors.

## 4. Primary User Journeys

### 4.1 Account and consent

1. User signs in with Apple for an external private beta. During owner-only
   development, a documented email/password Supabase Auth mode may be used
   until Apple Developer Program capabilities are available.
2. User confirms they are 18 or older.
3. User reads and accepts the private-beta terms and privacy notice.
4. User separately chooses whether to connect HealthKit and whether to upload meal or progress photos.
5. The app remains usable with reduced capability when optional permissions are denied.

### 4.2 Beginner onboarding

The user provides:

- goal and target direction;
- experience level;
- training days, session duration, schedule, and equipment;
- exercise preferences and dislikes;
- dietary pattern, allergies, dislikes, meal schedule, and budget considerations;
- height, weight, optional measurements, and desired unit system;
- known limitations, medications or conditions only to determine whether the MVP is appropriate;
- optional recent HealthKit history; and
- optional standardized physique photos.

Tracend produces an assessment summary, a proposed training block, nutrition targets, assumptions, confidence, and missing information. Nothing becomes active until the user reviews and approves it.

### 4.3 Experienced-user onboarding

The experienced user provides the beginner information plus:

- current or recent plan;
- recent exercise performance and training history;
- current calorie and macro targets if known;
- observed strong and weak areas;
- recent progress, plateaus, adherence, and concerns; and
- optional historical files or HealthKit summaries supported by the MVP import flow.

Tracend preserves valid current practices where possible, identifies gaps or conflicts, and proposes either continuation or a revised plan. The user approves the result.

### 4.4 Daily coaching loop

1. The user sees today's scheduled workout and current nutrition targets.
2. The user optionally completes a short check-in: sleep quality, energy, soreness, hunger, mood, pain, availability, and notes.
3. The system combines the check-in with HealthKit summaries and recent execution.
4. Tracend returns Training Coach, Nutrition Coach, and Head Coach cards.
5. Daily recommendations may adjust today's execution, but persistent target or plan changes enter a separate approval flow.

### 4.5 Workout execution

The active plan supplies ordered exercises, warm-up guidance, working sets, rep ranges, target load or effort, rest guidance, and substitutions.

For each exercise, the user can record:

- completed/skipped status;
- set number, repetitions, load, and RPE;
- optional technique or pump rating;
- pain flag and note;
- substitution and reason; and
- session-level duration, energy, and notes.

The user may edit an in-progress session. Completed sessions are immutable through normal UI; corrections create audited amendments.

### 4.6 Meal photo and nutrition confirmation

1. The user uploads or captures a meal photo.
2. AI proposes visible foods, preparation assumptions, portion estimates, confidence, and questions.
3. The user adds, removes, edits, or confirms foods and portions.
4. Confirmed items are matched to the hybrid food catalog and macros are calculated from catalog values.
5. Only confirmed items count toward daily nutrition totals.
6. A confirmed home meal can be saved as a reusable personal food or recipe.

The product must communicate that hidden ingredients and portions cannot be determined reliably from an image alone.

### 4.7 Progress review

The user records weight and optional waist, chest, hip, arm, and thigh measurements. A monthly flow guides consistent front, side, and back photos using comparable pose, distance, lighting, clothing, and timing.

Progress review combines:

- smoothed weight and measurement trends;
- training performance and workload;
- adherence and missed sessions;
- nutrition adherence and hunger;
- sleep and recovery context;
- standardized photo comparison; and
- previous decisions and their outcomes.

Photo analysis may describe visible development, balance, and approximate body-fat range with confidence. It must not claim precise composition, diagnose a condition, or infer sensitive traits unrelated to coaching.

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

Rejected proposals do not alter the plan. Accepted proposals create a new version while retaining the prior version and audit record.

## 5. Functional Requirements

### 5.1 Authentication and tenancy

- Use native Sign in with Apple through Supabase Auth for an external private
  beta. Owner-only development may use the email/password mode documented in
  ADR 0002; it is not an authentication bypass and does not change the
  canonical `auth.users.id` tenancy boundary.
- Every user-owned record must be scoped by authenticated user ID.
- Every exposed user-owned table and private Storage bucket must have tested RLS based on the Supabase authenticated user.
- Data API, RPC, and Edge Functions must never trust a client-supplied user ID for authorization.
- Account provides profile and goal review, connection status, notification and
  privacy controls, sanitized user-scoped AI usage, export, deletion, and sign
  out.
- The mobile app never accepts, stores, or displays an AI-provider API key.
  Provider credentials are owner-managed server secrets.
- Account export and deletion must be available from Settings.

### 5.2 HealthKit

Request only data needed for enabled features:

- steps;
- active energy;
- sleep;
- workouts;
- weight;
- resting heart rate; and
- heart-rate variability.

Permissions must be requested by type with plain-language purpose descriptions. Sync stores normalized daily summaries and source references needed for idempotency, not an unnecessary copy of every raw sample. Denied, partial, stale, or unavailable data must be visible and must not prevent manual use.

### 5.3 Plans and progression

- Plans are versioned and have draft, proposed, active, superseded, or archived status.
- Exactly one training-plan version and one nutrition-target version may be active per user at a time.
- AI cannot activate a version directly.
- Exercise substitutions must preserve the intended movement or muscle objective unless the change proposal explicitly changes it.
- A single poor workout must not trigger structural reprogramming.

### 5.4 Coaching decisions

- Each decision references an immutable computed feature snapshot.
- The response must conform to the schema in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md).
- The UI must distinguish observation, recommendation, and proposed persistent change.
- Decisions must show evidence in user-readable language.
- A failure to obtain AI output must not corrupt plans or block logging.

### 5.5 Notifications

The MVP may provide local or push reminders for scheduled workouts, check-ins, meal confirmation, weekly review, and pending proposals. Notifications must not reveal sensitive health or physique details on the lock screen.

### 5.6 Feedback and auditability

Users can rate a decision as useful, unclear, incorrect, or unsafe and add a note. Model runs, feature snapshots, proposals, approvals, rejections, corrections, exports, and deletions produce audit events without storing secrets or unnecessary raw prompt content.

### 5.7 Production daily experience

- Today presents one deterministic **Do this next** action assembled from the
  approved workout, active meal schedule, check-in, HealthKit freshness, and
  latest validated decision. It never substitutes fixtures for missing data.
- Train exposes the complete active weekly split, prescription detail, recent
  completed sessions, adherence, and comparable-set progression.
- Coach supports owner-scoped saved conversations for training, nutrition,
  recovery, progress, evidence, and app-usage questions. Only the latest 20
  messages plus minimized structured evidence are sent to the provider.
- Nutrition presents the next scheduled meal before secondary macro totals.
  Planned food, AI candidates, and confirmed consumption remain distinct.
- Coach conversations persist until thread deletion or account deletion.
  Conversation replies cannot activate plans, targets, meals, or durable facts.

### 5.8 AI budgets and routing

- Live coaching uses stable `gemini-3.5-flash` only after paid-service privacy
  terms and the complete evaluation gate pass.
- The monthly owner warning is USD 3, the server-side hard stop is USD 5, and
  conversational coaching is limited to 30 requests per owner/day.
- Meal verification uses `gemini-3.5-flash` with low thinking. Lite models are
  not production routes; cost is controlled through bounded context, output,
  request budgets, and task-specific thinking instead of a quality downgrade.
- Progress-photo interpretation remains separately consented and separately
  evaluated. Manual use and the approved plan survive every provider failure.

## 6. Evidence-Gated Change Policy

Defaults are defined in [AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md). Product behavior must follow these principles:

- daily safety or recovery adjustments may affect only the current session/day;
- structural training changes normally require repeated evidence across at least two affected sessions or two weeks of trend data;
- nutrition-target changes normally require at least 14 days of weight data and adequate adherence;
- adherence below the configured sufficiency threshold must be addressed before concluding that the plan failed;
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
- production vector RAG unless a later evaluation justifies it.

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
