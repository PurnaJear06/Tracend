# Review: Phase 5 v2 Chunk 4 — AI Usage + Shell + Account Precision Pro rebuild — 2026-08-24

Scope: branch `feature/feature-engine-phase-5-v2`, commit `82bf748` ("feat(ui): Phase 5 v2
Chunk 4 — AI Usage + Shell + Account Precision Pro rebuild"; tracker hash commit `8874c25`
verified documentation-only via `git diff 82bf748 HEAD --stat`). 19 files changed,
+1757 / −1038: 7 new widget files under `lib/features/account/widgets/`, account_screen.dart
1075 → 376 lines, shell tab capsule migrated to `TracendGlass`, dead widgets deleted from
`tracend_scaffold.dart`, 11 new tests (6 AI usage + 4 consent + 1 shell glass) plus updated
`account_destinations_test.dart`, plan tracker + PROGRESS_CONTEXT + UX_FLOWS §13 + both
handoffs updated. Reviewed against `.opencode/plans/phase-5-v2-precision-pro.md` §7 + "Chunk 4
decisions", AGENTS.md, DESIGN_SYSTEM.md §3.4, UX_FLOWS.md §13, SECURITY_PRIVACY.md, the merged
RPC definitions (`get_my_ai_usage`, `get_my_ai_budget_state`), and the Chunk 3 review format.

Verdict: PASS WITH FINDINGS

No blocking or major findings. The chunk delivers all seven scope items and honors every owner
decision. Data honesty is solid: the AI Usage screen binds only real merged-RPC fields —
verified field-by-field against the deployed `get_my_ai_usage`
(migration 20260702090000:218-223) and the overriding `get_my_ai_budget_state`
(migration 20260711100000:12-30, $1 warning / $2 hard stop / 10 daily) — with zero hardcoded
threshold copy anywhere in `lib/features/account` (grep confirms only RPC key reads). The old
screen's fabricated artifacts ("Qwen owner test" heading, `$3 warning · $5 hard stop` copy,
`?? 2` / `?? 10` fallback limits, "Lean muscle · Private beta" row detail) are all gone. The
fixture path (no budget fields) degrades to run counts + "Estimates only" without threshold
claims. The consent ledger is genuinely read-only, owner-scoped via the existing forced-RLS
`consent_records_select_own` policy, and matches DATA_MODEL.md's "latest record per user and
type" semantics. Sheets extracted behavior-identical (line-by-line comparison against the
pre-commit file); the coach-threads sheet gained honest loading/error states the old inline
version lacked. Glass budget intact (exactly one `BackdropFilter` implementation site inside
`TracendGlass`, two visible instances app-wide, asserted by test). Gates re-run green in this
review: analyze 0 issues, format clean, 273/273 tests. One MINOR finding (Account row cannot
distinguish usage-RPC failure from loading) and nine NITs, several pre-existing.

## Findings

1. [MINOR] lib/features/account/account_screen.dart:99-112,183 — The Account AI-usage row
   cannot distinguish an RPC failure from an in-flight load: the FutureBuilder only reads
   `snapshot.data`, so when `loadUsage()` throws, `_aiUsageTitle`/`_aiUsageDetail` receive
   null and the row shows "AI usage" / "Checking usage..." indefinitely — it claims to still
   be checking after the check already failed. The detail screen handles the same failure
   properly (ai_usage_screen.dart:58-68, error + working retry), so the user can recover by
   tapping in, but the row copy is dishonest about state. Suggested fix: branch on
   `snapshot.hasError` in the row builder → e.g. title "AI usage unavailable", detail
   "Tap to open and retry".

2. [NIT] lib/features/account/account_screen.dart:99-100 — `future: widget.coach.loadUsage()`
   is created inside `build()`: every rebuild of `AccountScreen` (e.g. the `setState` after
   saving the notification sheet at :313-317, or a theme change) fires a fresh
   `get_my_ai_usage` + `get_my_ai_budget_state` RPC pair and resets the row to
   "Checking usage...". Pre-existing: the pre-chunk screen had the identical pattern, carried
   through the rebuild. Suggested fix: hoist the future into `initState` alongside
   `_notifications` (and optionally refetch when the usage screen pops).

