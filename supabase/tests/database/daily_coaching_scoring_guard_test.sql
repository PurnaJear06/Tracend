begin;
select plan(7);

-- An athlete whose day has no daily snapshot yet, so the first chat creates it.
insert into auth.users(id,role) values
  ('f1999999-aaaa-4111-8111-111111111111','authenticated');
insert into public.training_plans(id,user_id,title,source) values
  ('f3999999-aaaa-4111-8111-111111111111','f1999999-aaaa-4111-8111-111111111111','Guard plan','imported');
insert into public.training_plan_versions(
  id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
  prescription,rationale,approved_at,effective_date)
values(
  'f4999999-aaaa-4111-8111-111111111111','f1999999-aaaa-4111-8111-111111111111',
  'f3999999-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Approved fixture',
  now(),current_date);
insert into public.nutrition_target_sets(
  id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
  rationale,approved_at,effective_date)
values(
  'f5999999-aaaa-4111-8111-111111111111','f1999999-aaaa-4111-8111-111111111111',
  1,'active',2000,140,220,65,'Approved fixture',now(),current_date);
insert into public.coach_threads(id,user_id,title,status)
values(
  'f7999999-aaaa-4111-8111-111111111111','f1999999-aaaa-4111-8111-111111111111',
  'Guard thread','active');

-- Simulated scoring-engine failure; the replacement rolls back with the test.
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

select is(
  (select count(*) from public.feature_snapshots
    where user_id='f1999999-aaaa-4111-8111-111111111111' and trigger_kind='daily'),
  0::bigint,
  '1: the day starts without a daily snapshot');

select lives_ok(
  $$create temporary table first_chat as select public.prepare_coach_chat_v8(
    'f1999999-aaaa-4111-8111-111111111111','f7999999-aaaa-4111-8111-111111111111',
    'How is my recovery today?','Asia/Kolkata',gen_random_uuid(),'recovery') value$$,
  '2: the first chat of the day survives a scoring failure');

select is(
  (select value->'context'->'computed_metrics'->>'unavailable' from first_chat),
  'true',
  '3: chat says computed scores are unavailable');

select is(
  (select value->'context'->'permitted_evidence' from first_chat),
  '["APPROVED_PLAN_ACTIVE"]'::jsonb,
  '4: chat permits only non-score evidence');

select is(
  (select features->>'scores_unavailable' from public.feature_snapshots
    where user_id='f1999999-aaaa-4111-8111-111111111111' and trigger_kind='daily'),
  'true',
  '5: the stored daily snapshot records that scores were unavailable');

select lives_ok(
  $$select public.prepare_coach_chat_v8(
    'f1999999-aaaa-4111-8111-111111111111','f7999999-aaaa-4111-8111-111111111111',
    'And tomorrow?','Asia/Kolkata',gen_random_uuid(),'general')$$,
  '6: later chats that day reuse the stored snapshot');

select is(
  (select public.prepare_daily_coaching(
    'f1999999-aaaa-4111-8111-111111111111',current_date,'Asia/Kolkata',gen_random_uuid())
    ->'permitted_evidence'),
  '["APPROVED_PLAN_ACTIVE"]'::jsonb,
  '7: the coach-decide path degrades the same way instead of failing');

select * from finish();
rollback;
