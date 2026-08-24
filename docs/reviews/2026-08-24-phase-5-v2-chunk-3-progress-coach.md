# Review: Phase 5 v2 Chunk 3 — Progress + Coach Precision Pro rebuild — 2026-08-24

Scope: branch `feature/feature-engine-phase-5-v2`, commit `672f28f` ("feat(ui): Phase 5 v2
Chunk 3 — Progress + Coach Precision Pro rebuild"; tracker hash commit `a508810` reviewed as
documentation-only). 23 files changed, +2982 / −1016: 3 new/extended shared widgets
(`EvidenceAccordion`, `ExpandableText`, `EvidenceTrendChart` regression overlay), 5 extracted
progress widget files + restyled `WeightTrendIndicator`, 4 extracted coach widget files,
progress_screen.dart 1066 → 466 lines, coach_screen.dart 758 → 462 lines, 4 new test files
(38 tests), plan tracker + PROGRESS_CONTEXT + handoff/frontend + handoff/design updates.
Reviewed against `.opencode/plans/phase-5-v2-precision-pro.md` §6 + "Chunk 3 decisions"
carry-forward notes, AGENTS.md, ALGORITHMS.md §5/§7, DESIGN_SYSTEM.md, UX_FLOWS.md §9/§11,
PRD.md §4.7, and the Chunk 2 review format.

Verdict: PASS WITH FINDINGS

No blocking findings. The chunk delivers everything in plan §6.1/§6.2 with no out-of-scope
additions (no deps, migrations, RPC, or Edge Function changes — verified via commit stat).
Data honesty is solid: the regression overlay derives deterministically from real server
slopes anchored through the measurement centroid, never invents an intercept, never
extrapolates beyond window or chart range, and R2 gating matches ALGORITHMS.md exactly
(28d-only, threshold 0.3, missing R2 = low confidence, 7d never gated). Every tappable thing
acts; the "Tap a history row" copy is now a real affordance. Three MINOR findings: two
documented-but-undisclosed semantic nuances in the overlay anchoring (window end and source
set can differ from the server's OLS window when the latest weigh-in is stale or HealthKit
weight lives only in `daily_health_summaries`), and one authority-doc tension
(DESIGN_SYSTEM.md "smoothing must be optional" vs the always-on labeled overlay, which
PRD.md §4.7 explicitly requests). Gates were recorded green (analyze 0 issues, format clean,
261 tests, unsigned iOS release build); they were not re-run in this read-only review.

## Findings

