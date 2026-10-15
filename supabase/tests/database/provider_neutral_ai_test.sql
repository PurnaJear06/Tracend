begin;
select plan(74);

-- a11...01 runs, usage and consent; 02 another athlete; 03-05 the budget.
insert into auth.users(id, role) values
  ('a1100000-0000-4000-8000-000000000001', 'authenticated'),
  ('a1100000-0000-4000-8000-000000000002', 'authenticated'),
  ('a1100000-0000-4000-8000-000000000003', 'authenticated'),
  ('a1100000-0000-4000-8000-000000000004', 'authenticated'),
  ('a1100000-0000-4000-8000-000000000005', 'authenticated');

insert into public.training_plans(id, user_id, title, source) values
  ('a1100000-0000-4000-8000-000000000011', 'a1100000-0000-4000-8000-000000000001',
   'A1 plan', 'mock_ai');
insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks, sessions_per_week,
  prescription, rationale, approved_at, effective_date)
values(
  'a1100000-0000-4000-8000-000000000012', 'a1100000-0000-4000-8000-000000000001',
  'a1100000-0000-4000-8000-000000000011', 1, 'active', 4, 3, '{}', 'Approved fixture',
  now(), current_date);
insert into public.nutrition_target_sets(
  id, user_id, version_number, status, calories, protein_g, carbohydrate_g, fat_g,
  rationale, approved_at, effective_date)
values(
  'a1100000-0000-4000-8000-000000000013', 'a1100000-0000-4000-8000-000000000001',
  1, 'active', 2200, 150, 240, 70, 'Approved fixture', now(), current_date);
insert into public.daily_check_ins(
  user_id, local_date, timezone, revision, idempotency_key,
  sleep_quality, energy, soreness, hunger, mood, pain_severity, available_to_train, note)
values
  ('a1100000-0000-4000-8000-000000000001', current_date, 'Asia/Kolkata', 1, gen_random_uuid(),
   3, 4, 2, 3, 4, 1, true, '');
insert into public.coach_threads(id, user_id, title, status) values
  ('a1100000-0000-4000-8000-000000000014', 'a1100000-0000-4000-8000-000000000001',
   'New conversation', 'active');
insert into public.meals(
  id, user_id, local_date, timezone, meal_type, source, status, idempotency_key)
values ('a1100000-0000-4000-8000-000000000015', 'a1100000-0000-4000-8000-000000000001',
  current_date, 'Asia/Kolkata', 'lunch', 'photo_analysis', 'draft',
  'a1100000-0000-4000-8000-000000000016');

create temporary table prep as select public.prepare_daily_coaching(
  'a1100000-0000-4000-8000-000000000001', current_date, 'Asia/Kolkata',
  'a1100000-0000-4000-8000-000000000020') value;
create temporary table ids as select
  (value->>'feature_snapshot_id')::uuid snapshot_id,
  (value->>'policy_evaluation_id')::uuid policy_id
from prep;

-- Run providers ------------------------------------------------------------------------

select lives_ok($$select public.persist_coach_chat_result(
  'a1100000-0000-4000-8000-000000000001', 'a1100000-0000-4000-8000-000000000014',
  'Protein?', 'a1100000-0000-4000-8000-000000000021',
  (select snapshot_id from ids), (select policy_id from ids),
  '{"answer":"Keep protein at 150 g.","evidence":[],"missing_data":[],"safety_state":"allowed"}'::jsonb,
  900, 'anthropic', 'claude-sonnet-5-5', 1000, 200, 0.004)$$,
  'a Coach answer from Claude is stored');
select lives_ok($$select public.persist_coach_chat_result(
  'a1100000-0000-4000-8000-000000000001', 'a1100000-0000-4000-8000-000000000014',
  'Carbs?', 'a1100000-0000-4000-8000-000000000022',
  (select snapshot_id from ids), (select policy_id from ids),
  '{"answer":"Keep carbs at 240 g.","evidence":[],"missing_data":[],"safety_state":"allowed"}'::jsonb,
  900, 'deepseek', 'deepseek-flash', 1000, 200, 0.001)$$,
  'a Coach answer from DeepSeek is still stored');
