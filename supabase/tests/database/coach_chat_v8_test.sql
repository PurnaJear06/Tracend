begin;
select plan(45);

insert into auth.users(id,role) values
  ('f1888888-aaaa-4111-8111-111111111111','authenticated');
insert into public.training_plans(id,user_id,title,source) values
  ('f3888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111','V8 plan','imported');
insert into public.training_plan_versions(
  id,user_id,plan_id,version_number,status,block_weeks,sessions_per_week,
  prescription,rationale,approved_at,effective_date)
values(
  'f4888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111',
  'f3888888-aaaa-4111-8111-111111111111',1,'active',4,3,'{}','Approved fixture',
  now(),current_date);
insert into public.nutrition_target_sets(
  id,user_id,version_number,status,calories,protein_g,carbohydrate_g,fat_g,
  rationale,approved_at,effective_date)
values(
  'f5888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111',
  1,'active',1900,150,190,60,'Approved fixture',now(),current_date);
insert into public.coach_threads(id,user_id,title,status)
values(
  'f7888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111',
  'New conversation','active');

-- Three completed sessions: 1, 10 and 20 days ago. The newest has two
-- completed sets (10 x 50 kg + 8 x 60 kg = 980 kg) and one skipped set.
insert into public.planned_workouts(
  id,user_id,plan_version_id,workout_order,name,objective,preferred_weekday,
  estimated_minutes,warm_up_guidance,cool_down_guidance)
values(
  'fd888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111',
  'f4888888-aaaa-4111-8111-111111111111',7,'Push day','Build strength.',1,60,
  'Warm up.','Cool down.');
insert into public.planned_exercises(
  id,user_id,planned_workout_id,exercise_order,display_name_snapshot,set_count,
  rep_min,rep_max,target_rpe,rest_seconds)
values(
  'fe888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111',
  'fd888888-aaaa-4111-8111-111111111111',1,'Bench press',3,8,10,8,120);
insert into public.workout_sessions(
  id,user_id,plan_version_id,planned_workout_id,state,local_date,timezone,
  idempotency_key,session_effort,duration_seconds,logging_completeness,completed_at)
select v.id,'f1888888-aaaa-4111-8111-111111111111','f4888888-aaaa-4111-8111-111111111111',
  'fd888888-aaaa-4111-8111-111111111111','completed',current_date - v.days_ago,
  'Asia/Kolkata',gen_random_uuid(),7,3600,1.0,now()
from (values
  ('f9888888-aaaa-4111-8111-000000000001'::uuid,1),
  ('f9888888-aaaa-4111-8111-000000000010'::uuid,10),
  ('f9888888-aaaa-4111-8111-000000000020'::uuid,20)) v(id,days_ago);
insert into public.exercise_performances(
  id,user_id,workout_session_id,planned_exercise_id,exercise_order,status)
values(
  'fa888888-aaaa-4111-8111-111111111111','f1888888-aaaa-4111-8111-111111111111',
  'f9888888-aaaa-4111-8111-000000000001','fe888888-aaaa-4111-8111-111111111111',1,'performed');
insert into public.exercise_sets(
  user_id,exercise_performance_id,set_number,repetitions,load_kg,rpe,completed)
values
  ('f1888888-aaaa-4111-8111-111111111111','fa888888-aaaa-4111-8111-111111111111',1,10,50,7,true),
  ('f1888888-aaaa-4111-8111-111111111111','fa888888-aaaa-4111-8111-111111111111',2,8,60,8,true),
  ('f1888888-aaaa-4111-8111-111111111111','fa888888-aaaa-4111-8111-111111111111',3,5,60,9,false);

-- Weight: an amended reading must be replaced by its amendment.
insert into public.body_measurements(id,user_id,measured_on,source,weight_kg)
values
  ('fb888888-aaaa-4111-8111-000000000001','f1888888-aaaa-4111-8111-111111111111',current_date-30,'manual',79.5),
  ('fb888888-aaaa-4111-8111-000000000002','f1888888-aaaa-4111-8111-111111111111',current_date-2,'manual',99.9);
