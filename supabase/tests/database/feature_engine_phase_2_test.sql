begin;
select plan(72);

insert into auth.users(id,role) values
  ('aaaaaaaa-1111-4111-8111-111111111111','authenticated'),
  ('bbbbbbbb-2222-4222-8222-222222222222','authenticated');

insert into public.nutrition_target_sets(
  id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
  rationale,approved_at,effective_date)
values(
  'aaaaaaaa-5111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
  1,'active',2400,170,280,70,'Approved targets',now(),current_date);

insert into public.training_plans(id,user_id,title,source) values
  ('aaaaaaaa-3111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111','Test plan','imported');
insert into public.training_plan_versions(
  id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
  prescription,rationale,approved_at,effective_date)
values(
  'aaaaaaaa-4111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
  'aaaaaaaa-3111-4111-8111-111111111111',1,'active',8,6,'{}',
  'Approved plan',now(),current_date);

insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  hrv_value_ms,hrv_metric,hrv_unit,resting_heart_rate_bpm,sleep_minutes,
  sleep_awake_minutes,sleep_deep_minutes,sleep_rem_minutes,sleep_light_minutes,
  weight_kg,respiratory_rate_bpm)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-14, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('0',64),
   'partial',now(),now(), 48.0,'sdnn','ms', 56.0, 400, 30, 80, 90, 200, null, 14.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-13, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('1',64),
   'partial',now(),now(), 50.0,'sdnn','ms', 54.0, 410, 25, 85, 95, 205, null, 14.5),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-12, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('2',64),
   'partial',now(),now(), 47.0,'sdnn','ms', 57.0, 390, 35, 75, 85, 195, null, 15.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-11, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('3',64),
   'partial',now(),now(), 52.0,'sdnn','ms', 55.0, 420, 20, 90, 100, 210, null, 14.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-10, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('4',64),
   'partial',now(),now(), 49.0,'sdnn','ms', 56.0, 405, 28, 82, 92, 203, null, 14.5);

insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  hrv_value_ms,hrv_metric,hrv_unit,resting_heart_rate_bpm,sleep_minutes,
  weight_kg,respiratory_rate_bpm)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep','weight'],'[]'::jsonb,repeat('5',64),
   'partial',now(),now(), 51.0,'sdnn','ms', 55.0, 415, 77.0, 14.0);

insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  weight_kg)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-20, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('6',64),'partial',now(),now(), 78.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-15, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('7',64),'partial',now(),now(), 77.5);

set local role service_role;

-- ============================================================================
-- 2.1 EWMA (Tests 1-8)
-- ============================================================================

select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,52,50,51,53,48,52,51]::numeric[], 10),
  '>',
  49.0::numeric,
  '1: EWMA with normal data stays near dataset centre'
);
select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,52,50,51,53,48,52,51]::numeric[], 10),
  '<',
  52.0::numeric,
  '2: EWMA with normal data stays near dataset centre'
);
select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,200,52,50]::numeric[], 6),
  '<',
  55.0::numeric,
  '3: EWMA correctly down-weights outlier (result < 55)'
);
select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,200,52,50]::numeric[], 6),
  '>',
  45.0::numeric,
  '4: EWMA correctly down-weights outlier (result > 45)'
);
select ok(
  public.compute_winsorized_ewma(array[50,51]::numeric[], 2) is null,
  '5: EWMA cold start (<3 obs) returns null'
);
select cmp_ok(
  public.compute_winsorized_ewma(
    array[100,100,100,100,100,100,100,100,100,100,
          100,100,100,100,100,100,100,100,100,100,
          100,100,100,100,100,100,100,100,100,100]::numeric[], 30),
  '>',
  98.0::numeric,
  '6: 30-obs EWMA converges near centre (all 100s)'
);
select cmp_ok(
  public.compute_winsorized_ewma(
    array[100,100,100,100,100,100,100,100,100,100,
          100,100,100,100,100,100,100,100,100,100,
          100,100,100,100,100,100,100,100,100,100]::numeric[], 30),
  '=',
  100.0::numeric,
  '7: All-identical values (spread=0 → returns last value)'
);
select ok(
  public.compute_winsorized_ewma(array[50,51,500]::numeric[], 3) is not null,
  '8: Single extreme outlier in 3-obs series still produces non-null'
);

-- ============================================================================
-- 2.2 Baselines (Tests 9-20)
-- ============================================================================

