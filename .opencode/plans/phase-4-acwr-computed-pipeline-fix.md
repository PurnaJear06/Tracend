# Phase 4 Fix — Computed Pipeline (revised v2)

## Root Cause (revised after Noop comparison)

**v1 diagnosis (superficial):** `get_my_daily_brief` reads from `feature_snapshots`
instead of `daily_computed_metrics`. Just switch the source table.

**v2 diagnosis (architectural):** The entire design of reading computed metrics from a
**cache table** is wrong. Noop does it correctly: analytics functions are **pure,
compute-on-the-fly from raw data**. No cache, no stale-data problem, no "did the cron
run yet?" question.

```
Noop pattern (correct):              Tracend v1 pattern (broken):
workout_sessions ─┐                  workout_sessions ─┐
health_summaries ─┤                  health_summaries ─┤
body_measurements─┼─→ compute → show                     ├─→ compute → cache
                  │                  body_measurements ─┘         ↓
                  └── pure, always fresh                   read cache → show
                                                                 ↑ GAP: cache may
                                                                 not exist for the
                                                                 requested date
```

`compute_daily_metrics` already computes fresh from raw data (queries
`workout_sessions`, `daily_health_summaries`, etc. directly). The bug is that
`get_my_daily_brief` reads a **cached copy** instead of calling `compute_daily_metrics`.

## What the v1 migration already fixed (deployed, correct, keep)

| Change | Status |
|--------|--------|
| `healthkit_auto_complete_workout` → `session_effort = 5` | Done, future auto-completes get effort |
| Backfill `session_effort = 5` for all existing completed sessions | Done |
| `recompute_stale_metrics` → also process `current_date` (was: only yesterday) | Done |
| `get_my_daily_brief` → read from `daily_computed_metrics` cache | Done, but **still wrong** (gaps remain) |

## What remains broken

### Gap 1: `get_my_daily_brief` depends on cache existing for today

`get_my_daily_brief(target_date)` → `daily_computed_metrics.local_date = target_date`.
If no row exists for today (rest day, no health sync, cron not yet run):
- `computed` → null → all widgets hidden

### Gap 2: `get_my_training_hub` still reads from `feature_snapshots`

The v1 migration only updated `get_my_daily_brief`. `get_my_training_hub` (line 191-200
of `20260724000002`) still reads `feature_snapshots`, which is stale by design
(snapshot at coaching time, not updated on app open).

### Gap 3: No on-demand fallback

Unlike `prepare_coach_chat` (which calls `prepare_daily_coaching` when data is missing,
line 560 of foundation.sql), `get_my_daily_brief` and `get_my_training_hub` never
trigger computation when data is absent. They just return null.

## Fix v2 (1 new forward-only migration)

### 1. `get_my_daily_brief` → compute on-the-fly

Convert from STABLE (read-only cache) to **plpgsql VOLATILE** that calls
`compute_daily_metrics(user_id, target_date, timezone)` directly.

Why this works:
- `compute_daily_metrics` already queries raw tables (`workout_sessions`,
  `daily_health_summaries`, `body_measurements`, `meals`, etc.) — it's a pure
  computation from source data
- The cached `daily_computed_metrics` row is still written (upsert) as a side
  effect, so other consumers like `prepare_coach_chat_v6` still have fast reads
- The app **always** shows accurate data — no more cat-and-mouse with cache
  freshness
- Coach accuracy is **unaffected**: `prepare_daily_coaching` already calls
  `compute_daily_metrics` directly (line 50 of coach_integration.sql)

Performance: `compute_daily_metrics` runs ~8 queries + light math. For a single-user
app this is <500ms. It already runs during coaching anyway.

```
New flow:
app opens → get_my_daily_brief
  → compute_daily_metrics(user_id, today, tz)  ← fresh computation
  → upserts daily_computed_metrics              ← cache for other consumers
  → returns computed scores                    ← app displays
```

### 2. `get_my_training_hub` → switch source

The `latest_computed` CTE currently reads `feature_snapshots` (stale). Switch to
`daily_computed_metrics`. Since `get_my_daily_brief` now populates the cache on every
call, and the Today tab loads before Train tab, the cache will be available.

If the user navigates directly to Train tab before Today tab: the computed section
returns nulls → widgets show '--' gracefully (existing behavior for null data).

## Migration: `20260726XXXXXX_fix_computed_on_the_fly.sql`

