# Tracend — Agent Instructions

**Product:** AI personal trainer (iOS). Evidence-driven coaching from health, training, nutrition data.
Active brand, not yet trademarked.

## Commands

**Always use repo wrappers.** Never invoke `flutter`, `dart`, `deno`, `supabase`, `docker`, or
`colima` directly. Pinned versions in `tool/versions.env`.

| Tool                  | Wrapper                       |
| --------------------- | ----------------------------- |
| `flutter ...` / `dart` | `./scripts/flutter.sh ...`   |
| `deno ...`            | `./scripts/deno.sh ...`       |
| `supabase ...`        | `./scripts/supabase.sh ...`   |
| `docker ...`          | `./scripts/docker.sh ...`     |

Key commands:

```sh
./scripts/flutter.sh pub get
./scripts/flutter.sh format --set-exit-if-changed lib test
./scripts/flutter.sh analyze
./scripts/flutter.sh test                           # all tests
./scripts/flutter.sh test path/to/single_test.dart  # single test
./scripts/flutter.sh build ios --release --no-codesign
./scripts/install-device.sh                          # signed release + install on paired iPhone
./scripts/deno.sh fmt --check supabase/functions
./scripts/deno.sh lint supabase/functions
./scripts/deno.sh test supabase/functions
./scripts/pre-deploy.sh                             # full gate (local)
./scripts/pre-deploy.sh --skip-colima --skip-reset   # skip DB if Colima unavailable
```

**Device install config lives in the gitignored `.env`** (`SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`,
optional `SENTRY_DSN`; see `.env.example`). `scripts/install-device.sh` sources it, builds the signed
release, and installs on the paired iPhone. **Never ask the user for these keys — read `.env`.**
If the publishable key is missing or rejected (401 "Invalid API key"), refresh it from the
authenticated CLI and pipe it into `.env` at runtime, e.g.
`./scripts/supabase.sh projects api-keys list --project-ref qsfzzsjenopqqqhvpyaw` then extract the
`sb_publishable_…` value with `grep -oE` into `.env`. Note: the environment redacts literal secret
values typed into tool calls, so write the key via shell variable/pipe — never via Write/Edit.

**CI uses vanilla commands** (`flutter`, `deno` directly). The setup actions place them on PATH.
Do not convert CI workflow steps to wrapper scripts.

**Edge Functions deploy with `--use-api`** (avoids Docker bind-mount issues on external SSD):
```sh
./scripts/supabase.sh functions deploy <name> --project-ref qsfzzsjenopqqqhvpyaw --use-api
```

**Migration push** always dry-run first:
```sh
./scripts/supabase.sh db push --linked --dry-run
./scripts/supabase.sh db push --linked
```

**Backup** before any production mutation:
```sh
./scripts/backup-db.sh               # schema + data
./scripts/backup-db.sh --schema-only
./scripts/backup-db.sh --data-only
```

**Rollback** an Edge Function:
```sh
./scripts/rollback-function.sh <name>
```

**Component gallery** (dev only, no production route):
```sh
./scripts/flutter.sh run -t lib/component_gallery.dart
```

All tooling state, caches, `.dart_tool/`, `build/` → `.tooling/` on external SSD. Never on
internal storage.

## Context & Docs (read order)

1. `docs/PROGRESS_CONTEXT.md` — live dashboard (read first, every session)
2. `docs/handoff/*.md` — per-workstream state (read the one relevant to your task)
3. Authority docs (update when behavior changes):
   - `docs/PRD.md` — scope, features
   - `docs/ARCHITECTURE.md` — data flow, layers
   - `docs/DATA_MODEL.md` — entities, fields, lifecycle
   - `docs/AI_SAFETY_SPEC.md` — model boundaries, provider rules
   - `docs/SECURITY_PRIVACY.md` — auth, RLS, encryption
   - `docs/UX_FLOWS.md` — navigation, screens
   - `docs/DESIGN_SYSTEM.md` — visual, components
   - `docs/TESTING_STRATEGY.md` — test layers, contract tests
   - `docs/IMPLEMENTATION_ROADMAP.md` — phases, sequencing
   - `docs/COST_MODEL.md` — provider costs, budget
   - `docs/CONTEXT_BUDGET.md` — Coach prompt budget
   - `docs/CI_CD_DEPLOYMENT.md` — pipeline design

If authority docs conflict, stop and report the conflict. Do not choose silently.