3. [NIT] lib/features/account/widgets/consent_ledger_screen.dart:38-39,47 — The doc comment
   (repeated in the plan tracker note, `.opencode/plans/phase-5-v2-precision-pro.md:94-97`)
   says the loader is "invoked once in `initState`", but `_records` is a `late final` field
   initializer that runs on first access during the first `build()`. Functionally equivalent
   here — the FutureBuilder subscribes in the same frame and the load-failure test passes
   without leaking to the test zone — but the contract wording is inaccurate. Suggested fix:
   say "initialized on first build", or assign eagerly in `initState` to match the comment.

4. [NIT] lib/features/account/widgets/consent_ledger_screen.dart:92-95 — Latest-per-purpose
   selection (`putIfAbsent` over the list) trusts input order; correctness depends entirely
   on the loader's `.order('created_at', ascending: false)` (account_screen.dart:257). A
   future loader that drops the ordering — or two rows sharing a `timestamptz` — would
   silently display stale consent as current. Suggested fix: sort by `createdAt` descending
   inside `_buildLedger` before dedup so the screen enforces its own contract.

5. [NIT] lib/features/account/account_screen.dart:256 ·
   lib/features/account/widgets/consent_ledger_screen.dart:20,28 — `source` is selected and
   parsed into `ConsentRecord` but never rendered in the ledger. It is meaningful consent
   context (`owner_development` vs `ios_app`, migration 20260701090000:34). Suggested fix:
   display it in `_ConsentRow`, or drop it from the select list.

6. [NIT] lib/features/account/widgets/ai_usage_screen.dart:95,97,153 ·
   lib/features/account/account_screen.dart:189,193 — Thresholds and limits render via
   `toStringAsFixed(0)`: today's deployed values ($1 warning / $2 hard stop) display
   correctly, but any fractional future value (e.g. a $1.50 warning threshold) would round
   to "$2". Values are RPC-bound — nothing is hardcoded — this is display formatting only.
   Suggested fix: render with up to 2 decimals (trim trailing zeros) or use a currency
   formatter.

