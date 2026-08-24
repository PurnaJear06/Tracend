# Frontend Handoff

## Active Personal Coaching Work

Train now has workout-scoped drafts, server resume, RPE/pain/explicit skip, honest unknown logging,
functional detail rows, complete progression lists, audited repair review, and HealthKit
reconciliation cards. Flutter analysis and 67/67 tests pass. The signed hosted 20.1 MB build is
installed and launched on the owner's iPhone 12.

The evidence UI repair replaces Today’s decorative stepper and equal metric grid with a compact
Signal Rail and prioritized Apple Health surface. Progress and steps share a date-aware labeled
chart; recent weight history shows eight days. Flutter analysis and 69/69 tests pass. The signed
hosted 20.1 MB replacement is installed, launched, and passes strict signature verification on the
owner's iPhone 12.

Owner device feedback superseded the Signal Rail. Today now has a generated, optimized
coaching-horizon asset and three tappable readiness factors with plain explanations. Progress
derives headline and raw chart from one ordered effective timeline, clips painting, and reserves
extra bottom-scroll clearance. Profile and goals and AI usage now open real stored-data detail
routes. Flutter analysis is clean, 70/70 tests pass, and the signed hosted 20.7 MB build is
installed/launched with strict signature verification.

**Scope:** Flutter iOS shell, navigation, themes, component gallery, local client boundaries, and
integration with Supabase client contracts.

This file is current-state handoff, not UX authority. UX behavior belongs in `docs/UX_FLOWS.md`;
visual system behavior belongs in `docs/DESIGN_SYSTEM.md`.

## Current State

- Flutter 3.41.7 / Dart 3.11.5 iOS-only app is scaffolded at repository root.
- The native target is iPhone-only. It uses programmatic `UIScene` setup, storyboard-free
  `UILaunchScreen`, and bundled iPhone icon PNGs so physical device compilation does not require
  CoreSimulator.
- The generic Flutter launcher icon was replaced on 2026-07-11 with the Tracend trajectory mark
  across the iPhone asset catalog. A signed hosted build passed strict verification, installed, and
  launched on the owner iPhone.
- Nutrition meal analysis now offers both **Analyze meal photo** (camera) and **Choose from Photo
  Library**. Both normalize to the existing JPEG upload, privacy/consent, candidate-edit, and
  confirmation path.
- Nutrition now opens Today but can move backward and forward through persisted daily logs (never
  beyond Today), making confirmed photo/manual meals visible after midnight instead of appearing
  reset.
- Coach now surfaces a collapsible `ReasoningChainCard` below assistant replies showing
  train-of-thought steps with evidence IDs. Preference statements are detected and prompt a
  `PreferencePromptChip` with save/dismiss actions, persisting via `persist_coach_preference` RPC.
  Flutter 68/68 tests pass.
- Live Coach replies now visibly identify **Qwen AI response**. A malformed or unavailable provider
  response is a retryable error, never generic fallback prose shown as a successful Coach answer.
  The signed hosted build with this behavior is installed and launched on the owner iPhone.
- Coach now exposes deterministic source coverage and separates model evidence, actual data gaps,
  and suggested next actions. This prevents generated bullets from appearing to be evidence and
  makes missing workout execution explicit.
- The context-coverage replacement signed build is installed and launched on the owner iPhone;
  Flutter analysis and 66/66 tests pass.
- `supabase_flutter` 2.15.0 is pinned. `AppEnvironment` accepts only `SUPABASE_URL` and
  `SUPABASE_PUBLISHABLE_KEY`; the shell runs unconfigured and contains no secret/service-role or
  AI-provider key path.
- TrainScreen hub now refreshes after workout completion via navigation result propagation
  (ActiveWorkoutScreen → WorkoutDetailScreen → TrainScreen). Adherence count updates without manual
  reload.
- HealthKit quick-complete: when Apple Health detects a workout on a day with a scheduled workout
  but no completed session, Train shows a prompt card for the selected weekday (today or any past
  day). "Yes, mark complete" creates an audited completed session with HealthKit-backed duration.
  "Log manually" opens the standard execution flow.
- Training hub `get_my_training_hub` version 1.2 no longer returns a hub-level candidate. A separate
  lightweight RPC `get_healthkit_completion_candidate(date)` is called per selected weekday.
  `healthkit_auto_complete_workout` creates audited auto-completed sessions. Migrations:
  `20260718100000_healthkit_auto_complete.sql` (original auto-complete),
  `20260718110000_healthkit_candidate_per_date.sql` (per-date refactor),
  `20260718150000_hub_completed_day_set.sql` (completion tracking + visual indicators).
