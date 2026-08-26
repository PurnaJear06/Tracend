# Review: Phase 5 v2 Chunk 7 — Recovery honesty — 2026-08-26

Scope: uncommitted working-tree change on `feature/feature-engine-phase-5-v2` (HEAD
`23c0330`). 19 tracked files modified (+632/−420) + 4 new untracked files:
`supabase/migrations/20260825120000_recovery_honesty.sql` (create-or-replace of
`compute_daily_metrics` + `get_my_daily_brief` v1.2), pgTAP
`supabase/tests/database/recovery_honesty_test.sql` (21 assertions), contract fixture
`test/contract/fixtures/daily_brief_v1_2.json`, `test/today_sync_test.dart` (8 tests).
Client: `recovery_breakdown.missing_components` parsing, No-data driver rows, honest NULL
recovery empty state, Apple Health section removed from Today (profile-only controls),
hero sync-everything chip. Docs amended same-change: ALGORITHMS §1, UX_FLOWS §5, both
handoffs, PROGRESS_CONTEXT, plan tracker. Untracked `session-ses_fcef.md` and
`.opencode/skills/ui-ux-pro-max/scripts/__pycache__/` ignored per instructions.

Verdict: **PASS WITH FINDINGS**

Reviewed fully: every file in the diff was read (diff + full files where context
mattered), both function bodies compared line-by-line against the previous versions
(`20260822120000_session_duration_cap.sql`, `20260726170000_fix_computed_on_the_fly.sql`,
`20260725000000_feature_engine_phase_2_fixes.sql`), all downstream SQL consumers of
`recovery_score` checked for NULL-safety, and the Flutter gates re-run during this review
(analyze clean, 314/314 tests pass). Nothing in the change was skipped.

## Findings

1. [MAJOR] `supabase/migrations/20260825120000_recovery_honesty.sql:230-235` —
   **`duration_score` uses the wrong baseline on days with respiratory data (pre-existing
   bug carried into the rewrite).** The `baseline` record variable (declared :32) is
   reused by every component block: HRV (:88), RHR (:104), Sleep (:120), then Resp
   (:136). The sleep-quality section (:218) runs afterwards and computes
   `duration_score := clip(480 / baseline.baseline_value * 100)` — but when today's
   `respiratory_rate_bpm` is present, the resp block ran last, so `baseline` holds the
   **resp-rate baseline** (~12–20 bpm → 480/15×100 ≈ 3200 → clipped to 100) or a NULL
   record when no resp baseline row exists (→ `else 100`). Only on days *without*
   respiratory data does it hold the intended sleep baseline. ALGORITHMS.md §3 documents
   the formula as `clip(target_480min / baseline_ewma * 100)` against the sleep EWMA, so
   the code diverges from the authority doc whenever resp data exists; duration carries
   weight 0.50 of `sleep_quality`, which feeds the `SLEEP_QUALITY_GOOD/POOR` coaching
   evidence codes. **Pre-existing:** byte-identical pattern in
   `20260822120000_session_duration_cap.sql:230-235` (resp block :145-154) and present
   since `20260725000000_feature_engine_phase_2_fixes.sql` — not introduced by this
   chunk, but carried undisclosed into a rewrite whose stated purpose is honesty, and not
   covered by the new pgTAP suite (user D has resp data, but both branches clip to 100
   for its ~407-minute sleep baseline, masking the bug). Practical impact is bounded
   (both branches yield 100 unless the sleep baseline exceeds 480 minutes), so this does
   not block the chunk. Suggested fix: a follow-up additive migration that selects the
   sleep baseline into a dedicated variable for `duration_score` (e.g.
   `select baseline_value into v_sleep_baseline from user_baselines where metric_name =
   'sleep_minutes'`), plus a pgTAP case with resp present AND sleep baseline > 480.

2. [MINOR] `docs/ALGORITHMS.md:292,295` — **§8 Versioning table left stale by the same
   change that edited §1.** "Daily scoring JSON `schema_version` 2.0" and "Daily brief
   RPC `schema_version` 1.1", while this change ships `2.1`
   (`20260825120000_recovery_honesty.sql:426`, `daily_computed_metrics.json:63`) and
   `1.2` (`:468,:488`, `daily_brief_v1_2.json:2`). Violates ALGORITHMS §8 rule 5
   ("Version bump in code must match version in constraint"). Fix: bump both table rows
   to 2.1 / 1.2.

3. [MINOR] `docs/UX_FLOWS.md:373-375` — **§12 HealthKit bullet now describes a surface
   this chunk deleted.** "Today reads stored daily summaries back into dated sleep,
   steps, energy, workout, resting-heart-rate, and HRV evidence. Draw a trend only when
   at least two real dated values exist…" described `HealthEvidenceSection` (deleted in
   this chunk; it rendered exactly those dated metrics and ≥2-value trends). After
   Chunk 7, Today's health evidence is the inline recovery drivers + the ≥4-day
   `TrajectoryTrend`, and Apple Health controls/status live in the profile only (as the
   updated §5 now says). Fix: rewrite the §12 bullet to match the new surface split
   (and reconcile the "at least two real dated values" with the ≥4-day trend rule).

