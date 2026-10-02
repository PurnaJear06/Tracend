-- Physique check (owner-only experiment, 2026-10).
--
-- The athlete can ask an AI model (Groq, qwen/qwen3.8-27b) which muscles to
-- develop, relative to their own build, from the front, side and back photos
-- of one complete progress photo set. The result is a visual estimate the
-- athlete reviews; only the muscles they confirm become their focus
-- (user_profiles.priority_muscles), which the Coach and the next plan read.
-- The Edge Function physique-check serves only the user IDs listed in its
-- PHYSIQUE_VISION_ALLOWED_USERS secret.
--
-- Photos go to a different provider than coaching, so photo AI has its own
-- notice and consent (consent_type progress_photo_ai), separate from the
-- ai_coaching notices: the DeepSeek notices stay true, DeepSeek never
-- receives photos.

-- Deleting photos ---------------------------------------------------------------

-- An analysis references its photo set without a cascade, so deleting a set
-- with an analysis failed. The analyses that used the set go first.
create or replace function public.delete_my_progress_photo_set(target_set_id uuid)
returns boolean language plpgsql security definer set search_path='' as $$
declare media_ids uuid[]; removed_analyses integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  if not exists(select 1 from public.progress_photo_sets where id=target_set_id and user_id=auth.uid())
    then return true; end if;
  select coalesce(array_agg(media_object_id),'{}') into media_ids from public.progress_photos
    where photo_set_id=target_set_id and user_id=auth.uid();
  delete from public.physique_analyses where user_id=auth.uid()
    and (baseline_photo_set_id=target_set_id or current_photo_set_id=target_set_id);
  get diagnostics removed_analyses = row_count;
  delete from public.progress_photo_sets where id=target_set_id and user_id=auth.uid();
  delete from public.media_objects where id=any(media_ids) and user_id=auth.uid();
  insert into public.audit_events(user_id,action_code,target_type,target_id,outcome,metadata)
  values(auth.uid(),'progress.photo_set.deleted','progress_photo_set',target_set_id,'succeeded',
    jsonb_build_object('physique_analyses',removed_analyses));
  return true;
end $$;
revoke all on function public.delete_my_progress_photo_set(uuid) from public,anon,authenticated;
grant execute on function public.delete_my_progress_photo_set(uuid) to authenticated;

-- Photo AI notice -----------------------------------------------------------------

-- The newest notice is current. A notice is never edited: a new provider,
-- model, data sent or retention is a new version, and a grant of an older
-- version stops counting.
create table public.photo_ai_notices (
  version text primary key check (version ~ '^[a-z0-9][a-z0-9.-]{0,31}$'),
  provider_label text not null check (length(provider_label) between 1 and 80),
  model text not null check (length(model) between 1 and 100),
  body text not null check (length(body) between 1 and 4000),
  created_at timestamptz not null default clock_timestamp()
);
alter table public.photo_ai_notices enable row level security;
alter table public.photo_ai_notices force row level security;
create policy photo_ai_notices_read on public.photo_ai_notices
  for select to authenticated using (true);
revoke all on public.photo_ai_notices from public, anon, authenticated;
grant select on public.photo_ai_notices to authenticated;

-- Run by the owner from the SQL editor when the provider, model, data sent or
-- retention changes.
create function private.publish_photo_ai_notice(
  notice_version text, notice_provider_label text, notice_model text, notice_body text
) returns void language sql security definer set search_path = '' as $$
  insert into public.photo_ai_notices(version, provider_label, model, body)
  values (notice_version, notice_provider_label, notice_model, notice_body);
$$;
revoke all on function private.publish_photo_ai_notice(text, text, text, text)
from public, anon, authenticated;

create function private.current_photo_ai_notice()
returns public.photo_ai_notices language sql stable security definer set search_path = '' as $$
  select * from public.photo_ai_notices order by created_at desc, version desc limit 1;
$$;
revoke all on function private.current_photo_ai_notice() from public, anon, authenticated;

select private.publish_photo_ai_notice(
  'progress-photo-ai-v1',
  'Groq',
  'qwen/qwen3.8-27b',
  'A physique check is an AI visual estimate, not a measurement. When you start one, Tracend '
  'sends Groq the front, side and back photos of the set you choose, with your sex, height, '
  'latest weight and body measurements, and your goal. Groq runs the model qwen/qwen3.8-27b, '
  'which suggests up to three muscles to develop, relative to your own build. Your name, email '
  'address and other photos are not sent, and Tracend never asks for a body-fat figure or a '
  'score.' || E'\n\n' ||
  'Groq is run by Groq, Inc., a US company. Tracend has turned on Groq''s Zero Data Retention, so '
  'Groq does not keep the photos or its answer after replying. Tracend keeps your photos '
  'privately and saves the result in your account.' || E'\n\n' ||
  'Nothing changes on its own: you choose which suggestions become your focus muscles. You can '
  'turn photo checks off at any time. That stops new checks; past results stay until you delete '
  'the photo set or your account. Your other AI coaching uses a different provider and never '
  'receives your photos.'
);

