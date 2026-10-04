# Tracend Data Model

## Personal Coaching Entities

Exercise status is `unknown`, `performed`, or explicitly `skipped`; performance kind is
`prescribed`, `substituted`, or `extra`. Sessions retain actual time, logging completeness and
correction state. `health_workout_references`, `workout_reconciliations`, and immutable
`coach_context_snapshots` preserve bounded provenance, owner decisions, and versioned prepared
facts. Only one effective manual body measurement remains current per user/date; re-entry creates an
immutable amendment and supersedes the prior row. Workout reconciliation candidate retrieval ranks
one best unresolved candidate per session, while confirmation closes competing suggestions
transactionally.

**Status:** Authoritative logical data model\
**Store:** Supabase PostgreSQL\
**Convention:** `snake_case`, UUID primary keys, UTC timestamps

## 1. Principles

- Every user-owned record is scoped by `user_id = auth.uid()`; Supabase Auth and mandatory RLS
  enforce the authenticated boundary.
- Plans, targets, computed features, decisions, and accepted changes are immutable or versioned.
- AI observations remain proposals until the user confirms them.
- HealthKit data is normalized into necessary daily summaries rather than copied without purpose.
- Media bytes live in private Supabase Storage buckets. PostgreSQL stores ownership, purpose,
  integrity, and lifecycle metadata.
- Canonical units are kilograms, centimeters, kilocalories, grams, minutes, beats per minute, and
  milliseconds.
- Structured PostgreSQL fields are the MVP memory system. Vector embeddings are deferred.
- **Forward-only migrations. Never edit an applied migration.**
- **Every migration must be additive.** Rename, drop, or change column type requires the two-step
  pattern: (1) add new column + deploy code that reads it; (2) later migration drops old column.
  New migrations must be safe for the currently-deployed Flutter app and Edge Functions.
- Every RPC consumed by Flutter (`get_my_training_hub`, `get_my_daily_brief`, etc.) must include an
  explicit `schema_version` field. Add fields, never remove or rename existing ones in a deployed
  migration. Only remove fields in a cleanup migration after all consuming builds are updated.

