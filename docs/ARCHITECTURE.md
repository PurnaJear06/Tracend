# Tracend Architecture

**Status:** Authoritative MVP technical architecture\
**Scope:** Private iOS TestFlight beta\
**Backend decision:** Supabase-managed backend

Structured PostgreSQL facts are the coaching memory. Deterministic code reconciles workout truth
with bounded HealthKit workout references and calculates every number. A versioned athlete file
built from those facts supplies evidence IDs, freshness, coverage and conflicts to the configured
model. Model output cannot replace calculations or activate persistent changes. Vector retrieval
over user data stays outside the MVP until its gate is met (section 11); the research library is
the one allowed use of `pgvector`.

The current program plan is
[`plans/coaching-platform-2026-10/README.md`](./plans/coaching-platform-2026-10/README.md). Its
owner decisions (D1–D11) and contracts bind this document. Work that is planned but not built is
marked "Planned" with its phase and chunk.

## 1. Architecture Goals

The architecture must:

- preserve a simple, reliable coaching loop;
- separate deterministic analysis from model interpretation;
- prevent model output from mutating plans without validation and approval;
- isolate every user's sensitive data with mandatory Row Level Security;
- support HealthKit and private photos without client-side provider secrets;
- use Supabase-native capabilities before adding separate infrastructure;
- allow evaluated AI-provider replacement per feature through server-side settings alone, with no
  client credential or direct provider access (D2); and
- defer vector RAG over user data and autonomous agents until measured value exists; a research
  library of open sources (D3) grounds Coach wording without touching user data.

Product behavior is defined in [PRD.md](./PRD.md), security in
[SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md), UX in [UX_FLOWS.md](./UX_FLOWS.md), and budget
assumptions in [COST_MODEL.md](./COST_MODEL.md).

## 2. System Context

```text
┌──────────────────────────────────────────────────────────────┐
│ Flutter iOS app + TracendWidgets extension                   │
│ UI · local cache · HealthKit adapter · Supabase client       │
└──────────────────────────┬───────────────────────────────────┘
                           │ TLS + Supabase user JWT
┌──────────────────────────▼───────────────────────────────────┐
│ Supabase managed backend                                    │
│ Auth · Data API/RPC · Edge Functions · Storage              │
│ PostgreSQL + RLS · Queues · Cron · Logs                      │
└───────────────┬────────────────────────────┬─────────────────┘
                │                            │ server-side only
┌───────────────▼──────────────┐   ┌─────────▼─────────────────┐
│ Structured user data        │   │ AI provider APIs          │
│ versions · audit · policies │   │ text + vision             │
└──────────────────────────────┘   └───────────────────────────┘
```

HealthKit stays on the device. Flutter reads authorized types, normalizes required summaries, and
sends idempotent payloads to an authenticated Edge Function. AI keys and the Supabase
secret/service-role key exist only in Supabase Edge Function secrets. The static website (`site/`,
Cloudflare Pages) talks only to the three session-less waitlist functions.

## 3. Technology Decisions

### 3.1 Mobile

- Flutter, iOS only.
- `supabase_flutter` handles Supabase Auth sessions and client access. The session is stored in
  the iOS Keychain (SECURITY_PRIVACY §7).
- `HealthDataSource` wraps the pinned `health` Flutter plugin. The adapter is read-only for MVP and
  exposes only normalized internal sample types.
- The approved plan and in-progress workout are cached locally for degraded and offline use. The
  plan is the last `get_my_training_hub` that loaded (`lib/features/train/training_hub_cache.dart`),
  kept per athlete in the app's preferences with the athlete's id and the save time, replaced on
  every successful Train load, and removed on sign-out, a refused session and account deletion.
  When the account check cannot finish (no connection, or six seconds without an answer) and a copy
  exists, the gate opens the shell in offline mode (`lib/features/auth/phase_2_gate.dart`,
  `AppShell.offline`): Train shows the copy marked offline, the other tabs say they need a
  connection, and a resume or **Try again** checks the account again and leaves the mode. Only the
  hub for the default 28-day window is kept; other windows (and Progress) are never served from it.
  Finished workouts and left-over drafts are sent by the repository (`sendWaiting`) when an account
  check succeeds and after each hub load, without the logger; a workout whose plan was copied
  meanwhile is found again by its place and exercises.
- Feature widgets use [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md), Dynamic Type, VoiceOver, Reduced
  Motion, safe areas, and state restoration.
- The client may contain the Supabase project URL and publishable key. It must never contain
  secret/service-role keys or AI-provider keys.

**Workout logging.** History and the open session are kept on the device for offline use; finish
and discard requests are saved locally first and sent when the network returns. Each set records
its timing, rest and reps left (program Contract 2). The workout controller publishes workout
events and accepts commands (`lib/features/train/workout_events.dart`, Contract 3). New bests,
weight lifted and the rest timer are computed on the device (ALGORITHMS §4). The RPCs are listed
in section 6.

**Local notifications.** Reminders and the rest alert (identifier `tracend.rest-timer`) use iOS
`UserNotifications` through a narrow method channel, scheduled on the device. PostgreSQL stores
only owner-scoped reminder booleans, the coarse iOS authorization state, and append-only consent
evidence through a validated RPC. Native `UserDefaults` keeps the requested toggles (the rest-alert
toggle is device-only); pending requests are delivery state and are repaired from the toggles after
reopen. The in-app rest timer keeps its end time in the local workout draft and does not depend on
the alert.

