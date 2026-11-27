# Menstrual Cycle Support Handoff

**As of:** 2026-11-27

Cycle support v1 is opt-in cycle tracking: a woman says how her cycle works, logs periods (or
allows them from Apple Health), sees an honest cycle line, and gets recovery, weight and Coach
answers that account for her cycle. The cycle explains; it never changes a plan, a target or the
recovery score. No fertility features, no diagnosis; pregnancy stays out of scope. Three PRs,
merged in order: data (PR 1), app (PR 2), Coach (PR 3).

## Data

- **Branch / PR:** `claude/cycle-foundation`, PR #208. Migrations
  `20261127141837_cycle_data_consent_type.sql` (the `cycle_data` consent type, alone) and
  `20261127142651_cycle_foundation.sql` (everything else). Additive only: no existing function is
  redefined, old app builds call nothing new.
- **Tables:** `cycle_settings` (one row per athlete) and `cycle_day_logs` (one row per athlete and
  day), read-only for the athlete under forced RLS, written only by the RPCs. Shapes and checks:
  `docs/DATA_MODEL.md` (§4, "`cycle_settings` and `cycle_day_logs`").
- **Engine:** `private.cycle_state(user_id, local_date)` is the only place a cycle day, phase,
  expected range, confidence or flag is computed. Rules and constants: `docs/ALGORITHMS.md` §11.
- **RPCs:** `get_my_cycle_v1`, `set_my_cycle_settings_v1`, `log_cycle_day_v1`,
  `import_cycle_days_v1`, `delete_my_cycle_data_v1` (authenticated) and `coach_cycle_state_v1`
  (service role only). All answer the cycle answer, `schema_version` `1.0` (import answers
  `{schema_version, imported, removed}`). Fixtures: `test/contract/fixtures/my_cycle_v1_0_off.json`,
  `my_cycle_v1_0_regular.json`, `my_cycle_v1_0_late.json`, `my_cycle_v1_0_contraception.json`; each
  is the whole answer for a real seed on 2026-11-27, compared in full by `cycle_engine_test.sql`
  (CI links `test/contract/fixtures` at `/contract-fixtures`; `scripts/test-db.sh` copies it).
- **Errors the app maps:** `42501` signed out or inactive account; `22023` bad input; `P0403` with
  message `cycle_consent_required`, `health_consent_required`, `cycle_tracking_off` or
  `apple_health_off`.
- **Consent:** `cycle_data`, notice version `2026-11-27`, inserted by the app when she turns
  tracking on. Reading Apple Health also needs `health_data`. "Delete my cycle data" deletes every
  day and the settings row and records `withdrawn` (source `ios_app`: the `consent_records` check
  allows only `owner_development` and `ios_app`).
- **Decisions made while building (spec gaps):**
  - `period_day` ends at once when today has a manual "no bleeding" row, instead of running on
    for the 2-day tolerance.
  - A bleed that is not a start yet (one light day) is a period day only when it is at least 15
    days after the last start; it also resets the long-gap count, so the long-gap card never says
    "no period logged" right after she logged one.
  - On hormonal contraception or with no periods, `cycles` is empty (withdrawal bleeds are not
    cycles) and period days 1–3 set `weight_water_window`.
  - `get_my_cycle_v1` returns tomorrow's row in `recent_days` (she may log tomorrow when her
    phone's date is ahead of her account's time zone); the engine reads days up to the local date
    only. Coach gets the 14 days ending the coaching date.
  - `import_cycle_days_v1` refuses an item with any key besides `local_date`, `flow`, `is_start`;
    `log_cycle_day_v1` treats a null `p_is_start` as false.
  - `coach_cycle_state_v1` is gated by its grant (service role only), like the Coach lookups.
  - Review round 1: a withdrawn `cycle_data` consent reads as tracking off everywhere; every
    writer locks the account row first, so a delete cannot race a log or an import; the import
    window starts no more than 400 days ago; a one-day guessed start is replaced by her real period
    1–9 days later (ALGORITHMS §11).
- **Tests:** `supabase/tests/database/cycle_engine_test.sql` (the engine on fixed dates) and
  `cycle_rpcs_test.sql` (gates, privileges, RLS, the Apple Health merge, key sets, deletion);
  `privacy-export` exports both tables.
- **After merge:** read-only checks that both tables exist with RLS on and no rows yet; nothing
  else to run. No Edge Function changes in this PR.
- **Later, not v1:** per-phase recovery baselines, wrist temperature, symptom patterns, reminders,
  a calendar view, cycle-aware nutrition-change eligibility, offline period logging.

## App

Added by the app PR.

## Coach

- **Branch / PR:** `claude/cycle-coach`. Deno only, no migration. Merge after PR 1: it reads
  `coach_cycle_state_v1`.
