begin;
select plan(39);

insert into auth.users(id, role) values
  ('a7000000-0000-4000-8000-000000000001', 'authenticated'),
  ('a7000000-0000-4000-8000-000000000002', 'authenticated'),
  ('a7000000-0000-4000-8000-000000000003', 'authenticated');

-- The limits row after migration 17 (USD 3 per athlete, USD 50 for everyone).
select is((select per_person_monthly_usd from private.ai_budget_limits), 3.00::numeric,
  'the per-athlete monthly stop is USD 3');
select is((select global_monthly_usd from private.ai_budget_limits), 50.00::numeric,
  'the stop across every account is USD 50');
select is((select count(*) from private.ai_budget_limits), 1::bigint, 'there is still one limits row');
select throws_ok($$update private.ai_budget_limits set per_person_monthly_usd = 0$$,
  '23514', null, 'a zero stop is refused');

-- The signatures and grants are unchanged.
select ok(has_function_privilege('service_role', 'public.reserve_ai_budget_v2(uuid,text,numeric)', 'execute'),
  'the service role reserves budget');
select ok(not has_function_privilege('authenticated', 'public.reserve_ai_budget_v2(uuid,text,numeric)', 'execute'),
  'clients cannot reserve budget');
select ok(not has_function_privilege('authenticated', 'public.assert_owner_ai_budget(uuid)', 'execute'),
  'clients cannot run the older check');
select ok(has_function_privilege('authenticated', 'public.get_my_ai_budget_state()', 'execute'),
  'the app can read its budget state');

-- USD 2.50 recorded: a call that keeps the athlete under USD 3 passes, one that crosses it does not.
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('a7000000-0000-4000-8000-000000000001', 'progress_vision', 'anthropic',
  'claude-sonnet-5-5', 1, 1, 2.50, 1);
set local role service_role;
select lives_ok($$select public.reserve_ai_budget_v2('a7000000-0000-4000-8000-000000000001',
  'physique_vision', 0.40)$$, 'USD 2.50 plus a USD 0.40 place stays under USD 3');
select throws_ok($$select public.reserve_ai_budget_v2('a7000000-0000-4000-8000-000000000001',
  'physique_vision', 0.20)$$, 'P0001', 'monthly cost limit reached',
  'USD 2.90 plus a USD 0.20 place crosses USD 3');
reset role;