insert into public.body_measurements(user_id,measured_on,source,weight_kg,amended_from_id)
values('f1888888-aaaa-4111-8111-111111111111',current_date-2,'manual',78.4,
  'fb888888-aaaa-4111-8111-000000000002');

set local role service_role;

select has_function(
  'public'::name, 'build_coach_athlete_context', array['uuid','date','text'],
  '1: athlete-context helper exists');

select has_function(
  'public'::name, 'prepare_coach_chat_v8', array['uuid','uuid','text','text','uuid','text'],
  '2: prepare_coach_chat_v8 exists');

select ok(
  not has_function_privilege('anon',
    'public.prepare_coach_chat_v8(uuid,uuid,text,text,uuid,text)','execute'),
  '3: v8 is not executable by anon');

select ok(
  has_function_privilege('service_role',
    'public.prepare_coach_chat_v8(uuid,uuid,text,text,uuid,text)','execute'),
  '4: v8 is executable by service_role');

select has_function(
  'public'::name, 'prepare_coach_chat_v7', array['uuid','uuid','text','text','uuid','text'],
  '5: prepare_coach_chat_v7 remains available for rollback');

create temporary table v8_by_kind as
select kind, public.prepare_coach_chat_v8(
  'f1888888-aaaa-4111-8111-111111111111',
  'f7888888-aaaa-4111-8111-111111111111',
  'Check my last two weeks workload and how long until 72 kg at 1900 kcal?',
  'Asia/Kolkata', gen_random_uuid(), kind) value
from unnest(array['recovery','nutrition_focus','daily_action','plan_change',
  'explain_evidence','general']) kind;

select is(
  (select count(distinct (select string_agg(k, ',' order by k)
    from jsonb_object_keys(value->'context') k)) from v8_by_kind),
  1::bigint,
  '6: every question kind receives the same context sections');

select ok(
  (select bool_and(value->'context' ?& array[
    'training_log_28d','training_totals','watch_workouts_14d','training_week_structure',
    'health_daily_28d','health_averages','weight_series_8w','check_ins_14d',
    'nutrition_daily_28d','today_confirmed_meals','nutrition_adherence',
    'nutrition_targets','active_plan','computed_metrics','permitted_evidence',
    'recent_messages','data_quality','omitted_sections']) from v8_by_kind),
  '7: the full athlete file reaches recovery, nutrition, daily, plan, evidence and general questions');

select is(
  (select value->'context'->>'schema_version' from v8_by_kind where kind='nutrition_focus'),
  '8.0',
  '8: v8 context shape is versioned');

select is(
  (select value->'context'->>'context_kind' from v8_by_kind where kind='nutrition_focus'),
  'nutrition_focus',
  '9: the classified kind is kept for telemetry only');

select is(
  (select value->'context'->'omitted_sections' from v8_by_kind where kind='general'),
  '[]'::jsonb,
  '10: a normal-sized file omits nothing');

select is(
  (select jsonb_array_length(value->'context'->'training_log_28d') from v8_by_kind where kind='recovery'),
  3,
  '11: the 28-day training log lists every completed session');

select is(
  (select value->'context'->'training_totals'->'last_14_days'->>'sessions' from v8_by_kind where kind='recovery'),
  '2',
  '12: 14-day totals count sessions inside the window only');

select is(
  (select value->'context'->'training_totals'->'last_7_days'->>'volume_kg' from v8_by_kind where kind='recovery'),
  '980.0',
  '13: volume counts completed sets only (10x50 + 8x60)');

select is(
  (select value->'context'->'training_log_28d'->0->>'completed_sets' from v8_by_kind where kind='recovery'),
  '2',
  '14: the newest session reports its completed sets');