7. [NIT] lib/features/account/widgets/coach_threads_sheet.dart:37-43 — `_delete` has no error
   path: if `deleteThread` throws, the exception is unhandled and the row stays without
   feedback. Identical gap existed in the pre-chunk inline version (not a regression; the
   sheet's `_load` does handle errors). Suggested fix: wrap in try/catch and surface an
   `_error` line consistent with the load path.

8. [NIT] .opencode/plans/phase-5-v2-precision-pro.md:100 · docs/handoff/frontend.md:403 ·
   docs/PROGRESS_CONTEXT.md:24 — Docs record "account_screen.dart 1075 → 379 lines"; the
   committed file is 376 lines (verified by direct read; unchanged since `82bf748`).
   Suggested fix: correct to 376.

9. [NIT] supabase/migrations/20260702090000_phase_5_controlled_coaching.sql:218-223 ·
   supabase/migrations/20260711100000_owner_groq_qwen_test_routing.sql:12-30 — Pre-existing:
   neither `get_my_ai_usage` nor `get_my_ai_budget_state` returns a `schema_version`, while
   AGENTS.md requires one on every RPC consumed by Flutter. Chunk 4 is the first dedicated
   consumer of both shapes and adds no version guard (the merge in
   coach_repository.dart:351-360 would silently absorb field renames). Not introduced by this
   commit (no RPC/migration changes). Suggested fix: additive `schema_version` field in a
   future cleanup migration, per the AGENTS.md two-step rule.

10. [NIT] lib/features/account/widgets/ai_usage_screen.dart:113-117 — In an unconfigured
    (fixture) environment, tapping the "AI service not configured" row opens a detail that
    shows "$0.0000 · estimated this month" and "Estimates only" without repeating the
    not-configured framing. Honest (real fixture zeros, no claim the service is active) and
    asserted by account_destinations_test.dart:35-41, but the row → detail framing is
    discontinuous. Suggested fix: pass a flag or detect the fixture repository and add a
    one-line "AI service not configured" note in the screen header.

## Verification of the requested focus items

1. **AI Usage screen rebuild — CONFIRMED.** Binds only real merged-RPC fields:
   `successful_runs`, `failed_runs`, `estimated_cost_usd` (get_my_ai_usage) and
   `today_requests`, `daily_limit`, `warning_threshold_usd`, `hard_stop_usd`, `warning`,
   `blocked` (get_my_ai_budget_state), merged in coach_repository.dart:351-360 with budget
   state overriding the shared `period`/`estimated_cost_usd` keys (the budget variant is the
   more complete sum — includes `ai_usage_events`). Thresholds/limits render from RPC values
   (ai_usage_screen.dart:94-97,153; account_screen.dart:187-194); grep for
   `\$3|\$5|hard_stop_usd` in `lib/features/account` finds only RPC key reads — no hardcoded
   threshold copy. Cost labeled operational estimate (ai_usage_screen.dart:181-183, "not an
   invoice or a subscription charge"). States: loading spinner (:55-57), honest empty
   ("No AI runs recorded this month." gated on real zeros, :88,168-174), unavailable with
   working retry (:58-68, tested via `_FlakyUsageRepository` with call counting);
   `_refresh` reassigns the future in `setState` (:41-45) and the refresh test counts the
   second fetch. No token counts, no per-feature breakdown rows, no period toggle. Fixture
   path (FixtureCoachRepository.loadUsage returns no budget fields, coach_repository.dart:
   396-401) degrades: no pill, no progress bar, no threshold rows, "Estimates only" service
   row (tested). Sanitization: error state shows generic copy, never raw errors; no keys,
   prompts, provider request IDs, or cross-user totals anywhere in the screen; RPCs are
   owner-scoped (`user_id=auth.uid()`).

2. **Consent ledger — CONFIRMED.** Direct select on `consent_records`
   (account_screen.dart:252-264) following the `_loadProfileGoals` pattern (:213-236), under
   existing forced RLS `consent_records_select_own` (migration 20260701090000:250-251,
   274-275; `user_id = auth.uid()`). All five canonical purposes render with labels matching
   the enum extensions (terms/privacy from 20260701090000:1; progress_photo_storage/
   progress_photo_ai from 20260702170000:1-2; notifications from 20260703090000:1); unknown
   future purposes append via `friendlyEnum` fallback (consent_ledger_screen.dart:96-99).
   Latest-per-purpose via `putIfAbsent` over the descending-ordered rows (:92-95). Read-only:
   no write/update/delete calls in the screen; withdrawal copy points to the owning flow
   (:132-134), matching UX_FLOWS §13:396-399 and SECURITY_PRIVACY.md:21. Missing purposes say
   "No record yet" (tested). Loading/empty/error states honest (error: "Your saved consent
   was not changed", tested).

3. **Account restyle + extraction — CONFIRMED.** account_screen.dart is 376 lines (< 500
   budget; docs say 379 — finding 8). All seven extraction targets exist under
   `lib/features/account/widgets/` and all files are < 500 lines (largest: account_sheets.dart
   306). Line-by-line comparison against `git show 82bf748^:.../account_screen.dart`:
   deletion sheet, export sheet, and notification sheet are logic-identical (same validation,
   error strings, AuthException handling, download-count increment, permission-denied copy);
   profile-goals content rows unchanged (only `TracendCard(raised: true)` →
   `PremiumGradientCard(glow: true)` restyle and helper renames `_friendly`→`friendlyEnum`
   etc., logic identical); `_openCoachThreads` keeps the `is! CoachChatRepository` guard +
   cast pattern (:279-289) and now opens the sheet immediately with honest loading/error
   states inside (improvement over the old load-before-open with no error handling); theme
   selector and sign-out behavior unchanged. `AccountRow` chevron renders only when `onTap`
   is provided (account_widgets.dart:63-70) with `Semantics(button: onTap != null)` (:28-30).
   The fabricated "Lean muscle · Private beta" detail replaced by honest static copy
   (account_screen.dart:76).

4. **Shell tab capsule — CONFIRMED.** Inline `ClipRRect`+`BackdropFilter`+`DecoratedBox`
   replaced by shadow-only `DecoratedBox` wrapping `TracendGlass` (app_shell.dart:170-198).
   5 tabs kept (:132-158); `MediaQuery.disableAnimationsOf` kept (:162) and still drives
   `Duration.zero` motion (:238,251-253). Glass budget: grep finds exactly one live
   `BackdropFilter` site, inside `tracend_glass.dart:46`; exactly two `TracendGlass`
   instances app-wide (app_shell.dart:181 capsule + today_hero.dart:214 confidence pill) —
   both sanctioned chrome sites per DESIGN_SYSTEM.md §3.4:142-147. New test asserts
   `find.byType(TracendGlass)` and `find.byType(BackdropFilter)` each find exactly 2
   (app_shell_test.dart:73-87). No glass on content cards anywhere in the chunk (all Account
   surfaces use `PremiumGradientCard`/`TracendCard`).

5. **Dead widget deletion — CONFIRMED.** `ComingSoonButton`, `MiniTrendChart`,
   `_MiniTrendPainter` removed from tracend_scaffold.dart (diff verified); grep across `lib`
   and `test` finds zero references; component gallery unaffected (gallery tests pass).

6. **Tests — CONFIRMED meaningful.** 11 new tests, all behavior-based and would fail on
   broken code: AI usage renders exact RPC-derived strings (`$1.8400`, `4 of 30`, `$3`/`$5`
   thresholds from the test's own payload — proving binding, not hardcoding), fixture
   degradation asserts absence of every threshold affordance, blocked state counted in both
   pill and Service row, retry/refresh verified via call counters (ai_usage_screen_test.dart:
   106-148); consent ledger asserts latest-per-purpose with an out-of-order input list,
   honest empty, and unchanged-on-failure (consent_ledger_test.dart:36-82). Count
   arithmetic verified: 262 prior + 11 new = 273, matching the re-run gate.

7. **Docs — CONFIRMED** (finding 8 aside). Plan tracker Chunk 4 row + decisions +
   implementation notes accurate (`.opencode/plans/phase-5-v2-precision-pro.md:20,87-110,
   515-529`, incl. the $3/$5 → $1/$2/10-day reconciliation note); PROGRESS_CONTEXT.md
   dashboard + workstream row updated; UX_FLOWS.md §13 amended for RPC-bound thresholds,
   degradation, and the consent ledger (:384-387,396-399) — matches implementation exactly;
   handoff/frontend.md chunk log and handoff/design.md scope/open-items/next-actions updated
   consistently.

8. **Owner decisions — CONFIRMED honored.** Privacy row → read-only ledger (chosen path
   implemented); Account = full restyle (PremiumGradientCard hero, icon-container rows,
   tabular-figure values); `session-ses_fcef.md` remains untracked, not committed, not
   gitignored (`git status --short` shows `?? session-ses_fcef.md`); coach-thread rows
   display-only with trailing delete as the action, documented in the widget doc comment
   (coach_threads_sheet.dart:6-7); budget thresholds bind RPC values with neither $3/$5 nor
   $1/$2 hardcoded.

## Checklist results

- Migrations: n/a (none in diff; commit touches only lib/test/docs/plan)
- RPCs consumed by Flutter (`schema_version`): finding #9 — pre-existing gap on both usage
  RPCs, now first-class consumed by the rebuilt screen; no RPC changed in this commit
- Contract fixtures: ok — no response-shape change; no fixtures exist for these two RPCs in
  `test/contract/fixtures/` (nothing to update)
- RLS: ok — consent ledger reads under existing forced RLS + `consent_records_select_own`
  (migration 20260701090000:250-251,274-275); no new tables
- Secrets: ok — none introduced; screen provably displays no keys, prompts, provider request
  IDs, raw errors, or cross-user totals
- Wrappers: ok — gates run via `./scripts/flutter.sh`; no direct tool invocations added
- MVP boundaries: ok — iOS-only UI work; no excluded features or infra
- No placeholders: ok — no TODO/FIXME/dead code; dead widgets deleted; fabricated copy
  ("Qwen owner test", hardcoded $3/$5) removed
- Docs: ok except finding #8 (379 vs 376 line count in three docs)
- Tests: ok — 273/273 re-run green in this review; safety fixtures untouched; NITs #3/#4
  (contract wording / order-trust) noted

## Gate results

Re-run in this review (repo wrappers):
- `./scripts/flutter.sh analyze` → No issues found (6.6s)
- `./scripts/flutter.sh test` → 273 passed, 0 failed
- `./scripts/flutter.sh format --set-exit-if-changed lib test` → 123 files, 0 changed
- Deno gates: n/a (no supabase/functions changes)
- iOS build: recorded "ios build ✓" in the plan tracker for `82bf748`; not re-run here