System behavior is defined in [ARCHITECTURE.md](./ARCHITECTURE.md); data classification and
retention are defined in [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

## 2. Shared Fields and Enums

Mutable user-owned tables generally include:

```text
id uuid primary key
user_id uuid not null
created_at timestamptz not null
updated_at timestamptz not null
row_version integer not null default 1
```

Common enums:

```text
goal_type         fat_loss | muscle_gain | recomposition | strength | aesthetic
plan_status       draft | proposed | active | superseded | archived
proposal_status   pending | accepted | rejected | expired | withdrawn
processing_status pending | processing | completed | failed | discarded
confidence        low | medium | high
decision_kind     onboarding | daily | weekly | on_demand
policy_outcome    allow | maintain_only | daily_adjustment_only | request_data | escalate
media_purpose     meal_analysis | progress_front | progress_side | progress_back
```

Enums use database constraints or migration-controlled application enums. Client-provided arbitrary
states are rejected.

## 3. Identity, Consent, and User State

### `auth.users` (Supabase managed)

Canonical account and identity root managed by Supabase Auth. Native Sign in with Apple identity is
linked here. Tracend does not store raw Apple identity tokens or implement a parallel
access/refresh-token table.

### `user_accounts`

One application-owned row keyed by `id = auth.users.id`, containing locale, timezone, unit system,
account status, onboarding state, and timestamps. The app writes `timezone` (the device's IANA
zone) through `set_my_timezone`, which accepts only names Postgres knows; before 2026-10 it stayed
at the default `UTC`. Email remains in Supabase Auth unless a documented
product need requires a minimized application copy.

### `consent_records`

Append-only records containing consent type, notice version, grant/withdrawal state, source, and
timestamp. Types include terms, privacy, AI coaching (`ai_coaching`), HealthKit sync, meal-photo AI,
progress-photo AI, and notifications. Current consent is the latest record per user and type.

### `ai_consent_notices` and `ai_notice_current`

Global, read-only to athletes. Each published AI notice has a version, a provider label, the
purposes it covers (`coach_chat`, `daily_coaching`, `onboarding_plan`), and its body. Notices are
never edited. `ai_notice_current` names the current notice for each purpose, one row per purpose.
`private.publish_ai_notice` inserts a notice and repoints its purposes in one transaction. An
`ai_coaching` consent counts for a purpose only when its `notice_version` is that purpose's current
version.

### `user_profiles`

One row per user containing adult-attestation timestamp, height, experience level, training
schedule, available time, activity description, and onboarding state. Do not store unnecessary
identity documents.

Since 2026-10, approval of an onboarding plan also writes the following, and only approval can
(column grants):

- `sex` (`male`, `female` or `unspecified`)
- `birth_year`
- `daily_activity`
- `equipment` (chip values)
- `limitations_note`
- `nutrition_note`
- `avoid_patterns` (movement patterns the athlete asked to avoid; read by the Coach) and
  `equipment_note`, since 2026-10-02
- `training_years` (`under_1`, `1_2`, `3_5`, `over_5`), `priority_muscles` (at most 2) and
  `strong_muscles` (at most 3), catalog target muscles, since the coach intake (2026-10); the Coach
  reads them

At the same time it writes the real `training_days` (ISO weekdays), `session_minutes`,
`height_cm` and `experience_level`. Clients can write only the fields onboarding step 0 writes.
The onboarding `current_plan` text is deliberately not kept on the profile: the approved plan
replaces it, and the onboarding feature snapshot keeps it for the audit trail. Approval dates the
plan, nutrition targets and onboarding weight with the athlete's local date
(`private.local_date_for`, from `user_accounts.timezone`).

### `onboarding_generations`

One row per onboarding plan generation, with columns:

- the snapshot hash of the reviewed answers;
- `status` (`running`, `succeeded`, `failed` or `superseded`);
- the attempt number and a lease;
- the resulting proposal;
- a failure code.

Rules:

- **One running generation per user.**
- **Claiming:** `claim_onboarding_generation` returns the running or finished generation for the
  same answers, and supersedes a generation for older answers.
- **Writes:** worker writes land only while their generation is still running and current.
- **Expiry:** an expired lease reads as `failed`, and a pending proposal past its `expires_at`
  (7 days) reads as `expired` in `get_my_onboarding_generation`, which also returns
  `proposal_expires_at`. Answering an expired proposal stores `expired` and returns it.
- **Movements to avoid:** the snapshot's `answers.avoid_patterns` (movement patterns) bind the
  stored proposal; `persist_onboarding_proposal_v3` (and v2, which delegates to it) refuses an
  exercise with an avoided pattern.
- **Apple Health:** the snapshot's `health` holds the 28-day summary used for the plan (or null),
  and `health_history` the usual months (or null), so both are part of the snapshot hash:
  connecting Apple Health builds a new plan.
- **Policy version:** the snapshot's `policy_version` (`onboarding-policy-v1` or `-v2`) is stored
  as the feature snapshot's engine version.
- **Telemetry:** `persist_onboarding_proposal_v3` adds the model call's thinking flag, latency,
  attempts, token counts and finish reason to the `onboarding.plan.generated` audit event.


### `onboarding_drafts`

One autosaved draft per user containing the selected beginner or experienced path, current section,
a bounded structured answer payload, timestamps, and row version. Drafts are user-owned under RLS
and remain separate from immutable feature snapshots and approved plans.

### `user_goals`

Versioned goals with type, priority, target direction, optional target value/date, aesthetic
emphasis, source, status, and activation period. Exactly one active goal is primary.

### `user_constraints`

Equipment, schedule constraints, exercise limitations, dietary pattern, allergies, exclusions, and
disclosed eligibility restrictions. Each entry records source, confirmation, and optional expiry.

### `user_preferences`

Confirmed training, food, schedule, communication, and notification preferences. Each preference has
category, typed value, provenance, confirmation timestamp, and optional expiry. Model-inferred
preferences cannot become confirmed automatically.

## 4. Health and Check-ins

### `health_sync_runs`

One device sync attempt with user, idempotency key, requested date window and types, returned types,
accepted/rejected counts, status, completion time, and sanitized error code. An empty type does not
prove permission denial.

### `daily_health_summaries`

One row per user, local date, and source scope containing:

- steps and active energy;
- sleep duration and supported stage totals;
- workout count and duration;
- weight when supplied by HealthKit;
- resting heart rate;
- HRV value, explicit metric, and unit;
- source/checksum metadata, completeness, and last-sync time.

The Phase 4 source scope is `healthkit`. HRV is stored only as milliseconds with the explicit `sdnn`
metric. Summaries are idempotently upserted. Incompatible HRV definitions are never combined.

### `daily_check_ins`

Daily user-reported sleep quality, energy, soreness, hunger, mood, pain, training availability,
adherence, and optional note. Rating scales are bounded. Edits preserve revision history. Red-flag
responses reach deterministic safety policy before AI.

One current revision exists per user and local date. User-scoped idempotency keys deduplicate
retries while older revisions remain immutable history.

## 5. Training

### `exercise_catalog`

Curated exercise definitions with stable slug, name, movement pattern, muscles, equipment,
laterality, level, contraindication tags, substitution group, instructions, and catalog version.
Catalog changes do not rewrite historical snapshots.

Implemented 2026-10 (`catalog-v1`, 72 exercises):

- **Columns:** slug, name, movement pattern, primary muscles (the first is the target),
  required equipment (empty means bodyweight), level, compound flag, `status`
  (`active` or `retired`) with `retired_at`, and catalog version.
- **Source:** the rows mirror `supabase/functions/_shared/onboarding/catalog.ts`, and a Deno
  test keeps the two equal.
- **Lifecycle:** exercises are retired, never deleted; generation uses only active ones.
- **Not yet implemented:** laterality, contraindication tags, substitution groups and
  instructions.

### `exercise_muscle_references`

Reviewed primary muscles for planned exercise names that are not catalog entries (2026-10-04),
for plans approved before the catalog. Columns: `name_key` (the exercise history key: lowercased,
trimmed, spaces collapsed; primary key), `name`, `primary_muscles` (the catalog's muscle groups,
1–4), `created_at`. Each row is reviewed by hand and added by migration; nothing writes it at run
time. The training hub reads a planned exercise's muscles from its catalog entry, else from this
list; it never gives such an exercise a slug, so exercise identity and history are unchanged and
the catalog stays the onboarding allowlist. RLS forced, no client access.

### `training_plans`

Plan lineage containing user, goal, title, block objective, source, and timestamps. The source
is one of:

- `ai` or `rules`: an onboarding plan, by origin;
- `mock_ai`: the Phase-2 onboarding plan;
- `user`, `imported` or `hybrid`.

Plans whose source is `ai`, `rules` or `imported` arrive with their workouts and never get the
generic seed.

### `training_plan_versions`

Immutable versions containing plan, version number, status, block length, sessions per week,
rationale, source decision, approval timestamp, and effective dates. A partial unique index allows
one active version per user.

### `planned_workouts`

Ordered workout templates containing plan version, name, objective, preferred weekday, estimated
duration, and warm-up/cool-down guidance.

Phase 3 expands these rows deterministically only after a training-plan version becomes active;
expansion does not modify the approved version.

### `planned_exercises`

Ordered prescriptions containing workout, catalog exercise and display snapshot, set count, rep
range, target RPE or reps in reserve, optional load/progression rule, rest range, notes, and
approved alternatives. `exercise_slug` (nullable, since 2026-10) references the catalog entry an onboarding plan
chose. The generic seed and the imported plan have none; since 2026-10-03 an older planned
exercise whose name is exactly one catalog name (case and spacing ignored) is linked to it by
migration, and any other name stays unlinked. `target_load_kg` (nullable, 0–2000, since
the coach intake) is the starting load Tracend set from a reported barbell top set; the training
hub (1.5) and daily brief (1.6) return it and the active workout pre-fills it.

### `onboarding_questions`

The coach's follow-up questions for one set of onboarding answers: user, `questions_hash` (the
answers and Apple Health data they were asked for), up to 3 questions (allowed topic, text, quick
answers), the reason none were asked, and the call's telemetry. `status` is `running` while one
request asks the model (until `lease_expires_at`), then `ready`. Written only by the
`onboarding-plan` function (`claim_onboarding_questions`, `store_onboarding_questions`,
`release_onboarding_questions`; service role); the athlete reads their own. The answers live in the onboarding draft (`follow_ups`, `follow_ups_hash`).