select is(
  (select value->'context'->'weight_series_8w'->0->>'weight_kg' from v8_by_kind where kind='recovery'),
  '78.40',
  '15: an amended weight is replaced by its amendment');

select is(
  (select jsonb_array_length(value->'context'->'weight_series_8w') from v8_by_kind where kind='recovery'),
  2,
  '16: the weight series keeps readings from the last eight weeks');

select is(
  (select context->>'schema_version' from public.coach_context_snapshots
    where id = (select (value->>'coach_context_snapshot_id')::uuid from v8_by_kind where kind='general')),
  '8.0',
  '17: the audit snapshot stores the context the model received');

-- The question is saved when the turn starts and survives a failed answer.
select lives_ok(
  $$select public.record_coach_chat_question(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'How long until 72 kg?','fc888888-aaaa-4111-8111-111111111111')$$,
  '18: the question is recorded before the model runs');

select lives_ok(
  $$select public.record_coach_chat_question(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'How long until 72 kg?','fc888888-aaaa-4111-8111-111111111111')$$,
  '19: recording the same request twice is safe');

select is(
  (select count(*) from public.coach_messages
    where thread_id='f7888888-aaaa-4111-8111-111111111111' and role='user'),
  1::bigint,
  '20: one request stores one user message');

select is(
  (select title from public.coach_threads where id='f7888888-aaaa-4111-8111-111111111111'),
  'How long until 72 kg?',
  '21: the first question names a new conversation');

select lives_ok(
  $$select public.persist_failed_coach_chat_run(
    'f1888888-aaaa-4111-8111-111111111111',
    (select (value->>'feature_snapshot_id')::uuid from v8_by_kind where kind='general'),
    (select (value->>'policy_evaluation_id')::uuid from v8_by_kind where kind='general'),
    'fc888888-aaaa-4111-8111-111111111111',1200,'provider_response_invalid','deepseek',
    'deepseek-v4-flash',array['reasoning_step_too_long','evidence_code_not_permitted'])$$,
  '22: a failed DeepSeek run is recorded');

select is(
  (select metadata->'rules' from public.audit_events
    where user_id='f1888888-aaaa-4111-8111-111111111111'
      and action_code='coach.chat.model_run.failed'),
  '["reasoning_step_too_long", "evidence_code_not_permitted"]'::jsonb,
  '23: the failure record keeps the finite rule names');

select throws_ok(
  $$select public.persist_failed_coach_chat_run(
    'f1888888-aaaa-4111-8111-111111111111',
    (select (value->>'feature_snapshot_id')::uuid from v8_by_kind where kind='general'),
    (select (value->>'policy_evaluation_id')::uuid from v8_by_kind where kind='general'),
    gen_random_uuid(),10,'provider_response_invalid','deepseek','deepseek-v4-flash',
    array['Free text is not a rule'])$$,
  '22023', 'invalid failure metadata',
  '24: failure records accept only finite rule names');

select lives_ok(
  $$select public.persist_coach_chat_data_summary(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'fc888888-aaaa-4111-8111-111111111111',
    '{"answer":"Here is what your data shows.","evidence":[],"missing_data":[],"safety_state":"unavailable"}'::jsonb)$$,
  '25: the labeled data summary is stored');

select lives_ok(
  $$select public.persist_coach_chat_data_summary(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'fc888888-aaaa-4111-8111-111111111111',
    '{"answer":"Here is what your data shows.","evidence":[],"missing_data":[],"safety_state":"unavailable"}'::jsonb)$$,
  '26: storing the same data summary twice is safe');

select is(
  (select count(*) from public.coach_messages
    where thread_id='f7888888-aaaa-4111-8111-111111111111' and answer_source='data_summary'),
  1::bigint,
  '27: one failed request stores one labeled data summary');

select is(
  (select count(*) from public.coach_messages where thread_id='f7888888-aaaa-4111-8111-111111111111'),
  2::bigint,
  '28: the thread keeps the question and the labeled reply');

