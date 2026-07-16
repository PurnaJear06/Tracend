# Tracend Architecture

## Personal Coaching State Engine

Structured PostgreSQL facts remain the coaching memory. Workout truth and
bounded HealthKit workout references are reconciled deterministically, then a
versioned Coach Context v2 snapshot supplies evidence IDs, freshness, coverage
and conflicts to Qwen. Model output cannot replace calculations or activate
persistent changes. Vector retrieval remains outside MVP until its evaluation
gate is met.

**Status:** Authoritative MVP technical architecture  
**Scope:** Private iOS TestFlight beta  
**Backend decision:** Supabase-managed backend

## 1. Architecture Goals

The architecture must:

- preserve a simple, reliable coaching loop;
- separate deterministic analysis from model interpretation;
- prevent model output from mutating plans without validation and approval;
- isolate every user's sensitive data with mandatory Row Level Security;
- support HealthKit and private photos without client-side provider secrets;
- use Supabase-native capabilities before adding separate infrastructure;
- allow evaluated AI-provider replacement behind a narrow adapter; and
- permit the narrowly documented ADR 0006 Groq Qwen owner test without any
  client credential or direct provider access; and
- defer vector RAG and autonomous agents until measured value exists.

Product behavior is defined in [PRD.md](./PRD.md), security in [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md), UX in [UX_FLOWS.md](./UX_FLOWS.md), and budget assumptions in [COST_MODEL.md](./COST_MODEL.md).

## 2. System Context

```text
┌──────────────────────────────────────────────────────────────┐
│ Flutter iOS app                                              │
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
│ Structured user data        │   │ AI provider API           │
│ versions · audit · policies │   │ text + vision             │
└──────────────────────────────┘   └───────────────────────────┘
```

HealthKit stays on the device. Flutter reads authorized types, normalizes required summaries, and sends idempotent payloads to an authenticated Edge Function. AI keys and the Supabase secret/service-role key exist only in Supabase Edge Function secrets.

## 3. Technology Decisions

### 3.1 Mobile

- Flutter targeting iOS first.
- `supabase_flutter` handles Supabase Auth sessions and client access.
- Native Sign in with Apple exchanges the Apple identity token and nonce with
  Supabase Auth for an external private beta. Owner-only development may use
  Supabase email/password through the same client auth boundary.
- `HealthDataSource` wraps the pinned `health` Flutter plugin. The adapter is
  read-only for MVP and exposes only normalized internal sample types.
- The approved plan and in-progress workout are cached locally for degraded/offline operation.
- Feature widgets use [DESIGN_SYSTEM.md](./DESIGN_SYSTEM.md), Dynamic Type, VoiceOver, Reduced Motion, safe areas, and state restoration.
- The client may contain the Supabase project URL and publishable key. It must never contain secret/service-role keys or AI-provider keys.

### 3.2 Supabase Auth

- Supabase Auth is the identity and session authority.
- Sign in with Apple is the external private-beta login provider. Until Apple
  Developer Program capabilities are available, owner-only builds may enable
  the email/password development mode from ADR 0002. Anonymous auth, hard-coded
  users, and client-side authentication bypasses are prohibited.
- The native Apple flow uses nonce validation and captures the name only when Apple supplies it on first authorization.
- Supabase access/refresh sessions are stored through platform-protected client storage; Tracend does not implement a parallel token issuer.
- Phase 8 reminders use iOS `UserNotifications` through a narrow Flutter method
  channel. Scheduling remains on-device; PostgreSQL stores only owner-scoped
  reminder booleans, the coarse iOS authorization state, and append-only
  consent evidence through a validated RPC. Native `UserDefaults` retains the
  device's requested toggles; pending notification requests are delivery state,
  not the preference source, and are repaired from those toggles after reopen.
