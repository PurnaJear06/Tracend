create extension if not exists pgmq;
create extension if not exists pg_cron;

select pgmq.create('weekly_reviews');

alter table public.feature_snapshots
  drop constraint feature_snapshots_trigger_kind_check;
alter table public.feature_snapshots
  add constraint feature_snapshots_trigger_kind_check
  check (trigger_kind in ('onboarding', 'daily', 'weekly'));

alter table public.progress_reviews
  add column feature_snapshot_id uuid,
  add column generation_kind text not null default 'deterministic'
    check (generation_kind = 'deterministic'),
  add constraint progress_reviews_feature_snapshot_owner
    foreign key (feature_snapshot_id, user_id)
    references public.feature_snapshots(id, user_id);

create type public.weekly_review_job_status as enum (
  'queued', 'processing', 'retryable', 'completed', 'failed', 'cancelled'
);

create table public.weekly_review_jobs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  review_week date not null,
  status public.weekly_review_job_status not null default 'queued',
  attempts smallint not null default 0 check (attempts between 0 and 3),
  max_attempts smallint not null default 3 check (max_attempts = 3),
  queue_message_id bigint,
  sanitized_error_code text check (
    sanitized_error_code is null or length(sanitized_error_code) between 1 and 80
  ),
  available_at timestamptz not null default now(),
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (user_id, review_week),
  unique (id, user_id),
  check (extract(isodow from review_week) = 1),
  check ((status = 'completed') = (completed_at is not null))
);

create index weekly_review_jobs_status_available
on public.weekly_review_jobs(status, available_at);
create index weekly_review_jobs_user_week
on public.weekly_review_jobs(user_id, review_week desc);

alter table public.weekly_review_jobs enable row level security;
alter table public.weekly_review_jobs force row level security;
create policy weekly_review_jobs_own_read on public.weekly_review_jobs
for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.weekly_review_jobs from anon, authenticated;
grant select on public.weekly_review_jobs to authenticated;

create function private.enqueue_weekly_review_job(
  target_user_id uuid,
  target_review_week date
) returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  job_id uuid;
  message_id bigint;
begin
  if extract(isodow from target_review_week) <> 1 then
    raise exception 'review week must start on Monday' using errcode = '22023';
  end if;

  insert into public.weekly_review_jobs(user_id, review_week)
  values (target_user_id, target_review_week)
  on conflict (user_id, review_week) do update
    set updated_at = public.weekly_review_jobs.updated_at
  returning id into job_id;

  if exists (
    select 1 from public.weekly_review_jobs
    where id = job_id and status in ('completed', 'processing', 'queued', 'retryable')
      and queue_message_id is not null
  ) then
    return job_id;
  end if;

  select pgmq.send('weekly_reviews', jsonb_build_object(
    'schema_version', '1.0', 'job_id', job_id
  )) into message_id;

  update public.weekly_review_jobs
  set status = 'queued', queue_message_id = message_id,
      available_at = now(), updated_at = now(), sanitized_error_code = null
  where id = job_id and status <> 'completed';
  return job_id;
end
$$;

create function public.request_my_weekly_review(target_review_week date)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  local_today date;
  current_monday date;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  select timezone(a.timezone, now())::date into local_today
  from public.user_accounts a
  where a.id = auth.uid() and a.account_status = 'active'
    and a.onboarding_state = 'completed';
  if local_today is null then
    raise exception 'active completed account required' using errcode = '42501';
  end if;
  current_monday := local_today - (extract(isodow from local_today)::integer - 1);
  if extract(isodow from target_review_week) <> 1
    or target_review_week < current_monday - 56
    or target_review_week > current_monday
  then
    raise exception 'invalid review week' using errcode = '22023';
  end if;
  return private.enqueue_weekly_review_job(auth.uid(), target_review_week);
end
$$;

create function public.schedule_weekly_progress_reviews()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  account record;
  target_week date;
  scheduled integer := 0;
begin
  for account in
    select id, timezone from public.user_accounts
    where account_status = 'active' and onboarding_state = 'completed'
  loop
    target_week := timezone(account.timezone, now())::date;
    target_week := target_week
      - (extract(isodow from target_week)::integer - 1) - 7;
    perform private.enqueue_weekly_review_job(account.id, target_week);
    scheduled := scheduled + 1;
  end loop;
  return scheduled;
end
$$;

create function private.generate_weekly_progress_review(target_job_id uuid)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.weekly_review_jobs%rowtype;
  account public.user_accounts%rowtype;
  week_end date;
  planned_sessions integer := 0;
  completed_workouts integer := 0;
  completed_sets integer := 0;
  check_in_days integer := 0;
  meal_days integer := 0;
  health_days integer := 0;
  measurement_days integer := 0;
  average_energy numeric;
  average_soreness numeric;
  features jsonb;
  coverage jsonb;
  missing text[] := '{}';
  snapshot_hash text;
  snapshot_id uuid;
  review_id uuid;
  outcome_code text;
  adherence_percent integer;
