# Tracend Data Model

**Status:** Authoritative logical data model  
**Store:** Supabase PostgreSQL  
**Convention:** `snake_case`, UUID primary keys, UTC timestamps

## 1. Principles

- Every user-owned record is scoped by `user_id = auth.uid()`; Supabase Auth and mandatory RLS enforce the authenticated boundary.
- Plans, targets, computed features, decisions, and accepted changes are immutable or versioned.
- AI observations remain proposals until the user confirms them.
- HealthKit data is normalized into necessary daily summaries rather than copied without purpose.
- Media bytes live in private Supabase Storage buckets. PostgreSQL stores ownership, purpose, integrity, and lifecycle metadata.
- Canonical units are kilograms, centimeters, kilocalories, grams, minutes, beats per minute, and milliseconds.
- Structured PostgreSQL fields are the MVP memory system. Vector embeddings are deferred.

System behavior is defined in [ARCHITECTURE.md](./ARCHITECTURE.md); data classification and retention are defined in [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

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

Enums use database constraints or migration-controlled application enums. Client-provided arbitrary states are rejected.

## 3. Identity, Consent, and User State

### `auth.users` (Supabase managed)

Canonical account and identity root managed by Supabase Auth. Native Sign in with Apple identity is linked here. Tracend does not store raw Apple identity tokens or implement a parallel access/refresh-token table.

### `user_accounts`

One application-owned row keyed by `id = auth.users.id`, containing locale, timezone, unit system, account status, onboarding state, and timestamps. Email remains in Supabase Auth unless a documented product need requires a minimized application copy.

### `consent_records`

Append-only records containing consent type, notice version, grant/withdrawal state, source, and timestamp. Types include terms, privacy, HealthKit sync, meal-photo AI, progress-photo AI, and notifications. Current consent is the latest record per user and type.

### `user_profiles`

One row per user containing adult-attestation timestamp, height, experience level, training schedule, available time, activity description, and onboarding state. Do not store unnecessary identity documents.

### `user_goals`

Versioned goals with type, priority, target direction, optional target value/date, aesthetic emphasis, source, status, and activation period. Exactly one active goal is primary.

### `user_constraints`

Equipment, schedule constraints, exercise limitations, dietary pattern, allergies, exclusions, and disclosed eligibility restrictions. Each entry records source, confirmation, and optional expiry.

### `user_preferences`

Confirmed training, food, schedule, communication, and notification preferences. Each preference has category, typed value, provenance, confirmation timestamp, and optional expiry. Model-inferred preferences cannot become confirmed automatically.

## 4. Health and Check-ins

### `health_sync_runs`

One device sync attempt with user, idempotency key, requested date window and types, returned types, accepted/rejected counts, status, completion time, and sanitized error code. An empty type does not prove permission denial.

### `daily_health_summaries`

One row per user, local date, and source scope containing:

- steps and active energy;
- sleep duration and supported stage totals;
- workout count and duration;
- weight when supplied by HealthKit;
- resting heart rate;
- HRV value, explicit metric, and unit;
- source/checksum metadata, completeness, and last-sync time.

Summaries are idempotently upserted. Incompatible HRV definitions are never combined.

### `daily_check_ins`

Daily user-reported sleep quality, energy, soreness, hunger, mood, pain, training availability, adherence, and optional note. Rating scales are bounded. Edits preserve revision history. Red-flag responses reach deterministic safety policy before AI.

## 5. Training

### `exercise_catalog`

Curated exercise definitions with stable slug, name, movement pattern, muscles, equipment, laterality, level, contraindication tags, substitution group, instructions, and catalog version. Catalog changes do not rewrite historical snapshots.

### `training_plans`

Plan lineage containing user, goal, title, block objective, source (`ai`, `user`, `imported`, or `hybrid`), and timestamps.

### `training_plan_versions`

Immutable versions containing plan, version number, status, block length, sessions per week, rationale, source decision, approval timestamp, and effective dates. A partial unique index allows one active version per user.

### `planned_workouts`

Ordered workout templates containing plan version, name, objective, preferred weekday, estimated duration, and warm-up/cool-down guidance.

### `planned_exercises`

Ordered prescriptions containing workout, catalog exercise and display snapshot, set count, rep range, target RPE or reps in reserve, optional load/progression rule, rest range, notes, and approved alternatives.

### `workout_sessions`

Scheduled or ad hoc executions with plan/version/workout references, local date, state, start/end times, duration, session effort/energy, completion reason, and notes.

### `exercise_performances`

Performed or skipped exercises with prescription reference, selected exercise, order, substitution/skip reason, pain flag, ratings, and note.

### `exercise_sets`

Set number, type, repetitions, load, RPE, completion, and rest duration. Ordering is unique within an exercise performance.

### `workout_amendments`

Append-only corrections to completed records containing field, old/new value, reason, actor, and time. Completed workouts are not silently rewritten.

## 6. Nutrition and Meals

### `nutrition_target_sets`

Versioned calories, protein, carbohydrate, fat, optional fiber/water, distribution guidance, rationale, source decision, status, approval, and effective dates. Exactly one target set is active per user.

### `food_catalog_items`

Normalized foods and products containing source, source ID, name, aliases, cuisine, preparation, nutrient basis, serving definition, calories/macros, data-quality version, licensing attribution, and status.

### `user_foods`

User-owned confirmed foods or recipes with serving definition, nutrients, catalog/ingredient references, source, and revision history. Personal entries are never promoted globally without review.

### `media_objects`

Private-object metadata containing user, purpose, opaque object key, type, byte size, checksum, lifecycle status, capture time, retention deadline, and deletion time. Clients never use object keys as authorization.

### `meal_analyses`

Asynchronous image jobs containing user, media object, provider/model/prompt references, status, confidence, failure code, and expiry. An analysis cannot contribute directly to nutrition totals.

### `meal_analysis_candidates`

Unconfirmed provider observations containing food label, preparation assumption, estimated quantity/unit, confidence, rank, and clarification question.

### `meals`

Meal header containing local date/time, meal type, source, optional analysis, confirmation status, and note.

### `meal_items`

Confirmed or manual items referencing catalog or user food, quantity, serving unit, calculated calories/macros, nutrient-source version, and confirmation time. Daily totals include only confirmed items.

## 7. Progress

### `body_measurements`

Date, source, weight, optional waist/chest/hip/arm/thigh measurements, protocol, confirmation, and amendment metadata. Manual and HealthKit values retain provenance and are not silently overwritten.

### `progress_photo_sets`

Periodic comparison sets containing date, capture-protocol version, timing context, processing consent, notes, and completion state.

### `progress_photos`

Links one private media object per front, side, or back pose to a photo set and stores framing/quality results. No public URL is stored.

### `physique_analyses`

Versioned comparison result referencing baseline/current sets, provider metadata, qualitative observations, development priorities, approximate body-fat range if returned, confidence, limitations, and validation state. It is not a body-composition measurement or diagnosis.

### `progress_reviews`

Weekly or milestone reviews referencing a feature snapshot and optional physique analysis, with adherence summary, observations, linked proposals, and user acknowledgement.

## 8. Coaching and Approval

### `feature_snapshots`

Immutable, schema-versioned coaching input containing user, trigger, date window, feature-engine version, active plan/target references, computed features, coverage, freshness, conflicts, missing-data flags, and data hash.

### `policy_evaluations`

Immutable deterministic result containing feature snapshot, policy version, outcome, triggered rule codes, permitted/prohibited actions, escalation code, and time.

### `model_runs`

Operational record containing user, purpose, provider, model, prompt/schema versions, feature and policy references, provider request ID, status, usage, latency, cost estimate, validation result, retry lineage, and sanitized error. It never stores provider secrets.

### `coach_decisions`

Immutable validated output containing decision kind/date, feature and policy references, successful model run, Training Coach section, Nutrition Coach section, Head Coach decision, evidence, missing data, risk flags, confidence, validity window, and feedback state.

### `change_proposals`

Bounded persistent proposal containing source decision, domain/action, current and proposed values or versions, evidence, rationale, expected benefit/downside, confidence, effective date, expiry, and status.

### `change_responses`

Append-only acceptance, rejection, or revision request. Acceptance runs one transaction that locks the current proposal, creates the new plan/target version, supersedes the previous version, and writes an audit event.

### `decision_feedback`

User rating (`useful`, `unclear`, `incorrect`, or `unsafe`), optional score/note, and time. Unsafe feedback opens review but does not automatically change policy.

## 9. Audit and Privacy Operations

### `audit_events`

Append-only actor, user scope, action code, opaque target, request correlation ID, outcome, sanitized metadata, and timestamp. Health values, notes, prompts, photo references, tokens, and secrets are prohibited in audit metadata.

### `data_exports`

Export scope, state, processing times, encrypted package reference, expiry, download count, and failure code. Downloads require short-lived user authorization.

### `deletion_requests`

Request, confirmation, schedule, processing state, completion evidence, and minimal tombstone. Deletion covers relational data, media, jobs, caches, backups, and supported provider state according to [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

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

Foreign keys, RLS policies, transactional functions, and Edge Function checks prevent cross-user references.

## 11. Required Constraints and Indexes

- One active training-plan version and nutrition-target set per user.
- Unique `(user_id, idempotency_key)` for sync and mutating operations.
- Unique daily summary scope and progress-photo pose.
- Bounded rating scales and nonnegative nutrition/load values.
- User/date indexes for summaries, sessions, meals, measurements, and decisions.
- Expiry/status indexes for proposals, media, exports, and jobs.
- Foreign-key ownership consistency across snapshots, model runs, decisions, and proposals.

RLS is mandatory for every exposed user-owned table. Policies derive ownership from `auth.uid()`, are least-privilege by operation, and are tested with authenticated users, anonymous access, and cross-user attempts. Edge Functions and transactional RPC add validation but never replace RLS on exposed data.

## 12. Future Vector Memory

Only after the gates in [ARCHITECTURE.md](./ARCHITECTURE.md) pass, add user-owned `memory_documents` and `memory_chunks` with source record, consent basis, classification, validity dates, deletion state, embedding provider/model/version, content hash, and vector.

Confirmed structured facts remain canonical. Retrieved text cannot override current goals, constraints, plans, or safety policy. Source deletion removes its embeddings.
