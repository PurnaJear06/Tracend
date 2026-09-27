begin;
select plan(23);

insert into auth.users(id,role) values
  ('f1111111-aaaa-4111-8111-111111111111','authenticated');
insert into public.training_plans(id,user_id,title,source) values
  ('f3111111-aaaa-4111-8111-111111111111','f1111111-aaaa-4111-8111-111111111111','V7 plan','imported');
insert into public.training_plan_versions(
  id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
  prescription,rationale,approved_at,effective_date)
values(
  'f4111111-aaaa-4111-8111-111111111111','f1111111-aaaa-4111-8111-111111111111',
  'f3111111-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Approved fixture',
  now(),current_date);
insert into public.nutrition_target_sets(
  id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
  rationale,approved_at,effective_date)
values(
  'f5111111-aaaa-4111-8111-111111111111','f1111111-aaaa-4111-8111-111111111111',
  1,'active',2200,150,240,70,'Approved fixture',now(),current_date);
insert into public.coach_threads(id,user_id,title,status)
values(
  'f7111111-aaaa-4111-8111-111111111111','f1111111-aaaa-4111-8111-111111111111',
  'V7 thread','active');

-- Stale health must not count as today's health evidence.
insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,steps)
values(
  'f1111111-aaaa-4111-8111-111111111111',current_date-1,'Asia/Kolkata',
  array['steps'],'[]'::jsonb,repeat('f',64),'partial',now(),now(),1000);

set local role service_role;

select has_function(
  'public'::name, 'derive_daily_coaching_evidence',
  array['jsonb','boolean','integer','boolean'],
  '1: shared evidence helper exists');

select ok(
  to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{"recovery":35},"data_confidence":"medium"}'::jsonb,true,0,false
  )) ? 'RECOVERY_BELOW_BASELINE',
  '2: poor recovery emits RECOVERY_BELOW_BASELINE');

select ok(
  not (to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{"recovery":35},"data_confidence":"medium"}'::jsonb,true,0,false
  )) ?| array['RECOVERY_WITHIN_BASELINE','CHECK_IN_RECOVERY_MIXED']),
  '3: poor recovery emits no conflicting recovery code');

select ok(
  to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{"recovery":45},"data_confidence":"medium"}'::jsonb,true,0,false
  )) ? 'CHECK_IN_RECOVERY_MIXED',
  '4: 40-49 recovery retains the legacy mixed-band code');

select ok(
  to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{"recovery":72},"data_confidence":"medium"}'::jsonb,true,0,false
  )) ? 'RECOVERY_WITHIN_BASELINE',
  '5: good recovery emits RECOVERY_WITHIN_BASELINE');

select ok(
  not (to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{"recovery":null},"data_confidence":"low"}'::jsonb,true,0,false
  )) ?| array['RECOVERY_WITHIN_BASELINE','RECOVERY_BELOW_BASELINE','CHECK_IN_RECOVERY_MIXED']),
  '6: NULL recovery emits no recovery evidence code');

select ok(
  not (to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{"recovery":null},"data_confidence":"low"}'::jsonb,false,null,false
  )) ? 'CHECK_IN_RECOVERY_MIXED'),
  '7: missing check-in cannot invent mixed recovery');

select ok(
  not (to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{},"data_confidence":"low"}'::jsonb,false,null,false
  )) ? 'HEALTH_CONTEXT_AVAILABLE'),
  '8: stale or absent health emits no health-context code');

select ok(
  to_jsonb(public.derive_daily_coaching_evidence(
    '{"scores":{},"data_confidence":"low"}'::jsonb,false,null,true
  )) ? 'HEALTH_CONTEXT_AVAILABLE',
  '9: same-date health emits health-context code');

select has_function(
  'public'::name, 'prepare_coach_chat_v7',
  array['uuid','uuid','text','text','uuid','text'],
  '10: prepare_coach_chat_v7 exists');

select ok(
  not has_function_privilege('anon',
    'public.prepare_coach_chat_v7(uuid,uuid,text,text,uuid,text)','execute'),
  '11: v7 is not executable by anon');

select ok(
  has_function_privilege('service_role',
    'public.prepare_coach_chat_v7(uuid,uuid,text,text,uuid,text)','execute'),
  '12: v7 is executable by service_role');