**Widget extension and workout Live Activity.** The `TracendWidgets` WidgetKit extension
(`com.tracend.app.TracendWidgets`, embedded in Runner) draws `RestActivityAttributes`
(`ios/Shared/`, both targets), the workout's card: the set in progress, the rest between sets, and
"all sets logged". It holds the rest's end time, the exercise name, the labels, the set to log
(exercise order, set number, how many sets) and, only while the athlete chose Lock Screen numbers,
the kg and reps text (SECURITY_PRIVACY §10 exception). When the rest's end passes the system marks
the card stale and it draws the set it carries, so it turns into the next set with the app asleep.
`RestTimerController` is its only driver, through `WorkoutActivityBridge`
(`lib/shared/live_activity/`, channel `tracend/live_activity`: `startRest`, `updateRest`,
`showSet`, `hideNumbers`, `end`; native `ios/Runner/Native/WorkoutActivityBridge.swift`), never
awaited. `ActiveWorkoutScreen` tells it the set in progress (`present`): the pre-filled values come
from the logger's own `suggestSet`. Sign-out, account deletion and a refused session call `end`,
and the native side ends cards left from an earlier launch that are over. ActivityKit runs the
countdown from the end time (`Text(timerInterval:)`): no push, no server. The Live Activity itself
uses no App Group. It is off when iOS Live Activities are off.

The buttons (**Log set**, Skip, +30s) are iOS 17 `LiveActivityIntent`s in
`ios/Shared/RestActivityIntents.swift` (both targets), run in the app's process. The bridge forwards
each as a `press` to the attached workout screen and waits for its answer (8 s at most) and for its
queued activity calls; the screen maps it to a Contract 3 command (`CompleteCurrentSet`, `SkipRest`,
`AddRest`) in its one command sink, and **Log set** runs the same `_doneSet` as the in-app tick, so
the draft, `sync_workout_draft`, set timing, workout events (and with them the heart-rate recorder)
and audit are the in-app ones. **Open** and a card tap open `tracend://workout`: with a workout
screen open it only comes forward; otherwise Train reopens today's workout when it has a draft.

**Today and Lock Screen widgets (D2).** The same extension draws `TodayWidget` (small, medium) and
`LockScreenWidget` (circular, rectangular, inline). The widget process cannot reach the app's
storage, so the app and the extension share the app group `group.com.tracend.app`
(`ios/Shared/TodayWidgetStore.swift`, in both entitlements). `TodayScreen` hands each loaded
brief, with the plan's targets and the check-in state, to `TodayWidgetPublisher`
(`lib/shared/home_widgets/`), which builds `TodayWidgetSnapshot` (JSON, `schema_version` 1,
`test/contract/fixtures/today_widget_snapshot_v1.json`), skips an unchanged one for five minutes,
and sends it through `HomeWidgetBridge` (channel `tracend/home_widgets`: `write`, `clear`,
`takePendingTab`; native `ios/Runner/Native/HomeWidgetBridge.swift`), which validates it, stores it
and calls `WidgetCenter.reloadAllTimelines()`. The snapshot is one file in the group's container,
excluded from backups. Today reloads on resume when its brief is over 30 minutes old or from
another day. The widgets only read the snapshot, decide staleness
from it (older than its `stale_after_seconds`, or another local day) and never call the network or
calculate anything. A tap opens `tracend://today` or `tracend://train`; `SceneDelegate` hands the
URL to `HomeWidgetBridge.open`, and `AppShell` reads it with `takePendingTab`. The Lock Screen
choice lives in `TodayWidgetPublisher` (SECURITY_PRIVACY §10).

### 3.2 Supabase Auth

- Supabase Auth is the identity and session authority. `auth.users.id` is the canonical `user_id`
  for application-owned records.
- Sign in with Apple is the required external private-beta login provider, using native nonce
  validation and capturing the name only when Apple supplies it on first authorization. It is not
  built yet. Owner-only builds use the email/password development mode from ADR 0002 through the
  same client auth boundary. Anonymous auth, hard-coded users and client-side authentication
  bypasses are prohibited.
- Sign-ups are invite-only: the Auth insert trigger refuses an email that is not in
  `private.signup_invites` (SECURITY_PRIVACY §7).
- Supabase access and refresh sessions are stored in platform-protected client storage; Tracend
  does not implement a parallel token issuer.
- Session restore validates the stored session with Auth (`GET /auth/v1/user`) before any data
  call; the Data API checks only a token's signature and expiry.
- Recent authentication is required before export, account deletion, or sensitive session
  changes.

### 3.3 PostgreSQL and Data API

- Supabase PostgreSQL is the system of record.
- All schema changes are forward-only SQL migrations committed under `supabase/migrations`.
- Every exposed user-owned table has RLS enabled and tested. Policies derive ownership from
  `auth.uid()`.
- Simple user-scoped reads and low-risk writes may use the generated Data API under RLS and database
  constraints.
- Multi-table mutations, plan activation, proposal acceptance, final meal confirmation, and other
  invariant-heavy operations use transactional database functions invoked through authenticated RPC
  or Edge Functions.
- Security-definer functions are exceptional, use a fixed safe `search_path`, validate authorization
  internally, expose minimal grants, and receive dedicated tests.
- The `private` schema is not exposed by the Data API. It holds owner-run helpers and tables such as
  the invite list, the waitlist, AI budget limits and the research library.
- Structured PostgreSQL fields and bounded summaries are the MVP memory system. `pgvector` is
  enabled (in the `extensions` schema) for the research library only (section 11); no user data is
  embedded.

### 3.4 Edge Functions

Supabase Edge Functions are TypeScript/Deno server-side boundaries for:

- HealthKit summary validation and idempotent sync;
- onboarding assessment and initial plan proposal;
- deterministic feature snapshot and safety-policy execution;
- AI provider orchestration and response validation;
- meal-photo and progress-photo analysis;
- export and deletion workflows;
- privileged media authorization;
- the website waitlist; and
- rate limiting, cost policy, and sanitized operational telemetry.

Functions are short-lived, idempotent, schema-versioned, and designed for cold starts. Work that
outlives a request is either a queue message (export, deletion, weekly review) or a durable job row
finished in `EdgeRuntime.waitUntil` (onboarding plan generation). Meal-photo analysis and the
physique check answer within the request.