select throws_ok($$select public.persist_coach_chat_result(
  'a1100000-0000-4000-8000-000000000001', 'a1100000-0000-4000-8000-000000000014',
  'Fat?', 'a1100000-0000-4000-8000-000000000023',
  (select snapshot_id from ids), (select policy_id from ids),
  '{"answer":"Keep fat at 70 g.","evidence":[],"missing_data":[],"safety_state":"allowed"}'::jsonb,
  900, 'acme', 'acme-1', 1000, 200, 0.001)$$,
  '22023', 'invalid chat result', 'a Coach answer from an unknown provider is refused');

select lives_ok($$select public.persist_daily_coaching_result_v2(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000024',
  ('{"schema_version":"1.0","decision_kind":"daily","local_date":"' || current_date || '",
    "training":{"action":"PROCEED_AS_PLANNED","summary":"Proceed.","today_adjustments":[]},
    "nutrition":{"action":"MAINTAIN_TARGETS","summary":"Maintain.","today_adjustments":[]},
    "head_coach":{"final_decision":"Keep the plan.","reason":"Plan active."},
    "evidence":[{"code":"APPROVED_PLAN_ACTIVE","label":"Plan active","source":"policy_evaluation"}],
    "confidence":"low","missing_data":[],"risk_flags":[],"change_proposals":[]}')::jsonb,
  125, 'openai_compatible', 'deepseek-flash', 320, 84, 0.0001)$$,
  'a daily decision through an OpenAI-compatible route is stored');
select throws_ok($$select public.persist_daily_coaching_result_v2(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000025', '{}'::jsonb,
  125, 'acme', 'acme-1', 320, 84, 0.0001)$$,
  '22023', 'invalid provider metadata', 'a daily decision from an unknown provider is refused');

select lives_ok($$select public.persist_failed_coaching_run_v2(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000026', 400, 'provider_timeout', 'anthropic', 'claude-sonnet-5-5')$$,
  'a failed Claude daily decision is recorded');
select lives_ok($$select public.persist_failed_coaching_run_v2(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000027', 400, 'provider_timeout', 'groq', 'qwen/qwen3.8-27b')$$,
  'a failed Groq daily decision is still recorded');
select throws_ok($$select public.persist_failed_coaching_run_v2(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000028', 400, 'provider_timeout', 'acme', 'acme-1')$$,
  '22023', 'invalid failure metadata', 'a failed run from an unknown provider is refused');

select lives_ok($$select public.persist_failed_coach_chat_run(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000029', 400, 'provider_timeout', 'openai_compatible',
  'deepseek-flash')$$,
  'a failed Coach chat through an OpenAI-compatible route is recorded');
select throws_ok($$select public.persist_failed_coach_chat_run(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000030', 400, 'provider_timeout', 'acme', 'acme-1')$$,
  '22023', 'invalid failure metadata', 'a failed Coach chat from an unknown provider is refused');
select lives_ok($$select public.persist_failed_coach_chat_run_v2(
  'a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids), (select policy_id from ids),
  'a1100000-0000-4000-8000-000000000031', 400, 'provider_refused', 'anthropic',
  'claude-sonnet-5-5', '{}', 900, 0, 0.003)$$,
  'a failed Claude Coach chat records its usage');

select is((select array_agg(distinct provider order by provider) from public.model_runs
  where user_id = 'a1100000-0000-4000-8000-000000000001'),
  array['anthropic','deepseek','groq','openai_compatible'],
  'model runs keep each provider as given');
select throws_ok($$insert into public.model_runs(user_id, feature_snapshot_id, policy_evaluation_id,
  idempotency_key, purpose, provider, model, prompt_version, schema_version, status,
  validation_status, latency_ms)
  values ('a1100000-0000-4000-8000-000000000001', (select snapshot_id from ids),
    (select policy_id from ids), 'a1100000-0000-4000-8000-000000000032', 'coach_chat', 'acme',
    'acme-1', 'coach-chat-v1', '1.0', 'failed', 'failed', 1)$$,
  '23514', null, 'the model run table refuses an unknown provider');

-- Usage events -------------------------------------------------------------------------

select lives_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'onboarding_plan', 'anthropic', 'claude-sonnet-5-5', 8000, 3000, 0.07, 30000)$$,
  'a Claude onboarding plan records its usage');
select lives_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'onboarding_questions', 'openai_compatible', 'deepseek-flash', 3000, 300, 0.001, 5000)$$,
  'OpenAI-compatible onboarding questions record their usage');