### `health_history_months`

One row per user and completed calendar month, from the app (`save_health_history`): workouts,
strength workouts, workout minutes, nights of sleep and their average, weigh-in days and their
average, days with any data, and the first and last date with data. Only months before the
athlete's current month, at most 12 back. Owner-read RLS; exported and deleted with the account.

### `workout_sessions`

Scheduled or ad hoc executions with plan/version/workout references, local date, state, start/end
times, duration, session effort/energy, completion reason, and notes.

`state` is `in_progress`, `completed` or `abandoned`. `abandon_workout` discards an open session
(audited as `workout.abandoned`); the rows stay, and every history, load and hub read counts
completed sessions only. `completion_source` (`manual`, `healthkit`, or null when no audit evidence
exists) and `session_effort_source` (`athlete`, `legacy_default`, `healthkit_default`) record
provenance; see ALGORITHMS §4 "Effort Provenance". `complete_workout_v2` is the only writer of
`athlete` effort.

### `exercise_performances`

Performed or skipped exercises with prescription reference, selected exercise, order,
substitution/skip reason, pain flag, ratings, and note.

`exercise_slug` is the catalog identity of a prescribed performance, copied from its planned
exercise by a trigger and cleared when the performance becomes a substitution or an extra
exercise. `get_my_exercise_history` keys history by slug; performances without one (older plans,
substitutions, extras) are keyed by their lowercased, trimmed name. Assisted exercises (catalog
`assisted-` slugs) rank their logged load as assistance, so less is better.

