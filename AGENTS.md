# Tracend Repository Instructions

These instructions are mandatory for every coding agent working in this repository.

## 1. Project Identity

**Product:** Tracend — An evidence-driven AI personal trainer that turns health, training,
nutrition, and progress data into clear coaching decisions.

Tracend is a working brand pending formal trademark and App Store name clearance.

## 2. Toolchain and Commands

**Every tool runs through repository wrappers.** Never invoke `flutter`, `dart`, `deno`, `supabase`,
`docker`, or `colima` directly. Always use the scripts under `./scripts/`.

**Pinned versions** are in `tool/versions.env`. Bootstrap before first use:

```sh
./scripts/bootstrap-flutter.sh          # Flutter 3.41.7 / Dart 3.11.5
./scripts/bootstrap-tools.sh            # Supabase CLI 2.101.0, Deno 2.9.0
./scripts/bootstrap-container-runtime.sh # Colima + Docker CLI
```

**Project-linked Supabase project:** `qsfzzsjenopqqqhvpyaw` ("Tracend", Singapore).

**Wrappers:**

| Command              | Wrapper                       |
| -------------------- | ----------------------------- |
| `flutter ...`        | `./scripts/flutter.sh ...`    |
| `dart ...`           | `./scripts/flutter.sh ...`    |
| `dart format` (only) | `./scripts/flutter.sh format` |
| `deno ...`           | `./scripts/deno.sh ...`       |
| `supabase ...`       | `./scripts/supabase.sh ...`   |
| `docker ...`         | `./scripts/docker.sh ...`     |

**Canonical verification sequence** (matches CI):

```sh
# Full gate — one command, all layers. Run before every production deploy.
./scripts/pre-deploy.sh

# Option: skip database steps when Colima is unavailable
./scripts/pre-deploy.sh --skip-colima --skip-reset

# Single-layer variants:
./scripts/pre-deploy.sh --deno-only       # Deno fmt + lint + test only
./scripts/pre-deploy.sh --flutter-only     # Flutter analyze + test + build only
./scripts/pre-deploy.sh --db-only          # pgTAP only (requires Colima)
./scripts/pre-deploy.sh --help             # Full options

# Individual commands (for focused iteration):
./scripts/flutter.sh pub get
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh analyze
./scripts/flutter.sh test
./scripts/flutter.sh test path/to/single_test.dart   # single test
./scripts/flutter.sh build ios --release --no-codesign
./scripts/deno.sh task check
./scripts/deno.sh test supabase/functions/path/to_test.ts  # single test
./scripts/container.sh start
./scripts/supabase.sh start
./scripts/supabase.sh db reset
./scripts/test-db.sh
./scripts/test-db.sh path/to/single_test.sql      # single pgTAP file
./scripts/supabase.sh stop
./scripts/container.sh stop
```

**Environment configuration** uses compile-time `--dart-define` values. Never commit `.env` files,
credentials, or production URLs. The `.env.example` contains names only. The app shell runs
unconfigured for UI development. Only `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` may reach
Flutter. Secret/service-role and AI provider keys stay in Supabase Edge Function secrets.

**CI uses vanilla commands, not wrappers.** The `.github/workflows/ci.yml` invokes `flutter` and
`deno` directly because setup actions place them on PATH. Do not convert CI steps to wrapper scripts.

**No iOS simulator.** The development Mac runs `build ios --release --no-codesign` as the
compilation gate. Runtime testing uses a physically connected iPhone after signing is configured.

**Colima DNS.** Fresh Colima VMs sometimes fail DNS resolution (host name lookup errors during
`pg_dump` in `backup-db.sh`). Restarting Colima or waiting a few minutes typically resolves it.

**Development-only component gallery** (no production route):

```sh
./scripts/flutter.sh run -t lib/component_gallery.dart
```

**Edge Function deployment** uses `--use-api` to avoid Docker bind-mount issues on the external SSD:

```sh
./scripts/supabase.sh functions deploy <name> --project-ref qsfzzsjenopqqqhvpyaw --use-api
```

**Migration deployment** requires dry-run first:

```sh
./scripts/supabase.sh db push --linked --dry-run
./scripts/supabase.sh db push --linked
```

All tooling state, caches, and build output stay under `.tooling/` on the external SSD. Never place
build output, `.dart_tool/`, or `build/` on internal storage.

## 3. Context and Docs

**Before any task**, read `docs/PROGRESS_CONTEXT.md` (live dashboard), then the relevant
`docs/handoff/*.md`. These rotate as work progresses; do not trust cached counts.

**Stable facts** (not kept in PROGRESS_CONTEXT):
- Groq Qwen `qwen/qwen3.6-27b` is the active Coach/chat provider (ADR 0006).
- Gemini `gemini-3.5-flash` is disabled pending paid-privacy evaluation gates.
- Flutter iOS app installed on owner's iPhone 12. No Android, no simulator.
- All 9 Edge Functions are active: coach-chat, coach-decide, health-check, health-sync,
  meal-analyze, meal-media-retention, onboarding-propose-plan, privacy-delete-account,
  privacy-export.

**Authority docs** (when behavior changes, update the one that owns it):
- Product scope → `docs/PRD.md`
- Architecture/data-flow → `docs/ARCHITECTURE.md`
- UX/navigation → `docs/UX_FLOWS.md`
- Visual/component → `docs/DESIGN_SYSTEM.md`
- Entities/fields/lifecycle → `docs/DATA_MODEL.md`
- AI/model authority → `docs/AI_SAFETY_SPEC.md`
- Security/privacy → `docs/SECURITY_PRIVACY.md`
- Test coverage → `docs/TESTING_STRATEGY.md`
- Delivery → `docs/IMPLEMENTATION_ROADMAP.md`
- Budget → `docs/COST_MODEL.md`

If authority docs conflict, stop and report the exact conflict — do not choose silently.

## 4. Non-Negotiable Architecture Rules

1. Deterministic code calculates trends, adherence, totals, baselines, and policy eligibility.
2. Model output is interpretation and proposal, not authoritative calculation.
3. Training Coach, Nutrition Coach, and Head Coach are typed perspectives in one controlled workflow
   for MVP.
4. Model output never activates a plan, confirms a meal, or writes a durable user fact.
5. Persistent changes require evidence, validation, explicit user approval, a new version, and an
   audit event.
6. The active plan remains usable when AI, HealthKit, or media processing fails.
7. User identity comes from authentication, never request ownership fields.
8. AI provider keys remain server-side.
9. Photos are private, purpose-bound, and accessed only through short-lived authorization.
10. Missing or conflicting data lowers confidence; it is never silently invented.
11. Every exposed user-owned table and Storage bucket has enabled, tested RLS.
12. Supabase secret/service-role keys never enter Flutter; only the project URL and publishable key
    may ship in the app.

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
databases, agent frameworks, or unrelated SDKs without a current requirement. Prefer Supabase-native
Auth, Data API/RPC, Edge Functions, Storage, Queues, and Cron.

## 6. AI and Data Rules

- Versioned structured schemas for feature snapshots, policy results, and model outputs.
- User notes, imported text, and retrieved content are untrusted data.
- Coaching models have no shell, web, arbitrary database, or unrestricted tool access.
- Validate schema, semantics, evidence references, catalog references, policy permissions, and
  proposal freshness. Reject the whole output on any validation failure.
- Raw sensitive content stays out of general logs and analytics.
- Structured user facts in PostgreSQL first. Embeddings only after Architecture gates pass and
  deletion propagation is tested.
- Coach-decide defaults to the deterministic mock. Live Gemini requires all named server-side
  secrets (`COACH_MODEL_PROVIDER`, `COACH_AI_ENABLED`, `GEMINI_API_KEY`, etc.) reviewed and
  configured together. The only approved production model is `gemini-3.5-flash` with medium thinking
  for Coach and low thinking for meal vision.
