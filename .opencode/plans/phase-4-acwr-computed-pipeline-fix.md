# Phase 4 Fix — Computed Pipeline (ACWR/Strain showing stale defaults)

**Root cause:** `get_my_daily_brief` reads from `feature_snapshots` (coaching snapshot),
never from `daily_computed_metrics` (cron-refreshed). Cron only processes yesterday.
HealthKit auto-complete sets `session_effort = NULL`.

## Fixes (single forward-only migration)

### 1. `get_my_daily_brief` → read from `daily_computed_metrics`

Replace `latest_computed` CTE to query `daily_computed_metrics`:

| Old source (`feature_snapshots`) | New source (`daily_computed_metrics`) |
|---|---|
| `features->'scores'` | `scores_jsonb` |
| `features->'baselines'` | `baseline_snapshot_jsonb` |
| `features->'data_confidence'` | `data_confidence` |

### 2. `prepare_daily_coaching` → upsert into `daily_computed_metrics`

After calling `compute_daily_metrics()`, also write to `daily_computed_metrics`
(already done — verify the upsert ON CONFLICT is present).

### 3. `healthkit_auto_complete_workout` → default effort

Set `session_effort = 5` (moderate, 1-10 scale) for auto-completed sessions
so they contribute to strain/ACWR calculations.

## Impact

- Today/Train/Progress widgets show fresh computed data
- Cron already recomputes daily → data available after next 6am run
- Coach invocation also triggers recompute → data available immediately
- Auto-completed HealthKit workouts now count toward training load

## Files changed

- `supabase/migrations/<timestamp>_fix_computed_pipeline.sql` — 1 new forward-only migration
- No Flutter changes
- No Edge Function changes

## Verification

- Dry-run migration push
- Check `get_my_daily_brief` returns non-zero `acwr`/`daily_strain` for user with sessions
- Flutter analyze + test (155 tests must still pass)
