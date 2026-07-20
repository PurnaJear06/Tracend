# Tracend Progress Context

**Active change:** Coach Continuity Memory (ADR-0009) — five-layer structured memory stack hosted
and deployed. Post-deploy fixes: (1) 20260717110001 fixed v4→v5 infinite recursion; (2)
20260717110002 expanded schema_version constraint for '4.0'; (3) 20260717110003 replaced unsupported
`jsonb_agg(... ORDER BY ...)` on hosted PG with subquery-based ordering for narrative, preferences,
and journal aggregation in v5; (4) 20260717110004 fixed ambiguous `coaching_date` PL/pgSQL variable
vs table column (table-qualified the references in the journal query). Prompt restructure
(coach-chat v16) separates `system` (rules, schema, evidence) from `user` (the user's actual
message) — previously the user's question was buried inside one giant user message alongside the
JSON context, causing the model to ignore it and emit the same plan-related answer regardless of
what was asked. Is now the primary content of the user message and the rule "Lead with one clear
recommendation" was removed in favour of "Answer the user's specific message first." `coach-chat`
v16 is ACTIVE. Owner should test one chat message (especially greetings and casual questions — these
previously returned canned plan advice).

**Purpose:** tiny live dashboard and pointer index, not a history dump.

## Required Agent Flow

1. Read `AGENTS.md` → this dashboard → relevant authority docs → scoped handoff.
2. Inspect actual files before editing. After work, update handoff + this dashboard.

## Context Layers

| Layer     | Path                       | Purpose                  | Read by Default |
| --------- | -------------------------- | ------------------------ | --------------- |
| Rules     | `AGENTS.md`                | Mandatory agent behavior | Yes             |
| Authority | `docs/*.md` specs          | Product/architecture/etc | Relevant only   |
| Dashboard | `docs/PROGRESS_CONTEXT.md` | Current phase, pointers  | Yes             |
| Handoff   | `docs/handoff/*.md`        | Per-workstream state     | Relevant only   |
| Worklog   | `docs/worklog/*.md`        | Detailed history         | When needed     |
| ADR       | `docs/adr/*.md`            | Durable decisions        | When relevant   |

## Current Phase

Phases 1–8 are hosted; Coach Continuity Memory (v6 schema + v16 prompt) is hosted and live.
Stability infrastructure deployed 2026-07-19, context budget guard + health-check deployed
2026-07-20. Pre-deploy gate, contract tests, Sentry, backups, auth hardening all live.

## Active Workstreams

| Workstream              | Status                               | Read Next                  | Detail History                                |
| ----------------------- | ------------------------------------ | -------------------------- | --------------------------------------------- |
| Backend foundation      | **Complete — verified**              | `docs/handoff/backend.md`  | worklogs                                      |
| Frontend/UI             | **Complete — iPhone release build**  | `docs/handoff/frontend.md` | worklogs                                      |
| Coach Continuity Memory | **Deployed**                         | `docs/handoff/backend.md`  | `docs/worklog/2026-07-17-coach-continuity.md` |
| Stitch/design           | **23 refs imported**                 | `docs/handoff/design.md`   | `design/stitch/README.md`                     |
| Stability infra         | **Complete — deployed**             | `AGENTS.md` §11            | N/A                                           |

## Global Current State

- Supabase project `qsfzzsjenopqqqhvpyaw` (Singapore); 50 migrations, 11 are fix migrations.
- Navigation: five tabs — Today · Train · Coach · Nutrition · Progress.
- Groq Qwen `qwen/qwen3.6-27b` is the owner-test Coach/chat provider (ADR 0006).
- Gemini `gemini-3.5-flash` remains disabled pending paid-privacy/evaluation gates.
- Sign in with Apple deferred; owner email/password mode active (ADR 0002).

## Global Open Decisions

- Apple Developer Program enrollment and TestFlight environment names.
- Licensed food catalog source.
- Owner smoke: rest-day Train, exact Nutrition foods, Today Health evidence refresh.
- Production migration deploy for `20260719090000_context_budget_guard.sql`. ✅ Deployed 2026-07-20.

## Coach Continuity (2026-07-17)

ADR-0009 five-layer structured memory: `coach_narrative_entries`, `user_preferences`,
`coach_session_summaries`, FTS on `coach_messages`, `prepare_coach_chat_v5`,
`search_coach_messages`, etc. `CoachChatAnswerV2` with optional `reasoning_chain`. `coach-chat` v16
with preference detection, FTS retrieval, session summary. Tests: pgTAP 36 assertions, Deno 58/58.
Post-deploy fixes: 4 migrations (v4→v5 recursion, schema_version constraint, jsonb_agg ordering,
ambiguous coaching_date). Prompt restructure separates system/rules from user/message.

## Global Known Issues

- Do not commit `.codex/config.toml`.
- CoreSimulator not used; physical iPhone for builds.
- Supabase CLI timeout on `db reset` is known, not a schema failure.
- Colima must be running for local pgTAP execution and Deno→DB contract tests.
- Contract test fixtures must be updated when RPC or Edge Function response shapes change — the act
  of updating them triggers a manual review of the shape change.

## HealthKit Quick-Complete (2026-07-18)

TrainScreen hub reloads after workout completion via `push<bool>` / `pop(true)`. When Apple Health
detects a workout on a day with a scheduled Tracend workout but no completed session, Train shows a
prompt card. "Yes, mark complete" calls `healthkit_auto_complete_workout` RPC. Per-date refactor:
lightweight `get_healthkit_completion_candidate(date)` RPC called per weekday. Completion state v1.3:
weekday strip shows green checkmark for completed days. `loadSession`/`start` accept optional
`localDate`. Auto-completed sessions show plan exercises read-only with info banner.

**Migrations:** `20260718100000`, `20260718110000`, `20260718150000`. All deployed.
**Tests:** Flutter 85/85 pass. Docs: PRD, UX_FLOWS, ARCHITECTURE, DATA_MODEL, SECURITY_PRIVACY,
AI_SAFETY_SPEC, TESTING_STRATEGY, frontend handoff updated.

## Stability Infrastructure (2026-07-19)

**Pre-deploy gate:** `scripts/pre-deploy.sh` runs deno fmt/lint/test, flutter analyze/test/build,
pgTAP, and migration dry-run. Supports `--deno-only`, `--flutter-only`, `--db-only`.

**Contract tests:** Flutter `test/contract/` (13 snapshot-based), Deno→DB
`_tests/db_contract_test.ts` (live, skipped when Supabase offline).

**Crash reporting:** Sentry on Flutter (`sentry_flutter`, `--dart-define SENTRY_DSN`) and Edge
Functions (`_shared/sentry.ts` wired into coach-chat, meal-analyze). `beforeSend` scrubber redacts
19 sensitive keys. Empty DSN = disabled.

**Backup:** `scripts/backup-db.sh` via session pooler → `.tooling/backups/YYYY-MM-DD/` + SHA-256
manifest.

**Rollback:** `scripts/rollback-function.sh <name>` redeploys prior git version with `--use-api`.

**Auth hardening:** Password min 8 + upper/lower/digit, re-auth for password change, email
confirmations on. Session timeouts deferred (Pro plan).

**Forward-compatible migrations:** Two-step rule — add then deploy then remove. Never single-step
rename/drop/type-change.

**Test counts:** pgTAP 270 assertions, Deno 92, Flutter 85. All pass.