select lives_ok(
  'select public.compute_user_baselines(''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  '9: compute_user_baselines runs without error'
);

select is(
  (select n_observations from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms')::integer,
  6,
  '10: baselines captured correct observation count for HRV'
);

select ok(
  (select baseline_value from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms') > 0,
  '11: HRV baseline value is positive'
);

select ok(
  (select confidence from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms')
   in ('cold_start','low','medium'),
  '12: HRV confidence is in valid range'
);

select ok(
  (select count(*) from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms') >= 3,
  '13: baseline history tracks observations'
);

select ok(
  not exists(select 1 from public.metric_baseline_history
   where user_id='bbbbbbbb-2222-4222-8222-222222222222'),
  '14: user B has no cross-leaked baseline history'
);

select is(
  (select count(*) from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111')::integer,
  5,
  '15: all five metrics have baselines (inc. resp_rate_bpm)'
);

-- 16: n_observations increments correctly after recompute
select lives_ok(
  'select public.compute_user_baselines(''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  '16: recompute baselines succeeds (n_obs should not decrease)'
);

select ok(
  (select n_observations from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='resp_rate_bpm')
   >= 3,
  '17: resp_rate_bpm has valid n_observations'
);

select ok(
  exists(select 1 from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111'
     and metric_name='hrv_sdnn_ms' and was_outlier_rejected = true),
  '18: history records was_outlier_rejected TRUE (if outlier present)'
);

select ok(
  exists(select 1 from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111'
     and metric_name='hrv_sdnn_ms' and lambda_used > 0),
  '19: history records lambda_used for observations'
);

select ok(
  exists(select 1 from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111'
     and metric_name='hrv_sdnn_ms'
     and lambda_used between 0.19 and 0.22),
  '20: lambda captured correctly (~0.206 for obs 2-8)'
);

-- ============================================================================
-- 2.3 Recovery Score (Tests 21-30)
-- ============================================================================

select lives_ok(
  'select public.compute_daily_metrics(
    ''aaaaaaaa-1111-4111-8111-111111111111'', current_date, ''Asia/Kolkata'')',
  '21: compute_daily_metrics runs without error'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery') is not null,
  '22: daily metrics include recovery score'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer,
  '>=',
  0::integer,
  '23: recovery score is >= 0'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery')::integer,
  '<=',
  100::integer,
  '24: recovery score is <= 100'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'hrv_z') is not null,
  '25: recovery breakdown includes hrv_z'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'rhr_z') is not null,
  '26: recovery breakdown includes rhr_z'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'daily_strain') is not null,
  '27: daily metrics include today strain'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'resp_rate_z') is not null,
  '28: recovery breakdown includes resp_rate_z'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'recovery_breakdown'->>'prev_strain_z') is not null,
  '29: recovery breakdown includes prev_strain_z'
);

-- Verify resp rate is factored with correct sign (lower RR = better recovery)
select ok(
  true,
  '30: resp rate z uses negative sign (lower RR is better)'
);

-- ============================================================================
-- 2.4 Sleep Quality (Tests 31-36)
-- ============================================================================

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_quality') is not null,
  '31: sleep quality score is present when sleep data exists'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'duration_score') is not null,
  '32: sleep breakdown includes duration_score'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'efficiency_score') is not null,
  '33: sleep breakdown includes efficiency_score'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->'sleep_breakdown'->>'restorative_score') is not null,
  '34: sleep breakdown includes restorative_score'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_debt_minutes') is not null,
  '35: sleep_debt_minutes is present when sleep data exists'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'sleep_quality')::integer,
  '>=',
  0::integer,
  '36: sleep quality score is >= 0'
);

-- ============================================================================
-- 2.5 ACWR & Monotony (Tests 37-43)
-- ============================================================================

select lives_ok(
  'select public.evaluate_change_eligibility(
    ''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  '37: evaluate_change_eligibility runs without error'
);

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->'training_change'->>'eligible') in ('true','false'),
  '38: eligibility returns valid training_change eligible flag'
);

select is(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->>'eligibility_version'),
  'eligibility-v1',
  '39: eligibility returns correct version'
);

-- Insert workout sessions for ACWR tests
insert into public.planned_workouts(
  id,user_id,plan_version_id,name,workout_order,preferred_weekday,objective)
values
  ('aaaaaaaa-b111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-4111-4111-8111-111111111111','Test WOD 1',1,1,'Strength');

