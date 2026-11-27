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
    window starts no more than 400 days ago.
  - Review round 2: the onboarding guess (manual, `is_start`, flow `unspecified`) is dropped when a
    real period lies within 14 days of it (ALGORITHMS §11). PR 2's day editor must never send
    `unspecified` together with `is_start`. The long-gap count also starts again at her newest
    `cycle_data` grant, and "Delete my cycle data" refuses (`42501`) a caller without an account.
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

Added by the Coach PR.