-- Conversation memory
select is(
  (select public.prepare_coach_chat_v8(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'And protein?','Asia/Kolkata',gen_random_uuid(),'general')->'context'->'recent_messages'),
  '[{"role": "user", "content": "How long until 72 kg?"}]'::jsonb,
  '29: a labeled data summary never returns to the coach as its own words');

-- A long thread saved before v8: each question and answer share created_at,
-- and 24 messages of about 2,000 characters exceed the base 18,000-character
-- guard. The newest answer is long and ends with a clarifying question.
reset role;
insert into public.coach_threads(id,user_id,title,status)
values('f7888888-aaaa-4111-8111-222222222222','f1888888-aaaa-4111-8111-111111111111',
  'Long conversation','active');
insert into public.coach_messages(user_id,thread_id,role,content,created_at)
select 'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-222222222222',
  r.role,
  case when t = 12 and r.role = 'assistant'
    then 'A12 ' || repeat('x', 5000) || ' Which day works best?'
    else (case r.role when 'user' then 'Q' else 'A' end) || lpad(t::text, 2, '0') || ' ' || repeat('x', 1995)
  end,
  now() - make_interval(mins => 60 - t)
from generate_series(1, 12) t cross join (values ('user'), ('assistant')) r(role);
set local role service_role;

select lives_ok(
  $$create temporary table v8_long as select public.prepare_coach_chat_v8(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-222222222222',
    'Monday', 'Asia/Kolkata', gen_random_uuid(), 'general') value$$,
  '30: a long conversation still gets an answer instead of chat context too large');

select is(
  (select jsonb_array_length(value->'context'->'recent_messages') from v8_long),
  10,
  '31: the coach keeps the ten newest messages');

select is(
  (select array[left(value->'context'->'recent_messages'->0->>'content', 3),
    left(value->'context'->'recent_messages'->9->>'content', 3)] from v8_long),
  array['Q08','A12'],
  '32: the newest turns are kept, oldest first');

select is(
  (select array[value->'context'->'recent_messages'->0->>'role',
    value->'context'->'recent_messages'->1->>'role'] from v8_long),
  array['user','assistant'],
  '33: a question saved with its answer comes first');

select ok(
  (select right(value->'context'->'recent_messages'->9->>'content', 21) = 'Which day works best?'
    and length(value->'context'->'recent_messages'->9->>'content') <= 2000 from v8_long),
  '34: a long answer is capped but keeps its closing clarifying question');

select ok(
  (select value->'context'->'recent_other_conversations' @> '[{"content": "How long until 72 kg?"}]'
    and not value->'context'->'recent_other_conversations' @> '[{"content": "Here is what your data shows."}]'
    from v8_long),
  '35: other conversations keep the question and leave out the data summary');

select lives_ok(
  $$select public.prepare_coach_chat_v7(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-222222222222',
    'Monday', 'Asia/Kolkata', gen_random_uuid(), 'general')$$,
  '36: the v7 rollback path also survives a long conversation');

-- A retried request (same idempotency key) reports what its first attempt
-- produced; a saved question alone is not a reply.
select ok(
  (select (value->>'replayed')::boolean and value->'turn' @> '{"state": "answered",
      "failure_code": "provider_response_invalid",
      "message": {"answer_source": "data_summary", "safety_state": "unavailable"}}'
    from (select public.prepare_coach_chat_v8(
      'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
      'How long until 72 kg?','Asia/Kolkata','fc888888-aaaa-4111-8111-111111111111',
      'general') value) replay),
  '37: a retry after a labeled data summary replays the summary');

select lives_ok(
  $$select public.record_coach_chat_question(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'And carbs?','fc888888-aaaa-4111-8111-333333333333')$$,
  '38: a second question is saved as its turn starts');

select is(
  (select public.prepare_coach_chat_v8(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'And carbs?','Asia/Kolkata','fc888888-aaaa-4111-8111-333333333333','general')
    ->'turn'->>'state'),
  'in_progress',
  '39: a retry while the model is still running is not a completed reply');

