# Review: Phase 5 v2 Chunk 7 — Recovery honesty (v2) — 2026-08-26

Scope: uncommitted working-tree change on `feature/feature-engine-phase-5-v2` (HEAD `23c0330`).
27 tracked files modified (+890/−498) + new untracked files: migration
`supabase/migrations/20260825120000_recovery_honesty.sql`, pgTAP
`supabase/tests/database/recovery_honesty_test.sql` (33 assertions), contract fixture
`test/contract/fixtures/daily_brief_v1_2.json`, `test/today_sync_test.dart` (10 tests), and the
v1 review doc itself. This is the v2 state: the v1 review
(`docs/reviews/2026-08-26-phase-5-v2-chunk-7-recovery-honesty.md`) covered the pre-visual-pass
state; its 8 findings were fixed in-tree, and the change was then extended with the device-QA
visual pass (32pt headline token, TextButton analytics, `labelCaps`) and the noop rigor fixes
(duration_score = tonight vs baseline, prev_strain spread gate, pgTAP 21→33). Untracked
`session-ses_fcef.md` and `.opencode/skills/ui-ux-pro-max/scripts/__pycache__/` are not part of
the change (see finding 9).

Verdict: **PASS WITH FINDINGS**

Reviewed fully: every file in the diff was read (diff + full files where context mattered); both
replaced functions compared line-by-line against `20260822120000_session_duration_cap.sql` and
`20260726170000_fix_computed_on_the_fly.sql`; baseline/EWMA math re-derived from
`20260724000001`/`20260725000000`; fixture and pgTAP arithmetic recomputed by hand; Flutter gates
re-run during this review (analyze clean, 318/318 tests). Nothing in the diff was skipped.

## v1 findings — resolution status

All 8 v1 findings verified resolved in the current tree:

1. [MAJOR] duration wrong-baseline bug — fixed: dedicated `sleep_baseline_value` select
   (`20260825120000_recovery_honesty.sql:253-255`), pgTAP user-G case (tests 22–24).
2. [MINOR] ALGORITHMS §8 stale — fixed (`docs/ALGORITHMS.md:299,302`: 2.1 / 1.2).
3. [MINOR] UX_FLOWS §12 stale HealthKit bullet — rewritten for inline-evidence + profile-controls.
4. [MINOR] sync chip hit area — padded inside the GestureDetector (`today_hero.dart:240-246`);
   measured ≈48pt tall (capsule ≈28pt + 2×10pt invisible padding) ≥ 44pt.
5. [MINOR] sync message overstates success — `unavailable` counted as failure
   (`today_screen.dart:123-126`), never-connected reports "not connected" (`:154-156`); both
   covered by new tests (`today_sync_test.dart:296-340`).
6. [NIT] fixture-mode doc comment — corrected (`today_hero.dart:42-45`).
7. [NIT] dead `computed_at` declaration — removed; `computed_at` now explicit in the upsert
   (`20260825120000_recovery_honesty.sql:448,455`).
8. [NIT] DESIGN_SYSTEM inventory — No-data driver state and fully-unusable `--` state added
   (`docs/DESIGN_SYSTEM.md:200-202`).

## Findings