- Hub v1.3 adds `completed_day_set` field (array of distinct dates with completed sessions). The
  weekday strip now shows green checkmark dots for completed days and gray dots for planned-only.
  WorkoutHero displays "Completed" pill + "View workout" (outlined) for completed days vs "Start
  workout" (filled) for uncompleted.
- `loadSession` and `start` repository methods now accept optional `{DateTime? localDate}`
  parameter. TrainScreen threads `_dateForWeekday(_weekday)` through `WorkoutDetailScreen` →
  `ActiveWorkoutScreen` → repository calls. This fixes the bug where past days always loaded today's
  session.
- `ActiveWorkoutScreen` detects auto-completed sessions (no exercise data) and shows planned
  exercises read-only with an info banner: "Auto-completed from Apple Health — no individual sets
  logged."
- Phase 4 pins `health` 13.3.1 behind `HealthDataSource`. The iOS target has HealthKit purpose
  strings and entitlement configuration for read-only steps, active energy, sleep, workouts, weight,
  resting heart rate, and HRV SDNN.
- ADR 0002 authorizes a real Supabase email/password mode for owner-only Phase 2 development.
  Credentials must never be compiled into or committed with the app. Sign in with Apple remains
  deferred until external beta distribution.
- Light/dark semantic themes, the Trajectory Lens, reusable surfaces, and the five-tab
  `IndexedStack` shell are implemented under `lib/`.
- A development-only component gallery is available through `lib/component_gallery.dart`; it does
  not add a production route.
- `Phase2Gate` restores Supabase sessions, routes unauthenticated users to the owner email/password
  form, routes incomplete users into onboarding, and exposes the five-tab shell only after
  transactional approval.
- Both beginner and experienced paths implement eligibility/consent, goal, schedule, equipment,
  nutrition/constraint context, autosave, review, mock proposal generation, and
  approve/reject/revision states. HealthKit is not requested in Phase 2.
- Account sign out uses Supabase Auth and returns to the auth gate.
- Phase 3 reads an approved planned workout under RLS and provides one-handed load, repetition, and
  set-completion controls. In-progress sets autosave to a user-scoped local draft, expose
  synced/pending state, restore after interruption, and use monotonic client revisions.
- Today includes the bounded daily check-in sheet. A failed request retains a local pending envelope
  instead of discarding the entry.
- Today and Account expose connected, partial, stale, unavailable, and manual-only HealthKit states.
  Permission is requested only after the user taps Connect Apple Health. Empty reads remain unknown
  rather than denied.
- On-device normalization removes duplicate sample identifiers, aggregates canonical daily values
  and supported sleep stages, records HRV as SDNN in milliseconds, hashes source/sample references,
  and sends summaries through authenticated `health-sync`; raw HealthKit samples are not uploaded.
- Today no longer presents fixture sleep, recovery, or readiness claims as observed evidence. Until
  real inputs exist it shows an explicit empty trend state while check-in, workout, and manual-only
  use remain available.
- A UI fidelity pass now upgrades built surfaces only: Today, Train, Workout Detail, Active Workout,
  Coach, Nutrition, and Progress use raised decision surfaces, semantic pills, metric strips,
  accessible chart shells, clearer progress indicators, and disabled planned-state controls instead
  of inert buttons. No new backend feature, HealthKit flow, live AI flow, or route was added.
- Owner physical-iPhone QA has started against the hosted build: email/password login works despite
  a stale localhost email-link redirect, onboarding reaches Section 1, check-in save works, and app
  close/reopen restores in-progress state.
- Widget/unit coverage verifies auth field validation, beginner approval, experienced draft
  restoration, public configuration gating, exactly five tabs, tab switching, Account as a detail
  route, component semantics, contrast, 375pt/390pt light and dark layouts, 2× accessibility text
  scaling, and Reduced Motion.
- All six canonical Stitch screen references are ready in `design/stitch/screens/` (Today, Train,
  Workout Detail, Coach, Nutrition, Progress) — see `docs/handoff/design.md`.
- The Progress export is a visual reference, not complete feature coverage: its Body Measurements
  and privacy-safe Progress Photos entry must follow `PRD.md` and `UX_FLOWS.md` even if the Stitch
  HTML remains unchanged.
- Sixteen authentication/onboarding references are indexed by
  `design/stitch/onboarding/screens.json`; Account/Profile is indexed by
  `design/stitch/account/screens.json`.
