-- Meal photo AI notice ------------------------------------------------------------------

-- Same rules as photo_ai_notices (the physique check), in its own table: the
-- newest row is current, so sharing that table would let a meal notice void
-- physique consent. `provider` lets meal-analyze refuse to send a photo to a
-- provider the current notice does not name.
create table public.meal_photo_ai_notices (
  version text primary key check (version ~ '^[a-z0-9][a-z0-9.-]{0,31}$'),
  provider text not null check (provider in ('groq', 'gemini')),
  provider_label text not null check (length(provider_label) between 1 and 80),
  model text not null check (length(model) between 1 and 100),
  body text not null check (length(body) between 1 and 4000),
  created_at timestamptz not null default clock_timestamp()
);
alter table public.meal_photo_ai_notices enable row level security;
alter table public.meal_photo_ai_notices force row level security;
create policy meal_photo_ai_notices_read on public.meal_photo_ai_notices
  for select to authenticated using (true);
revoke all on public.meal_photo_ai_notices from public, anon, authenticated;
grant select on public.meal_photo_ai_notices to authenticated;

-- Run by the owner from the SQL editor when the provider, model, data sent or
-- retention changes. A notice is never edited.
create function private.publish_meal_photo_ai_notice(
  notice_version text, notice_provider text, notice_provider_label text, notice_model text,
  notice_body text
) returns void language sql security definer set search_path = '' as $$
  insert into public.meal_photo_ai_notices(version, provider, provider_label, model, body)
  values (notice_version, notice_provider, notice_provider_label, notice_model, notice_body);
$$;
revoke all on function private.publish_meal_photo_ai_notice(text, text, text, text, text)
from public, anon, authenticated;

create function private.current_meal_photo_ai_notice()
returns public.meal_photo_ai_notices language sql stable security definer set search_path = '' as $$
  select * from public.meal_photo_ai_notices order by created_at desc, version desc limit 1;
$$;
revoke all on function private.current_meal_photo_ai_notice() from public, anon, authenticated;

select private.publish_meal_photo_ai_notice(
  'meal-photo-ai-v1',
  'groq',
  'Groq',
  'qwen/qwen3.8-27b',
  'Meal photo analysis is an AI estimate, not a measurement. When you analyze a meal photo, '
  'Tracend sends Groq a resized copy of that one photo. Groq runs the model qwen/qwen3.8-27b, '
  'which suggests the foods it sees with portions, calories and macros. Your name, email '
  'address, other photos and the rest of your data are not sent.' || E'\n\n' ||
  'Groq is run by Groq, Inc., a US company. Tracend has turned on Groq''s Zero Data Retention, '
  'so Groq does not keep the photo or its answer after replying. Tracend keeps the photo '
  'privately in your account and deletes it after the review window unless you save it.'
  || E'\n\n' ||
  'Nothing is logged until you review and confirm the foods. Without photo analysis you can '
  'still log meals yourself.'
);

-- Consent counts only when the athlete's newest meal_photo_ai record grants
-- exactly the current notice.
create function public.has_meal_photo_ai_consent(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select record.action = 'granted'
      and record.notice_version = (private.current_meal_photo_ai_notice()).version
    from public.consent_records record
    where record.user_id = target_user_id and record.consent_type = 'meal_photo_ai'
    order by record.created_at desc, record.id desc
    limit 1
  ), false);
$$;
revoke all on function public.has_meal_photo_ai_consent(uuid) from public, anon, authenticated;
grant execute on function public.has_meal_photo_ai_consent(uuid) to service_role;

-- What meal-analyze checks before a photo leaves: the grant, and the provider
-- the current notice names.
create function public.get_meal_photo_ai_consent(target_user_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'granted', public.has_meal_photo_ai_consent(target_user_id),
    'provider', (private.current_meal_photo_ai_notice()).provider);
$$;
revoke all on function public.get_meal_photo_ai_consent(uuid) from public, anon, authenticated;
grant execute on function public.get_meal_photo_ai_consent(uuid) to service_role;

-- The notice the app shows before the first analysis, and whether it is granted.
create function public.get_my_meal_photo_ai_notice()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare notice public.meal_photo_ai_notices;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  notice := private.current_meal_photo_ai_notice();
  return jsonb_build_object(
    'schema_version', '1.0',
    'version', notice.version,
    'provider_label', notice.provider_label,
    'model', notice.model,
    'body', notice.body,
    'granted', public.has_meal_photo_ai_consent(auth.uid()));
end $$;
revoke all on function public.get_my_meal_photo_ai_notice() from public, anon, authenticated;
grant execute on function public.get_my_meal_photo_ai_notice() to authenticated;

-- AI coaching notice v5 -----------------------------------------------------------------

-- v4 did not name everything the starting plan now sends (target weight, years
-- of training, what worked and stalled, focus and strong muscles, reported
-- barbell sets, follow-up answers, usual Apple Health months, change requests).
-- A new version makes the app ask again on its next start.
select private.publish_ai_notice(
  'ai-coaching-v5',
  'DeepSeek',
  array['coach_chat','daily_coaching','onboarding_plan'],
  'Your starting plan, the Coach chat and your daily decision are written by an AI model. To '
  'write your starting plan, and the few follow-up questions it may ask first, Tracend sends '
  'DeepSeek your onboarding answers: goal, age, sex, height, weight and target weight, daily '
  'activity, training days and session length, years of training and what has worked or '
  'stalled, equipment, limitations, movements to avoid, focus and strong muscles, diet notes, '
  'the barbell top sets you report with Tracend''s one-rep-max estimates, your answers to the '
  'follow-up questions, any changes you ask for to a proposal and, if you have one, your '
  'current plan. If you connected Apple Health, it also sends a summary of your last 4 weeks '
  '(average steps, active energy and sleep, workouts per week, and your weight trend) and of '
  'your usual completed months. For the Coach chat and daily decision it sends your training '
  'plan and workout logs, check-ins, Apple Health summaries (sleep, heart rate, HRV, steps and '
  'workouts), meals and nutrition targets, body measurements, goals, focus muscles and '
  'preferences, and the messages you send the Coach. Your name, email address and photos are '
  'not sent.' || E'\n\n' ||
  'DeepSeek is run by Hangzhou DeepSeek Artificial Intelligence Co., Ltd. and processes this '
  'data on servers in China. Its terms, not Tracend''s, decide how long it keeps requests.'
  || E'\n\n' ||
  'Tracend checks every AI plan against its safety ranges, and nothing starts until you approve '
  'it. Without AI coaching, Tracend builds your starting plan with its own rules, and your plan, '
  'logging, Apple Health sync and progress keep working; the Coach chat and AI daily decisions '
  'stay off. You can change this at any time in Account.'
);
