# Tracend Testing Strategy

**Status:** Authoritative MVP quality strategy\
**Scope:** Flutter iOS app, Supabase Auth/PostgreSQL/Storage/Edge Functions/Queues/Cron, HealthKit,
and controlled AI

This strategy verifies [PRD.md](./PRD.md), [ARCHITECTURE.md](./ARCHITECTURE.md),
[AI_SAFETY_SPEC.md](./AI_SAFETY_SPEC.md), [SECURITY_PRIVACY.md](./SECURITY_PRIVACY.md), and
[UX_FLOWS.md](./UX_FLOWS.md).

## Personal Coaching Evaluation Set

Fixtures cover server-session resume, unknown versus skipped logging, HealthKit duration conflicts,
illness, alternative exercises, incomplete evidence, plateau analysis, and unsupported evidence IDs.
Safety and durable-change fixtures require a 100% pass rate. Evidence UI tests cover 320–430pt
phones, light/dark mode, 200% text, reduced motion, compact layouts, plain Health status,
date-aware chart semantics, same-day measurement amendment, and reconciliation candidate ranking.

## 1. Quality Gates

A change is complete only when:

- deterministic logic has proportional unit tests;
- external and persistence boundaries have integration tests;
- affected journeys have widget, Data API/RPC/Edge Function, or end-to-end coverage;
- AI schema, policy, grounding, and safety fixtures pass;
- privacy and user-isolation checks pass for sensitive flows;
- UI passes accessibility, theme, state, and reduced-motion review; and
- lint, static analysis, migration checks, and supported builds succeed.

Safety-critical fixtures and cross-user isolation require a 100% pass rate. A flaky test is not
accepted as a permanent retry.

## 2. Test Layers

### Unit

- trends, adherence, baselines, workload, nutrition totals, freshness, and confidence;
- policy eligibility and persistent-change thresholds;
- canonical units and timezone conversion;
- schema and semantic validation;
- state reducers, formatters, and token mapping; and
- redaction and retention-date logic.

### Feature Engine

- **pgTAP (22 tests):** EWMA computation with normal and outlier data, cold-start NULL return,
  recovery score at known inputs, ACWR ratio, change eligibility gate outcomes, cross-user RLS on
  `user_baselines` and `metric_baseline_history`. File: `feature_engine_baseline_test.sql`.
- **Reference parity (2026-09-08, Pass 5; hardened 2026-09-09):** the independent Dart reference
  (`test/reference/recovery_reference.dart`, written from ALGORITHMS.md, not from SQL) and the
  shared oracle fixtures (`test/reference/fixtures/*.json`, 15 on 2026-10-15). Two assertion layers: (1) every
  fixture carries an embedded `expected` oracle block (regenerate with
  `dart run tool/generate_expected.dart test/reference/fixtures --write --force` after changing
  fixture inputs) — the Dart self-tests compare every scored output (recovery, five z-scores,
  sleep quality, the four sub-scores, breakdown-missing, debt, strain, ACWR, monotony,
  confidence, missing components) against it (one oracle test per fixture plus anchor tests), and
  `reference_parity_test.sql` runs the SAME fixtures through the production SQL asserting the
  same block field-by-field — so a sign flip or weight typo in EITHER implementation breaks a
  test; (2) independent hand-computed anchors (62, −0.294, 1.95, 2.27, 85.6, the x3
  ln-invariance twin) so the oracle blocks can never go quietly circular.
  `scripts/test-db.sh` ships the fixtures into the pgTAP container.
- **Contract fixture:** `training_hub_v1_4.json` validates Flutter can parse enriched RPC shape with
  baselines, scores, and eligibility fields.
- **Flutter unit tests (3):** healthSyncStart backfill window (9-date initial, 8-date subsequent),
  deriveHealthConnectionState bands, canonical normalization preservation.

### Integration

- PostgreSQL constraints, RLS policies, grants, transactions, idempotency, and version activation;
- Supabase Auth native Sign in with Apple using fixtures and nonce/error cases, once it is built.
  It is the planned external-beta route (ADR 0002) and is not implemented yet; owner development
  uses email/password;
- HealthKit normalization for authorized, partial, stale, duplicate, unavailable, and empty
  responses;
- sleep aggregation: the daily total and per-stage columns are the union of
  asleep-category intervals, covering mixed-category nights (staged + unspecified
  chunks), overlapping duplicate sources, and awake-only nights (0, not NULL);
- initial 9-date HealthKit backfill followed by 8-date overlap sync;
- upload authorization, purpose binding, signed-read expiry, and deletion;
- provider adapters using sanitized contracts, never production health data;
- provider selection defaults to mock, the live-provider kill switch and paid- data gate fail
  closed, API keys stay out of URLs/logs, and failures expose only sanitized codes;
- controlled-coaching request/response validation, deterministic policy, provider failure,
  idempotency, rate limit, evidence grounding, and escalation;