-- The purpose-ceiling reservation uses the same stop (meal_vision ceiling 0.01).
insert into public.ai_usage_events(user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('a7000000-0000-4000-8000-000000000002', 'meal_vision', 'anthropic',
  'claude-haiku-5-5', 1, 1, 2.99, 1);
set local role service_role;
select lives_ok($$select public.reserve_ai_budget('a7000000-0000-4000-8000-000000000002', 'meal_vision')$$,
  'USD 2.99 plus the USD 0.01 ceiling lands exactly on the stop and is admitted');
select throws_ok($$select public.reserve_ai_budget('a7000000-0000-4000-8000-000000000002', 'meal_vision')$$,
  'P0001', 'monthly cost limit reached', 'the next place would cross USD 3');

-- The older check refuses an athlete who reached USD 3 and passes one just under.
select throws_ok($$select public.assert_owner_ai_budget('a7000000-0000-4000-8000-000000000002')$$,
  'P0001', 'monthly cost limit reached', 'USD 3 of spend and places stops the older check');
select lives_ok($$select public.assert_owner_ai_budget('a7000000-0000-4000-8000-000000000003')$$,
  'an athlete with no spend passes the older check');
reset role;

-- The athlete's own view follows the stop and keeps every field.
set local role authenticated;
set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000002';
select is((public.get_my_ai_budget_state()->>'schema_version'), '1.0', 'the budget state is versioned');
select is((public.get_my_ai_budget_state()->>'hard_stop_usd')::numeric, 3::numeric,
  'the app is told the stop is USD 3');
select is((public.get_my_ai_budget_state()->>'warning_threshold_usd')::numeric, 1.5::numeric,
  'the warning is half the stop');
select is((public.get_my_ai_budget_state()->>'blocked')::boolean, true,
  'USD 3 of spend and places is blocked');
select is((public.get_my_ai_budget_state()->>'daily_limit')::int, 30, 'the daily limit is unchanged');
select ok((public.get_my_ai_budget_state()) ?& array['estimated_cost_usd', 'warning', 'today_requests', 'period'],
  'every earlier field is still there');
set local "request.jwt.claim.sub" = 'a7000000-0000-4000-8000-000000000003';
select is((public.get_my_ai_budget_state()->>'blocked')::boolean, false, 'an athlete with no spend is not blocked');
reset role;

-- The owner changes the stop from the SQL editor.
update private.ai_budget_limits set per_person_monthly_usd = 4;
set local role service_role;
select lives_ok($$select public.reserve_ai_budget_v2('a7000000-0000-4000-8000-000000000002',
  'meal_vision', 0.50)$$, 'raising the stop to USD 4 admits the athlete again');
reset role;

-- Every notice names its vendor (part 2 of migration code 17) -----------------------------

select is((select count(*) from public.ai_consent_notices where provider is null), 0::bigint,
  'every coaching notice names its vendor');
select is((select count(*) from public.photo_ai_notices where provider is null), 0::bigint,
  'every progress photo notice names its vendor');
select is((select count(*) from public.meal_photo_ai_notices where provider is null), 0::bigint,
  'every meal photo notice names its vendor');
select is((select provider from public.ai_consent_notices where version = 'ai-coaching-v5'), 'deepseek',
  'the coaching notice that named DeepSeek now says deepseek');
select is((select provider from public.photo_ai_notices where version = 'progress-photo-ai-v1'), 'groq',
  'the progress photo notice that named Groq now says groq');
select is((select provider from public.meal_photo_ai_notices where version = 'meal-photo-ai-v1'), 'groq',
  'the meal photo notice that named Groq still says groq');

select is(private.notice_vendor_from_label('DeepSeek', null), 'deepseek', 'DeepSeek maps to deepseek');
select is(private.notice_vendor_from_label('Groq', 'qwen/qwen3.8-27b'), 'groq', 'Groq with a Qwen model maps to groq');
select is(private.notice_vendor_from_label('Google Gemini', null), 'gemini', 'Google maps to gemini');
select throws_ok($$select private.notice_vendor_from_label('Acme', null)$$, '22023', null,
  'a label naming no known company is refused, never guessed');
select throws_ok($$select private.notice_vendor_from_label('DeepSeek and Groq', null)$$, '22023', null,
  'a label naming two companies is refused');

-- The four-argument publishers refuse and publish nothing.
select throws_ok($$select private.publish_ai_notice('ai-coaching-a7-old', 'Anthropic',
  array['coach_chat'], 'Old form.')$$, '22023', null, 'the four-argument coaching publisher refuses');
select throws_ok($$select private.publish_photo_ai_notice('progress-photo-ai-a7-old', 'Anthropic',
  'claude-sonnet-5-5', 'Old form.')$$, '22023', null, 'the four-argument photo publisher refuses');
select is((select count(*) from public.ai_consent_notices where version = 'ai-coaching-a7-old')
  + (select count(*) from public.photo_ai_notices where version = 'progress-photo-ai-a7-old'),
  0::bigint, 'a refused publish stores nothing');
select ok(not has_function_privilege('authenticated', 'private.publish_ai_notice(text,text,text[],text)', 'execute')
  and not has_function_privilege('service_role', 'private.publish_ai_notice(text,text,text[],text)', 'execute'),
  'the four-argument coaching publisher is still closed to clients');
select ok(not has_function_privilege('authenticated', 'private.publish_photo_ai_notice(text,text,text,text)', 'execute')
  and not has_function_privilege('service_role', 'private.publish_photo_ai_notice(text,text,text,text)', 'execute'),
  'the four-argument photo publisher is still closed to clients');
select lives_ok($$select private.publish_ai_notice('ai-coaching-a7-new', 'anthropic', 'Anthropic',
  array['coach_chat'], 'Five-argument form.')$$, 'the five-argument publisher names the vendor');

select * from finish();
rollback;