1. [MINOR] lib/shared/widgets/evidence_trend_chart.dart:62 — `deriveTrendOverlay` anchors the
   7d/28d window to the LAST CHART MEASUREMENT (`windowEnd = orderedValues.last.date`), while
   the server computes each slope over a window ending at the brief's `target_date`
   (ALGORITHMS.md §5: "observations from target_date − 6 through target_date"). When the most
   recent weigh-in predates the brief date (user hasn't weighed in today), the drawn
   "7-day trend" segment covers `[lastWeighIn−6, lastWeighIn]` while the slope value describes
   `[target−6, target]` — the labeled segment is shifted earlier than the window the number
   came from. Nothing is invented or extrapolated (the segment stays inside the chart range
   and passes through real measurements), and the plan's Chunk 3 decisions chose this anchoring
   deliberately to avoid drawing into measurement-free days; but the divergence is not
   disclosed in the widget contract. Suggested fix: document the divergence in the
   `deriveTrendOverlay`/`WeightTrendCard` doc comments ("window ends at the latest confirmed
   weigh-in, which may trail the server's target date"), or accept the brief's local date as
   an optional window end and clip the drawn segment to the last measurement.

2. [MINOR] lib/shared/widgets/evidence_trend_chart.dart:69-76 ·
   lib/features/progress/progress_repository.dart:130-161 — The centroid anchor is computed
   from `body_measurements` rows only (the chart's dots), but the server slope merges
   `body_measurements UNION daily_health_summaries` HealthKit weights for dates without a
   body-measurement row (migration 20260725000000:129-145, per ALGORITHMS.md §5 "Sources
   merged"). On such dates the drawn line keeps the correct slope but is anchored to a
   centroid that excludes observations the server's OLS fit used, so the line is a small
   parallel offset from the true server fit. Still anchored to real confirmed data — never
   fabricated — and the honesty copy ("each dot is an actual confirmed weigh-in") remains
   accurate for the dots. Suggested fix: state this in the `WeightTrendCard` binding-contract
   comment ("overlay anchored to displayed body_measurements centroid; server fit may include
   HealthKit-only summary weights"), or feed the merged weight series to the chart.

3. [MINOR] docs/DESIGN_SYSTEM.md:15-16 · docs/PRD.md:175 — Authority-doc tension surfaced by
   this chunk: the Evidence-visualization preamble says "Weight charts show confirmed raw
   weigh-ins by default; any later smoothing must be **optional** and visually distinct",
   while PRD.md §4.7 requests "smoothed weight and measurement trends". The new regression
   overlay is visually distinct and labeled (legend, dashed low-confidence, separate colors,
   semantics), but it is always shown whenever server slopes exist — no user toggle — and
   DESIGN_SYSTEM.md was not amended to cover it. Plan anti-failure rule 1 / owner ruling 2
   require authority docs to be amended in the same change, never silently overridden; Chunk 0
   amended §3.x/§10 for the new treatments but left this section untouched. Suggested fix:
   amend the Evidence-visualization section to permit labeled, R2-gated regression overlays on
   raw weigh-in charts (documenting the measured-vs-computed legend and low-confidence
   dashing), or add a show/hide toggle for the overlay.

4. [MINOR] lib/shared/widgets/evidence_accordion.dart:100-114 — The header's
   `Semantics(label: widget.title)` plus `ExcludeSemantics` around the whole Row hides the
   subtitle from VoiceOver: the Coach context header announces "Your coaching context,
   button, collapsed" but never the "7 of 8 sources available · 1 needs data" summary, which
   is the card's primary state signal. Label + expanded trait are present (DESIGN_SYSTEM.md §8
   baseline met), but the subtitle is exactly the "hint where useful" case. Suggested fix:
   append the subtitle to the semantics label when provided
   (`label: widget.subtitle == null ? widget.title : '${widget.title}. ${widget.subtitle}'`).

5. [NIT] lib/shared/widgets/expandable_text.dart:35-40 — The overflow-probe `TextPainter` is
   created inside the LayoutBuilder on every layout and never `dispose()`d; its native
   paragraph is only reclaimed by GC. Suggested fix: cache one painter in the State,
   update it via `text=`/`layout()`, and dispose it in `State.dispose()`.

6. [NIT] test/chunk3_progress_test.dart:71-82 — "body measurement, photo, and weekly review
   remain reachable" only scrolls each label into view and asserts it renders; it never taps,
   so it would still pass if the buttons' callbacks were dead. The tap-to-open behavior is
   properly tested for the history row (test 3), so coverage is adequate overall; the name
   just overstates. Suggested fix: rename to "...remain visible", or tap one control
   (e.g. Record measurement → expect the entry sheet).

7. [NIT] test/chunk3_coach_test.dart:137-145 — "loading and error states remain safe"
   exercises only the generate-failure error path; the loading state
   (`CoachDecisionCard` LinearProgressIndicator) is never asserted. Suggested fix: add a
   repository whose `loadLatest()` never completes and assert the progress indicator.

8. [NIT] docs/handoff/design.md:68 — The continuation line of Next-Safe-Actions item 5 is
   indented 4 spaces (one more than its siblings), which strict Markdown renders as a code
   block inside the list item. Suggested fix: align to 3 spaces.

9. [NIT] docs/handoff/frontend.md:150 — The Verification gate table still carries the prior
   chunk's iOS build line ("pass, HealthKit linked, 18.3 MB physical-device app"); this
   chunk's gate produced a 25.2 MB unsigned release build (plan tracker records "ios build
   ✓"). Suggested fix: refresh the build line when the Chunk 3 gate entry is finalized.

10. [NIT] lib/features/coach/widgets/coach_message_bubble.dart:41-46 — Chat-bubble corners use
    hardcoded `Radius.circular(18)` outside the documented shape lock (12/24/28/full,
    DESIGN_SYSTEM.md §3.3). Pre-existing: carried verbatim from the pre-chunk inline bubble;
    §5's `CoachMessage` spec ("restrained familiar bubble shape") never pinned a radius.
    Suggested fix: document the bubble as a shape-lock exception in DESIGN_SYSTEM.md §3.3 or
    map it to a token in a later chunk.

## Verification of the requested focus items

1. **Scope compliance — CONFIRMED.** Everything in §6.1/§6.2 delivered: regression overlay
   with legend + R2 gating + honesty copy (weight_trend_card.dart:70-73 keeps "Each dot is an
   actual confirmed weigh-in"); `WeightTrendIndicator` restyled into `PremiumGradientCard`
   with the `accentAmber` token and R2 stacked below the value (weight_trend_indicator.dart:
   151-158); measurement entry via real `save_body_measurement` RPC; tappable history rows →
   read-only `MeasurementDetailSheet`; progression rows display-only with honest caption
   (training_evidence_widgets.dart:93-96); `MetricSparkline` wired from real weigh-ins
   (progress_screen.dart:137-139, hidden < 2 values per weight_trend_indicator.dart:30-32);
   `EvidenceAccordion` replaces both raw `ExpansionTile` sites in Coach (grep confirms zero
   `ExpansionTile` left in coach/, remaining sites are Today/Health widgets);
   confidence always from `CoachDecision.confidence` (coach_decision_card.dart:132-141,
   tested); `ReasoningChainCard` kept; composer + suggestion pills real. Nothing
   out of scope: commit touches only lib/test/docs/plan — no pubspec, supabase/,
   migrations, RPC, or Edge Function changes.

2. **Data honesty — CONFIRMED** (with findings 1-2 as disclosed nuances). Slopes come only
   from `ComputedMetrics.scores.weightTrend7d/28d` (server `weight_trend_7d/28d_kg_per_day`,
   computed_metrics.dart:190-192); `deriveTrendOverlay` anchors through the window centroid
   (OLS property), clips start to `max(windowStart, chartStart)` and end to the last
   measurement (evidence_trend_chart.dart:81-95), returns null on empty/single-date evidence
   (no line rather than a fake one), and expands the y-range to include overlay endpoints so
   the line never renders outside the plot. R2 gating matches ALGORITHMS.md §5/§7 exactly:
   threshold constant 0.3 (evidence_trend_chart.dart:40), `lowConfidence = trendR2 == null ||
   trendR2! < 0.3` applied to the 28d line only (evidence_trend_chart.dart:135-141), 7d never
   gated (tested), missing R2 = dashed + "low confidence" (tested). Legend distinguishes
   "Measured" dots from computed lines; semantics announce "Dots are measured evidence; lines
   are computed models" (tested). Overlay legend renders only when an overlay exists — no
   orphan "Measured" legend (tested). `WeightTrendIndicator` chip shows R² only on the 28-day
   chip (weight_trend_indicator.dart:91-94). Sparkline values are the real measurement list,
   ascending (progress_repository.dart:159).

3. **Dead affordances — CONFIRMED none introduced.** History rows: `InkWell` + chevron +
   `Semantics(button: true, ...Opens details)` with a real `onOpen` → detail sheet
   (measurement_widgets.dart:104-156; tap tested). Detail sheet is read-only with no
   fake edit action. Progression rows have no tap target and carry the caption "Best confirmed
   values · display-only, no detail destination yet" (training_evidence_widgets.dart:93-96).
   `ExpandableText` renders its control only when `didExceedMaxLines` (both directions
   tested). Accordion header always toggles; content unmount only after collapse completes.
   Weekly-review card: ready→open sheet, pending→real refetch, failed/none→real
   generate request (progress_screen.dart:219-223). Composer disabled states real (sending /
   no chat backend / server `retry_after_seconds` cooldown). Follow-up chips call the real
   `_send` (tested via recorded `sentQuestions`). No `onPressed: () {}` in the diff.
   Pre-existing limitation noted, not numbered: history lists only the 8 most recent rows
   (`take(8)`, progress_screen.dart:158) while the chart may show older dots — the "Tap a
   history row" copy is true for every listed row, but dots older than the 8 listed have no
   row to verify them.

4. **Architecture rules — CONFIRMED.** Deterministic code computes the overlay; model output
   is display-only and never authoritative; confidence strings sourced from `CoachDecision`
   (anti-pattern §10 respected). Private photos remain purpose-bound: `PhotoSetCard` shows
   date/count/status only — no thumbnails anywhere on the overview; viewing requires an
   explicit View tap producing short-lived signed URLs ("links expire after 60 seconds",
   photo_widgets.dart:127). Production composition root verified: shell injects real
   repositories into both screens (app_shell.dart:97, 103-110), so Chunk 2's finding-1 class
   of bug does not recur here. Missing data lowers confidence (dashed line + label) rather
   than being invented. No secrets in the diff.

5. **Design system — CONFIRMED** (findings 3, 10 aside). All colors via `context.tracendColors`
   tokens — zero hardcoded hexes in new files (grep); radii via `TracendRadii` (accordion
   control 12, history-row ink 24); motion via `TracendMotion.standard`/`curve`
   (evidence_accordion.dart:55-60); Reduce Motion via `MediaQuery.disableAnimationsOf` with
   instant jump + immediate unmount (tested). Glass budget intact: grep finds exactly two
   live `BackdropFilter` sites app-wide, both pre-existing (app_shell.dart:174,
   tracend_glass.dart:46); all new surfaces use `PremiumGradientCard` (zero blur). Chunk 0
   carry-forward (assert light-theme `accentAmber` contrast when first wired) is satisfied —
   theme_test.dart:49-52 asserts light `accentAmber`/`accentNow` ≥ 3:1, and the token is now
   wired in `WeightTrendIndicator`.

6. **Code quality — CONFIRMED.** progress_screen.dart 466 lines, coach_screen.dart 462 lines
   (both < 500, verified by direct read). No TODO/FIXME/placeholder/commented-out code in the
   diff (grep clean). Widget extraction is behavior-preserving (side-by-side comparison
   of deleted inline classes vs new files shows identical logic plus token upgrades). State
   handling safe: progress loading/error-with-retry/empty all render (progress_screen.dart:
   87-94, 121-122; `_ErrorCard`); coach loading/empty/error paths tested; `FutureBuilder`
   brief loading renders the chart without overlays then upgrades when data arrives.

7. **Tests — CONFIRMED meaningful** (findings 6-7 as nits). 38 new tests (7 accordion + 17
   overlay + 6 progress + 8 coach; 223 + 38 = 261 matches the recorded gate). They are
   written from code behavior and would fail on broken code: centroid anchoring asserted
   numerically (`closeTo(78.8)`), window clipping by date, R2 gating both directions, 7d
   never gated, collapse-keeps-mounted-until-settle, Reduce Motion single-frame jump,
   semantics expanded-trait transitions, confidence never hardcoded (`find.textContaining(
   'medium')` findsNothing), follow-up chips recorded through the real send path. The
   `SystemChannels.platform` mock in chunk3_coach_test.dart:18-22 is justified: `_send`
   awaits `HapticFeedback.lightImpact()` (coach_screen.dart:202) before mounting the reply,
   and an unmocked platform channel never answers in widget tests — the plan's carry-forward
   note documents exactly this.

8. **Docs — MOSTLY CONFIRMED** (finding 3). Plan tracker updated (Chunk 3 row + hash
   added in `a508810`), "Chunk 3 decisions" notes are accurate and match the code,
   PROGRESS_CONTEXT.md dashboard + handoff/frontend.md chunk log + handoff/design.md scope
   all updated consistently. UX_FLOWS.md not contradicted (detail sheet and display-only
   progression fit §9; weekly review keeps §11's Mark-reviewed flow); nav-doc update deferred
   to Chunk 5 per plan §8.4, consistent with Chunks 1-2 precedent. The one gap: the
   DESIGN_SYSTEM.md Evidence-visualization section was not amended for the always-on overlay
   (finding 3).

## Authority-doc conflicts noticed

- DESIGN_SYSTEM.md:15-16 ("any later smoothing must be optional") vs PRD.md:175 ("smoothed
  weight and measurement trends") vs the implemented always-on labeled overlay — reported as
  finding 3 per the AGENTS.md rule "If authority docs conflict, stop and report the conflict.
  Do not choose silently." The implementation follows the owner-approved master plan (§6.1);
  the docs need reconciling, not the code.
- No other conflicts: ALGORITHMS.md §5/§7 semantics are implemented exactly (finding-free),
  and SECURITY_PRIVACY photo rules are respected.

## Checklist results

- Migrations: n/a (none in diff; plan "DB changes: NONE" verified via commit stat)
- RPCs consumed by Flutter (`schema_version`): n/a (no RPC changes; overlay consumes
  pre-existing `weight_trend_7d/28d_kg_per_day` + `weight_trend_r2_28d` fields, present since
  Phase 2 migrations and already in `ComputedScores`)
- Contract fixtures: ok (no response-shape change; `daily_brief_v1_1.json:113`
  and `daily_computed_metrics.json:37` already document `weight_trend_r2_28d`)
- RLS: n/a (no new tables; measurement detail reads go through the existing RLS-forced
  `body_measurements` select, progress_repository.dart:130-138)
- Secrets: ok (none introduced)
- Wrappers: ok (gates recorded via `./scripts/flutter.sh`; no direct tool invocations added)
- MVP boundaries: ok (iOS-only UI; no excluded features or infra)
- No placeholders: ok (no TODO/dead code/commented-out alternatives)
- Docs: finding #3 (DESIGN_SYSTEM Evidence-visualization not amended for the overlay);
  otherwise ok — plan tracker, PROGRESS_CONTEXT, both handoffs updated;
  UX_FLOWS deferred to Chunk 5 per plan §8.4; NITs #8/#9 (markdown indent, stale
  build-size line)
- Tests: ok — 38 new tests, 261/261 recorded green, safety fixtures untouched; NITs #6/#7
  (test-name/coverage precision)

## Gate results

Not re-run in this read-only review (per review instructions). Recorded in the plan
tracker and handoff for `672f28f`: `./scripts/flutter.sh analyze` → 0 issues ·
`./scripts/flutter.sh format` → clean · `./scripts/flutter.sh test` → 261 passed ·
`./scripts/flutter.sh build ios --release --no-codesign` → pass (25.2 MB, unsigned).
Test-count arithmetic independently verified: 223 prior + 38 new = 261. Deno gates n/a
(no supabase/functions changes).
