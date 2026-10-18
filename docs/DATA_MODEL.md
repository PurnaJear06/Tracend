# Tracend Data Model

**Status:** Authoritative logical data model\
**Store:** Supabase PostgreSQL\
**Convention:** `snake_case`, UUID primary keys, UTC timestamps

The migrations in `supabase/migrations` are the source of truth; this document describes their
final state. Entities that are part of the logical design but have no table yet are marked **Not
built**. Work scheduled by the coaching platform program
([`plans/coaching-platform-2026-10/README.md`](./plans/coaching-platform-2026-10/README.md)) is
marked **Planned** with its phase and chunk.

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
- Structured PostgreSQL fields are the MVP memory system. Vector embeddings of user data are
  deferred; only the research library (section 13) holds embeddings, and it holds no user data.
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
user_id uuid not null references user_accounts(id) on delete cascade
created_at timestamptz not null
updated_at timestamptz not null
row_version integer not null default 1
```

Most user-owned tables also carry `unique (id, user_id)` so child rows can reference a parent with
a composite foreign key that proves the same owner.

Postgres enums:

```text
account_status               active | deletion_pending | deleted
unit_system                  metric | imperial
onboarding_state             not_started | in_progress | completed
onboarding_path              beginner | experienced
experience_level             beginner | intermediate | advanced
consent_type                 terms | privacy | progress_photo_storage | progress_photo_ai |
                             notifications | ai_coaching | meal_photo_ai