### `exercise_sets`

Set number, type, repetitions, load, RPE, completion, and rest duration. Ordering is unique within
an exercise performance.

### `workout_amendments`

Append-only corrections to completed records containing field, old/new value, reason, actor, and
time. Completed workouts are not silently rewritten.

## 6. Nutrition and Meals

### `nutrition_target_sets`

Versioned calories, protein, carbohydrate, fat, optional fiber/water, distribution guidance,
rationale, source decision, status, approval, and effective dates. Exactly one target set is active
per user.

### `food_catalog_items`

Normalized foods and products containing source, source ID, name, aliases, cuisine, preparation,
nutrient basis, serving definition, calories/macros, data-quality version, licensing attribution,
and status.

### `user_foods`

User-owned confirmed foods or recipes with serving definition, nutrients, catalog/ingredient
references, source, and revision history. Personal entries are never promoted globally without
review.

### `media_objects`

Private-object metadata containing user, purpose, opaque object key, type, byte size, checksum,
lifecycle status (`active`, `pending_deletion`, or `deleted`), capture time, retention deadline,
explicit retention exemption, and deletion time. Retention workers claim due objects before deleting
Storage bytes, then finalize or schedule a retry. Clients never use object keys as authorization.

### `meal_analyses`

Asynchronous image jobs containing user, media object, provider/model/prompt references, status,
confidence, failure code, and expiry. An analysis cannot contribute directly to nutrition totals.

### `meal_analysis_candidates`

Unconfirmed provider observations containing food label, preparation assumption, estimated
quantity/unit, calories/macros, confidence, rank, selection state, and clarification question. User
corrections remain unconfirmed until transactional meal confirmation snapshots them into meal items.

### `meals`

Meal header containing local date/time, meal type, source, optional analysis, confirmation status,
and note. Explicit record deletion removes the owned header and cascading items/candidates, emits a
sanitized audit event, and makes linked non-exempt media immediately eligible for retention cleanup.

### `meal_items`

Confirmed or manual items referencing catalog or user food, quantity, serving unit, calculated
calories/macros, nutrient-source version, and confirmation time. Daily totals include only confirmed
items.

## 7. Progress

### `body_measurements`

Date, source, weight, optional waist/chest/hip/arm/thigh measurements, protocol, confirmation, and
amendment metadata. Manual and HealthKit values retain provenance and are not silently overwritten.

An incorrect setup fixture may be explicitly superseded with timestamp and a bounded correction
reason. Progress calculations exclude superseded rows while exports retain them as correction
history.

### `progress_photo_sets`

Periodic comparison sets containing date, capture-protocol version, timing context, processing
consent, notes, and completion state.

### `progress_photos`

Links one private media object per front, side, or back pose to a photo set and stores
framing/quality results. No public URL is stored.

### `physique_analyses`

Versioned comparison result referencing baseline/current sets, provider metadata, qualitative
observations, development priorities, confidence, limitations, and validation state. It is not a
body-composition measurement or diagnosis.

**Physique check (2026-10, owner-only).** Written only by `persist_physique_analysis` (service role)
for one complete set (baseline = current). `result` holds the validated reply
(`private.is_valid_physique_result`: 1–3 catalog muscles with confidence and reason, up to three
observations, photo issues from a fixed list, limitations; no body-fat field or score can be stored),
`notice_version` the photo AI notice it ran under, and `confirmed_muscles`/`confirmed_at` what the
athlete chose with `set_my_priority_muscles` (at most two, only suggested muscles), which also writes
`user_profiles.priority_muscles`. `body_fat_range` is never written. Deleting the set deletes its
analyses first; both are in the privacy export.

### `photo_ai_notices`

The progress-photo AI notice the athlete grants before a physique check: version, provider label,
model, body. The newest is current; published by migration or `private.publish_photo_ai_notice`,
never edited. A grant is a `consent_records` row of type `progress_photo_ai` naming the version
(`has_photo_ai_consent`, `get_my_photo_ai_notice`).

### `progress_reviews`

Weekly or milestone reviews referencing a feature snapshot and optional physique analysis, with
adherence summary, observations, linked proposals, and user acknowledgement.

**Phase 7 foundation (2026-07-02).** Manual measurements are written through an authenticated
validated RPC, retain canonical units and source, and expose deterministic first-to-latest weight
and waist deltas. Photo sets, pose links, and reviews are owner-scoped under forced RLS. The
separate private `progress-photos` bucket uses purpose-bound owner paths; storage consent and
AI-processing consent remain distinct.