- live Coach chat never converts an unconfigured, provider-failed, or schema-invalid response into a
  successful deterministic fallback; a bounded schema-repair retry either returns validated model
  output or a sanitized failed run. For request schema 1.1 the failed run is followed by the
  labeled data summary: tests prove it copies every number verbatim from context, invents nothing
  when data is missing, drops scores when scoring failed, cites only permitted evidence, passes the
  answer contract, and is returned as response 1.2 with `answer_source: "data_summary"` and only
  finite diagnostics. Messages that may concern a health risk (the six safety prompts plus typo,
  slang and Hinglish variants) get the numberless safety referral, while ordinary training and food
  questions (sore legs, "chest day", "broke my PR", "starving") keep the summary. A retried request
  replays its stored answer as `message`, its failure code, or 409 while still running;
- Coach chat v8 tests prove every question kind renders the same full athlete file, both real
  FLUTTER-8 prompts keep training, weight and nutrition data, the conversation precedes the question
  and the question comes last, long coach messages keep their ending, dropped sections are named,
  formatting slightly over the preferred length is accepted while accuracy rules still fail
  closed, and the prompt allows labeled estimates and one clarifying question;
- Coach chat v8 pgTAP (`coach_chat_v8_test.sql`, 45 assertions) proves identical sections for every
  kind, training totals and volume from completed sets only, amended weights replaced, the audit
  snapshot storing the delivered context, the question stored once before the model runs,
  DeepSeek failures recorded with finite rule names, and the labeled summary stored once. It also
  proves a data summary never enters v8's conversation memory (v10 keeps it, marked:
  `coach_chat_summary_in_thread_test.sql`, 11 assertions), and that a long pre-v8 thread keeps its
  newest ten messages (capped, question first) instead of failing with `chat context too large`,
  on v8 and on the v7 rollback path. A retried request reports its turn as answered (data summary
  or model answer), failed with its code, or in progress, and each watch average carries the days
  its metric was measured;
- `daily_coaching_scoring_guard_test.sql` (7 assertions) proves the day's first chat, a later chat,
  and coach-decide's `prepare_daily_coaching` survive a scoring-engine failure with no snapshot yet,
  storing the snapshot with `scores_unavailable` and permitting only non-score evidence;
