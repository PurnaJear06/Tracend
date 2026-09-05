# Post-deploy verification: Phase 5 v2 + coach-decide pipeline — 2026-09-02

Scope: owner device QA session one week after the Aug 26 merges (Chunk 7 + hotfixes
7.1/7.2 deployed). No code changed, no data modified — all database checks were
read-only REST `GET`s against the hosted project (`qsfzzsjenopqqqhvpyaw`) using the
service key obtained via the already-authenticated project-local Supabase CLI
(`./scripts/supabase.sh projects api-keys list`). The service key was used from a
temp file and deleted afterward; it never entered the transcript.

Fresh release build installed on Purna's iPhone 12 at 08:06 IST via
`./scripts/install-device.sh` (signed, 26.0 MB, team CGLRSQ8G95). First install
attempt failed with a CoreDevice connection reset (phone locked mid-transfer);
retry of the already-built `.app` succeeded — no rebuild needed.

## Verdict: pipeline fixed and verified; feature work complete

The headline: **every `daily_coaching` run since the Aug 26 DeepSeek hotfix has
succeeded.** `model_runs` (latest 10): Sep 2 — 2× `daily_coaching` succeeded
(2.6–3.1 s), 2× `coach_chat` succeeded; Aug 26 12:24 UTC — `daily_coaching`
succeeded. Before that: the familiar failure ladder (`deepseek_request_failed`
11:56, `provider_or_validation_failed` ×3 through 08:00). The owner's AI-usage
counter bump (3→4) after a chat message matches: one new successful `coach_chat`
run. **The decision pipeline hotfixes (7.1 whitelist + 7.2 thinking-mode) are
confirmed working end-to-end in production. This closes the last shipped-milestone
verification gap.**

## Evidence from production (read-only, 2026-09-02 ~03:30–03:35 UTC)

### Check-ins (`daily_check_ins`)

| local_date | energy | available | superseded_at | created_at (UTC) |
| --- | --- | --- | --- | --- |
| 2026-09-02 | 3 | **false** | null | 03:31:05 |
| 2026-09-02 | 3 | true | 03:31:05 | 03:30:31 |
| 2026-08-26 | 4 | true | null | (pre-fix week) |

Two check-ins 34 s apart today: the first save **did land**, the retry superseded it
(revision+supersede pattern working as designed; second save wins). **No check-ins
between Aug 26 and Sep 2** — owner's earlier "not updating" attempts never reached
the DB. This matches the transient-failure story below, and independently explains
the coach chat answering about the check-in: `coach_context_v5` reads *latest ever*
(`order by local_date desc limit 1`), so the "can you see my check-in" answer was
quoting **Aug 26's** values while the Today screen (correctly) showed nothing for
Sep 2 until the saves landed.

### Health summaries (`daily_health_summaries`, source_scope=healthkit)

| local_date | HRV ms | RHR | sleep_min | present_types |
| --- | --- | --- | --- | --- |
| 2026-09-02 | — | — | — | steps (102) |
| 2026-09-01 | 81.4 | 58 | — | energy,hrv,rhr,steps |
| 2026-08-31 | 74.4 | 63 | — | energy,hrv,rhr,steps |
| 2026-08-30 | 66.4 | 56 | — | energy,hrv,rhr,steps |
| 2026-08-29 | 87.7 | 55 | — | energy,hrv,rhr,steps |
| 2026-08-28 | 154.6 | 42 | — | energy,hrv,rhr,steps |
| 2026-08-27 | 53.7 | 58 | — | energy,hrv,rhr,steps |

Health sync **did run during the off week** (7-day window, `healthSyncStart`), so
HRV/RHR are current. But **sleep is NULL every day**, and today's row has no
HRV/RHR at all (partial day + likely watch-wear pattern). Recovery for today is
therefore NULL by the honest formula → the `--` score and "No data" driver rows the
owner saw on the phone are the system being honest, **not a bug** — provided the
watch genuinely isn't recording sleep (not worn to bed / HealthKit sleep permission
off). Open question A below.

### Computed metrics (`daily_computed_metrics`)

- Sep 2: recovery NULL, confidence low, ACWR 0.87, strain 0, monotony 5.57,
  missing_components = all five. Honest.
- Sep 1 / Aug 31 / Aug 30 / Aug 29: recovery 85 / 71 / 73 / 93 — the honest
  formula produces sensible scores on days with HRV+RHR even without sleep.
- **Anomaly: rows exist for future dates 2026-09-03..09-06**, all computed_at
  03:33–03:35 UTC Sep 2 (during the owner's sync taps), all identical (NULL
  recovery, same ACWR/monotony). Whatever recompute path ran at that moment wrote
  metrics for dates ahead of today. Benign-looking (recovery NULL there is
  "correct" for empty days) but future-dated rows in this table are a data-hygiene
  defect and the writing path needs identification.

## Findings (unfixed — owner instructed no code changes this session)

1. [MAJOR] **Check-in offline fallback is a dead letter.**
   `lib/features/today/check_in_sheet.dart:57-90` stores the envelope in
   SharedPreferences (`daily_check_in_pending`, :39) when `save_daily_check_in`
   throws, shows "will need a connection to sync" — but **nothing anywhere reads
   that key back** (verified by repo-wide grep: only reference is the write site).
   Failed check-ins are silently lost forever; the promise in the snackbar is
   false. Also note the save is a single un-retried RPC call (unlike health sync's
   3× retry), which is why transient failures were plausibly the owner's "not
   working" experience. Fix: replay queue on app start / after brief reload.