## Architecture (non-negotiable)

1. Deterministic code calculates trends, adherence, baselines. Model output is
   interpretation/proposal, never authoritative calculation.
2. Model output never activates a plan, confirms a meal, or writes a durable user fact.
3. Persistent changes require: evidence → validation → explicit user approval → new version →
   audit event.
4. The active plan must remain usable when AI, HealthKit, or media processing fails.
5. AI provider keys stay server-side. Supabase secret/service-role keys never enter Flutter.
6. All user-owned tables and Storage buckets have enabled, tested RLS. `auth.uid()` in policies.
7. Photos are private, purpose-bound. Access only through short-lived authorization.
8. Missing/conflicting data lowers confidence; never silently invented.

## Database Rules

- **Forward-only migrations. Never edit an applied migration.**
- **Every migration must be additive.** Rename, drop, or change column type → use two-step:
  (1) add new column, deploy code that reads it; (2) later migration drops old column.
- New migration renames/drops must be safe for the currently-deployed Flutter app and Edge Functions.
- Every RPC consumed by Flutter (`get_my_training_hub`, etc.) must include a `schema_version` field.
  Add fields, never remove or rename existing ones. Only remove in a cleanup migration after all
  consuming builds are updated.
- `auth.users.id` via `auth.uid()` in policies.
- No placeholders, TODO, dead code, or commented-out alternatives in completed work.

## MVP Boundaries (do NOT build)

No Android, no simulator. Excluded: Health Connect, App Store release, minors, pregnancy, medical
diets, eating disorders, rehab, medical-report analysis, exercise-video form correction,
subscriptions, payments, advertising, social features, trainer marketplace, autonomous agents.

Do not add: separate API server, microservices, caches, vector databases, agent frameworks, or
unrelated SDKs without a current requirement. Prefer Supabase-native: Auth, Data API/RPC, Edge
Functions, Storage, Queues, Cron.

## Deployment (automatic)

**Agents MUST NOT run `supabase db push` or `supabase functions deploy`.** Deployment is automated
via GitHub Actions:

- `ci.yml` — every push and PR: deno, flutter, ios-build, migration collision check
- `deploy.yml` — every merge to `main`: verify → dry-run → backup → migrate → deploy functions
  (9 parallel) → smoke test → tag
- `hotfix.yml` — manual `workflow_dispatch` for emergencies

Concurrency lock: `production-deploy` group (`cancel-in-progress: false`). One deploy at a time.

**Manual CLI deploy only when:** GitHub Actions is down OR user explicitly requests it. Must:
verify `./scripts/pre-deploy.sh`, dry-run first, backup first, report each step.

See `docs/CI_CD_DEPLOYMENT.md` for full design.

## Key Facts

- **Supabase project:** `qsfzzsjenopqqqhvpyaw` (Singapore, `ap-southeast-1`)
- **Coach provider:** DeepSeek V4 Flash (`COACH_MODEL_PROVIDER=deepseek`). Prior: Gemini
  `gemini-3.5-flash`, Groq Qwen `qwen/qwen3.6-27b` (superseded).
- **Coach-decide** defaults to deterministic mock. Live model requires all server-side secrets
  configured together.
- **Platform:** iOS only, owner's iPhone 12. No Android. `build ios --release --no-codesign`
  is the compilation gate.
- **9 Edge Functions:** coach-chat, coach-decide, health-check, health-sync, meal-analyze,
  meal-media-retention, onboarding-propose-plan, privacy-delete-account, privacy-export.
- **meal-media-retention** validates a `RETENTION_WORKER_SECRET` (not JWT), stored in Edge
  Function secrets + Supabase Vault. Never in Flutter, logs, or committed files.
- **Sentry:** active in Flutter (`--dart-define SENTRY_DSN=...`) and Edge Functions
  (`Deno.env.get("SENTRY_DSN")`). `beforeSend` scrubber redacts health values, meal content,
  photo URLs, prompts. Failures silent. Empty DSN = disabled.
- **Colima DNS:** fresh VMs sometimes fail DNS. Restart Colima or wait.
- **Contract tests:** `test/contract/` (Flutter→RPC, Flutter→Edge, fixture-based),
  `supabase/functions/_tests/db_contract_test.ts` (Deno→DB, needs local Supabase).
  When changing response shapes: update fixtures, increment `schema_version`.
- **No iOS simulator.** Physical iPhone for runtime testing after signing configured.