select lives_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'meal_vision', 'anthropic', 'claude-haiku-5-5', 1500, 400, 0.003, 4000)$$,
  'a Claude meal photo records its usage');
select lives_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'progress_vision', 'openai_compatible', 'qwen/qwen3.8-27b', 4000, 600, 0.002, 9000)$$,
  'an OpenAI-compatible physique check records its usage');
select lives_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'meal_vision', 'groq', 'qwen/qwen3.8-27b', 1200, 400, 0.002, 900)$$,
  'a Groq meal photo is still recorded');
select throws_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'meal_vision', 'groq', 'qwen/qwen3.9-27b', 1200, 400, 0.002, 900)$$,
  '22023', 'invalid usage event', 'old vision providers keep their pinned models');
select throws_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'meal_vision', 'anthropic', 'claude haiku!', 1200, 400, 0.002, 900)$$,
  '22023', 'invalid usage event', 'a malformed model id is refused');
select throws_ok($$select public.record_ai_usage_event('a1100000-0000-4000-8000-000000000001',
  'onboarding_plan', 'acme', 'acme-1', 1200, 400, 0.002, 900)$$,
  '22023', 'invalid usage event', 'usage from an unknown provider is refused');
select throws_ok($$insert into public.ai_usage_events(user_id, purpose, provider, model,
  input_units, output_units, estimated_cost_usd, latency_ms)
  values ('a1100000-0000-4000-8000-000000000001', 'meal_vision', 'acme', 'gemini-3.5-flash',
    1, 1, 0, 1)$$,
  '23514', null, 'the usage table refuses an unknown provider');
select throws_ok($$insert into public.ai_usage_events(user_id, purpose, provider, model,
  input_units, output_units, estimated_cost_usd, latency_ms)
  values ('a1100000-0000-4000-8000-000000000001', 'meal_vision', 'anthropic', 'claude haiku!',
    1, 1, 0, 1)$$,
  '23514', null, 'the usage table refuses a malformed model id');

select is(public.persist_meal_photo_candidates('a1100000-0000-4000-8000-000000000001',
  'a1100000-0000-4000-8000-000000000015',
  '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,
     "carbohydrate_g":24,"fat_g":5,"confidence":"low"}]'::jsonb,
  'anthropic', 'claude-haiku-5-5'), 1, 'meal candidates from Claude are saved');
select is(public.persist_meal_photo_candidates('a1100000-0000-4000-8000-000000000001',
  'a1100000-0000-4000-8000-000000000015',
  '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,
     "carbohydrate_g":24,"fat_g":5,"confidence":"low"}]'::jsonb,
  'groq', 'qwen/qwen3.8-27b'), 1, 'meal candidates from Groq are still saved');
select throws_ok($$select public.persist_meal_photo_candidates('a1100000-0000-4000-8000-000000000001',
  'a1100000-0000-4000-8000-000000000015',
  '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,
     "carbohydrate_g":24,"fat_g":5,"confidence":"low"}]'::jsonb,
  'acme', 'acme-1')$$,
  '22023', 'invalid meal analysis', 'meal candidates from an unknown provider are refused');