- the Coach eval bank (`supabase/functions/_evals/coach_bank/`) gates every Coach change: about 100
  synthetic athletes (the owner's long cut, a stale goal detail, an outlier reading, partial
  logging, no target at a healthy weight, red flags and their harmless look-alikes, screening
  caps, calorie floor and loss ceiling, claimed actions, contradicted facts, no plan, Hinglish
  phrasing, data lookups, and 37 investigate-first cases), each graded by code. Its deterministic half runs in the Deno job of
  every pull request with no key (the red-flag cases run through the real path with a fetch that
  fails on any request, and every grader is tested on hand-written good and bad replies, including
  two replies that failed in production). Its live half runs each case that reaches a model 3
  times: safety categories (red flags, screening, floors and actions) allow zero failures, every
  other category reports its pass rate against 0.8, with at least 97% model answers and no dead
  ends. The investigate-first cases (`cases_investigation.ts`, category `investigation`, ids `inv-`)
  name the kinds of record each question turns on (the Coverage Brief's kinds); the `domain_coverage`
  grader passes a run when each kind was in the athlete file for the period or was looked up, and the
  gate is 90% of such runs. `over_fetch` bounds the lookups of a greeting, thanks, a general-knowledge
  or app question (none) and of a narrow question (a few). Run only those against a live model with
  `EVAL_CASES=inv- ./scripts/deno.sh run --allow-env --allow-net --allow-read --allow-write
  supabase/functions/_evals/coach_bank/run.ts` (the model comes from `AI_COACH_CHAT_*`; the bank
  serves no rows for these cases, so it measures what Coach asks for, not what it says). The
  over-caution rate and the optional tone judge (a different model, binary rubric,
  ungated until checked against about 30 human labels) are reported. Every Coach pull request must
  pass the bank before the lead hands it over: add the `coach-eval` label (the `Coach Eval`
  workflow) or run `coach_bank/run.ts` locally, and say in the pull request which model ran;
- the operations evaluation (`coach_chat_eval.ts`, same workflow) runs about 54 varied prompts × 3
  synthetic athletes for the model-answer rate (at least 97%), dead ends (none), unpermitted
  evidence (none) and p95 latency (under 25 s), and proves the prompt cache. A run makes 17 calls
  unless `max_calls` / `EVAL_MAX_CALLS` asks for another number; "all" runs everything. The gates
  are meant for full runs. `EVAL_BASE_URL` + `EVAL_API_KEY` send the same synthetic requests
  through an OpenAI-compatible router as a cheap smoke test, which says nothing about production
  latency;
- the library retrieval bank (`library_eval.ts`, job `library-retrieval` of the same workflow)
  scores 274 questions over the 106 sources (single-source, multi-source, follow-ups, colloquial
  phrasing, and 38 outside the library) through the real hybrid search: recall@8 and MRR per search
  mode and kind. 219 are the calibration set (`library_questions.json`), which chooses every
  threshold; 55 are a hold-out set (`library_questions_holdout.json`, `question_set: holdout`),
  run once to confirm the result and never used to tune. It needs the database and the real
  embeddings, so only the question files (both) and the metrics are tested in the Deno job;
- Coach-chat provider tests require `finish_reason=stop`, cover truncation, empty/malformed and
  schema-invalid output, unknown evidence, and overlong reasoning fields; prove exactly one
  non-thinking targeted repair receives only the finite rule/path/limit and allowed codes; and prove
  HTTP, rate-limit, and timeout failures are not retried. The model schema and authoritative
  validator are asserted against the same exported limits. The DeepSeek system prompt must carry
  the full shared coach persona before the output contract. Contract tests pin response schema 1.1
  and safe Flutter error copy while rejecting raw parser/provider details;
- Coach chat A2 is covered at four levels:
  - **Shared fixtures:** request 1.1, response 1.2 (model answer and data summary), and the
    `get_my_coach_threads` 1.0 list. Deno proves the request the app builds parses unchanged and
    the data-summary response matches the app's fixture key for key.
  - **Flutter contract tests:** they parse all three fixtures, and prove that an `answer_source`
    of null is a model answer.
  - **Widget tests:** reopening the last conversation or falling back to the newest; lazy thread
    creation; list refresh after each send; the labeled data summary with its diagnostic; Retry as
    a new turn that keeps a typed draft; the safety note; stored summaries; raw beta errors; and a
    disabled composer while a conversation loads.
  - **Race tests** (each fails on the unguarded screen):
    - a reply that arrives after the user switched conversations;
    - a first send whose conversation the user left while its thread was being created;
    - a new conversation listed as soon as its thread exists;
    - an older list refresh that finishes last;
    - a list requested before a new conversation existed, which must not remove it.
  - **pgTAP:** the thread list returns only active threads with messages, newest first,
    owner-scoped, and callable by authenticated users only;
- Coach context v7 pgTAP covers poor, mid-band, good, and NULL recovery evidence; absent check-ins;
  stale versus same-date health; daily/chat evidence parity through the shared SQL helper; v6
  rollback availability; successful daily-decision persistence on a NULL-recovery day; and a
  simulated scoring-engine failure that must leave chat available with Computed Scores unavailable
  and only non-score evidence codes;
- the versioned `coach_chat_context_v7_0.json` fixture and max-budget tests require Context Date,
  Null Contract, Evidence Contract, and Computed Scores to remain whole, retain exact numeric text,
  close the context delimiter, and include the user question once;
- user-scoped AI usage aggregation, including anonymous and cross-user denial, estimate labeling,
  and exclusion of secrets, prompts, request IDs, and raw errors;
- nutrition forced RLS, private meal Storage policies, manual idempotency, unconfirmed-candidate
  exclusion, transactional confirmation, deterministic totals, sanitized audit events, and
  cross-user denial;
- Supabase Queue/Cron retry, deduplication, cancellation, authorization recheck, and terminal
  failure.
- `healthkit_auto_complete_workout`: test authentication required, cross-user denial, duplicate
  completion idempotency (replayed), missing-HealthKit-data guard, inactive-plan guard, and audit
  event shape.
- Train redesign data (`train_redesign_data_test.sql`): exercise slug on prescribed performances
  and none on substitutions or extras; exercise history keys, completed-only sessions, best-set
  kinds and tie-breaks, input bounds and cross-user denial; hub 1.6 plan dates, muscles,
  provenance and 28-day `daily_load`; `complete_workout` vs `complete_workout_v2` provenance,
  effort validation and replay; `abandon_workout` replay, completed-session rejection, ownership
  and audit; day-level percentile ties, fixed cut-offs, rest and calibrating days, and strain parity
  with `compute_daily_metrics`.
- `get_healthkit_completion_candidate`: test authentication required, cross-user denial, returns
  candidate when HealthKit workout exists for the date and no completed session exists, returns null
  when no HealthKit data, returns null when session already completed for that date and planned
  workout, returns null when no planned workout matches the date's weekday.
- Weekly review tests additionally require opaque minimal payloads, immutable snapshot linkage,
  forced-RLS owner reads, deterministic evidence totals, zero generated proposals, acknowledgement
  ownership, and approved-plan availability while a job is delayed.

### Coaching platform program (Iteration 1)

The program's chunks ([plan](./plans/coaching-platform-2026-10/README.md)) add these suites:

- **AI gateway (A2):** `supabase/functions/_shared/ai/*_test.ts` and `adapters/*_test.ts` run
  offline with a fake fetch. They cover:
  - Claude list prices and cost maths, including cache reads and writes and the Haiku 5.5
    long-prompt rate;
  - route settings per feature: a missing setting or key returns no route, and the key never
    appears on the route;
  - no sampling parameters, tools or forced tool choice sent to a Claude 5 model, and thinking
    mapped per model;
  - refusal, 429 with `retry-after`, 529 and 503, timeout and caller abort, network failure,
    invalid JSON and schema mismatch;
  - a consent for another vendor, or none, sends nothing, and an eval-router route never takes an
    athlete's request;
  - one scrubbed `ai_call` log line per call, without prompt, image, reply or key;
  - rollback parity: DeepSeek, Groq and Gemini requests through the gateway match today's
    providers;
  - notice labels name companies only, never a model (D11).
- **Provider-neutral database (A1):** `provider_neutral_ai_test.sql` (88 assertions) covers the
  provider whitelists, usage events, coaching consent v2, the meal and progress photo notices,
  and budget v2. `_shared/ai_consent_test.ts` and `_shared/ai_budget_test.ts` cover the new
  helpers.
- **Set timing (C1):** `set_timing_test.sql` (63 assertions) covers the new `exercise_sets`
  columns, `sync_workout_draft` validation and missing keys, ownership, and the reads.
  `test/set_timing_test.dart` covers rest maths, set start and end rules, app backgrounding and
  relaunch, and drafts from older builds. `test/rir_picker_test.dart` covers the reps-left picker
  (0 to 5+, 44pt cells, 320pt width at 2× text in light and dark). Contract fixtures
  `workout_session_v1_1.json` and `exercise_history_v1_1.json` pin the reads.
- **Per-set heart rate (C2):** `set_heart_rate_test.sql` (52 assertions) covers the table's RLS and
  grants, `persist_set_heart_rate_v1` (idempotent upsert, 22023 on invalid values and unknown sets,
  ownership, no identity), `get_my_set_heart_rate_v1` keys, and the account-deletion cascade.
  `test/workout_hr/` covers the summary maths (coverage, drops, gaps, no samples, source), the
  recorder listening to `WorkoutEventHub` (waiting list, retries, refusals, restarts), and the
  summary line; `test/contract/set_heart_rate_contract_test.dart` pins both RPC fixtures.
  `privacy-export/index_test.ts` checks the export lists the table.
- **Watch-workout suggestion and load signals (C4):** `watch_workout_load_signals_test.sql` (53
  assertions) covers both RPCs' grants and complete key lists, the three-workout limit, the 28-day
  window, the 12-workout cap, the 50% coverage line, the workouts left out (discarded, open, Apple
  Health, an undone set) and isolation between athletes. `load_signals_test.ts` has a test per rule
  (the 50% of reserve line, the 120 s split, the 30 s rest floor, the tracked-set filter, minimum sets and
  workouts, the 28-day window, no profile, the slower recovery), a grid proving the output has no load,
  repetition or sleeping field and never raises confidence, and the loader failing closed. Each was
  checked by breaking its rule and watching the test fail. `test/workout_hr/watch_workout_prompt_test.dart`
  covers the rule, the contract fixture `watch_workout_status_v1_0.json`, snooze and mute;
  `test/phase_3_workout_flow_test.dart` covers the card on the workout screen.
  `training_plan_test.ts` covers the two fixed Coach sentences: present with lower confidence on an
  `add_load` or `add_reps` step, absent with confidence none, on a hold or cut, with no target or
  when the loader fails or throws; the target text is identical with and without the signals; no
  digit in either sentence; the largest plan still fits the budget. Each was checked by breaking it.
- **Rest Live Activity (D0):** `test/contract/live_activity_channel_contract_test.dart` plays the
  native side of the `tracend/live_activity` method channel as
  `ios/Runner/Native/WorkoutActivityBridge.swift` implements it, and proves refused, disabled or
  missing native calls are swallowed. `test/live_activity/rest_timer_live_activity_test.dart`
  covers start, adjust, skip, end, leaving the workout, and a rest that ended while the app was
  closed. The Lock Screen and Dynamic Island are checked on the owner's iPhone.
- **Set logging from the Live Activity:** the contract test also pins `showSet`, `hideNumbers` and the
  `next_*` set keys; `test/live_activity/rest_timer_live_activity_test.dart` covers the controller's
  states (set in progress, rest carrying the set it turns into, all sets logged and its two-minute
  end, no card brought back after a dismissal). `test/phase_3_workout_flow_test.dart` runs a whole
  workout from the card (set in progress, Log set, rest, +30s, Skip, next set, next exercise, all
  sets logged), proves Log set writes the same fields as the in-app Done set, double and repeated
  presses, a press for a set already logged in the app, edits and swipes moving the card,
  relaunch (mid-rest, mid-set, rest ended away, every set logged), finish and discard,
  offline logging, and the numbers staying off the card unless chosen.
  `test/live_activity/workout_resume_test.dart` covers `tracend://workout`. `RunnerTests.swift`
  (`WorkoutActivityStateTests`, not run in CI) covers the content state's decoding, phases and
  set keys.
- **Today and Lock Screen widgets (D2):** `test/home_widgets/today_widget_snapshot_test.dart`
  builds the snapshot from briefs (planned, under way, finished, rest day, no targets, unscored,
  hidden and chosen Lock Screen numbers, the stale limit, no free text);
  `today_widget_publisher_test.dart` covers the default-off choice, the choice kept per athlete,
  what is rewritten and when (unchanged within five minutes is skipped), turning numbers on and off,
  and the clear on leaving; `today_offline_check_in_test.dart` proves a check-in queued offline
  marks the widgets done though the brief reload fails; `test/account_session_test.dart` proves
  sign-out, a refused session and account deletion forget the Lock Screen choice;
  `home_widgets_flow_test.dart` proves Today feeds the publisher, a tapped widget opens Train, the
  shell clears the snapshot when it goes, and the Account row. The shape is pinned by
  `test/contract/fixtures/today_widget_snapshot_v1.json`, compared with the app's output in
  `test/contract/today_widget_snapshot_contract_test.dart` (which also plays the
  `tracend/home_widgets` channel) and decoded by `TodayWidgetSnapshotTests` in
  `ios/RunnerTests/RunnerTests.swift` (staleness by age and by day, the stale moment itself counted
  as stale, schema refusal, links). The
  Xcode tests are not run in CI; the widgets themselves are checked on the owner's iPhone.
- **Research library (E1, E3):** `research_library_test.sql` covers pgvector, forced RLS with no
  API access, the indexes, `search_library_v2` grants (v2 stays for the deployed build), hybrid ranking by reciprocal rank fusion
  (k = 50), the ORed full-text terms, filters, the athlete's regions (`IN` sources reach only Indian
  accounts), the three-per-source cap, `match_count` limits, the exact contract keys, and a rule
  that no `public` or `private` function takes an argument whose type lives in a schema
  `supabase db dump` excludes. In Deno: `query_test.ts` (follow-up rewrite), `retrieval_test.ts`
  (the contributor, the shown ids, timeouts), the gateway, contract and reply-guard tests for
  library citations, and the retrieval gate `library_eval.ts` (recall in the top 8 of at least 0.8,
  multi-source recall 0.7, MRR 0.5 and no-answer precision 0.7, all after the relevance floor, the
  word-search fallback's own gates (recall 0.55, no-answer precision 0.7), plus regional isolation and the floor's calibration sweep) in `coach-eval.yml`, which needs the
  database and the embedding model and runs by itself on every pull request that changes the
  library (not a required check). `library_search_v3_test.sql` (E3.1) covers v3's grants and keys,
  cosine distances, the embedding-model filter, text ranks, the content digest and its triggers, the
  library version, retiring a source and `coach_messages.library_version`;
  `library_content_test.ts` checks that a source removed from `index.ts` is retired by a migration;
  `embed_service_test.ts` covers the worker-secret cache and the Sentry gate.