select lives_ok(
  $$select public.persist_failed_coach_chat_run(
    'f1888888-aaaa-4111-8111-111111111111',
    (select (value->>'feature_snapshot_id')::uuid from v8_by_kind where kind='general'),
    (select (value->>'policy_evaluation_id')::uuid from v8_by_kind where kind='general'),
    'fc888888-aaaa-4111-8111-333333333333',28000,'provider_timeout','deepseek',
    'deepseek-flash','{}')$$,
  '40: the second turn fails without a stored reply');

select ok(
  (select value->'turn' @> '{"state": "failed", "failure_code": "provider_timeout"}'
      and value->'turn'->'message' = 'null'::jsonb
    from (select public.prepare_coach_chat_v8(
      'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
      'And carbs?','Asia/Kolkata','fc888888-aaaa-4111-8111-333333333333',
      'general') value) replay),
  '41: a retry after a failure reports the failure code');

select lives_ok(
  $$select public.persist_coach_chat_result(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-222222222222',
    'Protein?','fc888888-aaaa-4111-8111-444444444444',
    (select (value->>'feature_snapshot_id')::uuid from v8_by_kind where kind='general'),
    (select (value->>'policy_evaluation_id')::uuid from v8_by_kind where kind='general'),
    '{"answer":"Keep protein at 150 g today.","evidence":[],"missing_data":[],
      "safety_state":"allowed","suggested_follow_ups":[]}'::jsonb,
    900,'deepseek','deepseek-flash',1000,200,0.001)$$,
  '42: a model answer is stored');

select ok(
  (select value->'turn' @> '{"state": "answered", "model_provider": "deepseek",
      "model": "deepseek-flash",
      "message": {"content": "Keep protein at 150 g today.", "safety_state": "allowed"}}'
      and value->'turn'->'message'->>'answer_source' is null
    from (select public.prepare_coach_chat_v8(
      'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-222222222222',
      'Protein?','Asia/Kolkata','fc888888-aaaa-4111-8111-444444444444',
      'general') value) replay),
  '43: a retry after a model answer replays that answer');

select ok(
  not has_function_privilege('authenticated', 'public.coach_chat_turn(uuid,uuid)', 'execute'),
  '44: the turn lookup is not executable by app users');

-- Watch data: steps on three days, sleep measured on one night.
reset role;
insert into public.daily_health_summaries(
  user_id,local_date,timezone,present_types,source_refs,source_checksum,
  completeness,observed_through,last_synced_at,steps,sleep_minutes)
values
  ('f1888888-aaaa-4111-8111-111111111111',current_date,'Asia/Kolkata',
    array['steps','sleep'],'[]'::jsonb,repeat('a',64),'partial',now(),now(),8000,420),
  ('f1888888-aaaa-4111-8111-111111111111',current_date-1,'Asia/Kolkata',
    array['steps'],'[]'::jsonb,repeat('b',64),'partial',now(),now(),9000,null),
  ('f1888888-aaaa-4111-8111-111111111111',current_date-2,'Asia/Kolkata',
    array['steps'],'[]'::jsonb,repeat('c',64),'partial',now(),now(),7000,null);
set local role service_role;

select is(
  (select (public.prepare_coach_chat_v8(
    'f1888888-aaaa-4111-8111-111111111111','f7888888-aaaa-4111-8111-111111111111',
    'How did I sleep this week?','Asia/Kolkata',gen_random_uuid(),'general')
    ->'context'->'health_averages'->'last_7_days')
    - array['avg_resting_heart_rate_bpm','avg_hrv_ms','days_with_resting_heart_rate',
      'days_with_hrv']),
  '{"days_synced": 3, "days_with_sleep": 1, "avg_sleep_minutes": 420,
    "days_with_steps": 3, "avg_steps": 8000}'::jsonb,
  '45: each watch-data average carries the days its metric was measured');

select * from finish();
rollback;