- Account may show sanitized user-scoped AI usage but must contain no provider API-key entry,
  storage, reveal, or transport path. Provider credentials stay in Supabase secrets.
- Backend contracts are complete and verified: Supabase CLI, migrations, RLS, Edge Function
  `CoachModelProvider` interface, and mock provider are all in place under `supabase/`.
- ADR `docs/adr/0001-phase-1-foundation.md` records pinned versions:
  - Flutter 3.41.7 / Dart 3.11.5
  - iOS minimum deployment target: **iOS 17.0**
  - Bundle identifier: `com.tracend.app` (pending brand/name clearance)
  - Pub cache: `$PWD/.tooling/pub-cache`
- `scripts/bootstrap-flutter.sh` installs the pinned SDK into `.tooling/flutter-sdk`.
  `scripts/flutter.sh` refuses to use another SDK and redirects Flutter/Dart home, pub, CocoaPods,
  ephemeral iOS, and build state into `.tooling/`.

## Verification

- `./scripts/flutter.sh format --set-exit-if-changed lib test` — pass
- `./scripts/flutter.sh analyze` — pass, no issues
- `./scripts/flutter.sh test` — pass, 262 tests (Phase 5 v2 Chunk 3 + review follow-ups)
- `./scripts/flutter.sh build ios --release --no-codesign` — pass, HealthKit linked, 25.2 MB
  unsigned physical-device app (Phase 5 v2 Chunk 3)
- `./scripts/flutter.sh build ios --config-only --no-codesign` — pass
- UI fidelity pass verification on 2026-07-01: format, analyze, tests, iOS config-only device build,
  signed hosted release build, and iPhone install all pass; no simulator was used.
- Hosted-config signed arm64 release build — pass; `Runner.app` produced under `build/ios/iphoneos/`
  (18.2 MB) and installed on the owner's iPhone 12.
- Phase 4 hosted-config signed arm64 release build — pass; the 19.1 MB app and embedded provisioning
  profile both contain the HealthKit entitlement, and the app is installed and trusted on the
  owner's iPhone 12.
- Owner enabled all requested Apple Health read types. Authenticated refresh completed as a valid
  partial sync: seven daily summaries accepted, zero rejected. Profile and Today intentionally show
  the same shared refresh state.
- Phase 5 adds real latest-decision reads to Today and a working Coach flow for generate/refresh,
  Head Coach decision, Training/Nutrition perspectives, evidence, confidence, missing data, and safe
  provider failure. Account shows sanitized owner-only monthly run/cost estimates. Flutter analysis
  and 35/35 tests pass; unsigned iOS release build passes at 18.3 MB.
- Phase 5 hosted-config signed release build passes at 19.1 MB and is installed on the owner's
  iPhone 12. After developer-profile trust, launch, Coach generation, Today decision state, and
  normal app behavior passed owner QA. Account service rows remain status/planned controls rather
  than detail routes.
- First launch and one-time iOS Developer App trust action are complete on the owner's iPhone 12. No
  simulator was used.
- Owner device smoke: login, onboarding entry, check-in save, and app close/reopen restore — pass.
- Phase 6 initial local slice replaces fixture nutrition totals with confirmed-only values, manual
  entry, sample candidate selection/confirmation, explicit uncertainty, safe failure, and a real
  timeline. Flutter tests pass 38/38; analysis and the unsigned 18.5 MB iOS device build pass.
- The signed hosted-config Phase 6 build passes at 19.2 MB and is installed on the owner's
  iPhone 12. Manual entry, sample selection/confirmation, totals, and close/reopen restoration
  passed owner-device QA.
- The local corrections/deletion slice adds editable candidate name, serving, calories and macros
  with inline validation and atomic confirmation. Timeline meals expose a labeled delete action with
  destructive confirmation; totals refresh after deletion. Flutter passes 40/40, analysis is clean,
  and the unsigned iOS device build passes at 18.5 MB. The backend is hosted and a signed
  hosted-config 19.2 MB build is installed and launched on the owner's iPhone; device QA for these
  two actions remains pending.
- Owner QA exposed that an existing draft timeline card could not reopen its candidate editor. Draft
  cards now show a full-width **Review & edit draft** action and restore their candidates; Flutter
  passes 41/41 and analysis is clean. The replacement signed 19.2 MB build is installed and
  launched; owner verification is pending.