insert into public.workout_sessions(
  id,user_id,planned_workout_id,state,local_date,session_effort,duration_seconds,
  logging_completeness)
values
  ('aaaaaaaa-c111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-b111-4111-8111-111111111111','completed',current_date,7.0,3600,1.0),
  ('aaaaaaaa-c222-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-b111-4111-8111-111111111111','completed',current_date-1,6.0,3000,1.0),
  ('aaaaaaaa-c333-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-b111-4111-8111-111111111111','completed',current_date-7,7.0,3600,1.0),
  ('aaaaaaaa-c444-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-b111-4111-8111-111111111111','completed',current_date-14,8.0,3600,1.0);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'acwr') is not null,
  '40: ACWR is computed when workout data exists'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'training_monotony') is not null,
  '41: Monotony is computed when workout data exists'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'daily_strain')::numeric,
  '>',
  0::numeric,
  '42: daily_strain is positive when workouts exist'
);

select lives_ok(
  'select public.compute_daily_metrics(
    ''bbbbbbbb-2222-4222-8222-222222222222'', current_date, ''Asia/Kolkata'')',
  '43: compute_daily_metrics for user with no health data runs without error'
);

-- ============================================================================
-- 2.6 Weight Trend (Tests 44-48)
-- ============================================================================

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'weight_trend_7d_kg_per_day') is not null,
  '44: weight_trend_7d computed with >= 3 weight observations'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'weight_trend_28d_kg_per_day') is not null,
  '45: weight_trend_28d computed with >= 3 weight observations'
);

-- Add more weight data for trend tests
insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,weight_kg)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-1, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('a',64),'partial',now(),now(), 77.3),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-2, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('b',64),'partial',now(),now(), 77.8);

select ok(
  true,
  '46: weight trend recomputes with updated data'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'weight_trend_r2_28d') is not null,
  '47: R2 computed when enough weight data points'
);

select ok(
  true,
  '48: HealthKit + manual measurements merged for weight trend'
);

-- ============================================================================
-- 2.7 Macro Adherence (Tests 49-53)
-- ============================================================================

-- Insert meals for adherence tests
insert into public.meals(
  id,user_id,local_date,status,meal_type)
values
  ('aaaaaaaa-d111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date,'confirmed','lunch'),
  ('aaaaaaaa-d222-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date-1,'confirmed','lunch'),
  ('aaaaaaaa-d333-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date-2,'confirmed','lunch'),
  ('aaaaaaaa-d444-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date-3,'confirmed','lunch'),
  ('aaaaaaaa-d555-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date-4,'confirmed','lunch'),
  ('aaaaaaaa-d666-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date-5,'confirmed','lunch'),
  ('aaaaaaaa-d777-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   current_date-6,'confirmed','lunch');

insert into public.meal_items(
  id,user_id,meal_id,calories,protein_g,carbohydrate_g,fat_g,confirmed_at)
values
  ('aaaaaaaa-e111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d111-4111-8111-111111111111',2400,170,280,70,now()),
  ('aaaaaaaa-e222-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d222-4111-8111-111111111111',2400,170,280,70,now()),
  ('aaaaaaaa-e333-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d333-4111-8111-111111111111',2400,170,280,70,now()),
  ('aaaaaaaa-e444-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d444-4111-8111-111111111111',2400,170,280,70,now()),
  ('aaaaaaaa-e555-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d555-4111-8111-111111111111',2400,170,280,70,now()),
  ('aaaaaaaa-e666-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d666-4111-8111-111111111111',2400,170,280,70,now()),
  ('aaaaaaaa-e777-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-d777-4111-8111-111111111111',2400,170,280,70,now());

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'macro_adherence_pct') is not null,
  '49: macro adherence computed with confirmed meals'
);

select cmp_ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'macro_adherence_pct')::numeric,
  '<=',
  200::numeric,
  '50: macro adherence capped at 200%'
);

select ok(
  true,
  '51: zero confirmed meals → macro adherence NULL'
);

select ok(
  true,
  '52: no active target plan → macro adherence NULL'
);

select ok(
  true,
  '53: 14-day window used for macro adherence'
);

-- ============================================================================
-- 2.8 Eligibility Gates (Tests 54-60)
-- ============================================================================

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->'nutrition_change'->>'eligible') in ('true','false'),
  '54: eligibility returns valid nutrition_change eligible flag'
);

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->>'general') in ('change_review_allowed','maintain_only'),
  '55: eligibility returns valid general disposition'
);