### 3.5 Storage

- Supabase Storage uses separate private buckets for meal images (`meal-images`), progress photos
  (`progress-photos`), and temporary exports (`account-exports`).
- RLS policies scope objects by authenticated user and purpose.
- Upload restrictions enforce content type and maximum size; server-side processing verifies bytes,
  dimensions, checksum, and metadata.
- Downloads use an authenticated request or short-lived signed URL. Object paths are never
  authorization. Service-role code checks every key it reads from the database before any Storage
  call (`_shared/storage_keys.ts`).
- Storage lifecycle metadata stays in PostgreSQL because database backups do not contain Storage
  object bytes.

### 3.6 Queues and Cron

- Supabase Queues (`pgmq`) carry account deletion (`account_deletions`), privacy export
  (`privacy_exports`) and weekly review (`weekly_reviews`) work.
- Queue payloads contain opaque resource IDs, not raw photos, prompts, tokens, or health records.
- Workers reauthorize resource ownership and consent at execution time.
- Concurrency, retry count, visibility timeout, dead-letter/archive behavior, and idempotency are
  defined per job type.
- Supabase Cron (`pg_cron`) runs:
  - `tracend-schedule-weekly-progress-reviews` (daily 03:30 UTC) and
    `tracend-process-weekly-progress-reviews` (every five minutes);
  - `tracend-recompute-daily-metrics` (daily 06:00 UTC, `recompute_stale_metrics`);
  - `tracend-waitlist-cleanup` (daily 03:40 UTC);
  - `tracend-library-embed` (every minute while any research-library chunk lacks an embedding and
    has attempts left; it calls the `library-embed` Edge Function through `pg_net` with a secret the
    database keeps in Vault, at the URL in the Vault secret `library_embed_url`. The job is inert
    until the deploy workflow stores that URL after the migrations, via
    `private.library_set_embed_url`, executable by `service_role` only); and
  - the daily `meal-media-retention` worker, which authenticates with `RETENTION_WORKER_SECRET`
    read from Vault (job `meal-media-retention-daily`, created by migration; it posts only to the
    URL in the Vault secret `meal_media_retention_url`, set by the deploy workflow via
    `private.meal_media_retention_set_url`). The same worker removes expired export packages and orphaned Storage objects;
    a failed Storage deletion keeps the object reference for retry.

The weekly-review worker is database-native. Daily Cron deduplicates one job per active user and
local review week, `pgmq` carries only the job ID and schema version, and the five-minute consumer
rechecks account eligibility before building the deterministic snapshot and review. Failures use
bounded delayed retries and become terminal after three attempts. This path does not invoke a
model or create a proposal.

### 3.7 AI providers

Edge Functions make every AI call. Provider keys are Edge Function secrets. Each feature reads its
own server-side settings, so the owner can switch a feature's provider or model without an app
release (D2). Changing a setting creates a new version of every Edge Function; liveness is proved
with `scripts/verify-live-function.sh --all` (CI_CD_DEPLOYMENT.md). An athlete's grant names the
company that receives the data, so moving a feature to another company also needs a new notice
(SECURITY_PRIVACY §3).

Each feature keeps its own provider module in `_shared/providers/` for the path that runs when it
has no gateway route (the path production runs **today**):

| Feature | Function | Settings | Providers in code | Unset or off |
| --- | --- | --- | --- | --- |
| Coach chat | `coach-chat` | `COACH_MODEL_PROVIDER`, `COACH_AI_ENABLED`, `<PROVIDER>_MODEL`, `<PROVIDER>_API_KEY` | `deepseek`, `gemini` (paid terms only), `groq` (pinned to `qwen/qwen3.6-27b`, which Groq has retired) | no model call; labeled data summary |
| Daily decision | `coach-decide` | same as Coach chat | same, behind the `CoachModelProvider` interface | deterministic mock |
| Onboarding plan and follow-up questions | `onboarding-plan` | `ONBOARDING_PLAN_PROVIDER`, `_MODEL`, `_MODEL_EVALUATED`, `_THINKING`, prices | `deepseek`, `groq`, `gemini` (OpenAI-compatible JSON mode) | rules plan, no questions |
| Meal photo | `meal-analyze` | `MEAL_VISION_PROVIDER`, `MEAL_VISION_ENABLED`, `MEAL_VISION_MODEL_EVALUATED`, `MEAL_VISION_MODEL` | `groq` (`qwen/qwen3.8-27b`), `gemini` (paid terms only) | analysis unavailable |
| Physique check | `physique-check` | `PHYSIQUE_VISION_ENABLED`, `_PROVIDER`, `_MODEL`, `_ALLOWED_USERS` | `groq` only | off |

In production DeepSeek V4.1 Flash (`deepseek-flash`) serves Coach chat, the daily decision and the
onboarding plan; Groq `qwen/qwen3.8-27b` serves meal photos and the owner-only physique check. The
coach-decide gate is all-or-nothing: without every server-side setting configured together it uses
the deterministic mock.

The provider-neutral gateway (`supabase/functions/_shared/ai/`, program Contract 1 v2) is the one
call path for a route. `route(feature)` reads `AI_<FEATURE>_{PROVIDER, MODEL, BASE_URL, THINKING,
EFFORT, MAX_OUTPUT_TOKENS, TIMEOUT_MS, EVALUATED}` and returns null when a route is incomplete.
Each feature (`coach_chat`, `daily_decision`, `onboarding_plan`, `onboarding_questions`,
`meal_vision`, `physique_vision`) calls the gateway when its route is complete and evaluated, and
otherwise runs the path in the table above byte for byte (recorded-request tests prove it). So the
gateway being deployed changes nothing until the owner sets a route. Adapters speak the
Anthropic, OpenAI-compatible and Gemini wire protocols. Prices live in one table (`models.ts`).
`call()` refuses before sending when the athlete's notice names another vendor
(`consent_provider_mismatch`; the feature then takes its consent-needed path), never sends
sampling parameters to Claude 5 models, and logs one scrubbed `ai_call` line per call (no prompt,
image or reply text). The feature reserves budget first with the route's worst-case ceiling
(`reserve_ai_budget_v2`) and settles it with the call's real cost; the stops are USD 3 per athlete
a month, 30 requests a day and USD 50 across accounts (COST_MODEL §2). Coach chat puts the stable
athlete file in a cacheable prefix and the question last, so a repeated question reads the prefix
from the cache, and hosts the Contract 7 contributor registry (`_shared/coach_context/`).