-- Coaching consent v2 -----------------------------------------------------------------

select ok(not has_function_privilege('authenticated', 'public.get_ai_consent_v2(uuid,text)', 'execute'),
  'clients cannot read another athlete''s consent');
select ok(has_function_privilege('service_role', 'public.get_ai_consent_v2(uuid,text)', 'execute'),
  'the service role reads consent');
select is((select array_agg(key order by key) from jsonb_object_keys(
    public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'coach_chat')) key),
  array['granted','notice_version','provider','schema_version'],
  'consent v2 returns exactly its four keys');
select is((select count(*) from public.ai_consent_notices where provider is not null), 0::bigint,
  'notices published before provider names keep a null provider');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'coach_chat'),
  jsonb_build_object('schema_version', '1.0', 'granted', false, 'provider', null,
    'notice_version', (select version from public.ai_notice_current where purpose = 'coach_chat')),
  'nothing is granted at first, and the current notice names no provider');

insert into public.consent_records(user_id, consent_type, notice_version, action, source)
select 'a1100000-0000-4000-8000-000000000001', 'ai_coaching', version, 'granted', 'ios_app'
from public.ai_notice_current where purpose = 'coach_chat';
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'coach_chat')->'granted',
  'true'::jsonb, 'a grant of a notice without a provider still counts as a grant');

select lives_ok($$select private.publish_ai_notice('ai-coaching-a1-test', 'anthropic',
  'Claude (Anthropic)', array['coach_chat','daily_coaching','onboarding_plan'], 'Test notice.')$$,
  'a notice naming its provider is published');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'coach_chat'),
  '{"schema_version": "1.0", "granted": false, "provider": "anthropic",
    "notice_version": "ai-coaching-a1-test"}'::jsonb,
  'a new notice needs a new grant and names its provider');

insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('a1100000-0000-4000-8000-000000000001', 'ai_coaching', 'ai-coaching-a1-test', 'granted',
  'ios_app');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'coach_chat'),
  '{"schema_version": "1.0", "granted": true, "provider": "anthropic",
    "notice_version": "ai-coaching-a1-test"}'::jsonb,
  'the grant of the current notice counts, with its provider');
select ok((select bool_and((public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', p)
    ->>'granted')::boolean
    and public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', p)->>'provider' = 'anthropic')
  from unnest(array['coach_chat','library_context','daily_coaching','daily_decision',
    'onboarding_plan','onboarding_questions']) p),
  'every coaching feature maps to its coaching notice');
select ok(public.has_ai_coaching_consent('a1100000-0000-4000-8000-000000000001', 'daily_coaching')
  and public.has_ai_coaching_consent('a1100000-0000-4000-8000-000000000001'),
  'has_ai_coaching_consent answers as before');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000002', 'coach_chat')->'granted',
  'false'::jsonb, 'another athlete''s grant does not count');

select throws_ok($$select private.publish_ai_notice('ai-coaching-a1-bad', 'acme', 'Acme',
  array['coach_chat'], 'Test notice.')$$,
  '23514', null, 'a notice naming an unknown provider is refused');
select throws_ok($$select private.publish_ai_notice('ai-coaching-a1-none', null, 'Acme',
  array['coach_chat'], 'Test notice.')$$,
  '22023', 'provider required', 'the new publisher requires a provider');
select lives_ok($$select private.publish_ai_notice('ai-coaching-a1-old', 'DeepSeek',
  array['onboarding_plan'], 'Old form.')$$,
  'the original publisher still works');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'onboarding_questions'),
  '{"schema_version": "1.0", "granted": false, "provider": null,
    "notice_version": "ai-coaching-a1-old"}'::jsonb,
  'a notice from the original publisher names no provider');

-- Meal photo notice -------------------------------------------------------------------