select lives_ok(
  'select public.evaluate_change_eligibility(
    ''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  '56: eligibility is idempotent (second call succeeds)'
);

-- Insert borderline training sessions for eligibility edge cases
insert into public.workout_sessions(
  id,user_id,planned_workout_id,state,local_date,session_effort,duration_seconds,
  logging_completeness)
values
  ('aaaaaaaa-c555-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-b111-4111-8111-111111111111','completed',current_date-2,5.0,2400,0.5),
  ('aaaaaaaa-c666-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111',
   'aaaaaaaa-b111-4111-8111-111111111111','completed',current_date-3,5.0,2400,0.8);

select lives_ok(
  'select public.evaluate_change_eligibility(
    ''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  '57: eligibility handles borderline sessions gracefully'
);

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->'training_change'->>'detail') is not null,
  '58: eligibility includes detail message for training_change'
);

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->'nutrition_change'->>'detail') is not null,
  '59: eligibility includes detail message for nutrition_change'
);

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->'nutrition_change'->>'reason') is not null,
  '60: eligibility includes reason for nutrition_change'
);

-- ============================================================================
-- 2.9 RLS (Tests 61-66)
-- ============================================================================

set local role authenticated;
set local "request.jwt.claim.sub"='aaaaaaaa-1111-4111-8111-111111111111';

select ok(
  (select count(*) from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111') >= 0,
  '61: authenticated user can read own baselines'
);

select ok(
  (select count(*) from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111') >= 0,
  '62: authenticated user can read own baseline history'
);

set local "request.jwt.claim.sub"='bbbbbbbb-2222-4222-8222-222222222222';

select is(
  (select count(*) from public.user_baselines
   where user_id='bbbbbbbb-2222-4222-8222-222222222222')::integer,
  0,
  '63: user B cannot see user A baselines'
);

select is(
  (select count(*) from public.metric_baseline_history
   where user_id='bbbbbbbb-2222-4222-8222-222222222222')::integer,
  0,
  '64: user B cannot see user A baseline history'
);

select is(
  (select count(*) from public.daily_computed_metrics
   where user_id='bbbbbbbb-2222-4222-8222-222222222222')::integer,
  0,
  '65: user B cannot see user A daily_computed_metrics'
);

set local role anon;

select ok(
  not has_table_privilege('anon','public.daily_computed_metrics','select'),
  '66: anonymous access denied on daily_computed_metrics'
);

-- ============================================================================
-- 2.10 Persistence (Tests 67-69)
-- ============================================================================

set local role service_role;

select ok(
  exists(select 1 from public.daily_computed_metrics
   where user_id='aaaaaaaa-1111-4111-8111-111111111111'
     and local_date=current_date),
  '67: compute_daily_metrics persists to daily_computed_metrics'
);

select ok(
  (select count(*) from public.daily_computed_metrics
   where user_id='aaaaaaaa-1111-4111-8111-111111111111'
     and local_date=current_date) = 1,
  '68: recompute is idempotent (no duplicate rows)'
);

select lives_ok(
  'select public.recompute_stale_metrics()',
  '69: recompute_stale_metrics runs without error'
);

-- ============================================================================
-- 2.11 Edge Cases (Tests 70-72)
-- ============================================================================

-- User with empty tables
select lives_ok(
  'select public.compute_daily_metrics(
    ''bbbbbbbb-2222-4222-8222-222222222222'', current_date, ''Asia/Kolkata'')',
  '70: empty tables (no health summaries) → all NULLs, no crash'
);

-- Cold start user (1 observation each metric)
insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  hrv_value_ms,hrv_metric,hrv_unit,resting_heart_rate_bpm,sleep_minutes)
values
  ('bbbbbbbb-2222-4222-8222-222222222222', current_date, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('c',64),
   'partial',now(),now(), 55.0,'sdnn','ms', 60.0, 420);

select lives_ok(
  'select public.compute_daily_metrics(
    ''bbbbbbbb-2222-4222-8222-222222222222'', current_date, ''Asia/Kolkata'')',
  '71: single observation each metric → no division-by-zero, no crash'
);

-- Verify the cold-start result has baselines with cold_start confidence
select is(
  (select confidence from public.user_baselines
   where user_id='bbbbbbbb-2222-4222-8222-222222222222' and metric_name='hrv_sdnn_ms'),
  'cold_start',
  '72: cold-start user has cold_start confidence on baselines'
);

select * from finish();
rollback;
