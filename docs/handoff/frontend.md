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
- `./scripts/flutter.sh test` — pass, 33 tests
- `./scripts/flutter.sh build ios --release --no-codesign` — pass, HealthKit linked, 18.3 MB
  physical-device app
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

- The installed hosted readback correction now turns stored Apple Health summaries into dated Today
  metrics plus real sleep/step trends, explains partial as sample availability rather than
  permission truth, and removes the fabricated Train performance curve and fictional week/schedule
  copy. Flutter analysis and 57/57 tests pass. Hosted build, automatic signing, strict code-sign
  verification, and iPhone installation pass; CLI launch was blocked only by the locked device.
- Hosted inspection found seven stored summary days through 2026-07-02: step, energy, workout,
  resting-HR, and HRV categories exist, while no sleep or HealthKit weight samples are stored. The
  latest server sync is still the earlier seven-day run, so the 31-day refresh has not reached the
  backend.
- The complete current source was freshly rebuilt on 2026-07-04: format, analysis, 65/65 tests,
  unsigned device build, hosted-config signing, strict code-sign verification, iPhone installation,
  and a subsequent unlocked CLI launch all pass.
- Local repair on 2026-07-05 fixes three owner-reported regressions before hosted deployment: Train
  no longer falls back to the first workout on unassigned/rest days, Today refreshes the daily brief
  after Apple Health sync and check-in saves, and stored HealthKit evidence reads the latest 31-day
  summary window instead of only same-day rows. Flutter format, analysis, 65/65 tests, and unsigned
  iPhone release build pass.

1. Prepare and download one owner export, then decrypt it on the external SSD using
   `docs/BETA_OPERATIONS.md`.
2. The hosted repair migration is deployed and the signed hosted build is installed on the owner's
   iPhone. Trust the current developer profile in iOS, then verify Sunday/rest day Train, exact
   Nutrition foods, and Today Health evidence refresh.
3. Do not device-test deletion with the owner account; hosted synthetic QA is the destructive gate.
4. Keep live meal/progress AI, catalog choice, and Sign in with Apple deferred pending their
   explicit decisions. Direct paid Gemini remains the reviewed provider path; do not substitute
   GLM/OpenRouter without a provider review.

## Do Not Do

- Do not add iPad, Android, subscriptions, social features, or public App Store release
  infrastructure.
- Do not boot or run an iOS simulator on the development Mac; use CLI device compilation and a
  physically connected iPhone.
- Do not hard-code production Supabase URL or keys.
- Do not expand routes beyond the PRD or add screens not in Phase 1.
- Do not place build output, `.dart_tool/`, or `build/` on internal storage.