- Candidate and manual forms now expose **Hide keyboard** while editing and support tap-outside plus
  drag dismissal after owner QA found no iOS numeric keyboard dismissal route. Flutter passes 42/42;
  the replacement signed 19.2 MB build is installed and launched. Owner verification passed
  candidate editing, dismissal, confirmation, deletion, totals, and restoration.
- Phase 7 local foundation replaces fixture Progress claims with honest empty, baseline, and
  deterministic trend states. It adds canonical manual entry, recent records, an accessible line
  summary, standardized private-photo guidance, and an editorial weekly-review preview.
- Phase 7 Flutter verification passes 47/47, analysis is clean, and the unsigned 18.6 MB iOS device
  build passes.
- The Phase 7 hosted-config signed build passes at 19.3 MB and is installed on the owner's
  iPhone 12. CLI launch succeeded after unlock; measurement persistence, baseline, weekly-review
  preview, and photo-guide QA passed.
- Private progress media now uses pinned `image_picker` 1.2.3, explicit storage consent, ordered
  front/side/back capture, partial-set recovery, 60-second private viewing, and deletion. The signed
  hosted build passes at 19.7 MB and is installed/launched on the owner's iPhone. Owner QA passed
  capture, persistence, viewing, and deletion. A follow-up fixes the discovered missing pose
  context: Tracend now names Front/Side/Back, shows 1/2/3 of 3, and gives framing guidance before
  every native camera launch. The replacement signed 19 MB build is installed and launched; prompt
  QA passed.
- The local weekly-review slice replaces the editorial fixture with real owner-scoped
  queued/ready/failed states and a seven-part deterministic review showing execution, recovery,
  confirmed nutrition, measurements, missing evidence, unchanged plan/targets, next focus, and
  acknowledgement. Flutter passes 49/49, analysis is clean, and the unsigned 18.9 MB iOS build
  passes. The backend migration is hosted and a signed 19 MB build is installed on the owner's
  iPhone. CLI launch remains pending only because the device was locked.
- The first device request showed the generic queue error and created no job. A sanitized hosted
  diagnostic confirmed the active completed owner is eligible; the same authenticated request then
  queued and completed normally with zero worker failures. The ready review now needs device open
  and acknowledgement QA.
- Direct inspection confirmed the persisted device access token had expired while its refresh token
  was valid. Account restoration and weekly-review generation now refresh an expired session;
  unrecoverable refresh shows a sanitized sign-in instruction. Flutter passes 50/50, analysis is
  clean, and the replacement signed 19 MB build is installed/launched. A read-only device check
  confirmed the refreshed session was persisted.
- Phase 7 ready-review opening and acknowledgement now pass on the owner device.
- Phase 8 notification controls use native iOS scheduling without another SDK: daily check-in and
  weekly-review toggles, permission-on-save, real status, denial guidance, and explicitly generic
  lock-screen copy. Flutter passes 51/51 and analysis. The backend is now hosted and the signed 19
  MB build is installed/launched on the owner's iPhone; permission/toggle persistence QA exposed a
  reopen reset. Account now reconciles the durable owner preference row back into authorized iOS
  pending requests on load, while denied or offline states remain safe. Flutter passes 53/53,
  analysis is clean, and the unsigned 19 MB device build passes. The hosted-config replacement
  passed strict signing with the active Gmail development identity/team, installed, and launched on
  the owner's iPhone. Reopen QA still reset, proving pending requests were not a reliable preference
  source. The native layer now stores only the two requested booleans in `UserDefaults`, repairs
  authorized pending requests from them, and surfaces scheduling errors. Flutter remains 53/53;
  analysis and the physical-device build pass. The hosted-config replacement passed strict signing,
  installed, and launched on the owner's iPhone.
- Owner QA confirms notification choices survive force-close/reopen.
- Phase 8 Account implements recent-authenticated encrypted export with a separate export password,
  ready/download state, expiry disclosure, and a 60-second secure download handoff. It also
  implements irreversible deletion, exact `DELETE` confirmation, server completion, and signed-out
  transition. Hosted synthetic export/decrypt/delete QA passes; destructive owner-account QA is
  prohibited. Flutter passes 55/55, analysis and iPhone-only build pass. The hosted-config app
  passed strict signing and installed on the connected iPhone; CLI launch was blocked only because
  the device was locked.
- Owner export download succeeded and server state recorded 1/3, but iOS returned a false URL-launch
  result after opening Safari. The client now uses external-browser mode and treats exception-free
  handoff as success so the sheet updates without a false error. The signed hosted replacement
  passed strict verification and installed; CLI launch was blocked only by device lock.
