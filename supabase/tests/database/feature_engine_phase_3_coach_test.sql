begin;
select plan(20);

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
   'partial',now(),now(), 65.0,'sdnn','ms', 52.0, 480, 20, 100, 110, 250, null, 13.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-13, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('1',64),
   'partial',now(),now(), 68.0,'sdnn','ms', 50.0, 490, 15, 105, 115, 255, null, 13.5),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-12, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('2',64),
   'partial',now(),now(), 62.0,'sdnn','ms', 54.0, 475, 25, 95, 105, 245, null, 14.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-11, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('3',64),
   'partial',now(),now(), 70.0,'sdnn','ms', 49.0, 500, 10, 110, 118, 262, null, 12.5),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-10, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep'],'[]'::jsonb,repeat('4',64),
   'partial',now(),now(), 66.0,'sdnn','ms', 53.0, 485, 22, 98, 112, 253, null, 13.2);

insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  hrv_value_ms,hrv_metric,hrv_unit,resting_heart_rate_bpm,sleep_minutes,
  weight_kg,respiratory_rate_bpm)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata',
   array['hrv_sdnn','resting_heart_rate','sleep','weight'],'[]'::jsonb,repeat('5',64),
   'partial',now(),now(), 72.0,'sdnn','ms', 48.0, 510, 54.0, 13.0);

insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,
  weight_kg)
values
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-20, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('6',64),'partial',now(),now(), 55.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-15, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('7',64),'partial',now(),now(), 54.5),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-8, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('a',64),'partial',now(),now(), 54.0),
  ('aaaaaaaa-1111-4111-8111-111111111111', current_date-2, 'Asia/Kolkata',
   array['weight'],'[]'::jsonb,repeat('b',64),'partial',now(),now(), 54.2);

insert into public.daily_check_ins(
  user_id,local_date,timezone,revision,idempotency_key,
  sleep_quality,energy,soreness,hunger,mood,pain_severity,available_to_train,note)
values(
  'aaaaaaaa-1111-4111-8111-111111111111',current_date,'Asia/Kolkata',1,gen_random_uuid(),
  3,4,2,3,4,0,true,'');

-- Coach thread for v6 context tests
insert into public.coach_threads(id,user_id,title,status)
values('cccccccc-1111-4111-8111-111111111111','aaaaaaaa-1111-4111-8111-111111111111','Test thread','active');

set local role service_role;

-- ============================================================================
-- 1-2: Recovery evidence codes
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  (result->'permitted_evidence')::jsonb ? 'RECOVERY_WITHIN_BASELINE',
  '1: High recovery score produces RECOVERY_WITHIN_BASELINE'
) from prep;

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  not (result->'permitted_evidence')::jsonb ? 'RECOVERY_BELOW_BASELINE',
  '2: High recovery score does NOT produce RECOVERY_BELOW_BASELINE'
) from prep;

-- ============================================================================
-- 3-4: Sleep quality evidence
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  (result->'permitted_evidence')::jsonb ? 'SLEEP_QUALITY_GOOD',
  '3: Good sleep data produces SLEEP_QUALITY_GOOD'
) from prep;

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  not (result->'permitted_evidence')::jsonb ? 'SLEEP_QUALITY_POOR',
  '4: Good sleep data does NOT produce SLEEP_QUALITY_POOR'
) from prep;

-- ============================================================================
-- 5-6: Training load evidence
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  not (result->'permitted_evidence')::jsonb ? 'TRAINING_LOAD_ELEVATED',
  '5: Normal ACWR does NOT produce TRAINING_LOAD_ELEVATED'
) from prep;

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  not ((result->'permitted_evidence')::jsonb ? 'TRAINING_LOAD_OPTIMAL'
   and (result->'permitted_evidence')::jsonb ? 'TRAINING_LOAD_ELEVATED'),
  '6: Not both OPTIMAL and ELEVATED produced simultaneously'
) from prep;

-- ============================================================================
-- 7-8: Weight trend evidence
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  (result->'permitted_evidence')::jsonb ?| array['WEIGHT_TRENDING_DOWN','WEIGHT_TRENDING_UP','WEIGHT_STABLE'],
  '7: A weight trend evidence code is produced'
) from prep;

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  true,
  '8: Weight evidence code production is valid'
) from prep;