- `auth.users.id` is the canonical `user_id` for application-owned records.
- Recent authentication is required before export, account deletion, or sensitive session changes.
- Phase 8 export reauthenticates the owner, queues only an opaque export ID,
  builds user-readable JSON/CSV plus purpose-organized private media, encrypts
  the ZIP with AES-256-GCM from a non-persisted password-derived key, and stores
  it in private `account-exports`. Signed download authorization lasts 60
  seconds and stops after three uses or seven days.
- Account deletion uses a separate recent-authenticated opaque job. Private
  Storage bytes are removed before canonical Auth deletion cascades through
  application data; only a content-free completion receipt remains for 180 days.

### 3.3 PostgreSQL and Data API

- Supabase PostgreSQL is the system of record.
- All schema changes are forward-only SQL migrations committed under `supabase/migrations`.
- Every exposed user-owned table has RLS enabled and tested. Policies derive ownership from `auth.uid()`.
- Simple user-scoped reads and low-risk writes may use the generated Data API under RLS and database constraints.
- Multi-table mutations, plan activation, proposal acceptance, final meal confirmation, and other invariant-heavy operations use transactional database functions invoked through authenticated RPC or Edge Functions.
- Security-definer functions are exceptional, use a fixed safe `search_path`, validate authorization internally, expose minimal grants, and receive dedicated tests.
- Structured PostgreSQL fields and bounded summaries are the MVP memory system. `pgvector` is not enabled.

### 3.4 Edge Functions

Supabase Edge Functions are TypeScript/Deno server-side boundaries for:

- HealthKit summary validation and idempotent sync;
- onboarding assessment and initial plan proposal;
- deterministic feature snapshot and safety-policy execution;
- AI provider orchestration and response validation;
- meal and progress-image analysis jobs;
- export and deletion workflows;
- privileged media authorization; and
- rate limiting, cost policy, and sanitized operational telemetry.

Functions are short-lived, idempotent, schema-versioned, and designed for cold starts. Long-running or retryable work is represented as queue messages rather than holding a client request open.

### 3.5 Storage

- Supabase Storage uses separate private buckets for meal images, progress photos, and temporary exports.
- RLS policies scope objects by authenticated user and purpose.
- Upload restrictions enforce content type and maximum size; server-side processing verifies bytes, dimensions, checksum, and metadata.
- Downloads use an authenticated request or short-lived signed URL. Object paths are never authorization.
- Storage lifecycle metadata remains in PostgreSQL because database backups do not contain Storage object bytes.

### 3.6 Queues and Cron

- Supabase Queues (`pgmq`) handles durable meal analysis, progress analysis, weekly review, export, deletion, and provider-retry work.
- Queue payloads contain opaque resource IDs, not raw photos, prompts, tokens, or health records.
- Workers reauthorize resource ownership and consent at execution time.
- Supabase Cron (`pg_cron`) schedules weekly reviews, retention cleanup, stale-job recovery, and cost/quality monitoring.
- The existing daily retention worker also removes expired export packages;
  failed Storage deletion retains the object reference for retry.
- Concurrency, retry count, visibility timeout, dead-letter/archive behavior, and idempotency are defined per job type.

The Phase 7 weekly-review worker is database-native: daily Cron deduplicates one
job per active user and local review week, `pgmq` carries only the job ID and
schema version, and a five-minute Cron consumer rechecks account eligibility
before building the deterministic snapshot and review. Failures use bounded
delayed retries and become terminal after three attempts. This path does not
invoke a model or create a proposal.

### 3.7 AI provider

- Edge Functions call providers through a small `CoachModelProvider` TypeScript interface.
- Gemini is the planned sole live provider for owner dogfooding, subject to the
  same privacy review and text/vision evaluation gates. Provider/model
  identifiers remain environment configuration; the mock provider stays the
  default until those gates pass.
- A server-only Gemini structured-output adapter may exist while disabled. It
  fails closed unless deployment explicitly attests that paid-service data
  terms are active; adapter presence is not provider activation.
- Calls use structured output, compact feature snapshots, request-level timeouts, and per-user rate/cost gates.
- Provider output never directly writes canonical user state. Validation and approval remain in deterministic code and PostgreSQL transactions.