4. [MINOR] `lib/features/today/widgets/today_hero.dart:160-164,201-210` — **the new sync
   chip's tap target is below the 44pt minimum.** The capsule is an 11pt label with
   `vertical: TracendSpacing.xxs + 2` padding (≈27pt tall) wrapped in a bare
   `GestureDetector`. DESIGN_SYSTEM.md §3.3 requires "Minimum touch target: 44×44pt" and
   §10 states "all chips use padded tap targets (48pt)"; Chunk 5 padded all five existing
   chips, and the Chunk 1 review flagged a 32pt hero button for the same reason. Fix:
   pad the hit area (e.g. `MaterialTapTargetSize.padded` context, `ConstrainedBox
   (minHeight: 44)`, or vertical hit-area padding around the gesture).

5. [MINOR] `lib/features/today/today_screen.dart:116-148` — **sync result message can
   overstate success**, against the chunk's honesty goal:
   - `HealthRepository.sync()` returns a non-throwing
     `HealthSyncStatus(state: unavailable)` when HealthKit cannot be read
     (`health_repository.dart:159-167` — device locked/HealthKit unavailable/revoked).
     `_syncEverything` discards the returned status, so a failed health read still ends
     with "Everything is up to date."
   - When Apple Health was never connected, the health stage is silently skipped
     (:118-121) and the same "Everything is up to date." is shown.
   Fix: inspect the returned `HealthSyncStatus.state` (count `unavailable` as an
   'Apple Health' failure) and/or report the not-connected case distinctly (e.g.
   "Synced. Apple Health is not connected.").

6. [NIT] `lib/features/today/widgets/today_hero.dart:35-36,132-136` — doc comment claims
   `onSync == null` renders the chip inert "(fixture/manual mode)", but `TodayScreen`
   always passes a non-null `_syncEverything` — including fixture mode
   (`today_screen.dart:220-221`), where a tap reloads fixtures and then reports
   "Everything is up to date." without syncing anything. The null branch is only
   reachable from tests. Fix: correct the comment, or pass `onSync` only when
   `environment.hasSupabaseConfiguration`.

7. [NIT] `supabase/migrations/20260825120000_recovery_honesty.sql:53,414-442` — the
   declared `computed_at timestamptz := now()` variable is never referenced (dead
   declaration carried from the prior version), and `computed_at` is omitted from the
   INSERT column list while the conflict update sets `computed_at = excluded.computed_at`.
   Empirically safe — `excluded` carries the column default, proven by the new pgTAP
   suite's repeated same-day upserts (tests 1–6 and 16–21 each call the function ≥5×
   per user/date against the `not null` column) — but listing `computed_at` explicitly in
   the insert would make the upsert self-evident. Pre-existing pattern; cosmetic.

8. [NIT] `docs/DESIGN_SYSTEM.md:191-199` — the `RecoveryReadoutCard` inventory entry
   lists the cold-start and low-confidence states but not Chunk 7's new per-driver
   "No data" state (implemented at `recovery_readout_card.dart:247-254`, covered by
   UX_FLOWS §5 "missing signals say No data"). Add the state to the component entry for
   completeness.

## Focus-item verification

1. **AGENTS.md rules — clean apart from findings 2/3.**
   - Forward-only/additive: the migration is a pure `create or replace` of two functions;
     no tables, columns, constraints, grants, or ownership change (grants persist across
     replace). Timestamp `20260825120000` is unique (nearest neighbour
     `20260825000000_add_deepseek_to_daily_coaching_rpc_whitelist.sql`).
   - schema_version add-never-remove: `get_my_daily_brief` v1.1→v1.2 body is
     line-identical to `20260726170000` except the two version strings; all nine v1.1
     fields preserved (`schema_version, local_date, today_workout, next_meal, check_in,
     health, nutrition, computed, latest_decision`); the unauthenticated branch is bumped
     too. The only shape change anywhere is additive (`recovery_breakdown
     .missing_components`); `recovery` becoming NULL is a value change, not a removal.
   - No placeholders/TODO/dead code in the new Dart/SQL (grep clean) — except the dead
     `computed_at` declaration (finding 7, pre-existing).
   - RLS intact: no schema changes; `daily_computed_metrics` keeps forced RLS +
     owner-read policy (`20260725000000:63-71`); both replaced functions keep
     `security definer set search_path = ''`.
   - Deterministic-code-not-model: recovery is computed entirely in SQL; the model only
     interprets. The sync chip's `coach.generate()` reuses the existing controlled
     coach-decide pipeline.

