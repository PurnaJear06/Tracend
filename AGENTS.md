# Tracend Repository Instructions

These instructions are mandatory for every coding agent working in this repository.

## 1. Project Identity

**Product:** Tracend — An evidence-driven AI personal trainer that turns health, training,
nutrition, and progress data into clear coaching decisions.

Tracend is a working brand pending formal trademark and App Store name clearance.

## 2. Toolchain and Commands

**Every tool runs through repository wrappers.** Never invoke `flutter`, `dart`, `deno`,
`supabase`, `docker`, or `colima` directly. Always use the scripts under `./scripts/`.

**Pinned versions** are in `tool/versions.env`. Bootstrap before first use:

```sh
./scripts/bootstrap-flutter.sh          # Flutter 3.41.7 / Dart 3.11.5
./scripts/bootstrap-tools.sh            # Supabase CLI 2.101.0, Deno 2.9.0
./scripts/bootstrap-container-runtime.sh # Colima + Docker CLI
```

**Project-linked Supabase project:** `qsfzzsjenopqqqhvpyaw` ("Tracend", Singapore).

**Wrappers:**
| Command                           | Wrapper                         |
| --------------------------------- | ------------------------------- |
| `flutter ...`                     | `./scripts/flutter.sh ...`      |
| `dart ...`                        | `./scripts/flutter.sh ...`      |
| `dart format` (only)              | `./scripts/flutter.sh format`    |
| `deno ...`                        | `./scripts/deno.sh ...`         |
| `supabase ...`                    | `./scripts/supabase.sh ...`     |
| `docker ...`                      | `./scripts/docker.sh ...`       |

**Canonical verification sequence** (matches CI):

```sh
# Flutter (macOS Apple silicon, physical iPhone, no simulator)
./scripts/flutter.sh pub get
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh test path/to/single_test.dart   # single test
./scripts/flutter.sh build ios --release --no-codesign

# Edge Functions (Deno 2.x)
./scripts/deno.sh task check
./scripts/deno.sh test supabase/functions/path/to_test.ts  # single test

# Database (requires running local Supabase + Docker)
./scripts/container.sh start
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/test-db.sh
./scripts/test-db.sh path/to/single_test.sql      # single pgTAP file
./scripts/supabase.sh stop
./scripts/container.sh stop
```