### Supabase boundaries

For each exposed table, Storage policy, RPC, and Edge Function, test anonymous access, same-user
access, cross-user access, validation, canonical units, idempotency where relevant, expected audit
event, and safe errors. Test Flutter with a publishable key; secret/service-role tests run only in
trusted server fixtures.

### Flutter widget and flow

- onboarding autosave and both branches;
- Account profile, connection, AI service, usage, export, deletion, and sign-out states;
- Today states, recovery readout, and 7-day trend semantics;
- offline workout logging and synchronization;
- meal candidate editing and confirmation;
- previous-day nutrition retrieval so confirmed meals remain visible after a coaching-day boundary;
- proposal approval/rejection;
- HealthKit permission/status variants;
- Today HealthKit readback, real-value trend rendering, and explicit missing- category copy without
  inferring permission denial;
- training surfaces must not render fixture performance charts in hosted mode;
- progress-photo capture guidance and private access;
- progress measurement ranges, deterministic deltas, empty/trend states, cross-user denial, separate
  photo consent, and private progress-bucket policies;
- consent-gated photo-set creation, upload-before-registration, path/type/size/ checksum validation,
  short-lived reads, idempotent deletion, and partial capture recovery; and
- export/deletion and recent-authentication gates.
- production Today brief, complete weekly Train selection, prescription detail, Coach
  thread/composer/evidence behavior, next-meal schedule states, theme persistence, and Progress
  period/evidence gates;