select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'meal_vision'),
  '{"schema_version": "1.0", "granted": false, "provider": "groq",
    "notice_version": "meal-photo-ai-v1"}'::jsonb,
  'meal vision reads the meal photo notice');
select lives_ok($$select private.publish_meal_photo_ai_notice('meal-photo-ai-a1-groq', 'groq',
  'Groq', 'qwen/qwen3.8-27b', 'Test notice.')$$,
  'a Groq meal photo notice is still accepted');
select lives_ok($$select private.publish_meal_photo_ai_notice('meal-photo-ai-a1-oc',
  'openai_compatible', 'DeepSeek', 'deepseek-flash', 'Test notice.')$$,
  'an OpenAI-compatible meal photo notice is accepted');
select lives_ok($$select private.publish_meal_photo_ai_notice('meal-photo-ai-a1', 'anthropic',
  'Claude (Anthropic)', 'claude-haiku-5-5', 'Test notice.')$$,
  'a Claude meal photo notice is accepted');
select throws_ok($$select private.publish_meal_photo_ai_notice('meal-photo-ai-a1-bad', 'acme',
  'Acme', 'acme-1', 'Test notice.')$$,
  '23514', null, 'a meal photo notice naming an unknown provider is refused');
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('a1100000-0000-4000-8000-000000000001', 'meal_photo_ai', 'meal-photo-ai-a1', 'granted',
  'ios_app');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'meal_vision'),
  '{"schema_version": "1.0", "granted": true, "provider": "anthropic",
    "notice_version": "meal-photo-ai-a1"}'::jsonb,
  'a grant of the Claude meal photo notice counts');
select is(public.get_meal_photo_ai_consent('a1100000-0000-4000-8000-000000000001'),
  '{"granted": true, "provider": "anthropic"}'::jsonb,
  'meal-analyze''s consent check answers as before');

-- Progress photo notice ---------------------------------------------------------------

select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'physique_vision'),
  '{"schema_version": "1.0", "granted": false, "provider": null,
    "notice_version": "progress-photo-ai-v1"}'::jsonb,
  'physique vision reads the progress photo notice');
select lives_ok($$select private.publish_photo_ai_notice('progress-photo-ai-a1', 'anthropic',
  'Claude (Anthropic)', 'claude-sonnet-5-5', 'Test notice.')$$,
  'a Claude progress photo notice is published with its provider');
select throws_ok($$select private.publish_photo_ai_notice('progress-photo-ai-a1-bad', 'acme',
  'Acme', 'acme-1', 'Test notice.')$$,
  '23514', null, 'a progress photo notice naming an unknown provider is refused');
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('a1100000-0000-4000-8000-000000000001', 'progress_photo_ai', 'progress-photo-ai-a1',
  'granted', 'ios_app');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'progress_vision'),
  '{"schema_version": "1.0", "granted": true, "provider": "anthropic",
    "notice_version": "progress-photo-ai-a1"}'::jsonb,
  'a grant of the Claude progress photo notice counts');
select lives_ok($$select private.publish_photo_ai_notice('progress-photo-ai-a1-old', 'Groq',
  'qwen/qwen3.8-27b', 'Old form.')$$,
  'the original progress photo publisher still works');
select is(public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'physique_vision'),
  '{"schema_version": "1.0", "granted": false, "provider": null,
    "notice_version": "progress-photo-ai-a1-old"}'::jsonb,
  'its notice names no provider and needs a new grant');

select throws_ok($$select public.get_ai_consent_v2('a1100000-0000-4000-8000-000000000001', 'acme')$$,
  '22023', 'invalid purpose', 'an unknown purpose is refused');

-- Budget v2 ---------------------------------------------------------------------------

select ok(not has_function_privilege('authenticated',
  'public.reserve_ai_budget_v2(uuid,text,numeric)', 'execute'),
  'clients cannot reserve budget');
select ok(has_function_privilege('service_role',
  'public.reserve_ai_budget_v2(uuid,text,numeric)', 'execute'),
  'the service role reserves budget');