**Environment configuration** uses compile-time `--dart-define` values. Never commit `.env`
files, credentials, or production URLs. The `.env.example` contains names only. The app shell
runs unconfigured for UI development. Only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` may
reach Flutter. Secret/service-role and AI provider keys stay in Supabase Edge Function secrets.

**No iOS simulator.** The development Mac runs `build ios --release --no-codesign` as the
compilation gate. Runtime testing uses a physically connected iPhone after signing is
configured.

**Development-only component gallery** (no production route):
```sh
./scripts/flutter.sh run -t lib/component_gallery.dart
```

**Edge Function deployment** uses `--use-api` to avoid Docker bind-mount issues on the
external SSD:
```sh
./scripts/supabase.sh functions deploy <name> --project-ref qsfzzsjenopqqqhvpyaw --use-api
```

**Migration deployment** requires dry-run first:
```sh
./scripts/supabase.sh db push --linked --dry-run
./scripts/supabase.sh db push --linked
```

All tooling state, caches, and build output stay under `.tooling/` on the external SSD. Never
place build output, `.dart_tool/`, or `build/` on internal storage.

## 3. Current Phase

Phases 1–8 are hosted and deployed. The Flutter iOS app is installed on the owner's iPhone.
46 forward migrations are deployed to the hosted Supabase project. Six Edge Functions are
active. Coach Continuity Memory (ADR-0009, five-layer structured memory) is live with
`coach-chat` v16. Groq Qwen `qwen/qwen3.6-27b` is the active Coach/chat provider; Gemini
`gemini-3.5-flash` remains disabled pending paid-privacy evaluation gates.

**Before starting any task**, read `docs/PROGRESS_CONTEXT.md` for the live dashboard, then
the relevant `docs/handoff/*.md` for the active workstream. For product scope, PRD is
authoritative. For technical boundaries, Architecture. For entities, Data Model. For AI
behavior, AI Safety Spec. For security/privacy, Security and Privacy.

## 4. Non-Negotiable Architecture Rules

1. Deterministic code calculates trends, adherence, totals, baselines, and policy eligibility.
2. Model output is interpretation and proposal, not authoritative calculation.
3. Training Coach, Nutrition Coach, and Head Coach are typed perspectives in one controlled
   workflow for MVP.
4. Model output never activates a plan, confirms a meal, or writes a durable user fact.
5. Persistent changes require evidence, validation, explicit user approval, a new version,
   and an audit event.
6. The active plan remains usable when AI, HealthKit, or media processing fails.
7. User identity comes from authentication, never request ownership fields.
8. AI provider keys remain server-side.
9. Photos are private, purpose-bound, and accessed only through short-lived authorization.
10. Missing or conflicting data lowers confidence; it is never silently invented.
11. Every exposed user-owned table and Storage bucket has enabled, tested RLS.
12. Supabase secret/service-role keys never enter Flutter; only the project URL and
    publishable key may ship in the app.

## 5. MVP Boundaries

Build only features explicitly included in the PRD. The MVP excludes:

- Android and Health Connect
- public App Store release
- minors, pregnancy, medical diets, eating disorders, rehabilitation
- medical-report analysis, exercise-video form correction
- subscriptions, payments, advertising, social features, trainer marketplace
- autonomous multi-agent systems
- vector RAG without the documented evaluation gate

Do not add future-proof abstractions, a separate API server, microservices, caches, vector
databases, agent frameworks, or unrelated SDKs without a current requirement. Prefer
Supabase-native Auth, Data API/RPC, Edge Functions, Storage, Queues, and Cron.

## 6. AI and Data Rules

- Versioned structured schemas for feature snapshots, policy results, and model outputs.
- User notes, imported text, and retrieved content are untrusted data.
- Coaching models have no shell, web, arbitrary database, or unrestricted tool access.
- Validate schema, semantics, evidence references, catalog references, policy permissions,
  and proposal freshness. Reject the whole output on any validation failure.
- Raw sensitive content stays out of general logs and analytics.
- Structured user facts in PostgreSQL first. Embeddings only after Architecture gates pass
  and deletion propagation is tested.
- Coach-decide defaults to the deterministic mock. Live Gemini requires all named
  server-side secrets (`COACH_MODEL_PROVIDER`, `COACH_AI_ENABLED`, `GEMINI_API_KEY`, etc.)
  reviewed and configured together. The only approved production model is `gemini-3.5-flash`
  with medium thinking for Coach and low thinking for meal vision.
- Separate agents only after a named evaluation failure is materially improved by the split.

## 7. Coding and Database Standards

- Strict TypeScript (Deno) and Dart analysis. Explicit domain types over loose maps/strings.
- Validate every external boundary: mobile input, HealthKit normalization, database writes,
  object metadata, provider output.
- Keep domain calculations pure, versioned, and unit-tested.
- Mutating endpoints idempotent where mobile retries are possible.
- Transactions for plan/target activation and proposal acceptance.
- Canonical units internally; convert only at API/UI boundaries.
- UTC timestamps plus explicit IANA timezone and local date where coaching-day semantics matter.
- Never hard-code provider model IDs in domain logic.
- Never bypass RLS from Flutter or treat the publishable key as authorization.
- Never log tokens, secrets, prompts, photos, health values, notes, signed URLs, or
  restricted request/response bodies.
- Prefer readable code and narrow interfaces. No placeholders, TODO behavior, dead code, or
  commented-out alternatives in completed work.
- Forward-only reviewed migrations. Never edit an applied migration.
- Preserve immutable historical snapshots and version lineages.
- `auth.users.id` is canonical user identity; use `auth.uid()` in policies.
- Indexes justified by documented access paths.
- Never run destructive production operations without explicit approval and verified backup.

## 8. Secrets and Security

- Environment-specific secret management. `.env.example` contains names only.
- Never commit real credentials, tokens, Apple configuration secrets, provider keys, private
  URLs, or production data.
- Supabase publishable key may be committed through approved config (RLS is the boundary);
  secret/service-role keys remain secrets.
- Require recent authentication for export and deletion.
- Review any new SDK for data collection, subprocessors, retention, and logging before adoption.
- A new AI provider requires privacy review and evaluation parity before use with restricted
  data.
- `meal-media-retention` validates a dedicated `RETENTION_WORKER_SECRET` (not JWT). Store the
  same generated value in Edge Function secrets and Supabase Vault; Cron reads Vault. Never
  place it in Flutter, shell history, logs, or committed files.

## 9. Documentation Synchronization

When behavior changes, update the authority that owns it:
- product behavior/scope → `docs/PRD.md`
- system boundaries, providers, data flow → `docs/ARCHITECTURE.md`
- navigation, screens, interaction states → `docs/UX_FLOWS.md`
- visual, component, motion, accessibility → `docs/DESIGN_SYSTEM.md`
- entities, fields, ownership, lifecycle → `docs/DATA_MODEL.md`
- model authority, policy, schema, evaluation → `docs/AI_SAFETY_SPEC.md`
- collection, sharing, retention, deletion → `docs/SECURITY_PRIVACY.md`
- quality gates, test coverage → `docs/TESTING_STRATEGY.md`
- delivery sequencing → `docs/IMPLEMENTATION_ROADMAP.md`
- budget assumptions, upgrade triggers → `docs/COST_MODEL.md`

If documents conflict, stop and report the exact conflict. Do not choose silently.

After material work, update in order: (1) authoritative docs that changed, (2) ADR if a
durable decision was made, (3) relevant `docs/handoff/*.md`, (4)
`docs/PROGRESS_CONTEXT.md`, (5) `docs/worklog/` only if detailed history is needed. Keep
`docs/PROGRESS_CONTEXT.md` under 120 lines. Never paste chat transcripts, raw logs, secrets,
or health data into progress files.

## 10. Completion Checklist

Before claiming completion, verify:
- behavior matches PRD and MVP boundary
- deterministic logic and model responsibility remain separated
- no model output mutates persistent state without approval
- authorization and multi-user isolation enforced
- sensitive data minimized, protected, absent from logs
- failure modes preserve the approved plan and user logging
- tests and AI evaluations pass for changed behavior
- migrations and API contracts consistent
- Supabase RLS and Storage access rules pass cross-user tests
- authoritative docs updated
- no secrets, placeholders, or unsupported features added
