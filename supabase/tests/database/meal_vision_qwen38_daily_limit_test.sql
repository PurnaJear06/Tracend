begin;

select plan(9);

insert into auth.users (id, role)
values ('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3', 'authenticated');

insert into public.meals (
  id, user_id, local_date, timezone, meal_type, source, status, idempotency_key)
values ('f4f4f4f4-f4f4-4f4f-8f4f-f4f4f4f4f4f4', 'e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3',
  current_date, 'Asia/Kolkata', 'lunch', 'photo_analysis', 'draft',
  'a5a5a5a5-a5a5-4a5a-8a5a-a5a5a5a5a5a5');

select is(
  public.persist_meal_photo_candidates('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3',
    'f4f4f4f4-f4f4-4f4f-8f4f-f4f4f4f4f4f4',
    '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,
       "carbohydrate_g":24,"fat_g":5,"confidence":"low"}]'::jsonb,
    'groq', 'qwen/qwen3.8-27b'),
  1,
  'candidates from Groq qwen3.8 are saved for review'
);

select throws_ok(
  $$select public.persist_meal_photo_candidates('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3',
    'f4f4f4f4-f4f4-4f4f-8f4f-f4f4f4f4f4f4',
    '[{"name":"Dal","serving_label":"1 bowl","calories":180,"protein_g":9,
       "carbohydrate_g":24,"fat_g":5,"confidence":"low"}]'::jsonb,
    'groq', 'qwen/qwen3.9-27b')$$,
  '22023',
  null,
  'candidates from an unlisted model are refused'
);

select lives_ok(
  $$select public.record_ai_usage_event('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3',
    'meal_vision', 'groq', 'qwen/qwen3.8-27b', 1200, 400, 0.002, 900)$$,
  'a meal photo analysed by Groq qwen3.8 is recorded'
);

select throws_ok(
  $$select public.record_ai_usage_event('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3',
    'meal_vision', 'groq', 'qwen/qwen3.9-27b', 1200, 400, 0.002, 900)$$,
  '22023',
  null,
  'an unlisted vision model is still refused'
);

insert into public.ai_usage_events (
  user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
select 'e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3', 'meal_vision', 'groq',
  'qwen/qwen3.8-27b', 1200, 400, 0.002, 900
from generate_series(1, 28);

select lives_ok(
  $$select public.assert_owner_ai_budget('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3')$$,
  '29 requests today stay within the daily limit'
);

insert into public.ai_usage_events (
  user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3', 'meal_vision', 'groq',
  'qwen/qwen3.8-27b', 1200, 400, 0.002, 900);

select throws_ok(
  $$select public.assert_owner_ai_budget('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3')$$,
  'P0001',
  'daily rate limit reached',
  'the 31st request of the day is refused'
);

set local role authenticated;
set local "request.jwt.claim.sub" = 'e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3';

select is(
  (public.get_my_ai_budget_state()->>'daily_limit')::int,
  30,
  'the app is told the daily limit is 30'
);

select is(
  (public.get_my_ai_budget_state()->>'hard_stop_usd')::numeric,
  2::numeric,
  'the monthly hard stop stays at USD 2'
);

reset role;

-- The monthly stop is checked before the daily count.
insert into public.ai_usage_events (
  user_id, purpose, provider, model, input_units, output_units,
  estimated_cost_usd, latency_ms)
values ('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3', 'meal_vision', 'groq',
  'qwen/qwen3.8-27b', 1200, 400, 2, 900);

select throws_ok(
  $$select public.assert_owner_ai_budget('e3e3e3e3-e3e3-4e3e-8e3e-e3e3e3e3e3e3')$$,
  'P0001',
  'monthly cost limit reached',
  'USD 2 of estimated spend this month stops AI requests'
);

select * from finish();
rollback;