- `git diff --check` — pass

## Constraints

- Frontend must remain iPhone-first. No iPad, Android, or web target.
- Only the Supabase publishable key and project URL may appear in the app. No secret/service-role
  key, no AI provider key.
- Package caches, build outputs, and generated artifacts must stay under `$PWD/.tooling/` on the
  external SSD.
- Routes must match `docs/UX_FLOWS.md` exactly (5-tab shell).
- Visual tokens and components must derive from `docs/DESIGN_SYSTEM.md` and the Stitch screen
  references in `design/stitch/screens/`.

## Next Safe Actions

1. **Merge `feature/feature-engine-phase-5` → `feature/feature-engine`.** CI/CD (deploy.yml) triggers on merge:
   backup → dry-run → migrate (1 pending migration: `20260822120000_session_duration_cap.sql`) → deploy 9 Edge Functions → smoke test → tag.
2. Prepare and download one owner export, then decrypt it on the external SSD using
   `docs/BETA_OPERATIONS.md`.
3. Do not device-test deletion with the owner account; hosted synthetic QA is the destructive gate.
4. ~~Known issue — July 22 strain 403~~ **Fixed** (2026-08-22): client clamp + server clamp +
   metrics exclusion. See "Session Duration Cap" section below.

## Phase 4 — Computed Metrics UI + Backend Pipeline (2026-07-26)

**Complete.** 6 widgets (RecoveryRing, SleepArchitectureCard, ReadinessStrip redesign,
TrainingLoadGauge, WeightTrendIndicator, MetricSparkline) integrated into Today/Train/Progress.
2 backend migrations deployed: session_effort backfill + recompute (v1), compute-on-the-fly
architecture fix (v2 — Noop pattern). `get_my_daily_brief` now always calls `compute_daily_metrics`
fresh; `get_my_training_hub` reads from `daily_computed_metrics`. Train screen reloads brief per
selected weekday so strain shows per-day. 155 Flutter tests pass, 0 analysis issues. iOS release
build (25.4MB) installed on Purna's iPhone 12 with live Supabase backend. Full details in
`docs/PROGRESS_CONTEXT.md`.

## Phase 5 — Design System Alignment (2026-08-22) — REVERTED

The uncommitted Phase 5 "Liquid Glass" UI work was **reverted in full** after an independent
audit (`docs/reviews/2026-08-18-qwen3-8-max-phase-5-ui-audit.md`) found it unsalvageable:
fabricated metrics displayed as real data, DESIGN_SYSTEM.md violations (glassmorphism as
default surface), 7 failing tests, orphaned widgets, no-op controls, ~30 BackdropFilter
performance landmines, and a non-additive migration. The two Phase 5 plan documents in
`.opencode/plans/` are historical artifacts, not instructions.

**Salvaged:** the 180-minute session duration cap (July-22 strain-403 fix), reworked additively.

## Phase 5 v2 — "Precision Pro" (2026-08-22) — IN PROGRESS

Chunked rebuild on `feature/feature-engine-phase-5-v2`; master plan + progress tracker:
`.opencode/plans/phase-5-v2-precision-pro.md`. Owner rulings: Stitch dark direction, all 5 tabs,
every implemented feature surfaced and working, real RPC data only.

**Chunk 0 complete (`c55d281`):** DESIGN_SYSTEM.md amended (§3.1 dark Stitch palette, §3.2
Spline Sans + IBM Plex Mono, §3.3 shape lock 12/24/28, §3.4 premium-gradient cards +
chrome-only glass budget, §10 anti-patterns); dark tokens updated (light theme unchanged);
genuine fonts committed (byte-size + SHA + usWeightClass verified; OFL via LicenseRegistry);
new shared widgets `TracendGlass` (chrome-only, opaque fallback), `PremiumGradientCard`
(zero blur), `MicroMotion` (Reduce Motion gated via `MediaQuery.disableAnimationsOf` —
pinned SDK has no `accessibilityFeaturesOf`). 175 tests pass. Review: PASS with findings
(`docs/reviews/2026-08-22-phase-5-v2-chunk-0-precision-pro-foundation.md`).