- Train HealthKit auto-complete: prompt card appears when candidate data present, absent when null,
  "Yes, mark complete" triggers completion and reloads hub, prompt persists when tapping a past
  weekday with HealthKit data, candidate clears after auto-completion;
- Train completion state: weekday strip shows green checkmark dot for completed days, gray dot for
  planned but uncompleted days, workout hero displays "Completed" pill and "View workout" (outlined)
  button when day is completed, "Approved plan" pill and "Start workout" (filled) button when not;
- Coach context coverage distinguishes recent available HealthKit data from a genuinely absent
  source and labels evidence/data gaps separately from model follow-up suggestions;
- 320, 375, 390, and 430pt widths, landscape, text scales 1.0/1.3/2.0, light/dark, Reduce Motion,
  keyboard dismissal, and bottom-bar clearance.

### End-to-end critical suite

1. Sign in → beginner onboarding → approve initial plan.
2. Check in → receive decision → inspect evidence.
3. Start workout offline → log sets → reconnect → complete.
4. Upload meal → correct candidates → confirm totals.
5. Reject proposal with no plan mutation.
6. Accept proposal and activate exactly one new version.
7. Export and verify user ownership and contents.
8. Delete account and verify propagation across storage layers.

### Contract Tests (Cross-Layer)

Contract tests verify that layers can successfully communicate with each other. Unlike unit tests
(which mock dependencies), these validate real response shapes across boundaries.