- Separate agents only after a named evaluation failure is materially improved by the split.

## 7. Coding and Database Standards

- Strict TypeScript (Deno) and Dart analysis. Explicit domain types over loose maps/strings.
- Validate every external boundary: mobile input, HealthKit normalization, database writes, object
  metadata, provider output.
- Keep domain calculations pure, versioned, and unit-tested.
- Mutating endpoints idempotent where mobile retries are possible.
- Transactions for plan/target activation and proposal acceptance.
- Canonical units internally; convert only at API/UI boundaries.
- UTC timestamps plus explicit IANA timezone and local date where coaching-day semantics matter.
- Never hard-code provider model IDs in domain logic.
- Never bypass RLS from Flutter or treat the publishable key as authorization.
- Never log tokens, secrets, prompts, photos, health values, notes, signed URLs, or restricted
  request/response bodies.
- No placeholders, TODO behavior, dead code, or commented-out alternatives in completed work.
- Forward-only reviewed migrations. Never edit an applied migration.
- Preserve immutable historical snapshots and version lineages.
- `auth.users.id` is canonical user identity; use `auth.uid()` in policies.
- Indexes justified by documented access paths.
- Never run destructive production operations without explicit approval and verified backup.

## 8. Secrets and Security

- Environment-specific secret management. `.env.example` contains names only.
- Never commit real credentials, tokens, Apple configuration secrets, provider keys, private URLs,
  or production data.
- Supabase publishable key may be committed through approved config (RLS is the boundary);
  secret/service-role keys remain secrets.
- Require recent authentication for export and deletion.
- Review any new SDK for data collection, subprocessors, retention, and logging before adoption.
- A new AI provider requires privacy review and evaluation parity before use with restricted data.
- `meal-media-retention` validates a dedicated `RETENTION_WORKER_SECRET` (not JWT). Store the same
  generated value in Edge Function secrets and Supabase Vault; Cron reads Vault. Never place it in
  Flutter, shell history, logs, or committed files.

## 9. Documentation Synchronization

When behavior changes, update the authority that owns it (see §3 for the doc map).

After material work, update in order: (1) authoritative docs that changed, (2) ADR if a durable
decision was made, (3) relevant `docs/handoff/*.md`, (4) `docs/PROGRESS_CONTEXT.md`, (5)
`docs/worklog/` only if detailed history is needed. Keep `docs/PROGRESS_CONTEXT.md` under 120 lines.
Never paste chat transcripts, raw logs, secrets, or health data into progress files.

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

## 11. Stability and Deployment

### Pre-Deploy Gate (Mandatory)

Before every `supabase db push --linked` to production, run the full gate:

```sh
./scripts/pre-deploy.sh
```

If any step fails, **do not deploy**. Fix the failure, then re-run the gate. The gate runs:

1. Local Supabase start + db reset (all migrations applied cleanly)
2. pgTAP database tests
3. Deno format + lint + test
4. Flutter static analysis
5. Flutter unit/widget tests
6. Flutter iOS release build
7. Production migration dry-run

### Forward-Compatible Migration Rules

**Every migration must be safe for the currently-deployed Flutter app and Edge Functions.**

Before writing a migration, answer these questions:

1. Does it **rename**, **drop**, or **change the type** of any column/function/RPC return field that
   is currently referenced by deployed Flutter or Edge Function code?
2. Does it **remove** an RPC parameter or change an RPC return shape that Flutter parses?

If the answer to either question is **yes**, use the two-step pattern:

**Step 1 (ADD):** Add the new column/function/field. Old code still works against the old column.
**Deploy:** Deploy Flutter + Edge Function that consume the new column. **Step 2 (REMOVE):** In a
follow-up migration (days later), drop the old column only after all deployed code has been updated.

**Never single-step a rename/drop/type-change.** The deployed Flutter app on the iPhone must
continue to work after the migration is applied but before the new build is installed.