**Chunk 1 complete (`1bcc0d8`):** Today screen rebuilt to Stitch. `TrajectoryLens` rewritten
as a bezier `CustomPainter` with `PathMetric` draw-on + pulsing NOW dot; NOW resolves only to
real computed fields (`recovery ?? last real point`), chip-rail fallback when <2 scores
(noop rule: never invent a value). Hero (confidence pill in `TracendGlass`, 42pt decision
headline, Start session disabled-not-no-op, View analytics hidden when unwired), restyled
`ReadinessStrip` (mono values, real z-chips), new readouts `SessionPlanCard`,
`MetabolicTargetCard`, `CoachPerspectiveCard` (real T/N toggle), `CheckInPromptBar`,
`PrecisionDivider`. 8 widgets extracted to `lib/features/today/widgets/` (screen 417 lines).
Wired `app_shell` tab callbacks (View analytics → Progress, LOG → Nutrition). Removed the
coaching-horizon backdrop + asset (DESIGN_SYSTEM §2 now documents the trajectory lens as the
signature element). 200 tests pass. Review: PASS with findings
(`docs/reviews/2026-08-22-phase-5-v2-chunk-1-today-screen.md`).

**Chunk 2 complete (2026-08-23) + review follow-ups (2026-08-24):** Train + Nutrition
rebuilt to Stitch. New shared widgets: `IntensityBar` (per-exercise planned `target_rpe`
bars + recorded-RPE marker from logged set RPE via `get_my_workout_session`, never the
hardcoded `session_effort = 8`; honest cold start), `DatePillStrip` (week pill navigation
with real chevron offset state, normalized-date set lookup, chevrons render only when
wired), `TargetsGrid` (real `NutritionTargets`/`NutritionSummary`, solid cells, mono
values, remaining protein). `NutritionInsightCard` binds
`CoachDecision.nutritionAction/Summary/confidence` (hidden when no decision). Train hero
binds `trainingSummary` coach insight. `TrainingSessionSummary` gained nullable `workoutId`
(hub v1.4) so recent-session rows open `WorkoutDetailScreen`; unresolvable rows are
display-only. `_ProgressionRow` converted to display-only facts. `TrainingLoadGauge`
restyled into `PremiumGradientCard` with token zone colors. Train/Nutrition sub-widgets
extracted to `lib/features/{train,nutrition}/widgets/`.

Review: PASS WITH FINDINGS
(`docs/reviews/2026-08-23-phase-5-v2-chunk-2-train-nutrition.md`). All findings fixed
2026-08-24: (1) `coach: _coach` injected into Train/Nutrition at the shell so insight
surfaces bind real decisions; (2) `_ScheduledMealRow`/`_MealCard` extracted to
`lib/features/nutrition/widgets/meal_cards.dart` (screen 589 → 453 lines); (3) four
screen-level tests added (recorded-RPE averaging/filtering, RecentSessionsCard
openable/display-only, WorkoutHero insight null-hiding, NutritionScreen insight-card
visibility); (4) v1.4 contract fixture gained `workout_id`/`effort`/`energy` + assertion;
(5) IntensityBar "Recorded" legend renders only when a marker exists; (6) TargetsGrid
null-summary shows "No confirmed meals yet"; (7) WorkoutHero doc comment corrected.
Finding 8 (date-scoped `loadLatest`) deferred to a later chunk. 223 tests pass, 0 analysis
issues.

**Chunk 3 complete (2026-08-24, `672f28f` + `288d14a`):** Progress + Coach rebuilt to Stitch. New shared widgets:
`EvidenceAccordion` (`lib/shared/widgets/evidence_accordion.dart`) — animates content height
BEFORE unmounting collapsed content, chevron rotates on the same controller, Reduce Motion
jumps instantly, header is a 44pt semantics button announcing expanded state; replaces both
raw `ExpansionTile` sites in Coach. `ExpandableText` — 6-line truncation with a Show
more/Show less control that renders only when the text actually overflows.
`EvidenceTrendChart` gained deterministic 7d/28d regression overlays from
`ComputedMetrics.weightTrend7d/28d`: each line is anchored to the window centroid of the real
confirmed weigh-ins and clipped to its window + chart range (no invented intercept, no
extrapolation); legend distinguishes measured dots from computed lines; R2 (28d only,
threshold 0.3 per ALGORITHMS.md §7; missing R2 = low confidence) renders the 28d line
dashed + "low confidence"; the 7d line is never R2-gated. `WeightTrendIndicator` restyled
into `PremiumGradientCard` with the `accentAmber` token and `MetricSparkline` wired from real
confirmed weigh-in values. Progress measurement history rows are tappable →
`MeasurementDetailSheet` (date, source, weight, optional tape values; read-only); strength
progression rows stay display-only with an honest caption. Coach screen rebuilt from extracted
widgets (`coach_decision_card`, `coach_context_card`, `coach_message_bubble`,
`coach_composer`); Progress screen rebuilt from
`widgets/{measurement_widgets,weight_trend_card,training_evidence_widgets,photo_widgets,weekly_review_widgets}.dart`;
both screens stay under the 500-line review budget. Widget tests that drive a chat send mock
`SystemChannels.platform` because `HapticFeedback.lightImpact()` never completes on the
unmocked test channel. 262 tests pass, 0 analysis issues, unsigned iOS release build
passes (25.2 MB).