1. [MINOR] `lib/shared/widgets/trajectory_trend.dart:503-507` — **one Today caps label missed the
   labelCaps unification, and the new doc sentence overclaims.** `_TrendTag` renders the
   '7-DAY TREND' (`:180`) and 'TREND' (`:601`) tags — rendered on Today via
   `today_screen.dart:352` — still at fontSize 10 with letterSpacing 1.4 (0.14em): exactly the
   sub-11pt wide-tracked pattern this visual pass removed everywhere else. It contradicts
   `docs/DESIGN_SYSTEM.md:127-128` ("rendered exclusively through `TracendTheme.labelCaps` so
   caps labels never drift below 11pt or wider than 0.08em tracking") and the handoff claim "all
   Today caps labels unified" (`docs/handoff/frontend.md:540-543`). The same doc sentence also
   overclaims globally: Train/Nutrition caps labels still use 10pt/1.2–1.4 ad-hoc styles
   (`lib/shared/widgets/targets_grid.dart:166-167,228-229,335-336`,
   `lib/shared/widgets/intensity_bar.dart:127-128`). Fix: switch `_TrendTag` to
   `TracendTheme.labelCaps`, and either scope the DESIGN_SYSTEM sentence to Today or track the
   other tabs as a follow-up.

2. [MINOR] `docs/DATA_MODEL.md:599-600` — **version inventory left stale by the same change that
   updated ALGORITHMS §8.** "`daily_computed_metrics.schema_version` = '2.0'" (the function now
   writes '2.1' — `20260825120000_recovery_honesty.sql:455`) and "RPC schema_version: ...
   `get_my_daily_brief` 1.1" (now '1.2' — `:497,:517`). Same class as v1 finding #2, missed in
   DATA_MODEL. (Line 552's column default '2.0' remains accurate — the DDL default is unchanged.)
   Fix: bump both entries.

3. [MINOR] `test/contract/fixtures/daily_computed_metrics.json:5,14,16` — **the fixture this
   change bumped to 2.1 is internally inconsistent with the shipped math** (all pre-existing —
   HEAD is byte-identical apart from `missing_components`/`schema_version` — but the file was
   touched in an arithmetic-honesty chunk, and the v1.2 brief fixture demonstrates the correct
   pattern):
   - `recovery` 72 ≠ 69 derived from its own z-scores under the new no-offset formula:
     composite = (0.55·0.517 + 0.20·0.455 + 0.15·0.798 + 0.05·0.500 − 0.05·0.300)/1.0 = 0.50505
     → round(100/(1+e^{−1.6·0.50505})) = round(69.17) = 69. It matched the old formula neither
     (that gives 76), so it never reflected either implementation.
   - `data_confidence` 'medium' with `missing_components: []` is impossible under the new rule
     (0 missing health components → 'high'; it was impossible under the old rule too).
   - `sleep_quality` 85 ≠ 80 derived from its own sub-scores:
     0.50·86.4 + 0.20·92.8 + 0.20·43.4 + 0.10·95.6 = 80.0.
   Tests only assert shape/range here, so nothing fails; risk is misleading future debugging.
   Fix: recompute the three values (69 / high / 80) or mark the fixture shape-only.

4. [NIT] `lib/features/today/widgets/today_hero.dart:286-289` — `labelCaps` used for non-caps
   text: the confidence pill renders mixed-case strings ('High confidence', 'Medium confidence',
   'Low confidence', 'Building baseline') through a helper documented as "the single style for
   uppercase section tags and card identifiers" (`tracend_theme.dart:17-20`, DESIGN_SYSTEM §3.2).
   Visually harmless; either accept it as the general small-label style (and re-doc/rename) or
   keep it caps-only. All 10 other labelCaps call sites on Today carry genuinely uppercase text.

5. [NIT] `lib/features/today/daily_brief_repository.dart:14,23,84` — `DailyBrief.decision` is now
   parsed but never consumed: this change removed the last reader (the hero `_syncLabel`
   previously used `decision['created_at']`; it now correctly uses `health['last_synced_at']`,
   `today_hero.dart:141-151`). AGENTS.md bans dead code in completed work. Fix: drop the field
   and its parsing, or keep it deliberately for contract-shape completeness and say so in a
   comment.

6. [NIT] `supabase/migrations/20260825120000_recovery_honesty.sql:253-264` — cold-start edge for
   the new duration formula: with < 3 sleep observations `compute_user_baselines` stores the
   first observation as the baseline (`20260725000000:155-172`), so on the very first logged
   night duration_score = tonight/tonight·100 = 100 regardless of duration (a 4-hour first night
   scores 100). ALGORITHMS §3 says the 480-min fallback applies "when no usable baseline exists"
   — a single-observation baseline is arguably not usable. Adjacent to, but distinct from, the
   deferred noop follow-ups already in `docs/handoff/backend.md`. Fix: add to that follow-up list
   (e.g. treat n_obs < 3 sleep baseline as the 480 fallback for duration).

7. [NIT] `supabase/tests/database/recovery_honesty_test.sql:110-111` — comment arithmetic is off:
   "(~525 -> ~91)" but the actual sleep EWMA for user G ≈ 517.8 → duration_score ≈ 96.6
   (500/517.8·100). The assertion (`< 100`) is correct and robust; comment-only inaccuracy.
   (User K's "(~57)" comment at `:241` is accurate: 300/522.4 ≈ 57.4.)

8. [NIT] `docs/adr/0010-deterministic-feature-engine.md:46` — still presents the +0.2 offset
   rationale ("anchor population mean z=0 to ~58%") with no supersession note. ADRs are
   historical records and ALGORITHMS.md carries the dated removal, so this is optional: a
   one-line "superseded 2026-08-25 by recovery-honesty (ALGORITHMS §1)" note would prevent
   confusion.

9. [NIT] Untracked cruft `session-ses_fcef.md` and
   `.opencode/skills/ui-ux-pro-max/scripts/__pycache__/` remain in the working tree, untracked
   and not gitignored (carry-forward, first noted in the Chunk 4 review). Keep them out of the
   commit or add ignore rules.

## Focus-item verification

1. **Migration is truly additive and deploy-safe — confirmed.**
   - Pure `create or replace` of two functions; no table/column/constraint/grant changes.
     Signatures unchanged: `compute_daily_metrics(uuid, date, text) → jsonb` and
     `get_my_daily_brief(date) → jsonb` (both `security definer set search_path = ''`, brief
     stays VOLATILE), so the replace cannot fail on signature mismatch and grants persist.
   - Timestamp `20260825120000` unique (nearest neighbours `20260825000000`, `20260822120000`).
   - `daily_computed_metrics.schema_version` has no CHECK constraint (default-only,
     `20260725000000:55`), so '2.1' inserts cleanly; `recovery_score` column is nullable
     (`:39`), so the new NULL recovery persists.
   - Client shape safety: all five z-keys initialized 0 (`:98`) and emitted via `round(…,3)` —
     non-null guarantee holds; `recovery` NULL is a value change only; `missing_components` is
     the sole additive key; all nine brief top-level fields preserved; unauthenticated branch
     bumped too (`:497`). Shipped HEAD client parses `recovery as int?` and tolerates absent
     `missing_components` (→ `[]`, contract-tested at
     `test/contract/daily_brief_contract_test.dart:148-155`); new client tolerates v1.1 servers.
     Safe in both deploy directions.
   - Behavior deltas vs `20260822120000` all match documented intent: per-component gate on
     value-today AND spread > 0 (`:100-163`); prev_strain gate on 7-day avg > 0 AND 28-day
     `stddev_samp > 0` (`:196-223`); recovery NULL iff `weight_total = 0` (`:225-231`); +0.2
     offset removed (`:228`); confidence counts the four HealthKit components (`:396-408`);
     dedicated sleep-baseline select + tonight-based duration (`:250-264`). Sleep
     efficiency/restorative/consistency, ACWR, weight trend, macro adherence, eligibility, and
     the upsert are otherwise line-identical to the prior version. Downstream NULL-safety was
     verified in the v1 review against unchanged consumers (`prepare_daily_coaching`,
     `prepare_coach_chat_v6`, `evaluate_change_eligibility`, `get_my_training_hub`).

2. **Strain-only arithmetic — verified against the SQL.** Fixture strains: 6 recent days at
   5.0·1200/600 = 10; older days 8.0·1800/600 = 24 (−10d) and 8.0·600/600 = 8 (−12d).
   prev7 = avg{10×6} = 10 ✓. 28-day window = {10,10,10,10,10,10,24,8}: mean = 92/8 = 11.5 ✓;
   Σ(x−μ)² = 6·2.25 + 156.25 + 12.25 = 182; sample variance = 182/7 = 26; stddev = √26 ≈ 5.099 ✓.
   strain_z = (10−11.5)/√26 = −1.5/√26 ≈ −0.29417 ✓. composite = −0.05·strain_z = +0.014709,
   weight_total = 0.05, normalized composite = +0.29417 ✓.
   recovery = round(100/(1+exp(−1.6·0.29417))) = round(100/(1+exp(−0.47068))) = round(61.55) =
   **62** ✓ (test 26). Old formula: round(100/(1+exp(−1.6·0.49417))) = round(68.80) = **69** ✓.
   missing = exactly the four health components (tests 27–28), confidence 'low' (test 29),
   prev_strain_z < 0 (test 30). Single-strain-day user J: prev7 = 10 > 0 but 28-day stddev NULL
   → `NULL > 0` is not true → prev_strain missing, weight_total = 0 → recovery NULL ✓ (tests
   31–32). plan(33) matches the 33 emitted assertions ✓.

3. **duration_score change — no client breakage.** Only consumer of
   `sleep_breakdown.duration_score` is `SleepBreakdown.durationScore`
   (`lib/features/today/computed_metrics.dart:77`, parsed as `num`), rendered by
   `_SleepSubScores` in `sleep_architecture_card.dart:127` as a neutral 'Duration' row with the
   value clamped to 0..100 for the bar — the server already clips (`:261`), so the semantic
   change (tonight's sleep vs personal baseline instead of time-invariant 480/baseline) cannot
   break parsing or layout. Fixture checks: user K's 300-min night — 300 is below hard_lower
   ≈ 445.9 (median 520, MAD 10, spread 14.826), so it is outlier-rejected from the EWMA
   (`compute_winsorized_ewma:41`), baseline ≈ 522.4, duration ≈ 57.4 < 70 ✓ (test 33); user G:
   baseline ≈ 517.8 → 96.6 < 100 ✓ (test 23). Cold-start edge noted as finding 6.

4. **labelCaps consistency — one miss (finding 1), one style note (finding 4).** All labelCaps
   call sites verified: sleep_architecture_card (SLEEP ARCHITECTURE, HRV BASELINE/RESTING HR),
   check_in_prompt_bar (CHECK-IN/EDIT), precision_divider (PRECISION READOUTS),
   recovery_readout_card (RECOVERY), metabolic_target_card (METABOLIC TARGET, LOG),
   session_plan_card (SESSION PLAN, LOAD), coach_perspective_card (T-COACH/N-COACH),
   today_hero pill. No remaining sub-11pt or >0.08em-tracked caps labels on Today except
   `_TrendTag` (finding 1). Driver-row labels (`recovery_readout_card.dart:256-261`) are 11pt
   with 0.6pt tracking (0.055em) — inside the documented bounds and mixed-case ('Sleep',
   'Resp', 'Strain'), so not a caps-label violation. `fonts_test.dart:38-57` locks the spec
   (11pt, 0.9 = 0.0818em ≈ 0.08em, w500, 16/11 height).

5. **Dynamic Type safety of hero action stacking — confirmed.** Threshold
   `MediaQuery.textScalerOf(context).scale(15) > 17` (`today_hero.dart:58`) = stack above ~1.13×
   scale, the same idiom as `tracend_scaffold.dart:287`; conservative direction (stacks before
   overflow is possible: below threshold the TextButton is intrinsically sized and only the
   FilledButton is `Expanded`; above it the `Column` is `crossAxisAlignment.stretch`).
   `dynamic_type_test.dart` passes at 320pt × 1.3 and × 2.0 (both exercise the stacked branch),
   re-run green in this review.

6. **Glass budget / 44pt targets — confirmed.** Exactly two `TracendGlass` sites
   (`app_shell.dart:181` tab capsule, `today_hero.dart:265` confidence pill); the sync chip is a
   plain `DecoratedBox` capsule (`today_hero.dart:186-193`) with an ≈48pt hit area (finding-free
   vs DESIGN_SYSTEM §3.3's 44×44 minimum); TextButton `minimumSize: Size(44, 44)`
   (`today_hero.dart:121`); FilledButton themed 44×52 (`tracend_theme.dart:129`). The glass
   budget test in `app_shell_test.dart` passes.

7. **Sync honesty pipeline — confirmed.** `HealthRepository.sync()` returns non-throwing
   `unavailable` when HealthKit can't be read (`health_repository.dart:159-167`);
   `_syncEverything` counts it as an 'Apple Health' failure (`today_screen.dart:123-126`),
   reports never-connected health as "not connected — set it up in your profile" (`:154-156`),
   and never reports "up to date" in either case. Auto-sync on open is prompt-free by
   construction (requires prior successful sync, 30-minute throttle, Supabase-configured only,
   silent catch — `:95-107`). Coach stage reuses the existing controlled coach-decide pipeline
   (`coach_repository.dart:323-348`), generating at most once per day. Decision age label
   ('today' vs 'from D Mon', `coach_perspective_card.dart:101-127`) prevents stale decisions
   masquerading as today's coaching; the 'from 23 Aug' test fixture (`today_widgets_test.dart:326`)
   is a fixed past date compared with year included, so it is not date-flaky. 10 sync tests +
   headline/TextButton/age-label tests all pass.

8. **AGENTS.md rules — clean apart from findings 1/2/3/5.** Forward-only/additive ✓ (item 1);
   schema_version add-never-remove ✓; no TODO/FIXME/dead code in new Dart/SQL (grep clean)
   except finding 5; no secrets (test URLs inert); wrapper discipline kept in all touched docs;
   MVP boundaries respected (Supabase-native only, no new infra); RLS untouched (no new tables;
   `daily_computed_metrics` keeps forced RLS + owner-read from `20260725000000:63-71`);
   deterministic-code-not-model preserved (recovery computed entirely in SQL; sync's
   `coach.generate()` reuses the controlled decision pipeline). Docs amended where behavior
   changed: ALGORITHMS §1/§3/§8, DESIGN_SYSTEM §3.2 + inventory, UX_FLOWS §1/§5/§12, both
   handoffs (incl. the deferred noop follow-ups), PROGRESS_CONTEXT, plan tracker — with the
   DATA_MODEL exception (finding 2) and the DESIGN_SYSTEM overclaim (finding 1).

## Checklist results

- Migrations (forward-only, additive): ok — create-or-replace only, unique timestamp, no
  schema/column/constraint changes, explicit `computed_at` in upsert.
- RPCs consumed by Flutter / schema_version: ok — brief 1.1→1.2 purely additive, all fields
  preserved, both branches bumped, z-keys stay non-null; persisted metrics 2.0→2.1.
- Contract fixtures: finding #3 — v1.2 brief fixture added and arithmetically consistent
  (composite 0.4747 → 68 ✓, 2 missing → medium ✓), v1.1 backward-compat asserted; the touched
  `daily_computed_metrics.json` carries pre-existing internal inconsistencies. Shape change
  (additive `missing_components`, nullable `recovery`) flagged for mandatory manual review —
  this review.
- RLS on new user-owned tables: n/a — no new tables; existing forced RLS untouched.
- Secrets: ok — none introduced; no `RETENTION_WORKER_SECRET` movement; test URLs inert.
- Wrappers: ok — docs/handoff reference only `./scripts/*.sh`; this review used wrappers.
- MVP boundaries: ok — no excluded features/infra.
- No placeholders/dead code: finding #5 (parsed-but-unused `DailyBrief.decision`); otherwise ok.
- Docs amended with behavior change: findings #1, #2, #8; otherwise accurate and consistent.
- Tests proportional to new logic: ok — 33-assertion pgTAP (incl. the exact production-day
  reproduction), 10 sync-pipeline tests, No-data readout tests, headline/TextButton/labelCaps
  spec tests, contract v1.2 group; finding #7 is a comment-only nit.

## Gate results

Run during this review (wrappers):
- `./scripts/flutter.sh analyze` — pass, 0 issues.
- `./scripts/flutter.sh test` — pass, **318/318** (matches the tracker claim).
- pgTAP: not run here (requires local Supabase/Colima). Implementer-reported:
  `recovery_honesty_test.sql` 33/33 and `feature_engine_phase_2_test.sql` 72/72 with the
  migration applied locally. Compatibility spot-checked by reading the phase-2 suite's recovery
  assertions (non-null + 0..100 range + z-key presence on a full-data user — all still hold
  under the new formula). The 4 pre-existing unrelated pgTAP drift failures
  (coach_context_v5, healthkit_auto_complete_workout, healthkit_completion_candidate,
  workout_persistence_reconciliation) accepted per instructions; none call the changed functions.
- Deno fmt/lint: not re-run — no `supabase/functions` files touched by this diff (grep confirms
  no Edge Function references `get_my_daily_brief`/`compute_daily_metrics`/`duration_score`).
- iOS release build not re-run (no platform-channel/native changes; recommend the standard
  pre-merge `build ios --release --no-codesign`).

## Findings — resolution (same-session, pre-commit)

1. [MINOR] `_TrendTag` ad-hoc caps — fixed: now `TracendTheme.labelCaps`
   (`lib/shared/widgets/trajectory_trend.dart`); DESIGN_SYSTEM wording rescoped to "every
   caps label on Today" with a Train/Nutrition adopt-when-touched note.
2. [MINOR] DATA_MODEL version inventory — fixed: `daily_computed_metrics` 2.1,
   `get_my_daily_brief` 1.2 (`docs/DATA_MODEL.md:599-600`).
3. [MINOR] `daily_computed_metrics.json` internal arithmetic — fixed: recovery 72→69
   (round(100/(1+exp(−1.6×0.50505))) from its own z-scores), sleep_quality 85→80
   (0.5×86.4+0.2×92.8+0.2×43.4+0.1×95.6), data_confidence medium→high (empty
   missing_components). Contract group asserts shape/ranges only — no test changes needed.
4. [NIT] labelCaps on non-caps pill text — fixed: confidence-pill labels uppercased
   (HIGH/MEDIUM/LOW CONFIDENCE, BUILDING BASELINE); tests updated.
5. [NIT] `DailyBrief.decision` allegedly unused — verified NOT dead: consumed by the
   `nextAction`/`reason` fallback getters (`daily_brief_repository.dart:31,46`). No change.
6. [NIT] cold-start first-night duration 100 — added to the deferred follow-up list in
   `docs/handoff/backend.md`.
7. [NIT] user-G comment arithmetic — corrected to ≈518 → ≈97.
8. [NIT] ADR 0010 offset rationale — supersession note added.
9. [NIT] `__pycache__/` — added to `.gitignore`; `session-ses_fcef.md` deletion still
   awaits explicit owner approval (carry-forward).