2. **Migration correctness — field preservation verified; one carried bug (finding 1).**
   - Return shape `{baselines, scores, data_confidence}` unchanged; every `scores` key
     from the old function present; `recovery_breakdown` gains only `missing_components`.
   - Behavior deltas vs `20260822120000`, all matching the documented intent: per-
     component weight gated on value-today AND `spread > 0` (:87-148); `missing_components`
     now also records sleep/resp/prev_strain gaps the old version never reported;
     `recovery` NULL iff `weight_total = 0` (:205-211); +0.2 offset removed;
     `data_confidence` counts the four HealthKit components with `today_health.id is null
     or ≥3 → low` (:369-379); persisted `schema_version` '2.0'→'2.1' (no CHECK constraint
     on the column — `20260725000000:55` is default-only — so '2.1' inserts cleanly).
     Sleep quality, ACWR, weight trend, macro adherence, eligibility, and the upsert are
     line-identical to the old function. No undocumented behavior change found beyond
     finding 1 (which is unchanged old behavior).
   - **`baseline` reuse in `duration_score`: confirmed bug, pre-existing** — see
     finding 1. The old function (`20260822120000:230-235`) has the identical pattern,
     and the pattern originates in `20260725000000`; the Chunk 7 rewrite preserves it
     byte-for-byte, so this migration introduces no regression there — but it is not the
     intended sleep baseline on resp-present days.
   - Downstream NULL-safety for the new NULL recovery: `prepare_daily_coaching`
     (`20260726000000:76-82`) guards `recovery_score is not null` on both branches
     (NULL → falls to `CHECK_IN_RECOVERY_MIXED`, and `data_confidence` will be 'low' →
     `DATA_CONFIDENCE_LOW`, so the mock provider still routes to GATHER_DATA — safe);
     `prepare_coach_chat_v6` (:188-211) is jsonb-NULL-safe; `evaluate_change_eligibility`
     does not read recovery; `get_my_training_hub` reads only acwr/monotony/strain.
   - Deploy-direction safety: the currently-shipped client (HEAD) already parses
     `recovery` as `int?` (`git show HEAD:lib/features/today/computed_metrics.dart`) and
     Chunk 6's readout already renders the null state, so migrating the server before the
     app is rebuilt is safe; the new client tolerates old servers (`missing_components`
     absent → `[]`, contract-tested).

3. **Contract tests — consistent.** New v1.2 group asserts top-level shape,
   `missing_components` list, model mapping, and all five z-keys staying numeric;
   the v1.1 group is retained plus a new backward-compat test (v1.1 payload without
   `missing_components` parses as none missing). `daily_computed_metrics.json` bumped to
   2.1 with `missing_components: []` and its test updated. Fixture arithmetic matches the
   new formula: composite `(0.55·0.273 + 0.20·1.034 − 0.05·(−0.456))/0.80 ≈ 0.475` →
   `round(100/(1+e^{−1.6·0.475})) = 68` ✓, and 2 missing health components → `medium`
   confidence ✓. No Deno-side assertions reference the brief or `compute_daily_metrics`
   (grep of `supabase/functions` clean), and no pgTAP file asserts schema_version '1.1'
   (`production_rebuild_foundation_test.sql` only checks `next_meal`/`health.local_date`,
   both preserved).

4. **Authority-doc consistency — mostly good; findings 2, 3, 8.** Band cutoffs in
   `recovery_readout_card.dart:109-115` (80/65/50/35) match the new ALGORITHMS §1 table
   exactly (z-equivalents recompute: 0.87→80.1, 0.39→65.1, 0→50); the "never used by any
   code path" claim about the old 3-band table is true (grep: no 34/67 band logic in
   `lib/`; it survives only in the historical backend handoff). Profile-only Health
   controls verified: `HealthStatusCard` remains in `account_screen.dart:87`, and
   `connectAndSync` — the only `requestReadAccess` path — is reachable solely from it.
   Hero sync chip copy matches UX_FLOWS §5 ("syncs Apple Health (when connected), the
   daily brief, and today's coaching decision"; timestamp = last health sync via
   `brief.health['last_synced_at']`, `today_hero.dart:112-121`). ALGORITHMS §1 Data
   Confidence section matches the migration (:369-379). The ALGORITHMS §3 duration
   formula matches intent but not code on resp-present days (finding 1).