select is((with held as (select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003', 'meal_vision', 0.004) id)
  select reserved_cost_usd from public.ai_budget_reservations r join held on r.id = held.id),
  0.004000::numeric(10,6), 'a place holds the caller''s ceiling');
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003',
  'meal_vision', 0)$$, '22023', 'invalid ceiling', 'a zero ceiling is refused');
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003',
  'meal_vision', -0.01)$$, '22023', 'invalid ceiling', 'a negative ceiling is refused');
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003',
  'meal_vision', 0.51)$$, '22023', 'invalid ceiling', 'a ceiling above USD 0.50 is refused');
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003',
  'meal_vision', null)$$, '22023', 'invalid ceiling', 'a missing ceiling is refused');
select is((with held as (select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003', 'onboarding_plan', 0.50) id)
  select reserved_cost_usd from public.ai_budget_reservations r join held on r.id = held.id),
  0.500000::numeric(10,6), 'a USD 0.50 ceiling is the most one place holds');
select is((with held as (select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003', 'coach_chat', 0.0000001) id)
  select reserved_cost_usd from public.ai_budget_reservations r join held on r.id = held.id),
  0.000001::numeric(10,6), 'a ceiling below a millionth rounds up, never down');
select is((with held as (
    select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003', 'physique_vision', 0.03) id
    union all
    select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003', 'daily_decision', 0.02)
    union all
    select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003', 'library_context', 0.01))
  select array_agg(r.purpose order by r.purpose) from public.ai_budget_reservations r
  join held on r.id = held.id),
  array['coach_chat','daily_coaching','progress_vision'],
  'gateway feature names are stored under today''s purposes');
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003',
  'acme', 0.01)$$, '22023', 'invalid purpose', 'an unknown purpose is refused');
select is((with held as (select public.reserve_ai_budget('a1100000-0000-4000-8000-000000000003', 'meal_vision') id)
  select reserved_cost_usd from public.ai_budget_reservations r join held on r.id = held.id),
  0.010000::numeric(10,6), 'the original reserve keeps the fixed purpose ceiling');

-- Open places count toward the day's 30 calls.
insert into public.ai_budget_reservations(user_id, purpose, reserved_cost_usd)
select 'a1100000-0000-4000-8000-000000000005', 'coach_chat', 0.02 from generate_series(1, 29);
select lives_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000005',
  'coach_chat', 0.02)$$, 'the 30th call of the day is admitted');
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000005',
  'coach_chat', 0.02)$$, 'P0001', 'daily rate limit reached', 'the 31st call of the day is refused');

-- The caller's ceiling, not the purpose's, decides whether the month's stop is crossed:
-- 1.90 recorded + 0.20 is refused although the fixed physique ceiling (0.03) would fit.
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('a1100000-0000-4000-8000-000000000004', 'progress_vision', 'anthropic',
  'claude-sonnet-5-5', 1, 1, 1.90, 1);
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000004',
  'physique_vision', 0.20)$$, 'P0001', 'monthly cost limit reached',
  'a place whose ceiling would cross the monthly stop is refused');
select lives_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000004',
  'physique_vision', 0.05)$$, 'a place that fits under the stop is admitted');
select is((select monthly_cost from private.ai_usage_totals('a1100000-0000-4000-8000-000000000004')),
  1.950000::numeric, 'an open place counts at the caller''s ceiling');

-- The stop across every account applies.
update private.ai_budget_limits
set global_monthly_usd = ceil(((select monthly_cost from private.ai_usage_totals(null)) + 0.10) * 100) / 100;
select throws_ok($$select public.reserve_ai_budget_v2('a1100000-0000-4000-8000-000000000003',
  'coach_chat', 0.20)$$, 'P0001', 'global monthly cost limit reached',
  'a place that would cross the global stop is refused');

select * from finish();
rollback;