Production routing uses stable `gemini-3.5-flash` with task-level thinking:
medium for normal Coach reasoning, high only for evaluated difficult review
cases, and low for bounded meal-image extraction. Lite models are not valid
production routes. The deterministic mock remains the rollback provider.

For the ADR 0006 owner Qwen test, a live chat may make one bounded
schema-repair retry. If Qwen still fails transport or semantic validation, the
Edge Function records a sanitized failed run and returns an unavailable result;
it must not persist or present a deterministic fallback as a model response.

## 4. Supabase Boundary Rules

| Operation | Allowed boundary |
|---|---|
| Read own profile/logs/approved plan | Data API with RLS |
| Read own sanitized AI usage summary | User-scoped RPC or Edge Function aggregated from `model_runs` |
| Draft check-in or in-progress workout | Data API/RPC with RLS, idempotency, and constraints |
| HealthKit sync | Edge Function |
| Activate or change plan/targets | Edge Function + transactional RPC |
| Confirm analyzed meal | Edge Function + transactional RPC |
| Invoke AI provider | Edge Function only |
| Create/read restricted signed media URL | Edge Function or tightly scoped Storage RLS |
| Export/delete account | Edge Function + Queue |
| Retention/weekly processing | Cron + Queue + Edge Function/database function |

The Flutter app never connects directly to PostgreSQL, bypasses RLS, invokes secret-key operations, or calculates authoritative plan mutations.

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

Training Coach, Nutrition Coach, and Head Coach are fields in one response, not autonomous processes.

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

The model receives prepared features and evidence identifiers, not unrestricted table access or raw history.

## 6. Client Integration Surface

### Supabase Auth

- Native Sign in with Apple through Supabase Auth for external beta builds, or
  the explicitly configured owner-development email/password mode from ADR
  0002.
- Session refresh, sign-out, and supported device-session revocation.

### Versioned Edge Functions

```text
onboarding-assess
onboarding-propose-plan
health-sync
workout-complete
meal-analyze
meal-confirm
coach-decide
coach-chat
meal-analyze
proposal-respond
progress-analyze
weekly-review
privacy-export
privacy-delete-account
```

`get_my_training_hub(period)`, `get_my_nutrition_schedule(date)`, and
`get_my_daily_brief(date)` are authenticated read-model RPCs. They derive
identity from `auth.uid()`, use only active approved versions and confirmed
execution, and return bounded structured data for the iPhone client.

Coach chat stores owner-scoped threads/messages in PostgreSQL under forced RLS.
`coach-chat` loads at most 20 recent messages from the current thread plus 20
recent messages from other saved Coach threads and compact deterministic context,
including the active goal/profile schedule, up to seven days of normalized
HealthKit summaries and confirmed nutrition totals, recent completed workouts,
measurements, the latest weekly/daily decisions, and the latest check-in,
invokes a no-tools structured-output provider, validates the complete answer
and evidence, and persists both messages atomically. The daily Head Coach
decision remains a separate immutable record pinned above conversation.
`prepare_coach_chat_v2` reconciles context coverage independently from the
same-day daily-decision policy: a recent HealthKit summary is valid chat
context even when the current calendar day has no complete HealthKit row.
`get_my_coach_context_status()` exposes only owner-scoped source availability,
counts, and latest dates; it returns no health values or provider secrets.

Meal-image analysis uploads to private purpose-bound Storage, creates an
unconfirmed draft, and invokes `meal-analyze`. Candidate food and portion data
remain estimates until transactional confirmation snapshots the user's
corrections into confirmed meal items.

Function request/response schemas are versioned, shared where practical, and validated at runtime. Function names are stable contracts; breaking changes require a new schema/version and migration path.

### Transactional RPC

RPC is used for narrow atomic operations such as activation of an approved plan version, acceptance/rejection of a proposal, completed-session amendment, and confirmed-meal persistence. Execute grants are explicit and RLS/ownership rules remain enforced.