Review: PASS WITH FINDINGS
(`docs/reviews/2026-08-24-phase-5-v2-chunk-3-progress-coach.md`). All 10 findings fixed
2026-08-24: (1+2) `deriveTrendOverlay`/`WeightTrendCard` binding contracts now disclose the
overlay window ending at the latest confirmed weigh-in (may trail the brief target date) and
the centroid anchor using displayed body-measurement dots only (server fit may merge
HealthKit summary weights); (3) DESIGN_SYSTEM.md Evidence-visualization amended to permit
labeled R²-gated regression overlays (raw dots never smoothed; reconciles PRD §4.7);
(4) `EvidenceAccordion` semantics label includes the subtitle; (5) `ExpandableText` caches
and disposes its overflow-probe `TextPainter`; (6) progress reachability test taps Record
measurement → entry sheet and Open weekly review → review sheet; (7) coach loading state
asserted via a never-completing repository; (8) design-handoff markdown indent fixed;
(9) frontend-handoff build line refreshed to 25.2 MB; (10) chat-bubble 18pt radius
documented as a shape-lock exception in DESIGN_SYSTEM.md §3.3.

**Chunk 4 complete (2026-08-24):** AI Usage + Shell + Account. `My AI usage` rebuilt as
`lib/features/account/widgets/ai_usage_screen.dart`: every value binds the merged
`get_my_ai_usage` + `get_my_ai_budget_state` response (`successful_runs`, `failed_runs`,
`estimated_cost_usd`, `today_requests`, `daily_limit`, `warning_threshold_usd`,
`hard_stop_usd`, `warning`, `blocked`); thresholds render from RPC values, never hardcoded;
cost labeled operational estimate; loading/empty/unavailable states with real retry and
Refresh usage refetch; fixture path (no budget fields) degrades to run counts + estimates
without threshold claims. New read-only consent ledger
(`lib/features/account/widgets/consent_ledger_screen.dart`) wired from the Privacy row:
latest append-only `consent_records` entry per purpose (terms, privacy,
progress_photo_storage, progress_photo_ai, notifications) via direct select under existing
RLS. Account restyled (PremiumGradientCard profile hero, icon-container rows, mono tabular
detail values) and extracted to `lib/features/account/widgets/` (`account_widgets`,
`profile_goals_screen`, `ai_usage_screen`, `consent_ledger_screen`, `account_sheets`,
`notification_sheet`, `coach_threads_sheet`); account_screen.dart 1075 → 388 lines.
Unconfigured environments show "AI service not configured" per UX_FLOWS §13. Shell tab
capsule inline `BackdropFilter` replaced by `TracendGlass` (glass budget unchanged: 2
visible sites, asserted in `app_shell_test.dart`). Dead `ComingSoonButton`,
`MiniTrendChart`, `_MiniTrendPainter` deleted from `tracend_scaffold.dart`. Coach-thread
rows documented as display-only with the trailing delete as the action.

Review: PASS WITH FINDINGS
(`docs/reviews/2026-08-24-phase-5-v2-chunk-4-ai-usage-shell-account.md`). All findings
fixed 2026-08-24: (1) Account AI row distinguishes RPC failure from loading — usage
future moved to `initState` (no rebuild re-fire) and the error branch shows
"AI usage unavailable · Open details to retry"; (2) consent ledger picks the latest
record per purpose by `created_at` regardless of input order; (3) consent rows render
the record source; (4) threshold copy uses fractional-safe `usdText` formatting;
(5) thread delete gained an error path; (6) doc line counts corrected. Deferred:
`get_my_ai_usage`/`get_my_ai_budget_state` lack `schema_version` (needs an additive DB
migration — out of this UI-only phase). Accepted: fixture-mode AI usage detail shows
"$0.0000 · Estimates only" without repeating the not-configured framing (honest,
test-asserted). 274 tests pass, 0 analysis issues.