select has_function(
  'public'::name, 'prepare_coach_chat_v6',
  array['uuid','uuid','text','text','uuid','text'],
  '13: prepare_coach_chat_v6 remains available for rollback');

create temporary table daily_prepared as
select public.prepare_daily_coaching(
  'f1111111-aaaa-4111-8111-111111111111',current_date,'Asia/Kolkata',
  'f6111111-aaaa-4111-8111-111111111111') value;

create temporary table chat_prepared as
select public.prepare_coach_chat_v7(
  'f1111111-aaaa-4111-8111-111111111111',
  'f7111111-aaaa-4111-8111-111111111111',
  'How is my recovery today?','Asia/Kolkata',gen_random_uuid(),'recovery') value;

select ok(
  not ((select value->'context'->'permitted_evidence' from chat_prepared)
    ?| array['RECOVERY_WITHIN_BASELINE','RECOVERY_BELOW_BASELINE','CHECK_IN_RECOVERY_MIXED']),
  '14: v7 emits no recovery code when fresh recovery is NULL');

select is(
  (select value->'context'->'computed_metrics'->>'local_date' from chat_prepared),
  current_date::text,
  '15: v7 computed scores are aligned to the coaching date');

select is(
  (select value->'context'->'permitted_evidence' from chat_prepared),
  (select value->'permitted_evidence' from daily_prepared),
  '16: chat and daily decision evidence are identical for one user/date');

select ok(
  not ((select value->'context'->'permitted_evidence' from chat_prepared)
    ? 'HEALTH_CONTEXT_AVAILABLE'),
  '17: v7 uses the same-date health window, not the old two-day chat window');

select is(
  (select value->'context'->>'schema_version' from chat_prepared),
  '7.0',
  '18: v7 context shape is versioned');

select lives_ok($$select public.persist_daily_coaching_result_v2(
  'f1111111-aaaa-4111-8111-111111111111',
  (select (value->>'feature_snapshot_id')::uuid from daily_prepared),
  (select (value->>'policy_evaluation_id')::uuid from daily_prepared),
  'f6111111-aaaa-4111-8111-111111111111',
  ('{"schema_version":"1.0","decision_kind":"daily","local_date":"'||current_date||'",
    "training":{"action":"GATHER_DATA","summary":"Add a check-in.","today_adjustments":[]},
    "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Maintain targets.","today_adjustments":[]},
    "head_coach":{"final_decision":"Keep the approved plan.","reason":"Recovery was not measured."},
    "evidence":[],"confidence":"low","missing_data":["recovery_check_in","health_context"],
    "risk_flags":[],"change_proposals":[]}')::jsonb,
  10,'mock','deterministic-mock-v2',0,0,0)$$,
  '19: coach-decide persistence path remains valid on a NULL-recovery day');

select is(
  (select count(*) from public.coach_decisions
    where user_id='f1111111-aaaa-4111-8111-111111111111'),
  1::bigint,
  '20: NULL-recovery daily decision is persisted once');

-- Simulated scoring-engine failure; the replacement rolls back with the test.
reset role;
create or replace function public.compute_daily_metrics(
  target_user_id uuid,
  target_date date,
  target_timezone text
)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  raise exception 'simulated scoring failure';
end $$;
set local role service_role;

select lives_ok(
  $$create temporary table chat_scoring_failed as
    select public.prepare_coach_chat_v7(
      'f1111111-aaaa-4111-8111-111111111111',
      'f7111111-aaaa-4111-8111-111111111111',
      'How is my recovery today?','Asia/Kolkata',gen_random_uuid(),'recovery') value$$,
  '21: v7 stays available when compute_daily_metrics raises');

select is(
  (select value->'context'->'computed_metrics'->>'unavailable' from chat_scoring_failed),
  'true',
  '22: a scoring failure surfaces as computed scores unavailable');

select is(
  (select value->'context'->'permitted_evidence' from chat_scoring_failed),
  '["APPROVED_PLAN_ACTIVE"]'::jsonb,
  '23: a scoring failure permits only non-score evidence codes');

select * from finish();
rollback;