## 7. Primary Data Flows

### HealthKit sync

1. Mobile requests an individual HealthKit permission in context.
2. Mobile reads the authorized date window and normalizes supported values.
3. Mobile computes source/checksum metadata required for deduplication.
4. `health-sync` verifies JWT, units, ranges, timestamps, and idempotency key.
5. A transaction upserts daily summaries and records the sync run.
6. Feature snapshots consume only successfully normalized records.

The first successful owner-device sync reads a bounded 31-day window so recent
project history can be restored; later syncs read seven days. Only normalized
daily summaries cross the device boundary, and the server contract rejects a
window longer than 31 days.

An empty response never proves permission denial.

### Meal analysis

1. Authenticated user creates a purpose-bound object in the private meal bucket.
2. Mobile uploads the compressed image under Storage RLS.
3. An Edge Function validates metadata/consent and enqueues an opaque analysis job.
4. Worker sends minimized image data or a short-lived reference to the provider.
5. Structured candidates are validated and stored as unconfirmed observations.
6. User edits candidates; `meal-confirm` resolves catalog items and calls transactional confirmation RPC.
7. Cron/Queue enforce meal-image retention.

### Progress photos

Progress photos use separate consent, bucket, prefix, RLS policy, queue, retention, and signed-read path. Raw images never enter routine coaching prompts.

The Phase 7 foundation hosts measurement and private-media metadata before any
vision provider is enabled. Flutter may show capture guidance while transfer is
unavailable, but real capture requires the private bucket policies plus an
authorized upload/read/delete path. Deterministic progress summaries remain
available when Storage, Queue, Cron, or AI is unavailable.

## 8. Environments and Deployment

- **local:** Supabase CLI + Docker-compatible runtime, local Edge Functions, mocked AI/HealthKit fixtures, and Flutter simulator/device configuration. The local Supabase stack must not be exposed publicly.
- **private-beta:** one hosted Supabase project in the nearest suitable region, separate project secrets, private buckets, quota alerts/manual backups on Free, Spend Cap on Pro, and a TestFlight build.
- **staging:** defer a second paid hosted project until beta complexity needs it; use local development and isolated synthetic fixtures first.

No environment shares production user data or reusable secret keys. Production changes deploy through reviewed migrations and versioned function deployments, not ad hoc dashboard edits.

## 9. Failure and Degradation

- **AI unavailable/invalid:** preserve approved plans and logging; show last valid timestamped decision and deterministic guidance.
- **HealthKit partial/unavailable:** show missing data and manual fallback; lower confidence.
- **Edge Function timeout:** return a resumable job/status response where applicable; never duplicate work.
- **Queue delayed:** expose processing status; retry within bounded policy.
- **Storage unavailable:** retain safe local draft when possible and allow non-photo features.
- **Conflicting data:** surface conflict and block persistent change until resolved.
- **Supabase outage:** cached approved plan and in-progress workout remain usable; sync resumes idempotently.
- **Authorization/RLS failure:** return no cross-user existence detail and emit a sanitized audit event.

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

The Account usage view reads a sanitized, authenticated per-user aggregation.
It does not expose provider credentials, prompts, provider request IDs, raw
errors, or cross-user totals. Provider secrets are configured only through
environment-specific Supabase secret management.

When using Pro, enable the Supabase Spend Cap before inviting testers. Free requires quota monitoring and manual database/Storage backups instead. AI providers require project-level budgets, per-user quotas, anomaly alerts, and a server-side kill switch. See [COST_MODEL.md](./COST_MODEL.md).

## 11. RAG and Multi-Agent Adoption Gates

### Structured memory first

Goals, preferences, constraints, plans, confirmed meals, decisions, and weekly summaries remain relational data retrieved with explicit user-scoped queries.

### Add vector retrieval only when all are true

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

LangGraph, Redis, a separate API server, and a dedicated vector store are not MVP dependencies.

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