**Chunk 5 implemented (2026-08-24):** Motion + A11y + copy audit. Motion:
`MicroMotionCountUp` added to `lib/shared/widgets/micro_motion.dart` (animates only on
value change, 600ms ease-out, static under Reduce Motion) and wired into the RecoveryRing
score; all nine Today brief sections wrapped in `MicroMotionEntrance` with fixed stagger
slots 0–8 (`MicroMotion.stagger`, 60ms/index capped at 8); the redundant inner entrance
around `TrajectoryLens` removed (hero-level stagger subsumes it). A11y: `_DriverBar`
gained a semantics label ("HRV driver, z-score 0.5", `excludeSemantics`); contrast asserts
extended in `theme_test.dart` (stateAttention/stateDanger ≥3:1 on canvas both themes,
actionOnPrimary ≥4.5:1 on the action fill, textPrimary ≥4.5:1 on canvas, light graphics
tokens ≥3:1); all five chips (2 ActionChip, 2 FilterChip, 1 ChoiceChip) use padded tap
targets (48pt); tab labels clamp to 1.3× text scale (iOS tab-bar convention) protecting the
70pt capsule; `_CardTag` label wraps instead of overflowing. Bubble semantics ("Coach
said"/"You said") verified present. Notification-sheet reminder times verified against the
native scheduler (`SceneDelegate.swift`: hour 19 daily; hour 18 weekday 1 = Sunday). New
`test/dynamic_type_test.dart` pumps all five tabs at 320pt and text scales 1.3×/2.0× (the
largest iOS scale) asserting no overflow — it surfaced and fixed two real overflows
(session_plan_card `_CardTag`, app_shell tab label). Copy self-audit found no filler, no
AI-cliché, and no fabricated numbers; every interpolated string traces to a repository
field. 284 tests pass, 0 analysis issues.

Review: PASS WITH FINDINGS
(`docs/reviews/2026-08-24-phase-5-v2-chunk-5-motion-a11y-copy.md`). All findings fixed
2026-08-24: (1, minor) the Today brief FutureBuilder now prefers retained snapshot data
over the waiting state, so `_BriefContent` stays mounted across check-in/sync reloads —
stagger entrances no longer replay and `MicroMotionCountUp` actually fires on score
changes (regression test asserts RecoveryRing element identity across a real check-in
reload); the test also surfaced and fixed two latent `setState(() => _brief = future)`
arrow bugs in today_screen.dart (callback returned a Future — same pattern fixed in
Chunk 4); (2) light textSecondary-on-canvas contrast assert added; (3) dynamic_type_test
gained a computed-brief Today test at 320pt × 2.0 covering the ring, driver bars, sleep
card, and lens (reduceMotion stops the pulse so pumpAndSettle completes); (4) `_DriverBar`
doc comment documents that the semantics label reports the true z-score while the bar fill
clamps to ±2. 287 tests pass, 0 analysis issues.

Next: iOS release build re-verified, then merge to `feature/feature-engine` (owner
action) — Phase 5 v2 implementation is complete.

## Session Duration Cap (2026-08-22)

**Client** (`active_workout_screen.dart`): `_maxSessionSeconds = 10800`, 15-second elapsed
timer, warning card when expired, duration clamped to 10800 on complete. Restart-safe
(elapsed computed from `_startedAt`). Widget test in `phase_3_workout_flow_test.dart`.

**Server** (`20260822120000_session_duration_cap.sql`, additive):
- `complete_workout` clamps `duration_seconds` via `LEAST(..., 10800)` — never hard-errors.
- `compute_daily_metrics` excludes `duration_seconds > 10800` rows from daily strain,
  7-day/28-day strain windows, and ACWR/monotony. This neutralizes the historical July-22
  row (30238s) without rewriting data.
- No constraint changes; existing CHECK `<= 86400` stays. A DB-level 10800 CHECK is deferred
  to a future two-step migration after the capped client build is installed.
- `health_sync_v1.ts` stays at 86400 (HealthKit workouts may legitimately exceed 3h).

## Do Not Do

- Do not add iPad, Android, subscriptions, social features, or public App Store release
  infrastructure.
- Do not boot or run an iOS simulator on the development Mac; use CLI device compilation and a
  physically connected iPhone.
- Do not hard-code production Supabase URL or keys.
- Do not expand routes beyond the PRD or add screens not in Phase 1.
- Do not place build output, `.dart_tool/`, or `build/` on internal storage.