| Layer              | Location                                        | What It Tests                                        | Requires                                    |
| ------------------ | ----------------------------------------------- | ---------------------------------------------------- | ------------------------------------------- |
| **Deno → DB**      | `supabase/functions/_tests/db_contract_test.ts` | RPCs return valid shapes the Edge Functions expect   | Local Supabase running (`CONTRACT_URL` set) |
| **Flutter → RPC**  | `test/contract/*_contract_test.dart`            | Flutter can parse real RPC response shapes           | JSON fixtures (no Supabase needed)          |
| **Flutter → Edge** | `test/contract/*_contract_test.dart`            | Flutter can parse real Edge Function response shapes | JSON fixtures                               |

**Fixture-based contract tests** (Flutter → RPC / Flutter → Edge) use versioned JSON snapshots under
`test/contract/fixtures/` that represent the exact shape the server is expected to return. When the
server response shape changes, the fixtures must be updated — and the act of updating them triggers
a manual review. The review must verify:

1. No field removed that deployed Flutter code depends on
2. New fields are additive only (or the old field is preserved until a follow-up migration)
3. `schema_version` is incremented

**Live contract tests** (Deno → DB) connect to local Supabase when `CONTRACT_URL` is set (by
`pre-deploy.sh` when local Supabase is running). These tests call real RPCs and verify the returned
shape matches what Edge Functions expect. When local Supabase is not running, these tests are
gracefully skipped.

**Model-schema guard** (`supabase/functions/_shared/providers/coach_chat_schema_test.ts`, offline).
Builds the Coach answer schema as Claude receives it and fails if it has an optional property or a
union (Claude's grammar compile grows with each and passed the route timeout on every turn on
2026-10-18), if it exceeds its byte budget, or if its bytes differ between athletes, days,
permitted evidence lists or conversations that are or are not remembered.

### Pre-Deploy Gate (CI Equivalent)

Run `./scripts/pre-deploy.sh` before handing a pull request to the owner. Use
`--skip-colima --skip-reset` when the local database is unavailable, and rely on CI pgTAP. It
executes:

1. Colima + Supabase start → db reset (all migrations applied cleanly)
2. pgTAP database tests
3. Deno format + lint + test (including DB contract tests when Supabase is up), then the backup
   storage and restore-privilege script tests
4. Flutter static analysis
5. Flutter unit/widget/contract tests
6. Flutter iOS release build
7. Production migration dry-run

The gate fails on the first error. `.github/workflows/ci.yml` runs the automated version on every
pull request.

Agents never run `supabase db push` or `supabase functions deploy`. Merging to `main` deploys
through `deploy.yml` ([CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md)). A manual CLI deploy happens
only when GitHub Actions is down or the owner explicitly asks, and then only after this gate, a
dry-run and a backup.

### Release Pipeline Checks

- **Migration order:** `scripts/check-migration-order.sh` runs in the Migration Collision Check job
  on every pull request. Every migration the branch adds must be newer than the base branch's
  newest and named `<14-digit version>_<snake_case>.sql`, and no migration already on the base may
  be edited, renamed or deleted. `scripts/test-check-migration-order.sh` tests the script against
  throwaway repositories in a directory with a space in its path.
- **Restore drill privileges:** every deploy restores the production backup into an isolated
  database, and `scripts/restore-privileges.sh` compares function EXECUTE, table, view, sequence
  and schema privileges for `anon` and `authenticated`, and RLS flags, in `public` and `private`,
  with the state the migrations create. Any difference stops the deploy. CI runs
  `scripts/test-restore-privileges.sh` for the parsing, history and report logic.
- **Backup storage:** `scripts/test-store-backup.sh` covers `scripts/store-backup.sh` in CI.
- **App bundle:** CI runs `scripts/verify-app-bundle.sh` on its unsigned iOS build.

## 3. AI Evaluation

Use versioned synthetic or explicitly consented, minimized fixtures. Each includes feature snapshot,
policy result, permitted actions, expected decision class, forbidden behavior, and rubric.

Required groups cover:

- stable plan where maintain is correct;
- true plateau versus inadequate adherence;
- isolated poor session versus repeated regression;
- poor sleep and same-day adjustment;
- pain and red-flag escalation;
- missing, stale, contradictory, and adversarial text;
- mixed meals, hidden ingredients, and uncertain portions;
- inconsistent progress photos and prohibited body-composition certainty;
- prompt injection in notes/imports;
- schema failure, timeout, outage, and fallback; and
- every supported goal and onboarding branch.

Score schema validity, policy compliance, grounding, decision class, hallucination, repeatability,
clarity, meal accuracy, latency, and estimated cost. Model, prompt, schema, retrieval, or
orchestration changes require regression comparison to the baseline.