consent_action               granted | withdrawn
goal_type                    fat_loss | muscle_gain | recomposition | strength | aesthetic
goal_status                  draft | active | superseded
version_status               draft | proposed | active | superseded | archived
proposal_status              pending | accepted | rejected | revision_requested | expired
proposal_response_action     accept | reject | request_revision
workout_session_state        in_progress | completed | abandoned
health_sync_status           completed | partial | failed
health_summary_completeness  complete | partial
policy_outcome               allow | maintain_only | daily_adjustment_only | request_data | escalate
model_run_status             succeeded | failed
meal_status                  draft | confirmed | discarded
meal_source                  manual | fixture_analysis | photo_analysis
weekly_review_job_status     queued | processing | retryable | completed | failed | cancelled
```

Other closed value sets use check constraints, for example media purpose (`meal_analysis`,
`progress_front`, `progress_side`, `progress_back`, `progress_lower`) and confidence (`low`,
`medium`, `high`). Client-provided arbitrary states are rejected.

## 3. Identity, Consent, and User State

### `auth.users` (Supabase managed)

Canonical account and identity root managed by Supabase Auth. A Sign in with Apple identity would
be linked here (not built; owner builds use email/password). Tracend does not store raw identity
tokens or implement a parallel access/refresh-token table. Email stays in Supabase Auth.

### `private.signup_invites`

The beta invite list: lowercased email (primary key), note, created time, and who claimed it and
when. Only the SQL editor reaches it. The sign-up trigger (`private.handle_new_auth_user`) refuses
an email that is not listed and claims the invite otherwise; every account that existed when the
list was introduced was seeded as claimed. Deleting the Auth user deletes the invite it claimed,
an unclaimed invite for its current email, and the waitlist signups for both (trigger
`auth_user_forget_invite`).

### `private.waitlist_signups`, `private.waitlist_attempts`, `private.waitlist_secret`

The website waitlist. A signup holds the lowercased email, status (`pending`, `confirmed`,
`unsubscribed`), SHA-256 hashes of the confirm and unsubscribe link tokens, the confirm link's
expiry (7 days), send count and time, an 8-character Crockford referral code and who referred it,
the consent version and time, invite time, browser time zone and `utm_*` tags. Attempts keep an
HMAC of the visitor's IP (salt in `waitlist_secret`) for one day, for the limit of 5 joins an hour
per network. No API role can read any of them; the Edge Functions use the service-role-only
`public.waitlist_join`, `waitlist_confirm`, `waitlist_unsubscribe` and `waitlist_unsent`. A daily
job (`tracend-waitlist-cleanup`) deletes signups never confirmed 30 days after their last email.
The owner invites with `private.invite_from_waitlist(n)`: confirmed, not yet invited signups, most
confirmed referrals first, then signup order, into `private.signup_invites`.

### `user_accounts`

One application-owned row keyed by `id = auth.users.id`: locale, `timezone` (IANA name, default
`UTC`), unit system, account status, onboarding state, and timestamps. The app writes `timezone`
only through `set_my_timezone`, which accepts only names Postgres knows; clients cannot write the
column directly. Readers such as the weekly-review scheduler go through `private.safe_timezone`,
and `private.local_date_for` gives the athlete's local date.

### `consent_records`

Append-only records: consent type, notice version, action (`granted` or `withdrawn`), source
(`owner_development` or `ios_app`), and time. Current consent is the latest record per user and
type. Clients may insert only `user_id`, `consent_type`, `notice_version`, `action` and `source`;
`created_at` always takes its default. At most 100 records a day per user. HealthKit permission is
held by iOS, not here.

### `ai_consent_notices` and `ai_notice_current`

Global, read-only to athletes. Each published notice has a version, a `provider_label`, the
purposes it covers (`coach_chat`, `daily_coaching`, `onboarding_plan`), its body, and `provider`:
the vendor that receives the data (`anthropic`, `deepseek`, `groq` or `gemini`; null on notices
published before vendor ids existed). `provider` is never an API shape such as an
OpenAI-compatible endpoint, since one shape reaches several vendors. Notices are never edited.

`ai_notice_current` names the current notice for each purpose, one row per purpose.
`private.publish_ai_notice(version, provider, provider_label, purposes, body)` inserts a notice and
repoints its purposes in one transaction. It refuses (22023) a `provider_label` that does not name
the provider's company (Anthropic, DeepSeek, Groq, Google; case ignored) or names another one. The
older four-argument form refuses (22023) since migration code 17, which also filled `provider` on
every earlier notice row.

An `ai_coaching` consent counts for a purpose only when its `notice_version` is that purpose's
current version (`has_ai_coaching_consent`, service role). `get_ai_consent_v2(target_user_id,
purpose)` (service role) returns `{schema_version, granted, provider, notice_version}` for the
notice current for a purpose or gateway feature: Coach chat and library context map to the
`coach_chat` notice, the daily decision to `daily_coaching`, onboarding plan and questions to
`onboarding_plan`, meal vision to the meal photo notice and physique vision to the photo notice.
A null `provider` makes the gateway refuse until a notice naming the route's vendor is granted.

### `user_profiles`

One row per user: adult-attestation time, eligibility, experience level, height, training days
(ISO weekdays), session minutes, and row version. Clients can write only the fields onboarding
step 0 writes. Approval of an onboarding plan writes the rest, and only approval can (column
grants):

- `sex` (`male`, `female` or `unspecified`), `birth_year`, `daily_activity`;
- `equipment` (chip values) and `equipment_note`;
- `avoid_patterns` (movement patterns the athlete asked to avoid; read by the Coach);
- `limitations_note` and `nutrition_note`;
- `training_years` (`under_1`, `1_2`, `3_5`, `over_5`), `priority_muscles` (at most 2) and
  `strong_muscles` (at most 3), catalog target muscles that the Coach reads; and
- the real `training_days`, `session_minutes`, `height_cm` and `experience_level`.

`set_my_priority_muscles` also writes `priority_muscles` from a physique check (section 7). The
onboarding `current_plan` text is deliberately not kept on the profile: the approved plan replaces
it, and the onboarding feature snapshot keeps it for the audit trail. Approval dates the plan,
nutrition targets and onboarding weight with the athlete's local date. Identity documents are
never stored.

### `user_goals`

Goals with type, priority (1–5), status (`draft`, `active`, `superseded`), a `details` object
with the goal's specifics such as a target weight (at most 16 KB), and activation time. Exactly one active goal is primary. At most 200 goals per user.

**Goal target (B7).** The end point of a goal lives in `details` under `target_weight_kg`,
`target_body_fat_pct_min`, `target_body_fat_pct_max`, `target_physique` (`visible_abs`,
`more_definition`, `athletic_build`, `bigger_muscles`, `stronger`, `lean_and_toned`, `other`),
`target_physique_note` (at most 120 characters), `target_date` and `target_set_at`, so the frozen
Coach athlete file already carries it. Any other `details` weight (such as `current_weight_kg`) is
the weight on the day the goal was written and is never a current or starting figure.
`set_goal_target_v1(...)` (authenticated, `auth.uid()`, security definer) replaces the whole target
on the active goal, requires a weight, a body-fat range or a physique goal (a date alone is not a
target), refuses a weight outside 30 to 300 kg or below BMI 18.5 at `user_profiles.height_cm`, a
reversed or out-of-range body-fat range, and a date that is not within the next three years, and
writes a `goal_target_set` audit event naming only the kinds of target set. `get_goal_target_v1()`
returns the target and `min_target_weight_kg`; both return `schema_version "1.0"`.
`get_goal_phase_inputs_v1(uuid)` is service role only and feeds the Coach goal phase review. Only
the athlete sets a target; the model has no path to these functions.

**Phase (A8).** An approved Coach proposal that changes the phase (`cut`, `maintenance`,
`diet_break`, `gain`) supersedes the active goal and inserts a new active goal row with
`details.phase`, `phase_started_on` and (for a diet break) `phase_ends_on`, and a new
`user_goals.source_proposal_id` naming the proposal. `activated_at` is carried over unless the goal
type changed, so "weeks into the goal" keeps counting through a diet break. A target in the
proposal replaces the old target keys; without one the old target stays. Undo inserts the earlier
goal again as a new row.

### `user_constraints` (Not built)

The logical design holds equipment, schedule constraints, exercise limitations, dietary pattern,
allergies, exclusions and disclosed eligibility restrictions, each with source, confirmation and
optional expiry. Today equipment, movements to avoid, limitations and diet notes live on
`user_profiles`.

### `user_preferences` (superseded by `coach_facts`)

Since A10 part 2 nothing in Coach chat reads or writes this table (the confirmed preferences were
copied into `coach_facts` when that table was created). Older app builds can still write it through
`persist_coach_preference`; "Forget everything" empties it. Kept until the frozen `prepare_coach_chat_v8`
is retired. Confirmed food, training, schedule, communication, notification and lifestyle preferences. Each row
stores `category`, `key` (1–120 characters), `value` (1–200 characters), `provenance`
(`onboarding`, `chat_statement`, `repeated_signal`, `manual`), `confirmed_at` and `superseded_at`.
Only one active row per user and key; a new value supersedes the old one. Model-inferred
preferences cannot become confirmed automatically. Forced RLS, read-only for authenticated. The app
confirms a preference through `persist_coach_preference`, which refuses any athlete but the caller
unless the caller is the service role.

### `notification_preferences`

One owner-scoped row: daily check-in and weekly-review reminder toggles, the coarse iOS
authorization status, and update time. The validated RPC (`save_my_notification_preferences`) also
appends `notifications-v1` grant or withdrawal evidence to `consent_records`. Notification content
and delivery history are not stored server-side.

### `onboarding_drafts`

One autosaved draft per user: the selected beginner or experienced path, current section, a
bounded answer payload (at most 128 KB, including the follow-up answers `follow_ups` and
`follow_ups_hash`), timestamps, and row version. Drafts are user-owned under RLS and remain
separate from immutable feature snapshots and approved plans.

### `onboarding_screenings`

The pre-plan health check (coaching platform Contract 8, chunk B6): one row per distinct set of
answers, so every answer the athlete gave stays on record. Columns: `id`, `user_id`,
`exercises_regularly`, `known_disease` (a known heart, metabolic or kidney condition), `symptoms`
(a current sign or symptom), `cleared_by_professional` (false when not asked), `outcome`
(`cleared`, `moderate_until_cleared` or `see_professional`) and `screened_at`. The newest row per
user is current; no row reads as `cleared`.

- **Written only by `record_screening_v1`** (the athlete's own session; it audits
  `onboarding_screening_recorded` with the outcome only). It works out the outcome in the database
  (`private.screening_outcome`), adds no row when the newest row has the same answers, and answers
  `{schema_version, outcome, screened_at}`. A check constraint makes a stored outcome that
  disagrees with its answers impossible. The same rule lives in
  `_shared/training/screening/screening.ts`, and both tests hold the same sixteen-row table.
- **RLS:** owner read only (`user_id = auth.uid()`); clients cannot insert, update or delete.
- **Privacy:** included in `privacy-export`; deleted with the account (cascade).
- The answers also sit in the onboarding draft payload (`screening`) so a plan request can read
  them; an old draft without the key reads as cleared.

### `onboarding_generations`

One row per onboarding plan generation: the snapshot hash of the reviewed answers, `status`
(`running`, `succeeded`, `failed` or `superseded`), the attempt number, a lease, the resulting
proposal (set exactly when `succeeded`), and a failure code.

- **One running generation per user.**
- **Claiming:** `claim_onboarding_generation` returns the running or finished generation for the
  same answers, and supersedes a generation for older answers.
- **Writes:** worker writes land only while their generation is still running and current.
- **Expiry:** an expired lease reads as `failed`, and a pending proposal past its `expires_at`
  (7 days) reads as `expired` in `get_my_onboarding_generation`, which also returns
  `proposal_expires_at`. Answering an expired proposal stores `expired` and returns it.
- **Movements to avoid:** the snapshot's `answers.avoid_patterns` bind the stored proposal;
  `persist_onboarding_proposal_v3` (and v2, which delegates to it) refuses an exercise with an
  avoided pattern.
- **Apple Health:** the snapshot's `health` holds the 28-day summary used for the plan (or null),
  and `health_history` the usual months (or null), so both are part of the snapshot hash:
  connecting Apple Health builds a new plan.
- **Policy version:** the snapshot's `policy_version` (`onboarding-policy-v1` or `-v2`) is stored
  as the feature snapshot's engine version.
- **Telemetry:** `persist_onboarding_proposal_v3` adds the model call's thinking flag, latency,
  attempts, token counts and finish reason to the `onboarding.plan.generated` audit event.

### `onboarding_questions`

The coach's follow-up questions for one set of onboarding answers: user, `questions_hash` (the
answers and Apple Health data they were asked for), up to 3 questions (allowed topic, text, quick
answers), the reason none were asked, and the call's telemetry. `status` is `running` while one
request asks the model (until `lease_expires_at`), then `ready`. Written only by the
`onboarding-plan` function (`claim_onboarding_questions`, `store_onboarding_questions`,
`release_onboarding_questions`; service role); the athlete reads their own. The answers live in the
onboarding draft.

## 4. Health and Check-ins

### `health_sync_runs`

One device sync attempt: user, idempotency key, requested date window (at most 31 days) and types,
returned types, accepted and rejected counts, status, completion time, and sanitized error code. An
empty type does not prove permission denial. At most 120 syncs an hour per user.

### `daily_health_summaries`

One row per user, local date and source scope (`healthkit`):

- steps and active energy;
- sleep minutes and stage totals (awake, light, deep, REM);
- workout count and minutes;
- weight when supplied by HealthKit;
- resting heart rate;
- respiratory rate (`respiratory_rate_bpm`, 0–100);
- HRV value (`hrv_value_ms`) with its explicit metric (`sdnn`) and unit (`ms`);
- night HRV (`hrv_sleep_ms`: the mean of readings taken during the night that ends on this date,
  a sleep session of three hours or more) and morning HRV (`hrv_morning_ms`: readings taken
  04:00–12:00 outside sleep), both subsets of the day's HRV and null without `hrv_value_ms`. HRV
  and breathing readings taken asleep belong to the morning the night ends on; a nap's breathing
  readings are left out;
- `present_types`, hashed source references and checksum, completeness, and sync times.

Summaries are idempotently upserted by `persist_health_sync_v2` (frozen for the coaching platform
program). Incompatible HRV definitions are never combined.

**Sync semantics.**

- Requested type codes: `steps`, `active_energy`, `sleep`, `workouts`, `weight`,
  `resting_heart_rate`, `hrv_sdnn`, `resp_rate`. The `health_sync_v1` contract also carries
  `hrv_sleep_ms` and `hrv_morning_ms` (0–1000, never without `hrv_value_ms`).
- Sleep attribution: consecutive sleep samples at most 60 minutes apart form one session, and the
  session belongs to the local day it ends (a 23:00→07:00 night lands whole on the morning's row).
  Other metrics attribute by sample start day. Attribution is done on the phone
  (`normalizeHealthSamples`); the Edge Function does no bucketing.
- Sleep totals: `sleep_minutes` is the union of every asleep interval (unspecified, Core, Deep,
  REM), and each stage column is the union within that stage. A night can mix categories, so
  preferring one category would discard measured minutes and a plain sum would double-count
  overlapping sources. An awake-only night is `0`, not null; the server's 1–960 scoring gate reads
  0 as absence.
- Sync window: today−7 for regular syncs (8 dates), today−8 for the first backfill (9 dates), wide
  enough to capture a full night that starts the evening before the window's first date.

### `health_workout_references`

Bounded HealthKit workout facts for reconciliation: hashed sample and source ids, activity type,
start, end, duration, optional energy, local date, and last sync time. Routes, heart-rate series and
unrelated raw samples are not copied. Unique per user and sample hash.

### `health_history_months`

One row per user and completed calendar month, from the app (`save_health_history`): workouts,
strength workouts, workout minutes, nights of sleep and their average, weigh-in days and their
average, days with any data, and the first and last date with data. Only months before the
athlete's current month, at most 12 back. Owner-read RLS; exported and deleted with the account.

### `daily_check_ins`

Daily user-reported sleep quality, energy, soreness, hunger and mood (1–5), pain severity (0–10),
availability to train, and an optional note (at most 1,000 characters). Red-flag responses reach
deterministic safety policy before AI.

One current revision exists per user and local date (`superseded_at` is null). User-scoped
idempotency keys deduplicate retries while older revisions remain immutable history.

## 5. Training

### `exercise_catalog`

Curated exercise definitions (`catalog-v1`, 72 exercises): slug (primary key), name, movement
pattern, primary muscles (the first is the target), required equipment (empty means bodyweight),
level (`beginner`, `intermediate`), compound flag, `status` (`active` or `retired`) with
`retired_at`, and catalog version. The rows mirror
`supabase/functions/_shared/onboarding/catalog.ts`, and a Deno test keeps the two equal. Exercises
are retired, never deleted; generation uses only active ones. Catalog changes do not rewrite
historical snapshots.

**Catalog v2 (B1, migration `20261015170021_exercise_catalog_v2.sql`).** Additive columns, mirrored
from `_shared/onboarding/catalog_v2.ts` (a Deno test keeps them equal):

- `secondary_muscles` (`text[]`, default empty): muscles trained indirectly, never a primary muscle;
- `knee_stress`, `back_stress`, `shoulder_stress` (`low`, `moderate`, `high`): rated with the
  in-house method in `_shared/training/standard/joint_stress.ts`, for choosing swaps and range
  limits (D6), never for diagnosis;
- `regressions`, `progressions` (`text[]` of slugs): easier and harder forms of the same movement
  pattern, mirrored both ways;
- `substitutes` (`text[]` of slugs): mutual alternatives sharing the pattern or the target muscle;
- `load_step_kg` (nullable): the smallest load increase of the loading implement (per dumbbell or
  kettlebell); null for bodyweight, bar, bench and band exercises;
- `exercise_role` (`variation`, `regression`, or null for the standard form): B0's ranking role.

No exercise links to itself; the migration refuses an unrated row or a link to a missing slug, and
pgTAP checks both. Nothing reads the new columns yet: `onboarding-plan` still selects the v1
columns and the rules plan reads roles from `catalog.ts`, so today's plans are unchanged (a Deno
test proves it byte for byte). The rule data B2 uses with them (rep ranges, rest, weekly sets,
progression steps, each value with a source) lives in `_shared/training/standard/`, not in SQL.

Not built: laterality and instructions.

### `exercise_muscle_references`

Reviewed primary muscles for planned exercise names that are not catalog entries, for plans
approved before the catalog. Columns: `name_key` (the exercise history key: lowercased, trimmed,
spaces collapsed; primary key), `name`, `primary_muscles` (the catalog's muscle groups, 1–4),
`created_at`. Each row is reviewed by hand and added by migration; nothing writes it at run time.
The training hub reads a planned exercise's muscles from its catalog entry, else from this list;
it never gives such an exercise a slug, so exercise identity and history are unchanged and the
catalog stays the onboarding allowlist. RLS forced, no client access.

### `training_plans`

Plan lineage: user, optional goal, title, source, and creation time. The source is one of:

- `ai` or `rules`: an onboarding plan, by origin;
- `mock_ai`: the Phase-2 onboarding plan;
- `user`, `imported` or `hybrid`.

Plans whose source is `ai`, `rules` or `imported` arrive with their workouts and never get the
generic seed.

### `training_plan_versions`

Immutable versions: plan, version number, status, block weeks (1–24), sessions per week,
prescription object, rationale, source proposal, approval time, and effective date. A partial
unique index allows one active version per user. A temporary block (A8) is an ordinary active
version with `ends_on` (its last day), `block_kind` (`temporary_block`, `intensity`, `focus` or
`next_session`) and `restores_version_id` (the version it replaced); the three are set together
or not at all. After `ends_on` the replaced version returns as a **new** version
(`private.end_plan_block`), by an hourly job (`tracend-end-plan-blocks`) and by every Coach
proposal read and answer, which end a due block for the caller first. Versions only grow: approval,
undo and the end of a block all insert a version and supersede the old one, and nothing is edited
in place. When an active version is inserted for a plan
whose source is not `ai`, `rules` or `imported`, a trigger seeds the generic planned workouts
deterministically; seeding does not modify the approved version.

### `planned_workouts`

Ordered workout templates: plan version, order (1–7), name, objective, preferred weekday, estimated
minutes, and warm-up and cool-down guidance.

### `planned_exercises`

Ordered prescriptions: planned workout, order, display-name snapshot, set count, rep range, target
RPE, rest seconds, and notes.

- `exercise_slug` (nullable) references the catalog entry an onboarding plan chose. The generic
  seed and the imported plan have none; an older planned exercise whose name is exactly one
  catalog name (case and spacing ignored) was linked by migration, and any other name stays
  unlinked.
- `target_load_kg` (nullable, 0–2000) is the starting load Tracend set from a reported barbell top
  set. The training hub and daily brief return it and the active workout pre-fills it.

### `workout_sessions`

Executions of a planned workout: plan version, planned workout, local date and time zone, state,
idempotency key and client revision, start and completion times, duration, session energy (1–5),
session effort (1–10), notes, actual start and end, logging completeness (0–1), and correction
status (`none`, `needs_review`, `corrected`). One open session per planned workout.

`state` is `in_progress`, `completed` or `abandoned`. `abandon_workout` discards an open session
(audited as `workout.abandoned`); the rows stay, and every history, load and hub read counts
completed sessions only. `completion_source` (`manual`, `healthkit`, or null when no audit evidence
exists) and `session_effort_source` (`athlete`, `legacy_default`, `healthkit_default`) record
provenance; see ALGORITHMS §4 "Effort Provenance". `complete_workout_v2` is the only writer of
`athlete` effort.

### `exercise_performances`

One row per exercise in a session: order, `status` (`unknown`, `performed` or explicitly
`skipped`), `performance_kind` (`prescribed`, `substituted` or `extra`), the planned exercise
(required unless `extra`), `performed_name` and `substitution_reason` (required for a
substitution), `provenance` (`tracend`, `owner_correction`, `imported`), rest seconds, pain flag
and note.

`exercise_slug` is the catalog identity of a prescribed performance, copied from its planned
exercise by a trigger and cleared when the performance becomes a substitution or an extra
exercise. `get_my_exercise_history` keys history by slug; performances without one (older plans,
substitutions, extras) are keyed by their lowercased, trimmed name. Assisted exercises (catalog
`assisted-` slugs) rank their logged load as assistance, so less is better.

### `exercise_sets`

Set number (unique within its performance), repetitions, load, RPE, completion flag, and the set
timing columns (all nullable):

| Column | Type | Rule |
|---|---|---|
| `started_at` | timestamptz | when the set began (see below) |
| `completed_at` | timestamptz | when it was ticked; `>= started_at` |
| `rest_before_seconds` | integer | rest taken from the previous tick to `started_at`, 0–3600 |
| `rir` | smallint | reps in reserve 0–5 (5 means 5 or more) |
| `timing_source` | text | `app` or `watch` |

A set begins at the end of the rest before it (Skip, or the timer's end), else at the athlete's
first edit of its kg or reps outside a rest. It has no start when it was ticked during its rest or
without an edit, and no rest when the gap is longer than an hour. The app takes every time from the
wall clock, so a rest that ran out while the phone slept ended at its stored end time. Undo clears
a set's times and re-measures any rest counted from its tick.

When the athlete picks reps left, the app also writes `rpe = 10 − rir`, the value the same answer
meant on the earlier 1–10 picker, so RPE readers (Coach context) stay consistent.

`sync_workout_draft` (program Contract 2) keeps a stored value when a set omits the key (installed
builds send none), clears it on an explicit null, and refuses (22023) a malformed value, a time more
than 10 minutes in the future or more than 10 minutes before the session's recorded start, and an
end before the start. Set times from before the server's recorded start stay on the phone and are
never sent (a workout started offline). A set sends only the keys it knows: one restored from a
draft without them (saved by an older build) sends none until the athlete ticks, un-ticks or
answers reps left on it, so it never clears times or reps left another device stored; un-ticking
sends explicit nulls. If the server still refuses the times (a phone clock more than 10 minutes
off), the app sends the same draft again without the five keys and syncs the rest of that workout
without them; the reps left still arrive as the matching RPE. A workout whose final sync is refused
is not finished. `get_my_workout_session` 1.1 and `get_my_exercise_history` 1.1 (last session's
sets) return the five fields; the privacy export selects every column.

### `exercise_set_heart_rate`

One heart-rate summary per set (program Contract 4), computed on the phone from Apple Health
samples; raw samples never leave the phone. Primary key `exercise_set_id` (the set, cascade), `user_id`
(account, cascade), and:

| Column | Type | Rule |
|---|---|---|
| `start_bpm` | smallint | reading nearest the set's start (within 10 s); null when none, 30–250 |
| `peak_bpm` | smallint | highest reading during the set; null when none, 30–250, not below start or end |
| `end_bpm` | smallint | reading nearest the set's end (within 10 s); null when none, 30–250 |
| `drop_30s_bpm` | smallint | `end_bpm` minus the reading nearest 30 s later; negative when it rose; null when either is missing |
| `drop_60s_bpm` | smallint | the same at 60 s |
| `coverage` | numeric(4,3) | 0–1, the share of the set plus 60 s, in 10-second slots, that holds a reading |
| `sample_count` | integer | readings from the set's start to 60 s after its end, 1–5000 |
| `source` | text | `watch_workout` (median gap between readings 10 s or less, at least three readings) or `background` |
| `created_at`, `updated_at` | timestamptz | `updated_at` moves when a later read replaces the row |

A set with no reading in its window has no row, and a missing value is never guessed. RLS is on and
forced (`user_id = auth.uid()` select only; clients cannot insert, update or delete).
`persist_set_heart_rate_v1(session_id, summaries)` (security definer, own workouts that are not
discarded, 1 to 100 summaries, each naming a finished set by `exercise_order` and `set_number`)
upserts one row per set and returns `{schema_version: "1.0", session_id, saved}`; invalid values and
unknown or unfinished sets raise 22023, another athlete's workout P0002. The app saves again when a
later read has more readings (the Watch syncs after the workout). `get_my_set_heart_rate_v1(session_id)`
returns `{schema_version: "1.0", session_id, sets: [...]}` with the Contract 4 columns keyed by
exercise order and set number. The privacy export lists the table and account deletion removes it
through the cascade. Heart rate does not change a load or a prescription (D9).

### `sleeping_heart_rate_nights` (shadow mode, C3, migration code 33)

One derived row per athlete and night (primary key `user_id`, `local_date`; `user_id` cascades with
the account). The phone works it out from Apple Health sleep and heart-rate samples; samples never
leave it. **SHADOW MODE (program decision D10):** stored and exported, read by no score, readiness
line, brief, baseline or Coach context until a later reviewed change. The pgTAP test
`sleeping_heart_rate_shadow_test.sql` proves the recovery score and baselines do not move when nights
are stored and that no function other than the save mentions the table.

| Column | Type | Rule |
|---|---|---|
| `local_date` | date | the local day the night ends on (the day Apple Health sleep is attributed to); at most one day after the server's date (timezones ahead of UTC), not over 400 days old |
| `median_bpm` | smallint | median of the readings taken asleep, 30–200 |
| `lowest_bpm` | smallint | the lowest mean of any 10-minute slot asleep that holds at least 2 readings (never one reading; a night with no such slot is not sent), 30–200, not above the median |
| `sample_count` | integer | readings asleep, 1–20000 (the phone sends a night only with at least 20) |
| `asleep_minutes` | integer | 1–1440 (the phone sends a night only with at least 180) |
| `coverage` | numeric(4,3) | 0–1, share of the night's 10-minute slots that hold a reading (the phone sends a night only at 0.5 or more) |
| `created_at`, `updated_at` | timestamptz | `updated_at` moves when a later read replaces the row |

RLS is on and forced (select own rows only; no direct insert, update or delete).
`persist_sleeping_heart_rate_v1(nights)` (security definer, authenticated, 1 to 14 nights) upserts per
night and returns `{schema_version: "1.0", saved, skipped}`. A night with an invalid value is skipped and
counted in `skipped` (one bad night does not lose the others, and the phone also drops a night outside
these bounds before sending); a request that is null, not a list or not 1 to 14 nights raises 22023. The privacy export lists
the table and account deletion removes it through the cascade.

**Heart-rate profile inputs (C3).** The profile (resting heart rate, estimated maximum, zones,
recovery after sets) is not stored. It is computed on demand by deterministic code (Dart in the app,
TypeScript for the Coach, with shared test cases) from
`get_my_heart_rate_inputs_v1(local_date default today)` (security definer, authenticated, own data,
date within 2 days of today) and, for the Coach's contributor, `get_heart_rate_inputs_v1(target_user,
local_date)` (service role only). Both return the same object, `schema_version` 1.0:
`{schema_version, as_of, birth_year, resting: [{local_date, bpm}], sets: [...], peak_candidates: [...]}`.
`resting` holds Apple Health resting heart rate of the last 14 days between 30 and 120 bpm, oldest first;
`sets` the recovery sets, newest first: per-set summaries (above) with a 60-second drop, an end heart rate
and 60%+ coverage, from the last 28 days and the 28 days before, each window capped at 200 on its own after
that filter, each with its workout's `local_date`; `peak_candidates` the 10 sets with the highest *trusted* peaks of the last 365 days: the trust rules
(Watch workout, 8+ readings, 60%+ coverage, 120 bpm up to the age ceiling, 210 with no age) are applied
before the limit, so untrusted higher peaks never crowd out a valid lower one. The SQL ceiling is the
formula + 21 (a superset of the exact check), and the profile code applies the exact one.
Discarded workouts are left out. Sleeping heart rate is never in the object.

### `workout_amendments`

Append-only corrections to completed sessions: field path, old and new value, reason, and time.
Completed workouts are not silently rewritten.

### `workout_reconciliations`

Matches between a workout session and a HealthKit workout reference: status (`suggested`,
`confirmed`, `rejected`, `conflict`), confidence (0–1), overlap seconds, duration difference, and
confirmation time (set exactly when `confirmed`). Candidate retrieval ranks one best unresolved
candidate per session; confirmation (`respond_workout_reconciliation`) closes competing
suggestions in the same transaction.

## 6. Nutrition and Meals

### `nutrition_target_sets`

Versioned calories, protein, carbohydrate and fat, rationale, source proposal, status, approval
time, and effective date. Exactly one target set is active per user.

### `nutrition_schedule_versions` and `nutrition_schedule_items`

Reviewed meal schedules are versioned independently of macro targets. Exactly one schedule version
is active per owner. Ordered items store slot, label, local time, window minutes, planned foods,
optional flag, and reminder preference. Activation supersedes the prior version transactionally and
writes an audit event. Confirmed meals may reference their schedule item; planned items never
contribute to consumed totals.

`get_my_nutrition_schedule(target_date)` (1.0) gives each item a `status`: `logged` (a confirmed
meal references it), `upcoming`, `due` (within `window_minutes` either side of `local_time`), then
`optional` or `skipped`. A requested day before the athlete's today is `skipped`, a later one
`upcoming`. "Now" and "today" are the request's time in `user_accounts.timezone` (an unset or
unknown zone reads as UTC), and the window is compared as timestamps on the requested day, so it
never wraps around midnight. `get_my_daily_brief.next_meal` is the first `due`, `upcoming` or
`optional` item.

### `food_catalog_items` (Not built)

The logical design holds normalized foods and products with source, aliases, cuisine, preparation,
nutrient basis, serving definition, calories and macros, data-quality version, licensing
attribution, and status. Today meal items carry a name snapshot and their own nutrients.

### `user_foods`

User-owned confirmed foods: name, serving label, calories and macros, and revision. Personal
entries are never promoted globally without review.

### `media_objects`

Private-object metadata: user, purpose, opaque object key, content type (`image/jpeg`,
`image/png`, `image/heic`), byte size (at most 10 MB), checksum, lifecycle status (`active`,
`pending_deletion`, `deleted`), retention deadline, retention exemption, and deletion time. Meal
photos get a 7-day deadline at upload; progress photos are exempt (deleted with their set or the
account). Retention workers claim due objects before deleting Storage bytes, then finalize or
schedule a retry. Clients never use object keys as authorization.

Keys follow the app's upload grammar (`<uid>/meal/<request id>.<ext>`,
`<uid>/progress/<set id>/<pose>.<ext>`), and the RPC that records a key requires an uploaded object
the caller owns (`private.is_owned_media_key`). The constraint `media_objects_object_key_safe`
keeps keys inside the owner's folder with no dot segments, `//`, `\`, `%` or control characters
(added `NOT VALID`, so older rows are not rechecked).

