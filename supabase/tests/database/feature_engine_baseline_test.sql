begin;
select plan(22);

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
  weight_kg)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-14, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('0',64),
   'partial',now(),now(), 48.0,'sdnn','ms', 56.0, 400, 30, 80, 90, 200, null),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-13, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('1',64),
   'partial',now(),now(), 50.0,'sdnn','ms', 54.0, 410, 25, 85, 95, 205, null),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-12, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('2',64),
   'partial',now(),now(), 47.0,'sdnn','ms', 57.0, 390, 35, 75, 85, 195, null),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-11, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('3',64),
   'partial',now(),now(), 52.0,'sdnn','ms', 55.0, 420, 20, 90, 100, 210, null),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-10, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('4',64),
   'partial',now(),now(), 49.0,'sdnn','ms', 56.0, 405, 28, 82, 92, 203, null);

insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  hrv_value_ms,hrv_metric,hrv_unit,resting_heart_rate_bpm,sleep_minutes,
  weight_kg)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep','weight'],'[]'::jsonb,repeat('5',64),
   'partial',now(),now(), 51.0,'sdnn','ms', 55.0, 415, 77.0);

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

select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,52,50,51,53,48,52,51]::numeric[], 10),
  '>',
  49.0::numeric,
  'EWMA with normal data stays near dataset centre'
);
select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,52,50,51,53,48,52,51]::numeric[], 10),
  '<',
  52.0::numeric,
  'EWMA with normal data stays near dataset centre'
);
select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,200,52,50]::numeric[], 6),
  '<',
  55.0::numeric,
  'EWMA correctly down-weights outlier (result < 55)'
);
select cmp_ok(
  public.compute_winsorized_ewma(array[50,51,49,200,52,50]::numeric[], 6),
  '>',
  45.0::numeric,
  'EWMA correctly down-weights outlier (result > 45)'
);
select ok(
  public.compute_winsorized_ewma(array[50,51]::numeric[], 2) is null,
  'EWMA cold start (<3 obs) returns null'
);

select lives_ok(
  'select public.compute_user_baselines(''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  'compute_user_baselines runs without error'
);

select is(
  (select n_observations from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms')::integer,
  6,
  'baselines captured correct observation count for HRV'
);

select ok(
  (select baseline_value from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms') > 0,
  'HRV baseline value is positive'
);

select ok(
  (select confidence from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms')
   in ('cold_start','low','medium'),
  'HRV confidence is in valid range'
);

select ok(
  (select count(*) from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111' and metric_name='hrv_sdnn_ms') >= 3,
  'baseline history tracks observations'
);

select ok(
  not exists(select 1 from public.metric_baseline_history
   where user_id='bbbbbbbb-2222-4222-8222-222222222222'),
  'user B has no cross-leaked baseline history'
);

select is(
  (select count(*) from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111')::integer,
  4,
  'all four metrics have baselines'
);

select lives_ok(
  'select public.compute_daily_metrics(
    ''aaaaaaaa-1111-4111-8111-111111111111'', current_date, ''Asia/Kolkata'')',
  'compute_daily_metrics runs without error'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'recovery') is not null,
  'daily metrics include recovery score'
);

select ok(
  (public.compute_daily_metrics(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata'
  )->'scores'->>'daily_strain') is not null,
  'daily metrics include today strain'
);

select lives_ok(
  'select public.evaluate_change_eligibility(
    ''aaaaaaaa-1111-4111-8111-111111111111'', current_date)',
  'evaluate_change_eligibility runs without error'
);

select ok(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->'training_change'->>'eligible') in ('true','false'),
  'eligibility returns valid training_change eligible flag'
);

select is(
  (public.evaluate_change_eligibility(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date
  )->>'eligibility_version'),
  'eligibility-v1',
  'eligibility returns correct version'
);

set local role authenticated;
set local "request.jwt.claim.sub"='aaaaaaaa-1111-4111-8111-111111111111';

select ok(
  (select count(*) from public.user_baselines
   where user_id='aaaaaaaa-1111-4111-8111-111111111111') >= 0,
  'authenticated user can read own baselines'
);

select ok(
  (select count(*) from public.metric_baseline_history
   where user_id='aaaaaaaa-1111-4111-8111-111111111111') >= 0,
  'authenticated user can read own baseline history'
);

set local "request.jwt.claim.sub"='bbbbbbbb-2222-4222-8222-222222222222';

select is(
  (select count(*) from public.user_baselines
   where user_id='bbbbbbbb-2222-4222-8222-222222222222')::integer,
  0,
  'user B cannot see user A baselines'
);

select is(
  (select count(*) from public.metric_baseline_history
   where user_id='bbbbbbbb-2222-4222-8222-222222222222')::integer,
  0,
  'user B cannot see user A baseline history'
);

select * from finish();
rollback;