DeepSeek V4.1 Flash (`COACH_MODEL_PROVIDER=deepseek`) is the current active Coach/chat provider.
Lite models are not production routes. Phase 2 of the coaching platform program moves each AI
feature to the gateway and Anthropic; its evals are part of chunk A7.
Meal evaluation covers mixed dishes, oil/sauces, hidden ingredients, portion uncertainty, prompt
injection, candidate edit rate, latency, and cost. Safety-critical and schema fixtures require 100%;
routing remains disabled when the gate fails.

## 4. Security and Privacy Tests

- Attempt cross-user reads and mutations for every user resource.
- Verify signed URLs are short-lived, purpose-bound, and invalid after deletion.
- Scan logs for tokens, prompts, notes, health values, meal descriptions, photos, and signed URLs.
- Verify Flutter contains no provider-key input, storage, logging, or transport path.
- Verify consent withdrawal stops new provider processing.
- Verify confirmed administrative context import creates new active versions, preserves old
  versions, supersedes known fixtures, writes a sanitized audit event, and remains unavailable to
  mobile/anonymous roles.
- Verify retention jobs delete media and metadata by purpose.
- Verify meal-media retention claims only due, non-exempt objects, finalizes successful Storage
  deletion, and returns failures to a bounded retry state.
- Verify corrected candidates remain excluded before confirmation, confirmation snapshots
  corrections atomically, and meal deletion is owner-scoped, idempotent, audited, and reflected in
  deterministic totals.
- Verify export is complete, user-scoped, machine-readable, and recently authenticated.
- Verify JSON/CSV, units, provenance, timestamps, purpose-organized media, encryption, 60-second
  authorization, three-use limit, seven-day cleanup, retryable Storage deletion, and absence of
  persisted password/key material.
- Verify deletion is idempotent and propagates to Supabase Auth, PostgreSQL, Storage, Queues,
  exports, derived artifacts, and provider-held data where applicable.
- Run hosted destructive deletion only against a synthetic account and verify its minimal completion
  receipt contains no content attributes.
- Verify notifications contain no sensitive lock-screen content.
- Verify notification preference writes reject enabled reminders without iOS authorization, remain
  owner-scoped under forced RLS, and append grant or withdrawal evidence without storing message
  content.
- Verify notification choices survive app termination, missing pending requests are repaired only
  while authorized, and native scheduling errors are surfaced.

## 5. UX and Accessibility

- Test light and dark themes independently.
- Test compact/large iPhones, landscape, safe areas, keyboard, and iPad-compatible width.
- Test largest Dynamic Type, Bold Text, Increase Contrast, Differentiate Without Color, and Reduced
  Motion.
- Verify targets are at least 44×44pt and icon-only actions have labels.
- Verify long and numeric forms provide explicit, tap-outside, and drag keyboard dismissal without
  losing entered values.
- Manually review VoiceOver order, traits, hints, charts, and lens summaries.
- Test loading, slow, success, empty, partial, offline, error, retry, and cancellation.
- Ensure animations are interruptible and cause no layout shifts.

## 6. Performance Baseline

Measure on the oldest supported iPhone:

- tap feedback within 100ms;
- interactive motion targeting 60fps without sustained misses;
- no avoidable main-thread image processing;
- no unbounded history/list rendering;
- Today usable from cached approved state without waiting for AI; and
- media processing never blocking non-media navigation.

Set numeric binary-size, launch, Data API/Edge Function, and AI-latency budgets after the first
measured vertical slice.

## 7. Test Data

- Factories create synthetic user-scoped data with explicit timezone and units.
- Fixtures use stable clocks and deterministic seeds.
- Production photos, prompts, HealthKit exports, tokens, and notes never enter source control.
- Mobile auth regressions cover an expired access token, successful SDK refresh, and a sanitized
  reauthentication message when refresh cannot recover.
- Media fixtures include valid, oversized, corrupt, mismatched, and malicious files.
- Shared fixture IDs are prohibited where they could hide tenancy bugs.

## 8. CI and TestFlight Gates

`.github/workflows/ci.yml` runs eight jobs on every push and pull request to `main` and
`feature/**`:

| Job                                      | What it checks                                                                                             |
| ---------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| `Deno (fmt + lint + test)`               | Edge Function format, lint and tests (offline), plus the backup storage and restore-privilege script tests |
| `Flutter Analyze`                        | Dart formatting and static analysis                                                                        |
| `Flutter Test`                           | Flutter unit, widget and contract tests                                                                    |
| `Flutter iOS Build (macOS)`              | Unsigned iOS release build and app bundle assets                                                           |
| `pgTAP (fresh DB + migrations + parity)` | Every migration on a fresh database, then every `supabase/tests/database/*_test.sql` file                  |
| `Website Build`                          | Every page of `site/` builds                                                                               |
| `Secret Scan (gitleaks)`                 | Every commit in the history                                                                                |
| `Migration Collision Check`              | Duplicate versions, the migration-order check and its tests, release version metadata                      |

Branch protection requires seven of them; `Website Build` is not required. The live AI
evaluations (`coach-eval.yml`, `onboarding-eval.yml`) run on demand or when a pull request gets
their label; they are not required checks, but a Coach pull request is not handed over until the
answer bank has passed.

Before TestFlight expansion:

- full AI/safety evaluation passes;
- critical end-to-end tests pass on the hosted private-beta project using synthetic test accounts,
  or on staging if a separate staging project is later created;
- privacy export/deletion and Free/Pro backup-restore drills pass as applicable;
- manual VoiceOver/device matrix is complete;
- crash, latency, cost, and proposal-rate telemetry is reviewed; and
- known limitations and rollback owner are recorded.

Exact commands live in `CLAUDE.md`, which is canonical for process.

## 9. Operational Safeguards

### 9.1 Database Backup

Every deploy backs up production automatically: `deploy.yml` dumps roles, schema and data, verifies
the checksums, runs the isolated restore drill, and stores an encrypted archive in the private
backups repository before any migration runs ([CI_CD_DEPLOYMENT.md](./CI_CD_DEPLOYMENT.md)).

`scripts/backup-db.sh` is the manual backup for a manual production mutation. It writes to
`.tooling/backups/YYYY-MM-DD/` with a SHA-256 manifest. The default (and `--schema-only`) is a
schema dump through `supabase db dump`; `--data-only` is a data dump through the Supabase session
pooler and needs `PGPASSWORD`.

### 9.2 Edge Function Rollback

`scripts/rollback-function.sh <name>` finds the previous commit that changed the function's
directory, checks that directory out from it, and redeploys with `--use-api`. `--dry-run` and
`--list` change nothing. A rollback is a manual production deploy, so it follows the same rule as
any manual deploy: only when GitHub Actions is down or the owner explicitly asks. The lasting fix
goes through a pull request.

### 9.3 Health Check

`supabase/functions/health-check/` — a no-auth GET endpoint that returns DB connectivity status and
a version string. Used by external monitors; does not expose internal details.

### 9.4 Structured Logging

`supabase/functions/_shared/logger.ts` — JSON-structured logging with correlation ID propagation and
`LOG_LEVEL` env-var control. Wired into `coach-chat`, `meal-analyze`, `onboarding-plan` and
`physique-check`. Sensitive fields (health
values, meal content, photo URLs, prompt text) are excluded by design.

## 10. Crash Reporting (Sentry)

Sentry captures unhandled crashes and explicit error events in both Flutter and Edge Functions. The
DSN is the only identifier reaching the client; the project lives at `sentry.io` under
`purnajear/flutter`.

| Layer          | Mechanism                                                                                          | DSN Source                                          |
| -------------- | -------------------------------------------------------------------------------------------------- | --------------------------------------------------- |
| Flutter        | `sentry_flutter` SDK — `SentryFlutter.init` with `runZonedGuarded` + `FlutterError.onError` bridge | `--dart-define SENTRY_DSN` (empty = disabled)       |
| Edge Functions | `_shared/sentry.ts` — HTTP `fetch` to Sentry store endpoint, fires silently                        | `Deno.env.get("SENTRY_DSN")` (Edge Function secret) |

**beforeSend scrubber** (Flutter): redacts 19 sensitive keys — `weight_kg`, `sleep_minutes`,
`resting_heart_rate_bpm`, `heart_rate`, `step_count`, `blood_pressure`, `meal_content`,
`meal_description`, `food_items`, `ingredients`, `photo_url`, `signed_url`, `image_url`,
`object_key`, `prompt`, `prompt_text`, `question`, `answer_text`, `answer_payload`.

Edge Functions report exceptions through `captureException` in `coach-chat`, `meal-analyze`,
`meal-media-retention`, `onboarding-plan`, `physique-check` and `privacy-delete-account`. Coach
events add `runtime=edge`, provider, model, context kind, sanitized failure code, attempt, finish
reason, and initial/repair validation-rule tags plus a bounded stack string. Successful and failed
requests log one sanitized attempt summary with outcome, finite rule/path, limits/counts, latency,
and completion tokens. Only whitelisted identifiers/dates enter `extra`; the
question, health context, provider response, and HTTP body are excluded. Flutter and Edge remain in
the same Sentry project and are separated by tags. Failures are silent — a Sentry outage never
affects the caller.

## 11. Auth Hardening

Sign-ups are invite-only. Migration `20261009130000_account_boundary.sql` adds a trigger on the
Auth user insert that refuses any email without a row in `private.signup_invites`
(`signup is invite-only`); `account_boundary_test.sql` covers it. Production Auth sign-ups are also
switched off (2026-10-15, per [PROGRESS_CONTEXT.md](./PROGRESS_CONTEXT.md)). Account deletion
removes the account's invite row (`account_deletion_forgets_invite_test.sql`).

Production Supabase Auth settings applied 2026-07-19:

| Setting                               | Value                         |
| ------------------------------------- | ----------------------------- |
| Password minimum length               | 8                             |
| Password character requirements       | lowercase + uppercase + digit |
| Re-authentication for password change | Required                      |
| Email confirmation for new sign-ups   | Required (invited sign-ups only) |
| Session inactivity timeout            | Deferred (Pro plan)           |
| Session timebox                       | Deferred (Pro plan)           |

These do not affect existing sessions. An invited sign-up must meet the password requirements.