begin
  select * into job from public.weekly_review_jobs
  where id = target_job_id for update;
  if not found then
    raise exception 'weekly review job not found' using errcode = 'P0002';
  end if;
  if job.status = 'completed' then
    select id into review_id from public.progress_reviews
    where user_id = job.user_id and review_week = job.review_week;
    return review_id;
  end if;
  select * into account from public.user_accounts
  where id = job.user_id and account_status = 'active'
    and onboarding_state = 'completed';
  if not found then
    update public.weekly_review_jobs
    set status = 'cancelled', updated_at = now(),
        sanitized_error_code = 'account_ineligible'
    where id = job.id;
    return null;
  end if;

  week_end := job.review_week + 6;
  update public.weekly_review_jobs
  set status = 'processing', attempts = attempts + 1,
      started_at = now(), updated_at = now()
  where id = job.id;

  select coalesce(max(sessions_per_week), 0) into planned_sessions
  from public.training_plan_versions
  where user_id = job.user_id and status = 'active';
  select count(*) into completed_workouts from public.workout_sessions
  where user_id = job.user_id and state = 'completed'
    and local_date between job.review_week and week_end;
  select count(*) into completed_sets
  from public.exercise_sets s
  join public.exercise_performances p on p.id = s.exercise_performance_id
  join public.workout_sessions w on w.id = p.workout_session_id
  where w.user_id = job.user_id and w.state = 'completed' and s.completed
    and w.local_date between job.review_week and week_end;
  select count(distinct local_date), round(avg(energy), 1), round(avg(soreness), 1)
  into check_in_days, average_energy, average_soreness
  from public.daily_check_ins
  where user_id = job.user_id and superseded_at is null
    and local_date between job.review_week and week_end;
  select count(distinct local_date) into meal_days from public.meals
  where user_id = job.user_id and status = 'confirmed'
    and local_date between job.review_week and week_end;
  select count(distinct local_date) into health_days
  from public.daily_health_summaries
  where user_id = job.user_id
    and local_date between job.review_week and week_end;
  select count(distinct measured_on) into measurement_days
  from public.body_measurements
  where user_id = job.user_id
    and measured_on between job.review_week and week_end;

  if planned_sessions = 0 then
    missing := array_append(missing, 'active_training_plan');
    adherence_percent := 0;
  else
    adherence_percent := least(100, round(completed_workouts * 100.0 / planned_sessions));
  end if;
  if check_in_days = 0 then missing := array_append(missing, 'recovery_check_ins'); end if;
  if meal_days = 0 then missing := array_append(missing, 'confirmed_nutrition'); end if;
  if health_days = 0 then missing := array_append(missing, 'health_context'); end if;
  outcome_code := case
    when completed_workouts = 0 then 'gather_execution_data'
    when check_in_days = 0 then 'training_logged_recovery_missing'
    else 'week_observed'
  end;

  features := jsonb_build_object(
    'review_week', job.review_week,
    'week_end', week_end,
    'timezone', account.timezone,
    'training', jsonb_build_object(
      'planned_sessions', planned_sessions,
      'completed_workouts', completed_workouts,
      'completed_sets', completed_sets,
      'adherence_percent', adherence_percent
    ),
    'recovery', jsonb_build_object(
      'check_in_days', check_in_days,
      'average_energy', average_energy,
      'average_soreness', average_soreness,
      'health_days', health_days
    ),
    'nutrition', jsonb_build_object('confirmed_days', meal_days),
    'progress', jsonb_build_object('measurement_days', measurement_days)
  );
  coverage := jsonb_build_object(
    'training', completed_workouts > 0,
    'recovery', check_in_days > 0,
    'nutrition', meal_days > 0,
    'health', health_days > 0,
    'measurements', measurement_days > 0
  );
  snapshot_hash := encode(
    extensions.digest(convert_to(features::text, 'UTF8'), 'sha256'), 'hex'
  );
  insert into public.feature_snapshots(
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    job.user_id, 'weekly', '1.0', 'weekly-deterministic-v1',
    features, coverage, missing, snapshot_hash
  ) on conflict(user_id, data_hash) do update
    set data_hash = excluded.data_hash
  returning id into snapshot_id;

  insert into public.progress_reviews(
    user_id, review_week, schema_version, summary,
    feature_snapshot_id, generation_kind
  ) values (
    job.user_id, job.review_week, '1.0',
    jsonb_build_object(
      'outcome_code', outcome_code,
      'training', features->'training',
      'recovery', features->'recovery',
      'nutrition', features->'nutrition',
      'progress', features->'progress',
      'missing_data', to_jsonb(missing),
      'unchanged', jsonb_build_object(
        'approved_plan', true,
        'nutrition_targets', true,
        'reason_code', 'no_persistent_change_from_weekly_review'
      ),
      'next_focus_code', case
        when completed_workouts = 0 then 'complete_next_planned_workout'
        when check_in_days = 0 then 'record_recovery_check_in'
        when meal_days = 0 then 'confirm_nutrition'
        else 'continue_approved_plan'
      end,
      'proposal_ids', '[]'::jsonb
    ), snapshot_id, 'deterministic'
  ) on conflict(user_id, review_week) do update
    set summary = excluded.summary,
        feature_snapshot_id = excluded.feature_snapshot_id,
        generation_kind = excluded.generation_kind
  returning id into review_id;

  update public.weekly_review_jobs
  set status = 'completed', completed_at = now(), updated_at = now(),
      sanitized_error_code = null
  where id = job.id;
  insert into public.audit_events(
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    job.user_id, 'progress.weekly_review.created', 'progress_review',
    review_id, 'succeeded', jsonb_build_object(
      'review_week', job.review_week, 'schema_version', '1.0',
      'generation_kind', 'deterministic'
    )
  );
  return review_id;