```sql
begin;

-- 1. get_my_daily_brief → compute fresh, not from cache
create or replace function public.get_my_daily_brief(
  target_date date default current_date
)
returns jsonb
language plpgsql
security definer
set search_path=''
volatile
as $$
declare
  v_user_id uuid := auth.uid();
  v_timezone text;
  v_metrics jsonb;
begin
  select coalesce(dhs.timezone, 'UTC') into v_timezone
  from public.daily_health_summaries dhs
  where dhs.user_id = v_user_id
    and dhs.source_scope = 'healthkit'
  order by dhs.local_date desc
  limit 1;

  v_metrics := public.compute_daily_metrics(v_user_id, target_date, v_timezone);

  return (
    select jsonb_build_object(
      'schema_version','1.1','local_date',target_date,
      'today_workout',(select value->'today_workout' from (
        select public.get_my_training_hub(28) value) t),
      'next_meal',(select item from (
        select public.get_my_nutrition_schedule(target_date) value) n,
        jsonb_array_elements(value->'items') item
        where item->>'status' in ('due','upcoming','optional')
        order by (item->>'order')::integer limit 1),
      'check_in',(select to_jsonb(c)-'user_id'-'note'-'idempotency_key'
        from public.daily_check_ins c where c.user_id=v_user_id
          and c.local_date=target_date and c.superseded_at is null limit 1),
      'health',(select jsonb_build_object('local_date',d.local_date,
        'last_synced_at',d.last_synced_at,'present_types',d.present_types,
        'completeness',d.completeness)
        from public.daily_health_summaries d
        where d.user_id=v_user_id and d.local_date<=target_date
          and d.local_date>=target_date-31
        order by d.local_date desc,d.last_synced_at desc limit 1),
      'nutrition',public.get_my_daily_nutrition(target_date),
      'computed', v_metrics,
      'latest_decision',(select jsonb_build_object('id',cd.id,
        'final_decision',cd.head_coach->>'final_decision',
        'reason',cd.head_coach->>'reason','confidence',cd.confidence,
        'created_at',cd.created_at,'evidence',cd.evidence,
        'missing_data',cd.missing_data)
        from public.coach_decisions cd where cd.user_id=v_user_id
        order by cd.created_at desc limit 1)
    )
  );
end;
$$;

-- 2. get_my_training_hub → read from daily_computed_metrics (was: feature_snapshots)
create or replace function public.get_my_training_hub(
  period_days integer default 28
)
returns jsonb
language sql
security definer
set search_path=''
stable
as $$
with active_version as (
  select v.id,v.plan_id,v.version_number,v.block_weeks,v.sessions_per_week,
    v.rationale,p.title
  from public.training_plan_versions v
  join public.training_plans p on p.id=v.plan_id and p.user_id=v.user_id
  where v.user_id=auth.uid() and v.status='active'
  limit 1
), workouts as (
  select w.*,
    coalesce((select jsonb_agg(jsonb_build_object(
      'id',ws.id,'local_date',ws.local_date,'state',ws.state,
      'duration_seconds',ws.duration_seconds,'session_effort',ws.session_effort,
      'notes',ws.notes,'started_at',ws.started_at,'completed_at',ws.completed_at
    ) order by ws.local_date desc) from public.workout_sessions ws
      where ws.planned_workout_id=w.id and ws.user_id=auth.uid()
        and ws.local_date >= current_date - period_days
    ), '[]'::jsonb) as sessions
  from public.planned_workouts w
  where w.user_id=auth.uid()
    and w.plan_version_id=(select id from active_version)
    and w.weekday is not null
  order by w.week_number asc,w.weekday asc
), completed_days as (
  select distinct ws.local_date::date from public.workout_sessions ws
  where ws.user_id=auth.uid()
    and ws.state='completed'
    and ws.local_date >= current_date - period_days
), latest_computed as (
  select dcm.scores_jsonb->'acwr' as acwr,
         dcm.scores_jsonb->'training_monotony' as monotony,
         dcm.scores_jsonb->'daily_strain' as today_strain
  from public.daily_computed_metrics dcm
  where dcm.user_id=auth.uid()
    and dcm.local_date=current_date
  order by dcm.computed_at desc limit 1
)
select jsonb_build_object(
  'schema_version','1.1',
  'plan_title',(select title from active_version),
  'today_workout',(select jsonb_build_object(
    'id',w.id,'name',w.name,'week_number',w.week_number,'weekday',w.weekday,
    'estimated_minutes',w.estimated_minutes,'warm_up',w.warm_up,
    'cooldown_cardio',w.cooldown_cardio,'objective',w.objective,
    'exercises',w.exercises,'sessions',w.sessions)
    from public.planned_workouts w
    where w.user_id=auth.uid()
      and w.plan_version_id=(select id from active_version)
      and w.weekday=(extract(dow from current_date)+1)::int
      limit 1),
  'workouts',(select jsonb_agg(to_jsonb(w)-'sessions') from workouts w),
  'completed_days',(select jsonb_agg(local_date) from completed_days),
  'computed',(select jsonb_build_object(
    'acwr',acwr,'monotony',monotony,'daily_strain',today_strain)
    from latest_computed)
);
$$;

commit;
```

## Impact

| Consumer | Before v2 | After v2 |
|----------|-----------|----------|
| Today screen (RecoveryRing, SleepCard, ReadinessStrip) | Reads cache, may be null → hidden | Always fresh, always shown |
| Train screen (TrainingLoadGauge) | Reads stale `feature_snapshots` | Reads fresh `daily_computed_metrics` |
| Progress screen (WeightTrendIndicator) | Reads cache | Always fresh |
| Coach (`prepare_daily_coaching`) | Already fresh (calls compute_daily_metrics) | Unchanged |
| Coach (`prepare_coach_chat_v6`) | Reads `daily_computed_metrics` cache | Now always populated |

## Files changed

- `supabase/migrations/<timestamp>_fix_computed_on_the_fly.sql` — 1 new migration
- No Flutter changes
- No Edge Function changes
- No revert of v1 migration (it's additive, not wrong — just incomplete)

## Verification

- Migration dry-run
- `get_my_daily_brief` always returns computed object (never null for users with data)
- `get_my_training_hub` computed section reads from `daily_computed_metrics`
- Flutter analyze + test (155 tests still pass)
- Build + install to phone, check Train tab and Today tab show real ACWR/strain