5. **Client parsing risk for nullable recovery — none found.** The only consumer of
   `computed.scores.recovery` in `lib/` is `recovery_readout_card.dart:28`, which
   branches on null (`--` + honest copy, semantics "Recovery score unavailable", band
   chip hidden). `ComputedScores.fromJson` parses `recovery as int?`; all five z-keys
   remain required `num` casts, matching the server guarantee that they stay non-null
   (initialized 0 at migration :83, `round(0,3)` emitted). `progress_repository.dart:309`
   reads the unrelated weekly-review `recovery` section. Glass budget holds: exactly two
   `TracendGlass` sites (`app_shell.dart:181`, `today_hero.dart:228`); the sync chip is a
   plain `DecoratedBox`. Deleted `health_evidence_section.dart` has no remaining code
   references, and `phase_4_healthkit_test.dart:209-239` now asserts Today exposes no
   Apple Health controls/evidence. Auto-sync is prompt-free by construction
   (`today_screen.dart:95-107`: requires prior successful sync, 30-minute throttle,
   Supabase-configured only, silent catch; `sync()` itself never requests access).

## Checklist results

- Migrations (forward-only, additive): ok — create-or-replace only, unique timestamp,
  no schema/column/constraint changes; finding #1 is carried behavior, not a migration
  rule violation.
- RPCs consumed by Flutter / schema_version: ok — 1.1→1.2 purely additive, all v1.1
  fields preserved, both branches bumped; finding #2 (ALGORITHMS §8 table stale).
- Contract fixtures: ok — v1.2 fixture + 2.1 computed-metrics fixture added/updated,
  v1.1 backward-compat asserted; shape change is additive and flagged for this review.
- RLS on new user-owned tables: n/a — no new tables; existing forced RLS untouched.
- Secrets: ok — none introduced; no `RETENTION_WORKER_SECRET` movement; test URLs are
  inert placeholders.
- Wrappers (no direct tool invocations): ok — docs/handoff/plan reference only
  `./scripts/*.sh`; this review used wrappers for the gates.
- MVP boundaries: ok — no excluded features/infra; Supabase-native only.
- No placeholders/dead code: finding #7 (dead `computed_at` declaration, pre-existing);
  finding #6 (inaccurate doc comment). Otherwise ok.
- Docs amended with behavior change: findings #2, #3, #8. §1/§5/handoff/dashboard
  updates otherwise accurate and consistent with the code.
- Tests proportional to new logic: ok — 21-assertion pgTAP for the honesty rules,
  8 sync-pipeline widget tests, No-data readout tests, contract v1.2 group; finding #1
  notes the one untested interaction (resp present + sleep baseline > 480).

## Gate results

Run during this review (wrappers):
- `./scripts/flutter.sh analyze` — pass, 0 issues.
- `./scripts/flutter.sh test` — pass, **314/314** (matches the handoff claim).
- Deno gates: not run — no `supabase/functions` files touched by this change.
- pgTAP: not run here (requires local Supabase/Colima). Implementer-reported:
  `recovery_honesty_test.sql` 21/21 and `feature_engine_phase_2_test.sql` pass locally.
  Known pre-existing drift in 4 unrelated pgTAP files (coach_context_v5,
  healthkit_auto_complete_workout, healthkit_completion_candidate,
  workout_persistence_reconciliation) verified as non-blocking: grep confirms none of
  them call `compute_daily_metrics` or `get_my_daily_brief`. Agree with not blocking.
- iOS release build not re-run (compilation gate unchanged by this diff beyond analyzed
  Dart; recommend the standard pre-merge `build ios --release --no-codesign`).

## Follow-ups (2026-08-26, fixed pre-commit)

All eight findings resolved in the working tree before commit:

1. [MAJOR] Fixed in the undeployed migration itself (owner-approved): dedicated
   `sleep_baseline_value` select for `duration_score`, dead `computed_at` declaration
   removed, `computed_at` listed explicitly in the upsert INSERT. Migration re-applied
   locally (schema_migrations entry re-recorded); pgTAP plan 21→24 with the
   resp-present + sleep-baseline > 480 case (user G). recovery_honesty 24/24 +
   feature_engine_phase_2 72/72 pass locally.
2. ALGORITHMS §8 table bumped: daily scoring JSON 2.1, daily brief RPC 1.2.
3. UX_FLOWS §12 HealthKit bullet rewritten for the inline-evidence + profile-controls
   split; "at least two real dated values" reconciled with the ≥4-day trend rule.
4. Sync chip hit area padded to ≥44pt (invisible vertical padding inside the
   GestureDetector; visible capsule unchanged).
5. `_syncEverything` inspects the returned `HealthSyncStatus`: `unavailable` counts
   as an Apple Health failure; never-connected health reports "Apple Health is not
   connected — set it up in your profile." instead of "Everything is up to date."
6. `onSync` doc comment corrected (null branch is test-only; fixture mode taps reload
   fixtures).
7. Resolved with finding 1 (dead declaration removed, insert self-evident).
8. DESIGN_SYSTEM `RecoveryReadoutCard` entry gained the No-data driver state and the
   fully-unusable `--` state.