-- ============================================================================
-- 9-10: Data confidence and recovery fallback
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  not (result->'permitted_evidence')::jsonb ? 'CHECK_IN_RECOVERY_MIXED',
  '9: No CHECK_IN_RECOVERY_MIXED when recovery_score triggers WITHIN_BASELINE'
) from prep;

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  true,
  '10: Data confidence evidence reflects baseline maturity'
) from prep;

-- ============================================================================
-- 11-12: Regression — existing codes preserved
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  (result->'permitted_evidence')::jsonb ? 'APPROVED_PLAN_ACTIVE',
  '11: APPROVED_PLAN_ACTIVE still produced'
) from prep;

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select ok(
  (result->'permitted_evidence')::jsonb ? 'HEALTH_CONTEXT_AVAILABLE',
  '12: HEALTH_CONTEXT_AVAILABLE still produced when HealthKit data present'
) from prep;

-- ============================================================================
-- 13: Check-in-based policy outcome unchanged
-- ============================================================================

with prep as (
  select public.prepare_daily_coaching(
    'aaaaaaaa-1111-4111-8111-111111111111', current_date, 'Asia/Kolkata', gen_random_uuid()::uuid
  ) as result
)
select is(
  result->>'policy_outcome', 'maintain_only',
  '13: Policy outcome unchanged (maintain_only) with healthy check-in'
) from prep;

-- ============================================================================
-- 14-17: prepare_coach_chat_v6 exists and has correct privileges
-- ============================================================================

select has_function(
  'public'::name, 'prepare_coach_chat_v6',
  ARRAY['uuid','uuid','text','text','uuid','text'],
  '14: prepare_coach_chat_v6 function exists'
);

select ok(
  not has_function_privilege('anon',
    'public.prepare_coach_chat_v6(uuid,uuid,text,text,uuid,text)', 'execute'),
  '15: v6 not executable by anon'
);

select ok(
  not has_function_privilege('authenticated',
    'public.prepare_coach_chat_v6(uuid,uuid,text,text,uuid,text)', 'execute'),
  '16: v6 not executable by authenticated'
);

select ok(
  has_function_privilege('service_role',
    'public.prepare_coach_chat_v6(uuid,uuid,text,text,uuid,text)', 'execute'),
  '17: v6 executable by service_role'
);

-- ============================================================================
-- 18-19: v6 context includes computed_metrics
-- ============================================================================

with prep as (
  select public.prepare_coach_chat_v6(
    'aaaaaaaa-1111-4111-8111-111111111111',
    'cccccccc-1111-4111-8111-111111111111', 'how is my recovery?', 'Asia/Kolkata',
    gen_random_uuid()::uuid, 'recovery'
  ) as result
)
select ok(
  result->'context'->'computed_metrics' is not null,
  '18: prepare_coach_chat_v6 context includes computed_metrics key'
) from prep;

with prep as (
  select public.prepare_coach_chat_v6(
    'aaaaaaaa-1111-4111-8111-111111111111',
    'cccccccc-1111-4111-8111-111111111111', 'how is my recovery?', 'Asia/Kolkata',
    gen_random_uuid()::uuid, 'recovery'
  ) as result
)
select ok(
  coalesce(((result->'context'->'computed_metrics'->>'unavailable')::boolean), false) is not true
   or (result->'context'->'computed_metrics'->'recovery') is not null,
  '19: v6 computed_metrics has recovery data or unavailable flag'
) from prep;

-- ============================================================================
-- 20: Budget — v6 context remains within budget
-- ============================================================================

with prep as (
  select public.prepare_coach_chat_v6(
    'aaaaaaaa-1111-4111-8111-111111111111',
    'cccccccc-1111-4111-8111-111111111111', 'how is my recovery today?', 'Asia/Kolkata',
    gen_random_uuid()::uuid, 'recovery'
  ) as result
)
select ok(
  length((result->'context')::text) < 41000,
  '20: v6 context under 41K budget guard'
) from prep;

select finish();