2. [MAJOR] **Future-dated `daily_computed_metrics` rows.** Rows for 2026-09-03
   through 09-06 created at Sep 2 03:33–03:35 UTC. **Root cause identified
   2026-09-02 (follow-up code read, no DB access needed): the Train screen
   weekday strip.** Tapping a future weekday pill of the current week (Thu–Sun
   after a Wednesday) drives `_dateForWeekday`
   (`lib/features/train/train_screen.dart:201`), which returns planned future
   dates — the week clamp at `:279` bounds `_weekOffset` weeks only, not days
   within the current week, and showing planned future days is intentional UX.
   Each selection loads the brief for that date → RPC
   `get_my_daily_brief(target_date=…)` → `compute_daily_metrics`, which (per the
   Jul 26 compute-on-the-fly change) computes fresh for whatever `target_date`
   it receives and **upserts a `daily_computed_metrics` row for it, with no
   future-date guard** (`20260825120000_recovery_honesty.sql:443`). The timeline
   matches: check-ins 03:30–03:31, then the four future rows 03:33–03:35 — the
   owner navigating Train's weekday pills right after checking in. ACWR/monotony
   identical across all four because future days have no sessions, so every
   window sees the same history. Benign for reads today
   (`get_my_training_hub` filters `local_date = current_date`), but the writing
   path should be fixed: skip the side-effect upsert when
   `target_date > current_date` (and note the same call runs
   `compute_user_baselines(target_user_id, target_date)`, which also anchors
   baselines to those future dates as a side effect).

3. [MINOR] **Coach chat asserts "today" for a stale check-in.** The v5 context
   feeds `last_check_in` and `latest_check_in_detail` (latest *ever*), and the
   model presented Aug 26 as "today". Two improvements: prompt should forbid
   asserting "today/recent" without comparing the date to the actual current date,
   and/or the context should expose check-in-today explicitly so the model doesn't
   infer.

4. [MINOR] **Possible TrajectoryTrend rendering gap.** The owner reported the
   7-day trend showing "only one point as 81 ms". The DB has **six HRV days in the
   7-day window** (Aug 27–Sep 1), which passes the ≥4 gate
   (`trendSeriesFor`, `lib/shared/widgets/trajectory_trend.dart:84`) — a full curve
   should draw. Follow-up code read (2026-09-02) found the widget and the
   `loadHistory` loader both clean: the loader
   (`lib/features/health/health_repository.dart:110`) pulls 31 days regardless of
   metric, and `trendSeriesFor` filters by metric with dots drawn for every
   recorded day — so six dots should render. Most likely explanations, in order:
   (a) the owner read the **HRV driver row** in `RecoveryReadoutCard` (a single
   "81 ms" value, easy to conflate with the trend), (b) a stale pre-sync view —
   Aug 27–Sep 1 HRV only landed in the DB during this morning's sync, so an
   earlier app open would legitimately show cold-start or fewer points, or
   (c) a genuine widget bug. A screenshot settles it. One real design nit found
   while reading: the window anchors to the **latest stored day** (Sep 2, HRV
   NULL) rather than the latest day *with data for the metric* — with ≥4 other
   days present this is harmless (the series still draws), but worth revisiting
   if the chart ever looks sparse when today's row exists but is empty.

5. [NOTE] **Sleep data absent everywhere.** Every recent day has NULL
   `sleep_minutes`. If the watch is worn to bed and Apple Health shows sleep, then
   the HealthKit read/permission or `normalizeHealthSamples` sleep path is broken —
   that becomes a real sync bug and also explains the perpetually-NULL
   sleep-quality/recovery components. Verify on-device first (open question A).

6. [NOTE] **ACWR 0.87 with zero recent strain.** ACWR reports 0.87 on days with
   strain 0 (no workouts since the off-week). The deferred noop follow-up "ACWR
   reports 1.0 with < 7 days of strain history" (`docs/handoff/backend.md`) is a
   cousin of this: the ratio is computed from whatever window exists rather than
   being NULL when history is insufficient. Existing deferred item; today's data
   re-confirms it. Monotony 5.57 on zero-variance strain windows similarly.

7. [NOTE] **`pubspec.lock` drift.** One-line uncommitted change on main
   (`flutter: ">=3.41.7"` → `"3.41.7"`) from a pub get — commit or discard.

## What the owner should test next (device QA)

1. Wear the Apple Watch to bed (or verify HealthKit sleep permission for Tracend),
   then tap Sync on Today tomorrow: recovery should show a real score with sleep
   present in the brief.
2. Send a screenshot of the Today screen (recovery readout + 7-day trend) to settle
   finding 4.
3. Do one check-in tomorrow: the Today prompt bar should flip to "Morning status
   recorded" immediately after the snackbar.
4. Open the Coach tab: today's decision card should render (the verified pipeline).

## Session facts for future agents

- The project-local Supabase CLI is authenticated and can reach the hosted project
  (`./scripts/supabase.sh projects list` works without login). `supabase db dump
  --linked` locally requires Colima/Docker, which failed this session
  ("did not receive an event with the running status" after 10 min — known-flaky);
  the REST-API read-only route described above worked instead and avoids Docker
  entirely. The Aug 26 "production backup analysis" was the CI
  `database-backup` artifact (deploy.yml:92), not a local dump.
- Owner's device: "Purna's iPhone" iPhone 12, CoreDevice id
  `76C49079-EEC2-5E22-A533-7ADE82AD4C49`; `xcrun devicectl` connections drop when
  the phone locks mid-transfer — retry the install of the existing `.app`, no
  rebuild needed.
- Owner user id in production: the `user_accounts` row with
  `onboarding_state='completed'` (mask id in notes; fetch fresh via the REST route
  if needed). A second, never-onboarded account from 2026-07-01 exists (test
  signup).