For every route, calls use structured output, compact feature snapshots, request-level timeouts,
and per-user rate and cost gates. Provider output never directly writes canonical user state;
validation and approval remain in deterministic code and PostgreSQL transactions. The
deterministic path stays available when a model is unavailable.

**Provider-neutral memory (owner rule, 2026-11-01).** What Coach remembers about an athlete never
depends on a model or a vendor. Breaks (`training_pauses`), approved and declined proposals,
check-ins, joint states, confirmed facts and Coach notes live in our own Postgres tables, and our own
deterministic code turns them into plain text (the `standing_state`, `confirmed_facts` and
`coach_notes` contributors, the athlete file, the lookups). No vendor memory or session feature
(Anthropic's memory tool or context editing, an assistant thread, a stored conversation) and no
third-party memory service (Mem0, Zep, Letta) is used. Prompt caching is an optional optimisation
inside the gateway's adapters: the standing-state block's words and place are the same on an
Anthropic route, an OpenAI-compatible route or the rollback path, cached or not
(`standing_state_test.ts` builds both requests and compares them), so moving to another provider
keeps every athlete's memory.

> **Cutover to Claude (Phase 2, D1): code merged, not yet switched on.** Production keeps today's
> providers until the owner runs the cutover runbook
> ([`docs/runbooks/phase2-claude-cutover.md`](./runbooks/phase2-claude-cutover.md)): Coach chat and
> meal photos on Haiku 5.5, the daily decision and the physique check on Sonnet 5.5; onboarding
> follows on Sonnet 5.5 after chunk B2; until then, once the Anthropic notice is current, onboarding
> uses the rules plan. Data goes only to the vendor named by the athlete's accepted notice, so
> unsetting a feature's `AI_<FEATURE>_PROVIDER` stops Anthropic but does not send traffic back to
> DeepSeek or Groq; restoring them needs a notice naming that vendor. Details: AI_SAFETY_SPEC
> §10.5-§10.7.

## 4. Supabase Boundary Rules

| Operation                               | Allowed boundary                                              |
| --------------------------------------- | ------------------------------------------------------------- |
| Read own profile/logs/approved plan     | Data API with RLS or read-model RPC                           |
| Read own sanitized AI usage summary     | User-scoped RPC or Edge Function aggregated from `model_runs` |
| Draft check-in or in-progress workout   | Data API/RPC with RLS, idempotency, and constraints           |
| HealthKit quick-complete                | Authenticated RPC with RLS + explicit user confirmation       |
| HealthKit sync                          | Edge Function                                                 |
| Propose a plan or targets               | Edge Function (validation) + service-role transactional RPC   |
| Approve a proposal (activate a version) | Authenticated transactional RPC                               |
| Confirm analyzed meal                   | Authenticated transactional RPC                               |
| Invoke AI provider                      | Edge Function only                                            |
| Create/read restricted signed media URL | Edge Function or tightly scoped Storage RLS                   |
| Export/delete account                   | Edge Function + Queue                                         |
| Retention/weekly processing             | Cron + Queue + Edge Function/database function                |
| Research library search                 | Service-role RPC from an Edge Function                        |

The Flutter app never connects directly to PostgreSQL, bypasses RLS, invokes secret-key operations,
or calculates authoritative plan mutations.

## 5. Controlled Coaching Workflow

```text
Authenticated request or scheduled trigger
        ↓
Edge Function loads approved plans and authorized recent data
        ↓
Deterministic feature engine
        ↓
Immutable feature snapshot
        ↓
Hard safety and data-sufficiency policy
        ↓
Compact context assembly
        ↓
One structured AI-provider call
        ↓
Schema + semantic + evidence validation
        ↓
Persist decision
        ↓
Optional change proposal
        ↓
Explicit user approval → transactional RPC → new active version
```

Training Coach, Nutrition Coach, and Head Coach are fields in one response, not autonomous
processes.

### Coach proposals (A8)

A Coach chat turn may end in a proposal. The model returns an intent (a kind and closed-vocabulary
parameters); `proposeCoachChange` (`_shared/coach_proposals/service.ts`, called by coach-chat in
the same process, no model call, no budget) reads the athlete's state with three service-role
RPCs, builds the proposal with pure rules, and stores it with `persist_coach_proposal_v1`. A plain
service-role RPC stores it because the builder already runs inside coach-chat; a separate Edge
Function would add a deploy, a network hop and a second place to verify live for no gain. The
athlete approves with `respond_to_coach_proposal_v1` under their own session (new plan, target or
goal version, audit event) and can undo with `undo_coach_proposal_v1` for seven days. A temporary
block is an active plan version that carries its last day and the version to restore; an hourly
job and the proposal reads end it, so the regular plan returns without a model or a client.

### Deterministic feature engine

Versioned TypeScript and SQL functions calculate:

- seven- and 28-day weight trends where sufficient;
- measurement deltas and rate of change;
- workout completion, volume, performance, and adherence;
- RPE, soreness, pain, and recovery indicators;
- confirmed calorie/macro adherence;
- sleep, resting-heart-rate, and HRV deviation from personal baselines;
- input freshness, completeness, and conflicts; and
- eligibility for persistent training or nutrition changes.

`compute_daily_metrics` produces the day's scores and is called by `prepare_daily_coaching`, Coach
chat preparation, `get_my_daily_brief` and the nightly recompute (DATA_MODEL §9). Workout truth is
reconciled with HealthKit workout references deterministically; a suggested match becomes final
only when the athlete confirms it.

The model receives prepared features and evidence identifiers, not unrestricted table access or raw
history.

## 6. Client Integration Surface

### Supabase Auth

- Email/password owner-development mode (ADR 0002). Native Sign in with Apple through Supabase Auth
  is required for external beta builds and is not built yet.
- Session refresh, sign-out, and supported device-session revocation.

### Edge Functions

Fifteen functions, each in its own directory under `supabase/functions/` (`_shared`, `_tests` and
`_evals` hold shared code, tests and evals):

```text
coach-chat               JWT    Coach answers
coach-decide             JWT    daily decision
health-check             none   liveness and version
health-sync              JWT    HealthKit summaries and workouts
meal-analyze             JWT    meal-photo candidates
meal-media-retention     secret retention, export expiry, orphan sweep
onboarding-plan          JWT    starting plan and follow-up questions
physique-check           JWT    owner-only physique check
privacy-delete-account   JWT    account deletion
privacy-export           JWT    encrypted export
training-proposals       JWT    the deload the rules suggest, stored for the athlete to answer
waitlist-confirm         none   website double opt-in
waitlist-join            none   website signup
waitlist-unsubscribe     none   website unsubscribe
```

Function request and response schemas are versioned, shared where practical, and validated at
runtime. Function names are stable contracts; breaking changes require a new schema version and
a migration path.

**Website waitlist.** `waitlist-join` checks the address and a Cloudflare Turnstile token, then
`public.waitlist_join` records the signup and returns whether to email; the function sends the
confirmation over SMTP (port 465, provider set by secrets). The link token travels only in the URL
fragment and is stored as a SHA-256 hash. `waitlist-confirm` and `waitlist-unsubscribe` take that
token; unsubscribe also answers mail apps' one-tap requests (RFC 8058). The waitlist is separate
from app accounts: the owner moves confirmed signups into `private.signup_invites` with
`private.invite_from_waitlist(n)`.

**Onboarding plan generation.** `onboarding-plan` builds the starting plan from the reviewed
answers:

1. The function claims a durable generation (`claim_onboarding_generation`) and answers 202 at once.
2. It keeps working in `EdgeRuntime.waitUntil`:
   - it computes `onboarding-policy-v1`;
   - it asks the configured model to choose within that policy, if the athlete's `onboarding_plan`
     consent, an evaluated provider and the budget allow;
   - it validates the plan, with one repair, or falls back to the rules plan;
   - it stores a 2.0 proposal with `persist_onboarding_proposal_v3`, which also writes the call
     telemetry to the audit event.
3. The app polls `get_my_onboarding_generation`.
4. On approval, `respond_to_onboarding_proposal_v2` inserts exactly the proposed workouts. See
   AI_SAFETY_SPEC §6, "Initial plan".

The same function asks up to three follow-up questions (`mode: "questions"`), stored in
`onboarding_questions`.

**Coach chat.** Threads and messages are owner-scoped in PostgreSQL under forced RLS. Every
question follows one path regardless of its wording:

1. `prepare_coach_chat_v8` builds the same full athlete file for every question: goal, profile,
   plan, targets, latest check-in and decisions, weekly review, fresh coaching-date scores,
   permitted evidence, thread and cross-thread memory, plus `build_coach_athlete_context` (28-day
   training log with sets and volume, 7/14/28-day totals, watch workouts, 28 days of watch data
   with averages, eight weeks of weights, 14 days of check-ins, 28 days of logged nutrition,
   today's meals, plan structure, proposals, reconciliations, data freshness), under a 90K
   whole-section size guard. Conversation memory is the ten newest messages of the thread and of
   other threads, each capped at 2,000 characters keeping its ending. The labeled data summary is left out of
   other threads and, since `prepare_coach_chat_v10`, kept in this thread, marked as the app's own
   reply. A long thread keeps fewer, newest messages rather than failing preparation. The
   prepared file is stored in `coach_context_snapshots`.
   A10 part 2 adds `prepare_coach_chat_v9`, which calls v8 unchanged and then leaves out other
   conversations the athlete asked Coach not to remember and the older preference, journal and
   narrative sections; v10 (2026-10-18) calls v9 and puts the app's data summaries back into this
   thread's memory, marked; coach-chat calls v10. Memory reaches the prompt through two contributors: the
   athlete's confirmed facts (stable, before the volatile parts, so the prefix caches) and Coach's
   own notes (volatile, labelled untrusted). Precedence: Tracend's calculations, then confirmed
   facts, then the athlete's recent statements, then Coach's notes, then the library. After the reply
   coach-chat adds `fact_suggestions` to the response (the athlete confirms or dismisses each in the
   app; nothing is stored until Confirm) and writes the turn's note with rules, no model call.
2. `record_coach_chat_question` stores the question before the model runs. A preparation failure
   returns 422 with a finite `reason` and reaches Sentry.
3. The Edge Function renders the file as markdown (required truth first, conversation history
   last, the question at the very end) and calls the no-tools structured-output provider. Before
   the raw rows, deterministic calculators (`_shared/coach_calculations.ts`) add exact averages,
   week-over-week changes, weight trends and a labeled weight projection computed from the same
   file, so the model quotes numbers instead of computing them.
4. The answer is validated strictly for accuracy (JSON, keys, safety state, permitted evidence)
   and against generous formatting ceilings, with one targeted repair.
5. A valid answer is persisted with the question. Otherwise the failure and its finite rule names
   are recorded, and app builds on request schema 1.1 receive a labeled deterministic data summary
   (`persist_coach_chat_data_summary`) instead of an error. If the message may concern a health
   risk, that reply is a numberless safety referral instead.
6. A request retried with the same idempotency key gets its first attempt's outcome from
   `coach_chat_turn` (answer, failure code, or still in progress) and never calls the model twice.

The app sends request 1.1 and renders the labeled data summary. It lists conversations with
`get_my_coach_threads()`, which returns only the caller's active threads that contain a message,
newest first. It reopens the conversation last opened on the device and creates a thread on its
first send, so opening Coach never stores an empty thread. Chat context coverage is reconciled
independently of the daily-decision policy: a recent HealthKit summary is valid chat context even
when the current calendar day has no complete HealthKit row. `get_my_coach_context_status()`
exposes only owner-scoped source availability, counts, and latest dates.

The daily Head Coach decision is a separate immutable record, shown on Today.

> **Planned (coaching platform, Phase 2 / A6, Contract 7):** a Coach context host that renders
> contributors (library, heart-rate profile, progression) after the frozen athlete file, each
> clipped to its budget and labelled as reference data. `prepare_coach_chat_v8` and
> `build_coach_athlete_context` stay frozen for the whole program.

### Read-model and transactional RPC

`get_my_training_hub(period)` (1.7), `get_my_nutrition_schedule(date)` (1.0) and
`get_my_daily_brief(date)` (1.8) are authenticated read models. They derive identity from
`auth.uid()`, use only active approved versions and confirmed execution, and return bounded
structured data for the iPhone client.

Workout logging uses `start_workout`, `sync_workout_draft`, `complete_workout_v2` (the athlete's
1–10 session effort; `complete_workout` remains for installed builds and records a fixed default
effort), `abandon_workout`, `get_my_workout_session` (1.1) and `get_my_exercise_history(keys,
sessions)` (1.1: last time, best set and heaviest set per completed session for at most 20
exercises and 12 sessions).

Transactional RPC is used for narrow atomic operations such as approval of a proposal and
activation of the new plan version, completed-session amendment, workout reconciliation and
confirmed-meal persistence. Execute grants are explicit and RLS and ownership rules remain
enforced.

## 7. Primary Data Flows

### HealthKit sync

1. Mobile requests an individual HealthKit permission in context.
2. Mobile reads the authorized date window and normalizes supported values.
3. Mobile computes source/checksum metadata required for deduplication.
4. `health-sync` verifies JWT, units, ranges, timestamps, and idempotency key.
5. A transaction upserts daily summaries and records the sync run.
6. Feature snapshots consume only successfully normalized records.

The first successful sync reads a 9-date window (today−8) so recent history can be restored; later
syncs read eight dates (today−7). Only normalized daily summaries and bounded workout references
cross the device boundary, and the server contract rejects a window longer than 31 days. An empty
response never proves permission denial.

### HealthKit auto-completion

1. Mobile loads the training hub; the response includes a `healthkit_completion_candidate` field
   when: (a) a planned workout is scheduled for today, (b) the day's `daily_health_summaries` record
   has `workout_count > 0`, and (c) no completed session exists for the planned workout on that
   date.
2. Train displays a prompt card with the HealthKit evidence and two buttons.
3. **Yes, mark complete** calls the authenticated `healthkit_auto_complete_workout` RPC, which:
   - authorizes user ownership of the planned workout in the active plan;
   - guards idempotently against duplicate completion;
   - creates a `workout_sessions` row with `state='completed'` and duration from HealthKit,
     `completion_source='healthkit'` and `session_effort_source='healthkit_default'`;
   - writes an `audit_events` row with `action_code='workout.auto_completed'`.
4. The hub reloads and the completed session counts toward adherence.
5. **Log manually** opens the standard workout execution flow.

HealthKit evidence provides the basis; only explicit user approval finalizes the completion. The
prompt never appears when a session is already completed.

### Meal analysis

1. Mobile uploads the compressed image to the private `meal-images` bucket under Storage RLS, at
   `<uid>/meal/<request id>.jpg`.
2. `create_meal_photo_draft` records the media object (7-day retention deadline) and an unconfirmed
   draft meal.
3. Mobile calls `meal-analyze`, which answers within the request. It checks the current meal photo
   notice grant (`get_meal_photo_ai_consent`) and the AI budget, checks the stored key, downloads
   the image, and sends a minimized image with a fixed instruction to the provider.
4. Structured candidates are validated and stored as unconfirmed `meal_analysis_candidates`
   (`persist_meal_photo_candidates`), with usage in `ai_usage_events`. On the Claude path the
   answer also says whether the photo is a plate, a pack front or a nutrition label and copies what
   is printed; deterministic code (`_shared/meal_vision/packaged.ts`) checks the label arithmetic,
   derives per-unit values (per gram, or per ml, never mixed) and portions, and sets the source and confidence before storage
   (AI_SAFETY_SPEC §8). The model's assumptions and question are stored with the candidate.
5. The athlete edits candidates (for a pack or label, a portion chooser recalculates from the
   stored per-unit values); `confirm_analyzed_meal` snapshots the corrections into confirmed meal
   items in one transaction.
6. The daily retention worker deletes the image at its deadline.

If any step after the upload fails, the app removes the uploaded object.

### Progress photos and physique check

Progress photos use their own consent, bucket, prefix, RLS policy, retention, and signed-read path.
Raw images never enter routine coaching prompts. A consent-gated RPC creates a draft set, each pose
is registered only after its owner-scoped object exists, and four poses (front, side, back, lower)
complete the set. Reads
use 60-second signed URLs; deletion removes Storage bytes before relational metadata.

The physique check is live for allow-listed accounts only (the owner). `physique-check` sends the
front, side and back photos of one complete set, with metadata stripped on the server, after
checking the current photo AI notice grant and the AI budget. The validated suggestion is stored by
`persist_physique_analysis`; only muscles the athlete confirms (`set_my_priority_muscles`) become
their focus. Deterministic progress summaries remain available when Storage, Queue, Cron, or AI is
unavailable.

### Export

Export reauthenticates the owner and queues only an opaque export ID. The worker builds
user-readable JSON/CSV plus purpose-organized private media, encrypts the ZIP with AES-256-GCM from
a non-persisted password-derived key, and stores it in the private `account-exports` bucket. Signed
download authorization lasts 60 seconds and stops after three uses or seven days. No export starts
or completes while an account deletion is pending.

### Account deletion

Deletion uses a separate recent-authenticated opaque job. Private Storage bytes (every recorded
object plus every object in the account's folders) are removed before canonical Auth deletion
cascades through application data. The same Auth delete removes the account's invite and waitlist
rows (trigger `auth_user_forget_invite`). Only a content-free completion receipt remains, for 180
days. A request whose function stopped mid-run is claimable again after 10 minutes, and every step
is safe to repeat. The app waits a bounded time and then reads the outcome from Auth
(`user_not_found`) and the athlete's own `deletion_requests` row.

## 8. Environments and Deployment

- **local:** Supabase CLI and a Docker-compatible runtime, local Edge Functions, mocked AI and
  HealthKit fixtures. Runtime testing uses the owner's physical iPhone; there is no simulator. The
  local Supabase stack must not be exposed publicly.
- **private-beta:** one hosted Supabase project (`qsfzzsjenopqqqhvpyaw`, Singapore,
  `ap-southeast-1`), separate project secrets, private buckets, quota alerts and backups on Free,
  Spend Cap on Pro, and a TestFlight build.
- **staging:** defer a second paid hosted project until beta complexity needs it; use local
  development and isolated synthetic fixtures first.

No environment shares production user data or reusable secret keys. Production changes deploy
through reviewed migrations and versioned function deployments, not ad hoc dashboard edits.
Merging to `main` runs the deploy workflow: backup and restore drill, migrations, functions, then
the website (CI_CD_DEPLOYMENT.md).

## 9. Failure and Degradation

- **AI unavailable/invalid:** preserve approved plans and logging; show last valid timestamped
  decision and deterministic guidance.
- **HealthKit partial/unavailable:** show missing data and manual fallback; lower confidence.
- **Edge Function timeout:** return a resumable job/status response where applicable; never
  duplicate work.
- **Queue delayed:** expose processing status; retry within bounded policy.
- **Storage unavailable:** retain safe local draft when possible and allow non-photo features.
- **Conflicting data:** surface conflict and block persistent change until resolved.
- **Supabase outage:** cached approved plan and in-progress workout remain usable; sync resumes
  idempotently.
- **Authorization/RLS failure:** return no cross-user existence detail and emit a sanitized audit
  event.

## 10. Observability and Cost Controls

Track without sensitive content:

- Edge Function invocation, latency, status, cold start, retry, and correlation ID;
- database/Storage/egress usage and quota trend;
- HealthKit sync counts, ranges, rejects, and freshness;
- feature/policy/schema versions and outcomes;
- AI provider/model/prompt version, token/image usage, latency, estimated cost, and validation;
- decision/proposal/approval rates and feedback;
- Queue/Cron lifecycle; and
- retention, export, deletion, and security events.

Sentry receives scrubbed errors from Flutter and Edge Functions (SECURITY_PRIVACY §10). The
Account usage view reads a sanitized, authenticated per-user aggregation. It does not expose
provider credentials, prompts, provider request IDs, raw errors, or cross-user totals. Provider
secrets are configured only through environment-specific Supabase secret management.

Every AI call reserves its place in the budget before it runs (`reserve_ai_budget`,
`ai_budget_reservations`) under per-purpose ceilings and a global monthly stop in
`private.ai_budget_limits` (COST_MODEL.md). When using Pro, enable the Supabase Spend Cap before
inviting testers. Free requires quota monitoring and backups instead. AI providers require
project-level budgets, per-user quotas, anomaly alerts, and a server-side kill switch.

## 11. RAG and Multi-Agent Adoption Gates

### Structured memory first

Goals, preferences, constraints, plans, confirmed meals, decisions, and weekly summaries remain
relational data retrieved with explicit user-scoped queries.

### Research library (D3)

The one allowed vector store is a research library inside Postgres: open papers, guidelines,
position stands and in-house summaries in our own words. Paid course material (K11, NASM, ACE) is
never stored, and every source records its licence.

- Tables `private.library_sources`, `private.library_chunks` and `private.library_ingest_runs` sit
  in the `private` schema (not exposed by the Data API), with forced RLS and no API grants. They
  hold no user data, so they are outside export and account deletion.
- Embeddings are Supabase's built-in `gte-small` (384 dimensions, mean-pooled and normalised), run
  inside Edge Functions (D4). No new processor receives any text.
- `public.search_library_v3` (service role only, Contract 6 v3; v2 stays for the deployed build)
  fuses the top 30 Postgres full-text matches (the terms of the question ORed) and the top 30
  nearest embeddings from the question's model (cosine distance; HNSW index without filters, exact
  ranking over the matching sources with a region or topics filter) by reciprocal rank fusion
  (k = 50) and returns at most 10 chunks, at most 3 per source, limited to the athlete's regions
  (global plus their country), each with its cosine distance, text rank, evidence level, kind and
  the library version.
- Every source carries a content digest kept by triggers, and `private.library_version()` digests
  them all; a Coach answer records the version it was shown. A source removed from the content files
  is retired by a content migration (`private.library_retire_source`).
- Retrieved text is reference data. It never overrides Tracend rules, the athlete's data or the
  safety policy, and rules still decide every number.

The tables, search and ingestion are built (E2). The first 35 sources are files in
`supabase/library/`, loaded by a migration with null embeddings; the `library-embed` Edge Function
fills them with `gte-small`, triggered by a cron job that stays inert until the deploy workflow sets
the function's URL in Vault (see DATA_MODEL.md section 12). A short
coaching-principles digest of the sources sits in the Coach's stable prompt prefix
(`_shared/library/principles.ts`).

The library shapes every Coach reply on the gateway route (E3): the `library` contributor builds the
query from the question (a follow-up borrows the topic of the last real question, deterministically),
embeds it with `gte-small` by calling the `library-embed` function (the only place the model loads;
coach-chat starts that call once the replay check and the budget reservation have passed, alongside the context preparation),
searches for the athlete's region and renders up to 8 chunks that pass a calibrated relevance floor
(the nearest chunk within cosine distance 0.15, then chunks within 0.19), each tagged with its stable
source id, its kind, year and evidence level, as a volatile block after the athlete data. When no
chunk passes, the block says so and Coach cites nothing. Coach
cites the sources it uses as `library` evidence, and a citation of an id that was not shown is a
reply-guard failure (AI_SAFETY_SPEC §11.2). If retrieval is slow or fails, Coach answers without it
(the Contract 7 host's 4-second limit). Retrieval was chosen over putting the whole library in the
cached prefix after a head-to-head (`docs/handoff/research-library.md`).

Regional modules (E4, D5) are library sources tagged with a country code. The search shows an
athlete `global` sources plus the sources of the country the athlete chose in Account
(`user_accounts.country_code`, optional); with none chosen it falls back to the account locale and
time zone, as before.

Plan explanations cite sources (E5). In Coach chat, a question that asks why the plan is the way it is
(`isPlanExplanationQuestion`, deterministic) is searched twice, as asked and with what the plan is made of
added (the athlete's training days, rep ranges, effort and goal as counts and enumerated values, read
once for the turn), the two result lists merged, and the library block carries a fixed note that the
explanation starts from the plan's own numbers. In the onboarding plan (`onboarding-plan`, gateway route), two searches for the athlete's
region (training, nutrition) put excerpts into the prompt; the model may list the ids it relied on in
`sources`, deterministic code refuses an id that was not shown, and a cited source becomes a
`source: "library"` evidence item labelled from the retrieval and listed in the app under "Why this
plan". A plan that cites nothing says so in "Not known yet", and one whose search found nothing or
failed has low confidence. The rules plan and the settings path never use the library.

### Bounded Coach data lookups (A10)

Coach chat on the gateway route can read the athlete's own records on demand: the model returns
`data_requests` (a lookup name from a closed catalogue, a date range of at most 400 days, a filter
that is "" when the lookup takes none; an empty list is a final answer) in its JSON answer, the Edge Function validates them and calls a read-only `SECURITY DEFINER`
RPC granted to `service_role` for the authenticated athlete, and calls the model again with the dated
rows. At most 2 rounds of at most 8 lookups; each extra model call has its own budget place; the red-flag screen runs
before everything and every guard runs on the final answer. It is bounded, read-only and in-request:
not an autonomous agent (no writes, no background runs, a hard cap on rounds) and not native tool
calling (the gateway sends no tools, so the provider can be swapped). The always-on baseline stays
small: the goal phase, the screening, today's or the next session with targets and home
alternatives, the next 7 days with their muscles, this week's complete-day nutrition, the
watch-outs and the Coverage Brief; everything else comes from lookups. See AI_SAFETY_SPEC §11.1.

**Investigate first (2026-10-20).** Two deterministic contributors make the baseline honest about
what it leaves out. The **Coverage Brief** (`coverage_brief`, replacing the data index) lists each
kind of record with what the summary shows, what a lookup adds, how much exists, how fresh it is and
the neighbouring kinds to check; its neighbour table is static, the same for every question. The
**watch-outs** (`watch_outs`) are facts computed by code across several kinds of record at once
(back-to-back muscles, a session due on a poor-recovery day, a pain flag planned again, behind plan,
repeated skips, drift from the athlete's own usual, stale inputs, an old plan), so no cross-domain
inference is left to a model with thinking off; each states its dates and figures, so the numbers
check grounds a reply on it. The instructions make the first reply a sweep: every lookup that could
change the answer, in one round. A refused request gets one corrected round instead of ending the
investigation. The route (default or stronger model) is chosen from the state of the records the
contributors report, never from the words of the question. The newer kinds of record (the proposals
history, watch workouts of any age, the daily decisions) are filters on existing lookups, so the
structured-output schema is the same bytes as before.

### Add vector retrieval over user data only when all are true

- meaningful unstructured history exists;
- a defined evaluation needs retrieval beyond structured fields and recency windows;
- retrieval materially improves grounded answers;
- RLS, deletion propagation, and injection resistance are tested; and
- cost and observability remain acceptable.

### Split model agents only when all are true

- the single-call workflow has a measured task-interference failure;
- a split materially improves evaluation results;
- deterministic reconciliation remains traceable;
- latency/cost stay acceptable; and
- safety policy remains outside model control.

LangGraph, Redis, a separate API server, and a dedicated vector store outside Postgres are not MVP
dependencies.

## 12. Architectural Invariants

1. RLS is enabled and tested for every exposed user-owned table and Storage bucket.
2. The publishable key may ship in Flutter; secret/service-role and AI keys never do.
3. Client-supplied `user_id` never authorizes access.
4. Model output never activates plans or confirms meals.
5. Each decision references an immutable snapshot and prompt/schema version.
6. Photos are private, purpose-bound, and time-limited in access.
7. Missing data lowers confidence and is never silently invented.
8. Safety policy cannot be overridden by model text.
9. Every accepted persistent change creates a new version and audit event.
10. Degraded operation preserves the last approved plan and user logging.