**Private media slice (2026-07-02).** A consent-gated RPC creates a draft set; each pose is
registered only after its owner-scoped Storage object exists. Three poses complete the set. Reads
use 60-second signed URLs; deletion removes Storage bytes before relational metadata.

**Weekly review slice (2026-07-02).** Each persisted review references an immutable weekly feature
snapshot and contains deterministic training, recovery, confirmed-nutrition, and measurement
coverage plus explicit missing data, unchanged-plan state, next focus, and acknowledgement.
User/week uniqueness makes generation idempotent. `weekly_review_jobs` owns queued, processing,
retryable, completed, failed, and cancelled lifecycle state with a three-attempt bound; queue
payloads contain only the opaque job ID.

### `notification_preferences`

One owner-scoped row stores daily check-in and weekly-review reminder toggles, the coarse iOS
authorization status, and update time. The validated RPC also appends `notifications-v1` grant or
withdrawal evidence to `consent_records`; notification content and delivery history are not stored
server-side.

## 8. Coaching and Approval

### `coach_threads` and `coach_messages`

Owner-scoped forced-RLS conversation state. Threads contain a bounded title, active/archived state,
and recent-message timestamps. Messages contain role, selectable text, validated evidence
references, missing-data labels, safety state, idempotency, and time. Thread deletion cascades
messages and writes a content-free audit event. Account deletion remains the final retention bound.
Messages also have a `search_vector` tsvector column for relevance-ranked full-text retrieval.

### `coach_narrative_entries`

Immutably versioned coaching timeline phases owned by the user. Each entry stores `phase` (phase
label), `headline` (deterministic 1-sentence summary), `since`/`until` dates, `cause_snapshot_ids`
(referencing context snapshots), and `superseded_by` (self-referencing version chain). At most one
entry is ongoing (`until is null`). Forced RLS, read-only for authenticated.

### `user_preferences`

Confirmed food, training, schedule, communication, notification, and lifestyle preferences. Each row
stores `category`, `key`, `value`, `provenance` (onboarding, chat_statement, repeated_signal,
manual), `confirmed_at`, and `superseded_at`. Only one active row per user+key. Model-inferred
preferences cannot become confirmed automatically. Forced RLS, read-only for authenticated.

### `coach_session_summaries`

Append-only deterministic daily journal entries. Each row contains `coaching_date`, `summary` (1-2
sentences), `thread_id`, and `key_snapshot_ids`. Capped at 30 recent entries per user; oldest
entries deleted on insertion. Forced RLS, read-only for authenticated.

### `feature_snapshots`

Immutable, schema-versioned coaching input containing user, trigger, date window, feature-engine
version, active plan/target references, computed features, coverage, freshness, conflicts,
missing-data flags, and data hash. Schema v2.0 adds `baselines`, `scores` (recovery, sleep_quality,
ACWR, monotony, weight_trend, macro_adherence), and `eligibility` gates to the features JSONB.

### `policy_evaluations`

Immutable deterministic result containing feature snapshot, policy version, outcome, triggered rule
codes, permitted/prohibited actions, escalation code, and time.

### `model_runs`

Operational record containing user, purpose, provider, model, prompt/schema versions, feature and
policy references, provider request ID, status, usage, latency, cost estimate, validation result,
retry lineage, and sanitized error. It never stores provider secrets.

Account usage summaries are computed from user-scoped `model_runs` through a restricted aggregate
query or RPC; they are not a second source of truth and must omit prompts, provider request
identifiers, and raw errors.

### `coach_decisions`

Immutable validated output containing decision kind/date, feature and policy references, successful
model run, Training Coach section, Nutrition Coach section, Head Coach decision, evidence, missing
data, risk flags, confidence, validity window, and feedback state.

### `change_proposals`

Bounded persistent proposal containing source decision, domain/action, current and proposed values
or versions, evidence, rationale, expected benefit/downside, confidence, effective date, expiry, and
status.

Onboarding proposals have two schema versions:

- **1.0:** the Phase-2 mock, with names only.
- **2.0 (2026-10):** the exact `weekly_structure` (workouts with catalog exercises, sets, reps,
  RPE and rest). It also records origin (`ai` or `rules`), provider, model, fallback reason, policy
  and catalog versions, and the assessment, assumptions and missing information. It shows how the
  calories were calculated.

`private.is_valid_initial_proposal_v2` checks the 2.0 structure, and the catalog is checked when the
proposal is stored and again when it is approved. v1 approval refuses 2.0 proposals.