end
$$;

create function private.record_weekly_review_failure(
  target_job_id uuid,
  error_code text
) returns public.weekly_review_job_status
language plpgsql
security definer
set search_path = ''
as $$
declare
  job public.weekly_review_jobs%rowtype;
  next_status public.weekly_review_job_status;
  message_id bigint;
begin
  if error_code is null or length(error_code) not between 1 and 80 then
    raise exception 'invalid error code' using errcode = '22023';
  end if;
  select * into job from public.weekly_review_jobs
  where id = target_job_id for update;
  if not found then return null; end if;
  next_status := case when job.attempts + 1 >= job.max_attempts
    then 'failed'::public.weekly_review_job_status
    else 'retryable'::public.weekly_review_job_status end;
  if next_status = 'retryable' then
    select pgmq.send('weekly_reviews', jsonb_build_object(
      'schema_version', '1.0', 'job_id', job.id
    ), least(3600, 60 * (job.attempts + 2))) into message_id;
  end if;
  update public.weekly_review_jobs
  set status = next_status, attempts = least(max_attempts, attempts + 1),
      queue_message_id = message_id,
      available_at = case when next_status = 'retryable'
        then now() + make_interval(secs => least(3600, 60 * (attempts + 2)))
        else available_at end,
      sanitized_error_code = error_code, updated_at = now()
  where id = job.id;
  return next_status;
end
$$;

create function public.process_weekly_progress_reviews(batch_size integer default 10)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  message record;
  job_id uuid;
  processed integer := 0;
  completed integer := 0;
  failed integer := 0;
begin
  if batch_size not between 1 and 50 then
    raise exception 'invalid batch size' using errcode = '22023';
  end if;
  for message in select * from pgmq.read('weekly_reviews', 120, batch_size)
  loop
    processed := processed + 1;
    job_id := null;
    begin
      if message.message->>'schema_version' <> '1.0'
        or coalesce(message.message->>'job_id', '') !~
          '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      then
        raise exception 'invalid queue message' using errcode = '22023';
      end if;
      job_id := (message.message->>'job_id')::uuid;
      if not exists(select 1 from public.weekly_review_jobs where id = job_id) then
        perform pgmq.archive('weekly_reviews', message.msg_id);
        continue;
      end if;
      perform private.generate_weekly_progress_review(job_id);
      perform pgmq.archive('weekly_reviews', message.msg_id);
      completed := completed + 1;
    exception when others then
      if job_id is not null then
        perform private.record_weekly_review_failure(job_id, 'generation_failed');
      end if;
      perform pgmq.archive('weekly_reviews', message.msg_id);
      failed := failed + 1;
    end;
  end loop;
  return jsonb_build_object(
    'schema_version', '1.0', 'processed', processed,
    'completed', completed, 'failed', failed
  );
end
$$;

create function public.acknowledge_my_progress_review(target_review_id uuid)
returns boolean
language plpgsql
security definer
set search_path = ''
as $$
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  update public.progress_reviews
  set acknowledged_at = coalesce(acknowledged_at, now())
  where id = target_review_id and user_id = auth.uid();
  return found;
end
$$;

revoke all on function private.enqueue_weekly_review_job(uuid, date),
  private.generate_weekly_progress_review(uuid),
  private.record_weekly_review_failure(uuid, text)
  from public, anon, authenticated, service_role;
revoke all on function public.request_my_weekly_review(date),
  public.schedule_weekly_progress_reviews(),
  public.process_weekly_progress_reviews(integer),
  public.acknowledge_my_progress_review(uuid)
  from public, anon, authenticated, service_role;
grant execute on function public.request_my_weekly_review(date),
  public.acknowledge_my_progress_review(uuid) to authenticated;
grant execute on function public.schedule_weekly_progress_reviews(),
  public.process_weekly_progress_reviews(integer) to service_role;

select cron.schedule(
  'tracend-schedule-weekly-progress-reviews',
  '30 3 * * *',
  'select public.schedule_weekly_progress_reviews()'
);
select cron.schedule(
  'tracend-process-weekly-progress-reviews',
  '*/5 * * * *',
  'select public.process_weekly_progress_reviews(10)'
);