### `meal_photo_ai_notices`

The meal photo AI notice the athlete grants before an analysis: version, `provider` (`deepseek`,
`groq`, `gemini` or `anthropic`), provider label, model, body. The newest is current; published by
`private.publish_meal_photo_ai_notice` (with the same label check as `publish_ai_notice`), never
edited. A grant is a `consent_records` row of type `meal_photo_ai` naming the version
(`has_meal_photo_ai_consent`, `get_meal_photo_ai_consent`, `get_my_meal_photo_ai_notice`).

### Meal analysis

There is no separate analysis-job table (`meal_analyses` is **Not built**): `meal-analyze` answers
within the request. The draft meal holds the media object; the provider and model are recorded in
`ai_usage_events` and in the `meal.photo.candidates_created` audit event.

### `meal_analysis_candidates`

Unconfirmed provider observations for one meal: order, food label, serving label, calories and
macros, confidence, and selection state. `persist_meal_photo_candidates` replaces them and accepts
only approved provider and model pairs. User corrections remain unconfirmed until transactional
confirmation snapshots them into meal items. An analysis never contributes directly to nutrition
totals.

### `meals`

Meal header: local date and time zone, meal type (`breakfast`, `lunch`, `dinner`, `snack`), source,
status (`draft`, `confirmed`, `discarded`), idempotency key, optional media object, optional
schedule item, note, and confirmation time. Explicit record deletion (`delete_my_meal`) removes the
owned header and cascading items and candidates, emits a sanitized audit event, and makes linked
non-exempt media immediately eligible for retention cleanup.