**RPC contract rule:** Every RPC consumed by Flutter (`get_my_training_hub`, `get_my_daily_brief`,
etc.) must include an explicit `schema_version` field. Add new fields, never remove or rename
existing fields in a deployed migration. Only remove fields in a cleanup migration after all Flutter
builds consuming the old fields are updated.

### Contract Tests

Three layers verify that the full stack works together:

| Layer              | Location                                        | What It Tests                                        | Requires                                 |
| ------------------ | ----------------------------------------------- | ---------------------------------------------------- | ---------------------------------------- |
| **Deno → DB**      | `supabase/functions/_tests/db_contract_test.ts` | RPCs return valid shapes the Edge Functions expect   | Local Supabase running                   |
| **Flutter → RPC**  | `test/contract/*_contract_test.dart`            | Flutter can parse real RPC response shapes           | JSON fixtures (no Supabase needed in CI) |
| **Flutter → Edge** | `test/contract/*_contract_test.dart`            | Flutter can parse real Edge Function response shapes | JSON fixtures                            |

**When adding or changing an RPC or Edge Function response shape:**

- Update the contract test fixture (which triggers a manual review of the shape change)
- Update Flutter parsing code to match
- Both must pass the gate before deployment

**When a contract test fixture is updated, the review must verify:**

- No field removed that deployed Flutter code depends on
- New fields are additive only (or the old field is preserved until the follow-up migration)
- `schema_version` is incremented

### Context Budget

Every addition to the Coach context pipeline must pass the budget contract test. See
`docs/CONTEXT_BUDGET.md` for rules, budgets, and what to do when the contract test fails.

### Deployment Order

When a feature touches multiple layers, deploy in this order:

1. Database migration (additive only — follow forward-compatible rules)
2. Edge Functions (accept both old and new payload shapes)
3. Flutter build + install to iPhone

Verify each layer deploys successfully before moving to the next. If any layer fails, roll back by
reverting the migration (using its rollback script) and re-deploying the old Edge Function version.

### Database Backup

Run before every production migration:

```sh
./scripts/backup-db.sh           # schema + data via session pooler
./scripts/backup-db.sh --schema-only
./scripts/backup-db.sh --data-only
```

Backups land in `.tooling/backups/YYYY-MM-DD/` with a SHA-256 manifest. Requires the Supabase
session pooler (port 6543, enabled on the hosted project). Backups are read-only; never run
destructive operations without a verified backup.

### Edge Function Rollback

```sh
./scripts/rollback-function.sh <name>   # coach-chat, meal-analyze, etc.
```

Queries the function's git history, checks out the prior committed version, and redeploys with
`--use-api`. Used when a deployed Edge Function needs an immediate revert.

### Sentry Crash Reporting

Sentry is active in both Flutter and Edge Functions:

| Layer | DSN Source | Disabled When |
|-------|-----------|---------------|
| Flutter | `--dart-define SENTRY_DSN=...` | DSN empty or omitted |
| Edge Functions | `Deno.env.get("SENTRY_DSN")` (hosted secret) | Secret absent |

**Flutter build with Sentry:**

```sh
./scripts/flutter.sh build ios --release --no-codesign \
  --dart-define SENTRY_DSN=https://6d3f662b0d2eda3941ad9b529c2d3446@o4511762519490560.ingest.us.sentry.io/4511762526830592 \
  --dart-define SUPABASE_URL=... \
  --dart-define SUPABASE_PUBLISHABLE_KEY=...
```

**Edge Function secret** (set once, survives deploys):

```sh
./scripts/supabase.sh secrets set SENTRY_DSN=https://6d3f662b0d2eda3941ad9b529c2d3446@o4511762519490560.ingest.us.sentry.io/4511762526830592
```

The `beforeSend` scrubber redacts HealthKit values, meal content, photo URLs, and prompt text
before events leave the device. Sentry failures are silent — they never affect the app or the
Edge Function caller.