### `change_responses`

Append-only acceptance, rejection, or revision request (with an optional `revision_note`, ≤500
characters, since 2026-10). Acceptance runs one transaction that locks
the current proposal, creates the new plan/target version, supersedes the previous version, and
writes an audit event.

### `decision_feedback`

User rating (`useful`, `unclear`, `incorrect`, or `unsafe`), optional score/note, and time. Unsafe
feedback opens review but does not automatically change policy.

### `nutrition_schedule_versions` and `nutrition_schedule_items`

Reviewed meal schedules are versioned independently of macro targets. Exactly one schedule version
is active per owner. Ordered items store slot, local time, window, planned foods/quantities,
optional state, and reminder preference. Activation supersedes the prior version transactionally and
writes an audit event. Confirmed meals may reference their schedule item; planned items never
contribute to consumed totals.

`get_my_nutrition_schedule(target_date)` gives each item a `status`: `logged` (a confirmed meal
references it), `upcoming`, `due` (within `window_minutes` either side of `local_time`), then
`optional` or `skipped`. A requested day before the athlete's today is `skipped`, a later one
`upcoming`. Since 2026-10-04 (`20261004100000`) "now" and "today" are the request's time in
`user_accounts.timezone` (an unset or unknown zone reads as UTC), not the database clock, and the
window is compared as timestamps on the requested day, so it no longer wraps around midnight.
`get_my_daily_brief.next_meal` is the first `due`, `upcoming` or `optional` item. Response 1.0 is
unchanged.

## 9. Audit and Privacy Operations

### `audit_events`

Append-only actor, user scope, action code, opaque target, request correlation ID, outcome,
sanitized metadata, and timestamp. Health values, notes, prompts, photo references, tokens, and
secrets are prohibited in audit metadata.

`workout.auto_completed` records that the user confirmed a HealthKit-detected workout as complete;
metadata includes the planned workout ID, date, duration, and source label.

### `data_exports`

Export scope, state, processing times, encrypted package reference, expiry, download count, and
failure code. Downloads require short-lived user authorization.

Phase 8 permits one complete open export per owner, stores no encryption password or key, expires
packages after seven days, and allows at most three downloads. The private Storage path is not
included in authenticated grants.

### `deletion_requests`

Opaque queued state, request/processing/completion times, and sanitized failure code. It
intentionally has no Auth foreign key so a content-free completion receipt can survive user deletion
for 180 days; it stores no email, health data, media path, prompt, or token.