### `meal_items`

Confirmed items: optional user food, name snapshot, serving label, calories and macros, and
confirmation time. Daily totals include only confirmed items.

## 7. Progress

### `body_measurements`

Date, source (`manual` or `healthkit`), weight, optional waist, chest, hip, arm and thigh, protocol
version, confirmation time, and amendment metadata. Manual and HealthKit values keep provenance and
are not silently overwritten. Measurements are written through an authenticated validated RPC
(`save_body_measurement`).

Only one effective manual measurement is current per user and date. Re-entry creates an immutable
amendment (`amended_from_id`) and supersedes the prior row (`superseded_at`, with a bounded
`correction_reason`). Progress calculations exclude superseded rows while exports keep them as
correction history.

### `progress_photo_sets`

Comparison sets: capture date, capture-protocol version, timing context, processing consent, notes,
and status (`draft`, `complete`). A consent-gated RPC creates a draft set. At most 10 new sets a day
per user.

### `progress_photos`

Links one private media object per pose (`front`, `side`, `back`, `lower`) to a photo set, with a
quality status. Each pose is registered only after its owner-scoped Storage object exists, and the
fourth pose completes the set. No public URL is stored. Reads use 60-second signed URLs; deletion
removes Storage bytes before relational metadata.

### `physique_analyses`

Versioned comparison result referencing baseline and current sets, with provider and model,
confidence, limitations, and validation state. It is not a body-composition measurement or
diagnosis.

The owner-only physique check writes it only through `persist_physique_analysis` (service role)
for one complete set (baseline = current). `result` holds the validated reply
(`private.is_valid_physique_result`: 1–3 catalog muscles with confidence and reason, up to three
observations, photo issues from a fixed list, limitations; no body-fat field or score can be
stored), `notice_version` the photo AI notice it ran under, and `confirmed_muscles`/`confirmed_at`
what the athlete chose with `set_my_priority_muscles` (at most two, only suggested muscles), which
also writes `user_profiles.priority_muscles`. `body_fat_range` is never written. Deleting the set
deletes its analyses first (`delete_my_progress_photo_set`); both are in the privacy export.

### `photo_ai_notices`

The progress-photo AI notice the athlete grants before a physique check: version, `provider`
(same values as `ai_consent_notices.provider`; null on earlier notices), provider label, model,
body. The newest is current; published by migration or
`private.publish_photo_ai_notice(version, provider, provider_label, model, body)` (with the same
label check), never edited. A grant is a `consent_records` row of type `progress_photo_ai` naming
the version (`has_photo_ai_consent`, `get_my_photo_ai_notice`).

### `progress_reviews`

Weekly reviews: review week, schema version, deterministic summary, the weekly feature snapshot
it was built from, generation kind (`deterministic`), and acknowledgement time. The summary holds
training, recovery, confirmed-nutrition and measurement coverage plus explicit missing data,
unchanged-plan state and next focus. User and week uniqueness makes generation idempotent.

### `weekly_review_jobs`

Queue state for weekly reviews: review week (a Monday), status (`queued`, `processing`,
`retryable`, `completed`, `failed`, `cancelled`), attempts (at most 3), queue message id,
sanitized error code, and times. Queue payloads contain only the opaque job ID.

## 8. Coaching and Approval

### `coach_threads` and `coach_messages`

Owner-scoped forced-RLS conversation state. Threads hold a bounded title, active or archived
state, and last-message time. Messages hold role, text (at most 12,000 characters), validated
evidence references, missing-data labels, safety state (`allowed`, `limited`, `refused`,
`unavailable`), `answer_source` (`model` or `data_summary`), idempotency key, time, and a generated
`search_vector` for relevance-ranked full-text retrieval. Thread deletion cascades messages and
writes a content-free audit event. At most 50 new threads a day and 1,000 in all per user. Account
deletion is the final retention bound.