-- Consent counts only when the athlete's newest progress_photo_ai record
-- grants exactly the current notice.
create function public.has_photo_ai_consent(target_user_id uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select coalesce((
    select record.action = 'granted'
      and record.notice_version = (private.current_photo_ai_notice()).version
    from public.consent_records record
    where record.user_id = target_user_id and record.consent_type = 'progress_photo_ai'
    order by record.created_at desc, record.id desc
    limit 1
  ), false);
$$;
revoke all on function public.has_photo_ai_consent(uuid) from public, anon, authenticated;
grant execute on function public.has_photo_ai_consent(uuid) to service_role;

-- The notice the app shows before a check, and whether the athlete granted it.
create function public.get_my_photo_ai_notice()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare notice public.photo_ai_notices;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  notice := private.current_photo_ai_notice();
  return jsonb_build_object(
    'schema_version', '1.0',
    'version', notice.version,
    'provider_label', notice.provider_label,
    'model', notice.model,
    'body', notice.body,
    'granted', public.has_photo_ai_consent(auth.uid()));
end $$;
revoke all on function public.get_my_photo_ai_notice() from public, anon, authenticated;
grant execute on function public.get_my_photo_ai_notice() to authenticated;

-- Analyses ------------------------------------------------------------------------

-- The model's answer, as the server validated it (_shared/physique/contract.ts):
-- 1-3 muscles to develop with confidence and a short reason, up to three
-- neutral observations, photo issues from a fixed list and the limitations.
-- No body-fat figure and no score can be stored.
create function private.is_valid_physique_result(result jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select jsonb_typeof(result) = 'object'
    and (select array_agg(key order by key) from jsonb_object_keys(result) key)
      = array['development_priorities','limitations','observations','photo_issues','schema_version']
    and result ->> 'schema_version' = '1.0'
    and jsonb_typeof(result -> 'development_priorities') = 'array'
    and jsonb_array_length(result -> 'development_priorities') between 1 and 3
    and not exists (
      select 1 from jsonb_array_elements(result -> 'development_priorities') item
      where not (
        jsonb_typeof(item) = 'object'
        and (select count(*) from jsonb_object_keys(item)) = 3
        and coalesce(item ->> 'muscle' in ('quads','glutes','hamstrings','chest','back',
          'shoulders','biceps','triceps','core','calves'), false)
        and coalesce(item ->> 'confidence' in ('low','medium','high'), false)
        and private.jsonb_text_between(item -> 'reason', 1, 120)
      )
    )
    and (select count(distinct item ->> 'muscle')
      from jsonb_array_elements(result -> 'development_priorities') item)
      = jsonb_array_length(result -> 'development_priorities')
    and jsonb_typeof(result -> 'observations') = 'array'
    and jsonb_array_length(result -> 'observations') <= 3
    and not exists (
      select 1 from jsonb_array_elements(result -> 'observations') item
      where not private.jsonb_text_between(item, 1, 160)
    )
    and jsonb_typeof(result -> 'photo_issues') = 'array'
    and jsonb_array_length(result -> 'photo_issues') <= 3
    and not exists (
      select 1 from jsonb_array_elements(result -> 'photo_issues') item
      where not coalesce(item #>> '{}' in ('lighting','pose','clothing','framing','blur','mismatch')
        and jsonb_typeof(item) = 'string', false)
    )
    and private.jsonb_text_between(result -> 'limitations', 1, 240);
$$;
revoke all on function private.is_valid_physique_result(jsonb) from public, anon, authenticated;

alter table public.physique_analyses
  add column result jsonb check (result is null or private.is_valid_physique_result(result)),
  add column notice_version text check (length(notice_version) between 1 and 32),
  add column confirmed_muscles text[] check (
    cardinality(confirmed_muscles) <= 2 and confirmed_muscles <@ array['quads','glutes',
      'hamstrings','chest','back','shoulders','biceps','triceps','core','calves']),
  add column confirmed_at timestamptz;

-- Called by physique-check with the service role after the result passed the
-- contract. One complete set is both the baseline and the current set.
create function public.persist_physique_analysis(
  target_user_id uuid,
  target_set_id uuid,
  analysis_result jsonb,
  run_provider text,
  run_model text,
  run_notice_version text,
  run_metadata jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare analysis_id uuid;
begin
  if not exists (select 1 from public.progress_photo_sets
    where id = target_set_id and user_id = target_user_id and status = 'complete') then
    raise exception 'photo set not found' using errcode = 'P0002';
  end if;
  if run_notice_version is distinct from (private.current_photo_ai_notice()).version then
    raise exception 'notice changed' using errcode = '22023';
  end if;
  insert into public.physique_analyses(
    user_id, baseline_photo_set_id, current_photo_set_id, provider, model, confidence,
    validation_state, result, notice_version
  ) values (
    target_user_id, target_set_id, target_set_id, run_provider, run_model,
    analysis_result #>> '{development_priorities,0,confidence}', 'validated',
    analysis_result, run_notice_version
  ) returning id into analysis_id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (target_user_id, 'progress.physique_check.completed', 'physique_analysis', analysis_id,
    'succeeded', jsonb_strip_nulls(jsonb_build_object(
      'provider', run_provider, 'model', run_model, 'notice_version', run_notice_version,
      'priorities', jsonb_array_length(analysis_result -> 'development_priorities'),
      'photo_issues', jsonb_array_length(analysis_result -> 'photo_issues')))
      || coalesce(run_metadata, '{}'::jsonb));
  return analysis_id;
end $$;
revoke all on function public.persist_physique_analysis(uuid, uuid, jsonb, text, text, text, jsonb)
from public, anon, authenticated;
grant execute on function public.persist_physique_analysis(uuid, uuid, jsonb, text, text, text, jsonb)
to service_role;

-- Focus muscles -----------------------------------------------------------------

-- The athlete's choice of up to two focus muscles, in catalog order. From a
-- physique check, only muscles that check suggested, and the analysis records
-- what was confirmed. The Coach reads them at once; the active plan keeps its
-- volume until its next review.
create function public.set_my_priority_muscles(muscles text[], source_analysis_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  catalog constant text[] := array['quads','glutes','hamstrings','chest','back','shoulders',
    'biceps','triceps','core','calves'];
  chosen text[];
  suggested text[];
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if muscles is null or not (muscles <@ catalog) then
    raise exception 'unknown muscle' using errcode = '22023';
  end if;
  chosen := array(select muscle from unnest(catalog) with ordinality catalog_muscle(muscle, ord)
    where muscle = any(muscles) order by ord);
  if cardinality(chosen) > 2 then
    raise exception 'at most two focus muscles' using errcode = '22023';
  end if;
  if source_analysis_id is not null then
    select array(select item ->> 'muscle'
      from jsonb_array_elements(result -> 'development_priorities') item)
    into suggested
    from public.physique_analyses
    where id = source_analysis_id and user_id = auth.uid() and result is not null;
    if suggested is null then raise exception 'analysis not found' using errcode = 'P0002'; end if;
    if not (chosen <@ suggested) then
      raise exception 'only suggested muscles' using errcode = '22023';
    end if;
  end if;
  update public.user_profiles set priority_muscles = chosen where user_id = auth.uid();
  if not found then raise exception 'profile not found' using errcode = 'P0002'; end if;
  if source_analysis_id is not null then
    update public.physique_analyses set confirmed_muscles = chosen, confirmed_at = now()
      where id = source_analysis_id and user_id = auth.uid();
  end if;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (auth.uid(), 'profile.priority_muscles.updated', 'user_profile', auth.uid(), 'succeeded',
    jsonb_build_object('muscles', to_jsonb(chosen),
      'source', case when source_analysis_id is null then 'athlete' else 'physique_check' end));
  return jsonb_build_object('schema_version', '1.0', 'priority_muscles', to_jsonb(chosen));
end $$;
revoke all on function public.set_my_priority_muscles(text[], uuid) from public, anon, authenticated;
grant execute on function public.set_my_priority_muscles(text[], uuid) to authenticated;

-- AI budget ---------------------------------------------------------------------

-- A physique check counts toward the daily request limit like every other
-- model call (its cost already counted toward the monthly stop).
create or replace function public.assert_owner_ai_budget(target_user_id uuid)
returns void language plpgsql security definer set search_path='' as $$
declare monthly_cost numeric; today_requests integer;
begin
  select coalesce(sum(estimated_cost_usd),0), count(*) filter(where purpose in
    ('daily_coaching','coach_chat','meal_vision','progress_vision','onboarding_plan','onboarding_questions')
    and created_at>=date_trunc('day',now()))
  into monthly_cost,today_requests from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=target_user_id and created_at>=date_trunc('month',now())
    union all select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=target_user_id and created_at>=date_trunc('month',now())
  ) usage;
  if monthly_cost>=2 then raise exception 'monthly cost limit reached' using errcode='P0001'; end if;
  if today_requests>=30 then raise exception 'daily rate limit reached' using errcode='P0001'; end if;
end $$;

create or replace function public.get_my_ai_budget_state()
returns jsonb language sql security definer set search_path='' stable as $$
with usage as (
  select coalesce(sum(estimated_cost_usd),0) monthly_cost,
    count(*) filter(where purpose in ('daily_coaching','coach_chat','meal_vision','progress_vision',
      'onboarding_plan','onboarding_questions')
      and created_at>=date_trunc('day',now())) today_requests
  from (
    select purpose,estimated_cost_usd,created_at from public.model_runs
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
    union all
    select purpose,estimated_cost_usd,created_at from public.ai_usage_events
    where user_id=auth.uid() and created_at>=date_trunc('month',now())
  ) all_usage
)
select jsonb_build_object('period','current_month','estimated_cost_usd',monthly_cost,
  'warning_threshold_usd',1,'hard_stop_usd',2,'warning',monthly_cost>=1,
  'blocked',monthly_cost>=2,'today_requests',today_requests,'daily_limit',30)
from usage;
$$;