Request, confirmation, schedule, processing state, completion evidence, and minimal tombstone.
Deletion covers relational data, media, jobs, caches, backups, and supported provider state
according to [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

## 10. Relationships

```text
auth.users / user_accounts
 ├── profile / goals / constraints / preferences / consent
 ├── health summaries / check-ins
 ├── training plans ─ plan versions ─ planned workouts ─ planned exercises
 ├── workout sessions ─ exercise performances ─ exercise sets
 ├── nutrition targets / meals ─ confirmed meal items
 ├── measurements / progress photo sets / physique analyses
 ├── feature snapshots ─ policy evaluations ─ coach decisions
 │                                            └── change proposals ─ responses
 └── model runs / media / audit / exports / deletion requests
```

Foreign keys, RLS policies, transactional functions, and Edge Function checks prevent cross-user
references.

## 11. Required Constraints and Indexes

- One active training-plan version and nutrition-target set per user.
- Unique `(user_id, idempotency_key)` for sync and mutating operations.
- Unique daily summary scope and progress-photo pose.
- Bounded rating scales and nonnegative nutrition/load values.
- User/date indexes for summaries, sessions, meals, measurements, and decisions.
- Expiry/status indexes for proposals, media, exports, and jobs.
- Foreign-key ownership consistency across snapshots, model runs, decisions, and proposals.

RLS is mandatory for every exposed user-owned table. Policies derive ownership from `auth.uid()`,
are least-privilege by operation, and are tested with authenticated users, anonymous access, and
cross-user attempts. Edge Functions and transactional RPC add validation but never replace RLS on
exposed data.

## 12. Future Vector Memory

Only after the gates in [ARCHITECTURE.md](./ARCHITECTURE.md) pass, add user-owned `memory_documents`
and `memory_chunks` with source record, consent basis, classification, validity dates, deletion
state, embedding provider/model/version, content hash, and vector.

Confirmed structured facts remain canonical. Retrieved text cannot override current goals,
constraints, plans, or safety policy. Source deletion removes its embeddings.

## 13. Feature Engine

### `user_baselines`

One row per user per metric. Winsorized EWMA baselines computed from `daily_health_summaries` by
`compute_user_baselines`. Row per (user_id, metric_name). Upserted on each recompute.

| Field          | Type    | Description                                       |
| -------------- | ------- | ------------------------------------------------- |
| id             | uuid PK |                                                   |
| user_id        | uuid FK | auth.users.id                                     |
| metric_name    | text    | hrv_sdnn_ms, resting_hr_bpm, sleep_minutes, weight_kg |
| baseline_value | numeric | Current EWMA                                      |
| spread         | numeric | MAD spread for z-score denominator                |
| confidence     | text    | cold_start, low, medium, high                     |
| n_observations | integer | Count of valid observations processed             |
| last_observation_date | date | Most recent daily_health_summary date used        |
| created_at     | timestamptz |                                                |
| updated_at     | timestamptz |                                                |

UNIQUE (user_id, metric_name). UNIQUE (id, user_id). Forced RLS, read-only for authenticated.

### `metric_baseline_history`

Immutable per-observation audit trail. Append-only via `compute_user_baselines` RPC. One row per raw
observation processed. Linked list via `prior_baseline_id`.

| Field               | Type    | Description                                |
| ------------------- | ------- | ------------------------------------------ |
| id                  | uuid PK |                                            |
| user_id             | uuid FK | auth.users.id                              |
| metric_name         | text    |                                            |
| observation_date    | date    | Source daily_health_summaries date         |
| raw_value           | numeric | Pre-processing value                       |
| z_score             | numeric | Post-Winsor z-score                        |
| ewma_after          | numeric | EWMA after this observation                |
| was_winsorized      | boolean | Clamped to ±3×spread boundary              |
| was_outlier_rejected | boolean | Excluded as >5×spread hard outlier         |
| lambda_used         | numeric | anti-anchoring λ (3-day → 14-day half-life)|
| prior_baseline_id   | uuid FK | Self-referential linked list               |
| created_at          | timestamptz |                                         |

Forced RLS, read-only for authenticated.

### Scoring Functions

All PostgreSQL functions, deterministic, service-only SECURITY DEFINER.

| Function                      | Signature                                    | Returns |
| ----------------------------- | -------------------------------------------- | ------- |
| `compute_winsorized_ewma`     | (values numeric[], n_obs int)                | numeric |
| `compute_user_baselines`      | (user_id uuid, date date)                    | void    |
| `compute_daily_metrics`       | (user_id uuid, date date, tz text)           | jsonb   |
| `compute_recovery_score`      | internal to compute_daily_metrics            | numeric |
| `compute_sleep_quality`       | internal to compute_daily_metrics            | numeric |
| `evaluate_change_eligibility` | (user_id uuid, snapshot_id uuid, version text) | jsonb |

### Orchestrator

`compute_daily_metrics` calls all scorers, returns JSONB with keys: `recovery_score`,
`recovery_breakdown`, `sleep_quality_score`, `acwr`, `training_monotony`, `weight_trend_7d`,
`weight_trend_28d`, `macro_adherence_pct`, `data_confidence`, `eligibility`.

Called by: `prepare_daily_coaching`, `prepare_coach_chat_v5`, health-sync post-sync trigger, nightly
`recompute_stale_metrics` cron (06:00 UTC).

### `daily_computed_metrics`

One row per user per date. Persisted scoring output from `compute_daily_metrics`. Upserted on each compute run.

| Field                        | Type    | Description                                      |
| ---------------------------- | ------- | ------------------------------------------------ |
| id                           | uuid PK |                                                  |
| user_id                      | uuid FK | auth.users.id                                    |
| local_date                   | date    | Coaching day                                     |
| recovery_score               | integer | 0–100                                           |
| sleep_quality_score          | integer | 0–100                                           |
| sleep_debt_minutes           | integer | Nullable; positive = under target                |
| daily_strain                 | numeric | sRPE total                                       |
| acwr                         | numeric | Acute:chronic ratio, nullable                    |
| training_monotony            | numeric | 7-day avg / stddev, nullable                     |
| weight_trend_7d_kg_per_day   | numeric | Nullable; OLS slope                              |
| weight_trend_28d_kg_per_day  | numeric | Nullable; OLS slope                              |
| macro_adherence_pct          | numeric | Nullable; 14-day avg capped at 200%              |
| data_confidence              | text    | cold_start, low, medium, high                    |
| scores_jsonb                 | jsonb   | Full recovery/sleep/strain/adherence breakdown   |
| baseline_snapshot_jsonb      | jsonb   | Baselines at compute time                        |
| eligibility_jsonb            | jsonb   | Change eligibility result                        |
| computed_at                  | timestamptz |                                               |
| schema_version               | text    | '2.0'                                            |

UNIQUE (user_id, local_date). Forced RLS, read-only for authenticated.

Future-date guard (`20260906140000`): `compute_daily_metrics` never folds baselines through, or persists a row for, `target_date > current_date + 1` (max civil offset UTC+14, so `current_date + 1` is the latest possible local "today" anywhere; guards the Train weekday strip / week-rail future pages). Future briefs return the parse-stable read-only payload: recovery null, z-keys zero, all components missing, stored baselines unrefreshed, `data_confidence` low. Existing future-dated rows were deleted once in the same migration (derived data; recomputed on each brief).

### Algorithm Reference

Full formula definitions with literature citations in [ALGORITHMS.md](./ALGORITHMS.md).

### Baseline Metrics (5 total)

hrv_sdnn_ms, resting_hr_bpm, sleep_minutes, weight_kg, resp_rate_bpm.

### Recovery Score Weights

| Component    | Weight | Direction                     |
| ------------ | ------ | ----------------------------- |
| HRV (SDNN)   | 0.55   | Higher = better               |
| RHR          | 0.20   | Lower = better                |
| Sleep        | 0.15   | Higher = better               |
| Resp Rate    | 0.05   | Lower = better (collected since 2026-09-06) |
| Prev Strain  | 0.05   | Lower 7-day avg = better      |

### Sleep Quality Weights

| Component    | Weight |
| ------------ | ------ |
| Duration     | 0.50   |
| Efficiency   | 0.20   |
| Restorative  | 0.20   |
| Consistency  | 0.10   |

### Confidence Tiers

- <3 observations → cold_start
- 3–6 observations → low
- 7–13 observations → medium
- ≥14 observations → high

### Schema Additions

- `daily_health_summaries.respiratory_rate_bpm` (numeric, 0–100)
- `daily_health_summaries.present_types` now includes `resp_rate`
- `persist_health_sync` accepts `resp_rate` requests and persists `respiratory_rate_bpm`
  (migration `20260906120000`); Edge contract `health_sync_v1` carries the type and key

### Health Sync Semantics

- Requested type codes: steps, active_energy, sleep, workouts, weight,
  resting_heart_rate, hrv_sdnn, resp_rate.
- Sleep attribution: consecutive sleep samples ≤ 60 min apart form one session, and the
  session is attributed to the local day it ENDS (a 23:00→07:00 night lands whole on the
  morning's row). All other metrics attribute by sample start day. Attribution is
  client-side (`normalizeHealthSamples`); the Edge function performs no bucketing.
- Sleep totals: `sleep_minutes` is the UNION of every asleep-category interval
  (unspecified + Core + Deep + REM), and each stage column is the union within that
  stage. A night can mix categories (a staged, scheduled stretch plus auto-detected
  unspecified fragments), so a category preference discards measured minutes (fixed
  2026-09-11: production stored 146 of 386 measured minutes) and a plain sum
  double-counts overlapping sources. An awake-only night is `0`, not NULL — the
  `health_sync_v1` contract couples the sleep type to a defined `sleep_minutes`, and the
  server's 1–960 scoring gate reads 0 as absence.
- Sync window: today−7 for regular syncs (8 dates), today−8 for the initial backfill
  (9 dates) — wide enough that the fetch captures a full night whose start falls the
  evening before the window's first date (HealthKit queries match by start instant).

### Constraint Additions

- `feature_snapshots.schema_version` IN ('1.0', '2.0')
- `policy_evaluations.policy_version` IN ('daily-v1', 'eligibility-v1')
- `daily_computed_metrics.schema_version` = '2.1'
- RPC schema_version: `get_my_training_hub` 1.4, `get_my_daily_brief` 1.2 (since raised: hub 1.6
  on 2026-10-03, adding plan dates, exercise muscles, completion source and `daily_load`)
- `get_my_daily_brief` 1.7 (2026-10-04, `20261004130000`) adds, without changing any 1.6 field:
  `recovery_previous` (yesterday's stored `daily_computed_metrics.recovery_score`); `plan` (the
  active plan's `title`, `version_number`, `block_weeks` and `week_number`, weeks since
  `effective_date`, else the approval date, from 1 and not capped); `week` (Monday to Sunday of
  the requested date's week: `local_date`, `recovery` and `strain` from `daily_computed_metrics`,
  today's from the live computation, `trained` when a session that day is `completed`, and
  `planned` when the active plan has a workout on that weekday); and `today_session` (the
  requested day's latest session that is not `abandoned`: its `state` and, per `exercise_order`,
  the count of `completed` sets). The Today page draws its week, plan line and session strip from
  these; nothing is derived on the phone
