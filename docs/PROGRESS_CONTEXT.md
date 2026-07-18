# Tracend Progress Context

**Active change:** Coach Continuity Memory (ADR-0009) — five-layer structured memory stack
hosted and deployed. Post-deploy fixes:
(1) 20260717110001 fixed v4→v5 infinite recursion;
(2) 20260717110002 expanded schema_version constraint for '4.0';
(3) 20260717110003 replaced unsupported `jsonb_agg(... ORDER BY ...)` on hosted PG with
subquery-based ordering for narrative, preferences, and journal aggregation in v5;
(4) 20260717110004 fixed ambiguous `coaching_date` PL/pgSQL variable vs table column
(table-qualified the references in the journal query).
Prompt restructure (coach-chat v16) separates `system` (rules, schema, evidence) from
`user` (the user's actual message) — previously the user's question was buried inside one
giant user message alongside the JSON context, causing the model to ignore it and emit the
same plan-related answer regardless of what was asked. Is now the primary content of the
user message and the rule "Lead with one clear recommendation" was removed in favour of
"Answer the user's specific message first."
`coach-chat` v16 is ACTIVE. Owner should test one chat message (especially greetings and
casual questions — these previously returned canned plan advice).

**Purpose:** tiny live dashboard and pointer index, not a history dump.

## Required Agent Flow

1. Read `AGENTS.md`.
2. Read only the authoritative docs relevant to the task.
3. Read this dashboard.
4. Open the scoped handoff file for the active workstream.
5. Inspect actual files before editing.
6. After material work, update the scoped handoff file and this dashboard.

## Context Layers

| Layer     | Path                       | Purpose                 | Read by Default |
| --------- | -------------------------- | ----------------------- | --------------- |
| Rules     | `AGENTS.md`                | Mandatory agent behavior | Yes             |
| Authority | `docs/*.md` specs          | Product/architecture/etc | Relevant only   |
| Dashboard | `docs/PROGRESS_CONTEXT.md` | Current phase, pointers  | Yes             |
| Handoff   | `docs/handoff/*.md`        | Per-workstream state     | Relevant only   |
| Worklog   | `docs/worklog/*.md`        | Detailed history         | When needed     |
| ADR       | `docs/adr/*.md`            | Durable decisions        | When relevant   |

## Current Phase

Phases 1–8 are hosted; Coach Continuity Memory (v6 schema + v16 prompt) is hosted and
live. Local pgTAP suite for the new functions is written but not yet executed locally
(Colima required); hosted migrations through `20260717110004` pass.

## Active Workstreams

| Workstream              | Status                              | Read Next              | Detail History                                |
| ----------------------- | ----------------------------------- | ---------------------- | --------------------------------------------- |
| Backend foundation      | **Complete — verified**             | `docs/handoff/backend.md` | worklogs                                     |
| Frontend/UI             | **Complete — iPhone release build** | `docs/handoff/frontend.md` | worklogs                                    |
| Coach Continuity Memory | **Local — all checks pass**         | `docs/handoff/backend.md` | `docs/worklog/2026-07-17-coach-continuity.md` |
| Stitch/design           | **23 refs imported**                | `docs/handoff/design.md`  | `design/stitch/README.md`                    |

## Global Current State

- Supabase project `qsfzzsjenopqqqhvpyaw` (Singapore); migrations through `20260716130200` matched
  remote.
- Navigation: five tabs — Today · Train · Coach · Nutrition · Progress.
- Groq Qwen `qwen/qwen3.6-27b` is the owner-test Coach/chat provider (ADR 0006).
- Gemini `gemini-3.5-flash` remains disabled pending paid-privacy/evaluation gates.
- Sign in with Apple deferred; owner email/password mode active (ADR 0002).

## Global Open Decisions

- Apple Developer Program enrollment and TestFlight environment names.
- Licensed food catalog source.
- Owner smoke: rest-day Train, exact Nutrition foods, Today Health evidence refresh.
- pgTAP run + hosted migration deploy for Coach Continuity (20260717XXXXXX series).

## Coach Continuity — What Changed (2026-07-17)

**New tables:** `coach_narrative_entries`, `user_preferences`, `coach_session_summaries`
**New FTS:** tsvector + GIN index on `coach_messages`
**New functions:** `prepare_coach_chat_v5`, `persist_coach_narrative_entry`,
`persist_coach_preference`, `persist_coach_session_summary`, `search_coach_messages`
**Updated contracts:** `CoachChatAnswerV2` with optional `reasoning_chain`
**New Flutter widgets:** `ReasoningChainCard`, `PreferencePromptChip`
**Updated Edge Function:** `coach-chat` v15 with preference detection, FTS retrieval, session summary
**Tests:** pgTAP 36 assertions (file only — not yet run); Deno 56/56; Flutter 68/68
**Docs:** `docs/adr/0009-coach-continuity-memory.md`, `docs/proposals/coach-continuity.md`

## Global Known Issues

- Do not commit `.codex/config.toml`.
- CoreSimulator not used; physical iPhone for builds.
- Supabase CLI timeout on `db reset` is known, not a schema failure.
- Colima must be running for local pgTAP execution.

## HealthKit Quick-Complete (2026-07-18)

**Bug fix:** TrainScreen hub now reloads after workout completion. Navigation chain
(ActiveWorkoutScreen → WorkoutDetailScreen → TrainScreen) propagates a completion result
via `push<bool>` / `pop(true)`, and `_WorkoutHero.onWorkoutChanged` refreshes the hub.

**New feature:** When Apple Health detects a workout on a day with a scheduled Tracend workout
but no completed session, Train shows a prompt card for the selected weekday (today or any past
day). "Yes, mark complete" calls the new `healthkit_auto_complete_workout` RPC (creates completed
session with duration from `daily_health_summaries`, writes `workout.auto_completed` audit event).
"Log manually" opens the standard execution flow.

**Per-date refactor (v1.2):** The candidate is no longer returned inside `get_my_training_hub`
(which was hardcoded to `current_date`). Instead, a lightweight `get_healthkit_completion_candidate(date)`
RPC is called per selected weekday via a `HealthkitCandidateRepository` interface. The train screen
maintains `_healthkitCandidate` local state and fetches on weekday change.

**Completion state + date threading (v1.3):** Hub adds `completed_day_set` for per-day completion
tracking. Weekday strip shows green checkmark dots for completed days, gray dots for planned-only.
WorkoutHero shows "Completed" pill + "View workout" for completed days. `loadSession`/`start` now
accept optional `localDate` to fix the bug where past days loaded today's session. Date is threaded
from train screen through `WorkoutDetailScreen` → `ActiveWorkoutScreen` → repository.
`ActiveWorkoutScreen` detects auto-completed sessions (no exercise data) and shows plan exercises
read-only with info banner.

**Changed files:** `train_screen.dart`, `workout_detail_screen.dart`, `active_workout_screen.dart`,
`workout_repository.dart`, `test/production_rebuild_flutter_test.dart`.

**Migrations:** `20260718100000_healthkit_auto_complete.sql` (hub + auto-complete RPC),
`20260718110000_healthkit_candidate_per_date.sql` (per-date refactor),
`20260718150000_hub_completed_day_set.sql` (completion tracking v1.3). All deployed to hosted.

**Docs updated:** PRD, UX_FLOWS, ARCHITECTURE, DATA_MODEL, SECURITY_PRIVACY,
AI_SAFETY_SPEC, TESTING_STRATEGY, frontend handoff.

**Tests:** Flutter 72/72 pass.