- **Notice gate:** `NoticeScope` gains `cycle_data`; `firstNoticeNaming` is 7 for `breathing_rate`,
  `workout_notes` and `cycle_data` (`_shared/ai_notice_coverage.ts`). `coach-chat` passes the
  athlete's scopes to the contributors (`CoachContextInput.noticeScopes`) and the lookups; the eval
  harness does the same from the case's `noticeVersion` (default the live `ai-coaching-v6`). Until
  the owner publishes v7 no athlete holds it, so Coach behaves as before: no cycle read, no cycle
  block, no "withheld" line, the same watch-outs (`cycle_test.ts`, `cases_cycle_test.ts`).
- **`cycle` contributor** (`_shared/coach_context/contributors/cycle.ts`): volatile, after the
  heart-rate profile, budget 2,800. Registered on both routes, but only the gateway route reads the
  accepted notice version, so on the rollback (DeepSeek) path no scope is open and it renders
  nothing (fails closed). Reads the cycle answer once per turn through
  `sharedRead` (key `cycle_state`, shared with the watch-outs, 1.5 s deadline) and parses it strictly
  (an unknown value is unreadable, never "off"). Renders nothing without the scope, with tracking off
  (also after "Delete my cycle data") or after a failed read. Otherwise: status, today's cycle day,
  phase and confidence, expected range, typical and recent lengths, `Long gap without a period:
  yes|no`, the water-weight window, fixed rules (no training or food change by phase, the expected
  heart-rate, HRV and water shifts, when to see a doctor, never fertility, ovulation, pregnancy odds,
  contraception advice or an unnamed condition), then the last 14 logged days. Grounding: `records`
  (dates, day numbers, lengths). Trace `cycle_context` carries the read status only (`ok`,
  `unavailable`, `failed`, `timeout`), never whether tracking is on.
- **Watch-outs:** with the scope, in `second_half` of a regular cycle at medium or high confidence, a
  resting heart rate or HRV drift with -2 < z <= -1 becomes a data line ("within what the second half
  of a natural cycle often brings"), not a decision watch-out; z <= -2 stays a watch-out.
- **Reply rules** (`_shared/coach_safety/reply_guard.ts`, each with a repair hint):
  `fertility_or_contraception_claim` and `cycle_condition_named` apply to every athlete (they need no
  data); `deficit_advice_with_long_gap` applies while the cycle block's long-gap line says yes. The
  fertility rule reads "safe days/window/time" and "the pill" only in a sentence about a cycle,
  pregnancy or contraception. The condition rule lists only PCOS/PCOD, endometriosis, PMDD,
  adenomyosis, fibroids and amenorrhoea (a test keeps every library and digest word off it). The
  long-gap rule shares the onboarding plan check's claim words (`deficitClaim`, now exported) with
  its own denials, voided by until, then, resume, keep it, for now, fine or working; the plan
  check's `noDeficit` is unchanged.
- **Red flags:** `severe_pain` has a `benign` exemption by positive attribution only ("period pain",
  "menstrual cramps", "pain on my period"), with no undoing word next to it (not, missed, late,
  after, since, before, like, worse than, no, positive, test, pregnant) and no emergency or injury
  word anywhere (one side, fever, temperature, vomiting, fainting, dizziness, soaking, clots, heavy
  bleeding, bleeding through, worst, sudden, breathing, painkillers, any body part or injury).
  `diagnosis_request` covers asking whether a cycle condition, perimenopause or menopause is the
  cause. Cases in `exemptions_adversarial_test.ts`.
- **Principles digest v4:** the cycle has its own line (no training by phase, expected shifts, when
  to see a doctor, what never to say). It changes the cached prefix for every athlete; it holds no
  athlete data.
- **Evals:** coach_bank `cases_cycle.ts` (five red flags that must still hit, severe period pain that
  must not, five guard cases); coach_sim personas `cycle_second_half`, `cycle_pill`,
  `cycle_irregular`, `cycle_long_gap` with scenarios `cycle-recovery` and `cycle-long-gap`. The live
  model runs are not done yet: run them before v7 is published (`EVAL_CASES=cycle` for the bank,
  `EVAL_SIM_FILTER=cycle` for the simulator). CI runs every case's graders on hand-written good and
  bad replies and every persona's turn build, with no model.
- **Owner step (later):** publish v7 with the SQL in `docs/notices/ai-coaching-v7.md`, then accept it
  in the app. A rollback notice is now v8 and must name the same data (runbook step 6.2).
- **Later, not v1:** a cycle-aware check on Coach's nutrition proposals (the reply rule covers the
  reply text; a proposal to lower calories still goes to the proposal engine's own rules).