A10 adds two nullable columns on an assistant message, written by the Edge Function with the service
role and never by the app (the app has select only): `guard_faults text[]` (rule names with counts,
for example `rule:numbers_not_grounded:2`, `outcome:repair_timeout`, and
`fallback:provider_response_invalid` when the turn ended in the data summary) and `lookups text[]`
(the lookups a turn ran with their row counts, for example `exercise_history:14`). Names and counts
only, never message content; a check limits each to 12 entries of `[a-z0-9_:]`. Row-level security
limits both to the message's owner.

E3's production pass (migration `20261018170044_library_search_v3`) adds `library_version text`
(16 lower-case hex characters, checked): the research library version the turn searched
(`private.library_version()`, returned on every `search_library_v3` row), written by coach-chat with
the turn trace on a model answer whose library search returned rows. It says which library content
the answer was shown; it holds no content.

#### Coach data lookups and baseline reads (A10, migration code 20)

Read-only `SECURITY DEFINER` functions, granted to `service_role` only, each returning
`schema_version` `1.0` (the user id comes from the authenticated Edge Function call; dates of
records such as plan versions and goals are the athlete's local days, `private.local_day`):

- Baseline, `(p_user_id, p_local_date)`: `get_coach_plan_state_v1` (the active plan's sessions with
  exercises, the sessions finished this ISO week, equipment and movements to avoid, and the next
  targets from `get_progression_summary_v1`), `get_coach_nutrition_state_v1` (the week's days with
  complete flags, the target, the schedule with what is logged, what was eaten today, where meals
  came from), `get_coach_data_index_v1` (first and last date and count per kind of record).
- Lookups (ten), `(p_user_id, p_from, p_to, p_filter)`, range cut to 400 days, rows capped:
  `coach_lookup_workouts_v1`, `_exercise_history_v1`, `_meals_v1`, `_body_v1`, `_check_ins_v1`,
  `_recovery_v1`, `_plan_history_v1`, `_goals_v1`, `_weekly_reviews_v1`,
  `_health_history_v1`. Check-in notes are cut to 300 characters; a goal returns its target keys only
  (never the free-form details).
- `private.nutrition_day_totals` and `private.nutrition_complete_day_rules` define a complete
  logging day (ALGORITHMS.md section 6); `evaluate_change_eligibility` averages complete days only.

`coach_messages.proposal_id` (nullable, A8) points at the Coach proposal an assistant reply
introduced (`on delete set null`). `link_coach_proposal_v1` (service role) sets it once the reply is
stored and sets `change_proposals.source_message_id` the other way; the thread load returns it, so
the card shows live and on reload. `get_coach_proposals_context_v1(user, local_date)` (service role)
feeds the Coach context: the running block and its last day, the goal phase and its end date (a
phase or block that has ended is reported as ended), proposals waiting and how recent ones were
answered.


### `coach_context_snapshots`

The prepared Coach context for one question or decision: thread, schema version, trigger kind
(`chat`, `daily`, `weekly`, `plan_review`), coaching date, the context object, and its SHA-256
checksum. Coach chat preparation writes it with the prepared athlete file.
Deleting a thread deletes its snapshots.

Coach chat preparation (`prepare_coach_chat`, under every `prepare_coach_chat_v*` layer) works on
the athlete's own date: `private.local_date_for` (the account time zone, UTC when unset), not the
server's UTC date. The day's `daily` feature snapshot is picked by its `features.local_date`, and a
snapshot made for an athlete with a plan is not reused after the plan is gone, or the reverse. It
has no spending limit of its own: `coach-chat` reserves budget before preparing anything
(`reserve_ai_budget`, which reads `private.ai_budget_limits`), and `budget_warning` is true when the
month's spend (recorded and reserved) reaches 80% of `per_person_monthly_usd`, the same threshold as
`get_my_ai_budget_state().warning` (before migration code 19 chat's warning was the literal USD 3 and the budget state's was half the stop).

An athlete with no active plan or no active nutrition target can still chat (a plan is needed
for the daily decision, `prepare_daily_coaching`, which still raises `approved plan required`;
chat uses `private.prepare_daily_coaching_core` with `for_chat`). The context says so in
`plan_status`: `has_active_plan`, `has_nutrition_target`, `reason` (`null`, `no_approved_plan`, or
`see_professional` when the newest screening says so), `screening_outcome` and `screened_on` (null
when never screened). `active_plan` and `nutrition_targets` are null, and
`APPROVED_PLAN_ACTIVE` is not in `permitted_evidence`.

### `coach_facts` and `coach_notes` (A10 part 2, migration code 20)

**`coach_facts`** holds what the athlete confirmed for Coach, in a closed vocabulary: `kind` is one of
`injury_limitation`, `schedule_constraint`, `equipment`, `food_like`, `food_dislike`, `allergy`,
`exercise_like`, `exercise_dislike`, `coaching_style`, `other_preference` (goal, target and screening
keep their own tables). Each row has a `subject` (short, lower case, 1 to 60 characters), a
`statement` (the athlete's words, 1 to 200), a `source` (`athlete_typed`,
`coach_suggestion_confirmed`, `onboarding`), `confirmed_at`, `reconfirm_at` (injuries 28 days and
schedule constraints 90 days after confirmation, else null), `lineage_id` and `version`. A fact is
versioned: an edit or "still true" supersedes the current row (`superseded_at`) and adds the next
version; at most one active row per user, kind and subject; at most 60 active facts. Forced RLS,
read-only for authenticated; every write is an athlete action through `save_coach_fact_v1`,
`reconfirm_coach_fact_v1`, `delete_coach_fact_v1` (deletes every version) or
`forget_coach_memory_v1`, each audited without the athlete's words. No Edge Function and no model
writes a fact (Architecture 2).

**`coach_notes`** holds Coach's own short notes, written by `persist_coach_note_v1` (service role)
after a reply, from rules and structured fields, never from the Coach's prose: `entry_kind`
(`conversation`, or `advice` for a proposal the athlete answered), `note_date`, `summary` (a template
sentence), `topics` and `concerns` (closed lists), `advice` and `commitments` (jsonb, at most 4 each),
`follow_through` (`followed`, `partly`, `not_followed`, set once a week has passed), `message_ids`
(the messages it came from), `proposal_id` and `expires_at` (60 days). An athlete keeps at most 20 notes: the newest, except that a note still waiting for its
follow-through check (a training-days commitment under 28 days old) is kept ahead of the others. A note for a conversation with `coach_threads.remember = false` is refused. Deleting
a conversation deletes its notes. Forced RLS, read-only for authenticated; the athlete deletes a note
with `delete_coach_note_v1`. Notes are untrusted when read back.

`change_proposals` gains `memory_noted_at` (set once, never cleared) and `source_remembered` (copied
from the conversation by a trigger when `source_message_id` is set; true for proposals that existed
when the column was added, false for a new one until it is linked to a reply in a remembered
conversation, so a proposal that never gets linked is never noted). "Forget
everything" also marks every proposal made so far noted (answered or pending) and removes the older preference, journal and
narrative sections from the athlete's stored `coach_context_snapshots` (with their checksum).

`coach_threads.remember` (default true) marks a conversation the athlete asked Coach not to remember
(`create_coach_thread_v2`): no notes, no suggested facts, excluded from `coach_lookup_past_messages_v1`
and `search_coach_messages`, and left out of every other conversation's context by
`prepare_coach_chat_v9`.

### `coach_narrative_entries` (never written)

Versioned coaching timeline phases owned by the user: `phase`, `headline` (deterministic one-
sentence summary), `since`/`until` dates, `cause_snapshot_ids`, and `superseded_by` (version
chain). At most one entry is ongoing (`until is null`). Forced RLS, read-only for authenticated.

### `coach_session_summaries` (superseded by `coach_notes`)

Nothing writes this table since A10 part 2 (the per-turn summary recycled the Coach's own prose).
Append-only deterministic daily journal entries: `coaching_date`, `summary` (1–2 sentences),
`thread_id`, and `key_snapshot_ids`. Only the 30 newest entries per user are kept. Forced RLS,
read-only for authenticated.

### `feature_snapshots`

Immutable, schema-versioned coaching input: user, trigger kind (`onboarding`, `daily`, `weekly`),
schema version (`1.0` or `2.0`), feature-engine version, features, coverage, missing-data flags, and
data hash (unique per user). Schema 2.0 adds `baselines`, `scores` (recovery, sleep quality, ACWR,
monotony, weight trend, macro adherence) and `eligibility` gates to the features.

### `policy_evaluations`

Immutable deterministic result: feature snapshot, policy version (`daily-v1` or
`eligibility-v1`), outcome, triggered rule codes, and permitted and prohibited actions.

### `model_runs`

Operational record of a Coach chat or daily-decision call: user, purpose (`daily_coaching`,
`coach_chat`), provider, model, prompt version, schema version, feature snapshot and policy
references, idempotency key, status, validation result, usage, latency, cost estimate, and
sanitized error. It never stores provider secrets. `provider` is the vendor that received the data:
`mock`, `gemini`, `groq`, `deepseek` or `anthropic`.

Account usage summaries are computed from user-scoped `model_runs` through a restricted RPC
(`get_my_ai_usage`); they are not a second source of truth and omit prompts, provider request
identifiers, and raw errors.

### `ai_usage_events`

Usage of the other AI features: purpose (`meal_vision`, `progress_vision`, `onboarding_plan`,
`onboarding_questions`), provider (`gemini`, `groq`, `deepseek`, `anthropic`), model, token
counts, cost estimate, and latency. Model ids are pinned for the vision vendors; onboarding
purposes and `anthropic` accept any well-formed model id (at most 100 characters). Written by
`record_ai_usage_event` (service role).

### `ai_budget_reservations` and `private.ai_budget_limits`

A reservation holds a call's place in the AI budget until its usage is recorded (COST_MODEL):
purpose, reserved cost, and settlement time. `reserve_ai_budget` holds the purpose's fixed ceiling;
`reserve_ai_budget_v2` holds the caller's route ceiling (USD 0.001 to 0.50) and maps gateway
feature names onto the same purposes. `private.ai_budget_limits` is a single row with the global
monthly stop.

### `coach_decisions`

Immutable validated daily decision: kind (`daily`), local date, feature snapshot, policy evaluation,
the model run, Training Coach, Nutrition Coach and Head Coach sections, evidence, confidence,
missing data, risk flags, and validity window.

### `change_proposals`

Bounded persistent proposal: feature snapshot, schema version, proposed training and nutrition,
evidence, rationale, expected benefit, downside, confidence, effective date, expiry, and status.

Onboarding proposals have two schema versions:

- **1.0:** the Phase-2 mock, with names only.
- **2.0:** the exact `weekly_structure` (workouts with catalog exercises, sets, reps, RPE and
  rest). It also records origin (`ai` or `rules`), provider, model, fallback reason, policy and
  catalog versions, and the assessment, assumptions and missing information. It shows how the
  calories were calculated.

`private.is_valid_initial_proposal_v2` checks the 2.0 structure, and the catalog is checked when the
proposal is stored and again when it is approved. v1 approval refuses 2.0 proposals.

> **Planned (Phase 4 / B4, Contract 5):** same-day readiness adjustments
> (`get_my_day_adjustment_v1`, `respond_to_day_adjustment_v1`), answered by the athlete with an
> audit event (migration code 24).

**Coach proposals (3.0, chunk A8).** Coach asks for a change in chat; rules compute it and the
athlete approves it with one tap. A 3.0 row has no feature snapshot (`feature_snapshot_id` is now
nullable; 1.0 and 2.0 rows still require one) and adds `proposal_kind` (`temporary_block`,
`training_schedule`, `exercise_swap`, `intensity_or_phase`, `goal_or_phase`, `nutrition_targets`,
`next_session_adjustment`), `proposal_payload` (`{training?, nutrition?, goal?}`: what approval
writes), `before_snapshot` and `after_snapshot` (the card's rows and sessions), `basis` (the active
training, nutrition and goal version ids and the screening outcome it was computed from),
`source_message_id` (the chat message, set null if the message is deleted), `ends_on`,
`applied_at`, `undo_until` (seven days after approval), `undone_at` and `applied_changes` (the ids
approval created and replaced, and the profile values it changed, for undo). `proposed_training` and
`proposed_nutrition` hold a short summary, so the frozen Coach context still lists the proposal and
how the athlete answered. The payload's structure and bounds are checked by
`private.is_valid_coach_proposal_row` (training, nutrition, goal), and `persist_coach_proposal_v1`
also refuses calories under the sex minimum, a target weight below BMI 18.5 and a basis that is no
longer current. A newer pending proposal replaces an open one that would change the same thing.

| RPC | Caller | Purpose |
| --- | --- | --- |
| `get_coach_proposal_inputs_v1(uuid)` | service role | profile, screening outcome, active plan with sessions, nutrition, goal, change-eligibility gates, whether today's session is done |
| `persist_coach_proposal_v1(...)` | service role | stores one pending proposal, expires the ones it replaces, writes `coach_proposal_created` |
| `get_my_coach_proposals_v1(p_proposal_id, p_limit)` | athlete | the card: status, rationale, before and after, `can_undo`; ends a due block first |
| `respond_to_coach_proposal_v1(proposal_id, action, note)` | athlete | `approve`, `decline` or `change`; approve re-checks pending, expiry, basis and screening and writes the new version(s) |
| `undo_coach_proposal_v1(proposal_id)` | athlete | restores what approval replaced, as new versions, within seven days |

All return `schema_version "1.0"`. Approval records a proposal as `expired` (and reports the
reason) when it is past `expires_at`, when the active plan, nutrition or goal is no longer the one
in `basis`, when a temporary block's last day has passed, or when a block is already running; it
also runs again what the build checked. `basis.gates` names the change-eligibility gates the build
required (`nutrition_change`, `training_change`), and both persist and approval run them; persist
stores `weight_check_kg` (the newest weight reading) and `profile_check` (the profile fields the
rules read), and approval expires the proposal when the weight has moved by more than 1% or any
profile field differs. Approval also re-checks the calorie minimum and that every catalog slug is
still active. Reasons: `expired`, `plan_changed`, `nutrition_changed`, `goal_changed`,
`not_eligible`, `below_minimum`, `catalog_changed`, `profile_changed`, `weight_changed`,
`block_over`, `block_running`. It raises 55000 when the health check became stricter since the
proposal was built. Undo restores the profile only for values still as the proposal set them
(`applied_changes.profile_after`), holds the returning plan to the current health check (effort 7 or
lower under `moderate_until_cleared`, as when a block ends) and raises 55000 under
`see_professional`. `get_coach_proposal_inputs_v1` ends a due block first, so an ended block is never
read as running. Undo reports
`superseded` when a later change replaced the versions the proposal created, and
`undo_window_ended` after seven days, instead of raising. Audit events: `coach_proposal_created`,
`_accepted`, `_declined`, `_changed`, `_expired`, `_undone` and `coach_proposal_block_ended`.

### `change_responses`

Append-only acceptance, rejection, or revision request, one per proposal, with an optional
`revision_note` (at most 500 characters). Acceptance runs one transaction that locks the current
proposal, creates the new plan and target versions, supersedes the previous versions, and writes an
audit event.

### `decision_feedback` (Not built)

The logical design holds a user rating (`useful`, `unclear`, `incorrect`, or `unsafe`), optional
score and note, and time. Unsafe feedback opens review but does not automatically change policy.

## 9. Feature Engine

Deterministic scores computed in PostgreSQL. Formulas and citations are in
[ALGORITHMS.md](./ALGORITHMS.md).

### `user_baselines`

One row per user and metric: winsorized EWMA baselines computed from `daily_health_summaries` by
`compute_user_baselines`, upserted on each recompute.

| Field                 | Type        | Description                                            |
| --------------------- | ----------- | ------------------------------------------------------ |
| id                    | uuid PK     |                                                        |
| user_id               | uuid FK     | `user_accounts.id`                                     |
| metric_name           | text        | `hrv_sdnn_ms`, `resting_hr_bpm`, `sleep_minutes`, `weight_kg`, `resp_rate_bpm`, `hrv_sleep_ms`, `hrv_morning_ms` |
| baseline_value        | numeric     | Current EWMA                                           |
| spread                | numeric     | MAD spread for the z-score denominator, ≥ 0            |
| n_observations        | integer     | Valid observations processed                           |
| confidence            | text        | `cold_start`, `low`, `medium`, `high`                  |
| last_calculated_at    | timestamptz |                                                        |
| last_observation_date | date        | Most recent summary date used                          |
| engine_version        | text        | Default `baseline-v1`                                  |

UNIQUE (user_id, metric_name). Forced RLS, read-only for authenticated. Confidence tiers: fewer
than 3 observations `cold_start`, 3–6 `low`, 7–13 `medium`, 14 or more `high`.

### `metric_baseline_history`

Append-only per-observation trail written by `compute_user_baselines`: metric, baseline value,
spread and observation count after the observation, observation date, raw value, whether it was
winsorized (clamped to ±3 × spread) or rejected as an outlier (beyond 5 × spread), the λ used
(3-day half-life for the first eight observations, then 14-day), `prior_baseline_id` (linked list),
engine version, and creation time. Forced RLS, read-only for authenticated.

### `daily_computed_metrics`

One row per user and date, upserted by `compute_daily_metrics`.

| Field                        | Type        | Description                                    |
| ---------------------------- | ----------- | ---------------------------------------------- |
| id                           | uuid PK     |                                                |
| user_id                      | uuid FK     | `user_accounts.id`                             |
| local_date                   | date        | Coaching day                                   |
| recovery_score               | integer     | 0–100                                          |
| sleep_quality_score          | integer     | 0–100                                          |
| sleep_debt_minutes           | integer     | Nullable; positive = under target              |
| daily_strain                 | numeric     | sRPE total                                     |
| acwr                         | numeric     | Acute:chronic ratio, nullable                  |
| training_monotony            | numeric     | 7-day mean / standard deviation, nullable      |
| weight_trend_7d_kg_per_day   | numeric     | Nullable; OLS slope                            |
| weight_trend_28d_kg_per_day  | numeric     | Nullable; OLS slope                            |
| macro_adherence_pct          | numeric     | Nullable; 14-day mean capped at 200%           |
| data_confidence              | text        | `cold_start`, `low`, `medium`, `high`          |
| scores_jsonb                 | jsonb       | Full recovery, sleep, strain, adherence detail |
| baseline_snapshot_jsonb      | jsonb       | Baselines at compute time                      |
| eligibility_jsonb            | jsonb       | Change eligibility result                      |
| computed_at                  | timestamptz |                                                |
| schema_version               | text        | `2.3` on every computed row (column default `2.0`; older rows keep their value) |

UNIQUE (user_id, local_date). Forced RLS, read-only for authenticated.

### Functions

All deterministic PostgreSQL functions; the security-definer ones are service-only.

| Function                      | Signature                                         | Returns |
| ----------------------------- | ------------------------------------------------- | ------- |
| `compute_winsorized_ewma`     | (metric_values numeric[], n_obs integer)          | numeric |
| `compute_user_baselines`      | (target_user_id uuid, target_date date)           | void    |
| `compute_daily_metrics`       | (target_user_id uuid, target_date date, target_timezone text) | jsonb |
| `evaluate_change_eligibility` | (target_user_id uuid, coaching_date date)         | jsonb   |
| `recompute_stale_metrics`     | ()                                                | integer |

`compute_daily_metrics` refreshes baselines and returns `{baselines, scores, today_raw,
data_confidence}`. `scores` holds `recovery`, `recovery_mode` (`night` or `morning`),
`recovery_settled`, `recovery_breakdown` (z-scores, weights and `missing_components`),
`sleep_quality`, `sleep_breakdown`, `sleep_debt_minutes`, `daily_strain`, `acwr`,
`training_monotony`, the 7- and 28-day weight trends with the 28-day R², and
`macro_adherence_pct`. It is called by `prepare_daily_coaching`, Coach chat preparation
(`prepare_coach_chat_v7`, which `prepare_coach_chat_v8` builds on), `get_my_daily_brief`, and the
nightly `recompute_stale_metrics` Cron job (06:00 UTC).

Future dates: it never folds baselines through, or persists a row for, a date later than
`current_date + 1` (UTC+14 makes that the latest possible local today). A future brief gets a
read-only payload: recovery null, z-keys zero, all components missing, stored baselines unchanged,
`data_confidence` low.

### Score weights

Recovery, night score (the morning estimate's weights are in ALGORITHMS §1, Recovery Modes; night
HRV is scored against `hrv_sleep_ms`, morning HRV against `hrv_morning_ms`):

| Component    | Weight | Direction                     |
| ------------ | ------ | ----------------------------- |
| HRV (SDNN)   | 0.55   | Higher = better               |
| RHR          | 0.20   | Lower = better                |
| Sleep        | 0.15   | Higher = better               |
| Resp rate    | 0.05   | Lower = better                |
| Prev strain  | 0.05   | Lower 7-day mean = better     |

Sleep quality:

| Component    | Weight |
| ------------ | ------ |
| Duration     | 0.50   |
| Efficiency   | 0.20   |
| Restorative  | 0.20   |
| Consistency  | 0.10   |

### Read-model versions

- `get_my_training_hub` 1.7: `next_targets` (below) added to 1.6's plan dates, exercise muscles,
  completion source and `daily_load`. Every 1.6 key is unchanged.
  - `next_targets`: one entry per active-plan exercise with logged sets in the last 180 days, in
    plan order: `planned_exercise_id`, `exercise_key` (catalog slug, else the name key), `name`,
    `action` (`add_load`, `add_reps`, `hold`, `lower`), `reason` (`top_of_range`, `within_range`,
    `top_no_step`, `incomplete`, `effort`, `below_range`, `stall`, `away`, `skipped`, `pain`),
    `load_kg` (null without a load), `reps`, `sets`, `confidence` (`high`, or `low` when reps in
    reserve were not logged for every working set) and `basis` (`last_date`; `recent`, up to three
    sessions latest first, each `local_date`, `load_kg`, `sets`, `min_reps`, `total_reps`,
    `min_rir`, `effort_known`, `pain`). An exercise without logged sets has no entry.
  - `get_progression_summary_v1(p_user_id)` (service role only) returns `{schema_version: '1.0',
    targets}` with the same entries, for Coach context.
- `get_my_daily_brief` 1.8:
  - `recovery_previous` (yesterday's stored `recovery_score`);
  - `plan` (the active plan's `title`, `version_number`, `block_weeks` and `week_number`, weeks
    since `effective_date`, else the approval date, from 1 and not capped);
  - `week` (Monday to Sunday of the requested date's week: `local_date`, `recovery` and `strain`
    from `daily_computed_metrics`, today's from the live computation, `trained` when a session
    that day is `completed`, and `planned` when the active plan has a workout on that weekday);
  - `today_session` (the requested day's latest session that is not `abandoned`: its `state` and,
    per `exercise_order`, the count of `completed` sets); and
  - `computed` with `scores.recovery_mode`, `scores.recovery_settled`, the breakdown's
    `check_in_z` and `weights`, `today_raw.hrv_scored_ms` and `.resting_hr_scored_bpm`, and
    `baselines` including `hrv_sleep_ms` and `hrv_morning_ms`; `missing_components` may list
    `check_in`.

  The Today page draws its week, plan line and session strip from these; nothing is derived on the
  phone.

## 10. Audit and Privacy Operations

### `audit_events`

Append-only user scope, action code, target type and opaque target id, outcome (`succeeded` or
`rejected`), sanitized metadata, and time. Health values, notes, prompts, photo references, tokens,
and secrets are prohibited in audit metadata.

`workout.auto_completed` records that the user confirmed a HealthKit-detected workout as complete;
metadata includes the planned workout ID, date, duration, and source label.

### `data_exports`

Export scope (`complete`), status (`queued`, `processing`, `ready`, `failed`, `expired`), times,
encrypted package path and size, expiry, download count (at most 3), queue message id, and failure
code. One open export per owner. No encryption password or key is stored; packages expire after
seven days. Downloads require short-lived user authorization, and the private Storage path is not
included in authenticated grants.

### `deletion_requests`

Opaque queued state (`queued`, `processing`, `completed`, `failed`), queue message id,
request, start and completion times, and sanitized failure code. It intentionally has no Auth
foreign key so a content-free completion receipt can survive user deletion for 180 days; it stores
no email, health data, media path, prompt, or token. Deletion covers relational data, media, jobs,
caches, backups, and supported provider state according to
[SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md).

## 11. Relationships

```text
auth.users / user_accounts
 ├── profile / goals / preferences / consent / notification preferences
 ├── health summaries / workout references / history months / check-ins
 ├── training plans ─ plan versions ─ planned workouts ─ planned exercises
 ├── workout sessions ─ exercise performances ─ exercise sets
 │                   └── reconciliations ─ health workout references
 ├── nutrition targets / schedules / meals ─ candidates / confirmed meal items
 ├── measurements / progress photo sets ─ photos / physique analyses
 ├── feature snapshots ─ policy evaluations ─ model runs ─ coach decisions
 │                    └── change proposals ─ responses
 ├── coach threads ─ messages / context snapshots / narrative / session summaries
 └── usage / budget reservations / media / audit / exports / deletion requests
```

Foreign keys, RLS policies, transactional functions, and Edge Function checks prevent cross-user
references.

## 12. Required Constraints and Indexes

- One active training-plan version, nutrition-target set and nutrition schedule per user.
- Unique `(user_id, idempotency_key)` for sync and mutating operations.
- Unique daily summary scope and progress-photo pose.
- Bounded rating scales and nonnegative nutrition/load values.
- User/date indexes for summaries, sessions, meals, measurements, and decisions.
- Expiry/status indexes for proposals, media, exports, and jobs.
- Foreign-key ownership consistency across snapshots, model runs, decisions, and proposals.
- Per-user row caps raise SQLSTATE 54000 (`private.enforce_user_row_limit`; SECURITY_PRIVACY §7).

RLS is mandatory for every exposed user-owned table. Policies derive ownership from `auth.uid()`,
are least-privilege by operation, and are tested with authenticated users, anonymous access, and
cross-user attempts. Edge Functions and transactional RPC add validation but never replace RLS on
exposed data.

## 13. Research Library and Future Vector Memory

### Research library (D3, migration `20261015150041_research_library`)

Open papers, guidelines, position stands and in-house summaries in our own words, for Coach answers
and plan explanations. No user data; not exposed by the Data API (`private` schema); forced RLS
with no policies; no grants to `anon`, `authenticated` or `service_role`. Edge Functions reach it
only through service-role functions. Not part of privacy export or account deletion. `pgvector`
lives in the `extensions` schema. The tables are empty until ingestion.

> **Planned (Phase 3 / E2):** ingestion and the first 30 sources. **Phase 3 / E3 (code 43):** the
> library inside Coach chat. **Phase 4 / E4 (code 44):** regional modules.

#### `private.library_sources`

| Field          | Type        | Description                                                         |
| -------------- | ----------- | ------------------------------------------------------------------- |
| id             | uuid PK     |                                                                     |
| manifest_key   | text UNIQUE | Stable key from the ingestion manifest (`^[a-z0-9][a-z0-9_.-]{0,119}$`) |
| title          | text        | 1–500 characters                                                    |
| authors        | text[]      | Default empty                                                       |
| year           | smallint    | 1900–2100, nullable                                                 |
| doi            | text        | Nullable                                                            |
| url            | text        | `https://` only, nullable                                           |
| licence        | text        | Required: the licence the source is stored under                    |
| region         | text[]      | Required, at least one entry; each `global` or an ISO 3166-1 alpha-2 code (`IN`, `US`, `GB`, `AU`) |
| topics         | text[]      | Topic tags used by search filters                                   |
| evidence_level | text        | Nullable, free text set by ingestion                                |
| kind           | text        | `paper`, `guideline`, `position_stand`, `summary`                   |
| content_sha256 | text        | SHA-256 (hex) of what the loader stored for the source (`private.library_source_digest`); kept current by triggers, nullable (migration `20261018170044`) |
| created_at     | timestamptz |                                                                     |

#### `private.library_chunks`

| Field           | Type                       | Description                                                  |
| --------------- | -------------------------- | ------------------------------------------------------------ |
| id              | uuid PK                    |                                                              |
| source_id       | uuid FK                    | `library_sources.id`, on delete cascade                      |
| ordinal         | integer                    | Position in the source, from 0; UNIQUE (source_id, ordinal) |
| section         | text                       | Section name, nullable                                       |
| header          | text                       | Context header written at ingestion (source and section)     |
| body            | text                       | 1–8000 characters                                            |
| token_count     | integer                    | 1–2000                                                       |
| embedding       | `extensions.vector(384)`   | gte-small, mean-pooled and normalised; null until embedded   |
| embed_attempts  | integer, default 0         | Failed embedding attempts; at 5 the chunk is no longer offered and cron goes quiet about it |
| embed_failed_at | timestamptz                | Time of the last failed attempt                              |
| embedding_model | text                       | Model that made the embedding (e.g. `gte-small`); set exactly when `embedding` is set, so a model change re-embeds selectively |
| fts             | tsvector, generated stored | `to_tsvector('english', header || ' ' || body)`              |
| created_at      | timestamptz                |                                                              |

Indexes: HNSW on `embedding` (`vector_cosine_ops`), GIN on `fts`, and the unique
`(source_id, ordinal)` btree, which also serves `source_id` lookups and the cascade.

#### `private.library_ingest_runs`

One row per ingestion run: `id`, `started_at`, `finished_at` (null exactly while `status` is
`running`), `status` (`running`, `succeeded`, `failed`), `source_count`, `chunk_count`, `error`
(at most 2000 characters).

#### Content and ingestion (E2, migration `20261017150842_library_content`)

Content lives in the repo as `supabase/library/sources/*.ts` (one object per source: metadata,
licence, region, topics, why it was chosen, and a summary in Tracend's own words split into titled
sections). `supabase/functions/_shared/library/chunk.ts` splits each section into chunks of at most
1400 characters, each with the context header `Source: <label>, <title>. Section: <section>.`
(`token_count` is characters / 4, at most 512 so a chunk fits the `gte-small` window). The first
migration loads 35 sources and about 120 chunks, all with a null embedding, through
`private.library_replace_source(source jsonb, chunks jsonb)`: it upserts a source by `manifest_key`
and replaces its chunks only when their text changed, so loading a block again keeps valid
embeddings. A later content update is a new migration holding the blocks printed by
`_shared/library/build_migration.ts` for the changed sources; `library_content_test.ts` fails when a
content file differs from the newest migration that loads it.

**Retiring, digests and the library version (migration `20261018170044_library_search_v3`).** A
source removed from `supabase/library/index.ts` is retired by a content migration holding its retire
block (`build_migration.ts --retire <key>` prints `select private.library_retire_source('<key>');`),
which deletes the source and, by the foreign key, its chunks; it returns whether a source was
removed, so the block can run twice. `library_content_test.ts` fails while a migration still loads a
source that `index.ts` no longer lists and no later block retires it, and when a source is retired
after its newest load. Triggers on both tables keep `library_sources.content_sha256` equal to
`private.library_source_digest(id)`: the digest of the source's loader fields and its chunks'
ordinal, section, header, body and token count (embeddings, attempts and timestamps are left out, so
embedding a chunk does not change it). `private.library_version()` is the first 16 hex characters of a
SHA-256 over every source's `manifest_key:content_sha256`, in key order: it changes exactly when a
source is added, changed or retired, and two databases with the same content report the same
version. None of the three is executable by an API role. A migration that adds a content column to
the loader adds it to `library_source_digest` too.

Embeddings are filled server-side. Service-role functions (all security definer, empty
`search_path`, no grant to `anon` or `authenticated`):

| Function | Purpose |
|---|---|
| `library_worker_authorized_v1(candidate text)` | true when `candidate` is the Vault secret `library_worker_secret` |
| `library_pending_chunks_v1(batch_size integer, exclude_ids uuid[] default null)` | `{chunk_id, source_id, input_text}` of chunks without an embedding and with fewer than 5 failed attempts, leaving out `exclude_ids` (batch 1 to 200, default 25); `input_text` is header, line break, body |
| `library_store_embeddings_v1(model text, items jsonb)` | stores `[{chunk_id, embedding}]` (384 numbers) with `embedding_model` on chunks that have none; returns the count; a wrong size raises `22000`, an item without a `chunk_id` or an embedding raises `22023` and nothing is stored |
| `library_record_embed_failures_v1(chunk_ids uuid[])` | counts one failed attempt on each chunk still without an embedding; returns how many reached the limit of 5 with this call |
| `library_record_run_v1(started_at, succeeded, source_count, chunk_count, error)` | one finished `library_ingest_runs` row |
| `library_status_v1()` | `{schema_version, sources, chunks, embedded_chunks}` |

`private.library_worker_secret()` creates the Vault secret on first use (a restore does not carry
Vault, so a restored database makes a new one). `private.library_embed_kick()` posts to the
`library-embed` Edge Function through `pg_net` when any chunk lacks an embedding and has attempts
left, and the pg_cron job `tracend-library-embed` runs it every minute. The target URL is the Vault
secret `library_embed_url`; the kick does nothing while it is missing or blank, so the job is inert
until the deploy workflow runs `private.library_set_embed_url(url)` after the migrations (idempotent;
it accepts only `https://<20 lowercase letters>.supabase.co/functions/v1/library-embed`). The
loader, the worker secret and the kick are not executable by any API role; `library_set_embed_url`
is executable by `service_role` only (and needs a direct SQL connection, because `private` is not
exposed to the Data API).

#### `public.search_library_v2(query_text, query_embedding, match_count, filters, target_user_id)`

Contract 6 v2 (E3, migration `20261018140043_library_search_v2`; it replaces and drops
`search_library_v1`, which nothing deployed called). Security definer, empty `search_path`,
executable by `service_role` only. Takes the 30 best full-text matches and the 30 nearest
embeddings (cosine distance) and merges them by reciprocal rank fusion:
`score = Σ 1 / (50 + rank)` over the lists a chunk appears in. Full-text search ORs the terms of the
question: lower-cased words of letters and digits, stemmed by the English configuration with its
stop words dropped, ranked by `ts_rank` (length-normalised). v1's `websearch_to_tsquery` ANDed every
word, so a whole question matched almost nothing. Returns up to `match_count` rows (clamped to
1–10, null = 8), best first, at most three per source, each
`{schema_version: 2, chunk_id, source_id, source_key, title, year, url, section, body, header, score}`.
`source_key` is the stable manifest key Coach cites; `source_id` differs in every database.

- Only the first 1000 characters of `query_text` are used. A null or blank `query_text`, or one
  of stop words only, skips full-text search; a null `query_embedding` skips vector search; both
  skipped returns no rows.
- `query_embedding` is declared as `public.library_embedding`, a domain over
  `extensions.vector(384)`; callers pass the same JSON number array. Another size raises `22000`
  ("expected 384 dimensions").
- Without filters the nearest embeddings come from the HNSW index; with a filter they are ranked
  exactly over the matching sources' chunks (an HNSW scan stops after `ef_search` = 40
  candidates, which a narrow filter could empty).
- `filters` is null or an object with optional `region` and `topics` text arrays. A source matches
  when its array overlaps the filter; an absent, null or empty array does not filter. Any other key
  or a non-text-array value raises `22023`. Sources that apply everywhere carry `global` in
  `region`, so a regional caller passes for example `["global", "IN"]`.
- `target_user_id` (optional): when set and `filters` has no `region`, the search is limited to the
  athlete's regions from `private.library_regions_for_account(uuid)` (not executable by any API
  role): always `global`, plus the country in `user_accounts.locale` (`en-IN`, `en_US`) and `IN` for
  the `Asia/Kolkata` and `Asia/Calcutta` time zones, because the app stores no country yet. An
  unknown account gets `global` only. A source tagged `IN` therefore reaches only athletes in
  India. When the app stores a country, change that one function.
- `public.library_worker_secret_v1()` (same migration): returns the Vault worker secret
  (`private.library_worker_secret()`), executable by `service_role` only. Coach chat uses it as the
  bearer when it calls `library-embed` to embed the question, so gte-small never loads inside
  coach-chat.
- Coach does not filter by topic: the tags are free text, and a hard topic filter would drop the
  second source of a question that spans topics. The `topics` filter stays for callers that know
  what they want.

#### `public.search_library_v3(query_text, query_embedding, query_embedding_model, match_count, filters, target_user_id)`

Contract 6 v3 (E3 production pass, migration `20261018170044_library_search_v3`; additive, v2 stays
for the deployed Coach chat until a cleanup migration). The same search as v2, with:

- `query_embedding_model` (text): the model that embedded `query_embedding` (`gte-small`). Required
  when an embedding is passed (`22023` otherwise); vector search compares only chunks whose
  `embedding_model` equals it, so a re-embedding with another model never mixes two models' vectors.
  The unfiltered path keeps the HNSW index (every chunk shares one model, so the filter drops
  nothing).
- Rows `{schema_version: 3, chunk_id, source_id, source_key, title, year, url, section, body, header,
  evidence_level, kind, score, vector_distance, text_rank, library_version}`. `vector_distance` is
  the cosine distance (`<=>`) between the chunk and the question for every row whose chunk carries an
  embedding from that model, null without a query embedding. `text_rank` is `ts_rank` (normalisation
  1) for the ORed terms, 0 when the chunk holds none of them, null when the question has no
  searchable term. `library_version` is `private.library_version()`, the same on every row.
- Coach chat applies the relevance floor to these rows (`_shared/library/retrieval.ts`,
  `relevantRows`): excerpts are shown only when the nearest chunk is within the top limit, then every
  chunk within the row limit and every strong full-text hit. The calibration is in
  `docs/handoff/research-library.md`.

#### Dump-safe function signatures (all schemas we own)

`supabase db dump` (CLI 2.101.0) drops every GRANT and REVOKE line that names, after `ON`, a
quoted identifier from its excluded-schema list (`information_schema`, `pg_*`, `_analytics`,
`_realtime`, `_supavisor`, `auth`, `etl`, `extensions`, `pgbouncer`, `realtime`, `storage`,
`supabase_functions`, `supabase_migrations`, `cron`, `dbdev`, `graphql`, `graphql_public`, `net`,
`pgmq`, `pgsodium`, `pgsodium_masks`, `pgtle`, `repack`, `tiger`, `tiger_data`, `timescaledb_*`,
`_timescaledb_*`, `topology`, `vault`). A function restored from such a dump keeps Supabase's
default grants, so `anon` and `authenticated` could call it. Therefore no function in `public` or
`private` may take an input argument whose type lives in one of those schemas (wrap the type in a
domain in `public`, as `public.library_embedding` does), have an input argument or a name equal
to one of those names, and no table, view or sequence there may be named like one.
`supabase/tests/database/research_library_test.sql` asserts all four. Return types are not in a
GRANT line and are allowed. The deploy's restore drill also compares privileges after a restore
(CI_CD_DEPLOYMENT.md).

### Future vector memory

Only after the gates in [ARCHITECTURE.md](./ARCHITECTURE.md) pass, add user-owned `memory_documents`
and `memory_chunks` with source record, consent basis, classification, validity dates, deletion
state, embedding provider/model/version, content hash, and vector.

Confirmed structured facts remain canonical. Retrieved text cannot override current goals,
constraints, plans, or safety policy. Source deletion removes its embeddings.
