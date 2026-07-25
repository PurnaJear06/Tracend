create table public.user_baselines (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  metric_name text not null check (metric_name in (
    'hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_minutes', 'weight_kg'
  )),
  baseline_value numeric not null,
  spread numeric not null check (spread >= 0),
  n_observations integer not null check (n_observations >= 0),
  confidence text not null check (confidence in (
    'cold_start', 'low', 'medium', 'high'
  )),
  last_calculated_at timestamptz not null default now(),
  last_observation_date date,
  engine_version text not null default 'baseline-v1',
  unique (user_id, metric_name),
  unique (id, user_id)
);

create table public.metric_baseline_history (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  metric_name text not null check (metric_name in (
    'hrv_sdnn_ms', 'resting_hr_bpm', 'sleep_minutes', 'weight_kg'
  )),
  baseline_value numeric not null,
  spread numeric,
  n_observations integer not null check (n_observations >= 0),
  observation_date date,
  raw_value numeric,
  was_winsorized boolean not null default false,
  was_outlier_rejected boolean not null default false,
  lambda_used numeric not null,
  prior_baseline_id uuid references public.metric_baseline_history(id),
  engine_version text not null default 'baseline-v1',
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create index user_baselines_user
on public.user_baselines(user_id);

create index metric_baseline_history_user_metric_date
on public.metric_baseline_history(user_id, metric_name, observation_date desc);

alter table public.user_baselines enable row level security;
alter table public.user_baselines force row level security;
alter table public.metric_baseline_history enable row level security;
alter table public.metric_baseline_history force row level security;

create policy user_baselines_own_read on public.user_baselines
  for select to authenticated
  using (user_id = (select auth.uid()));

create policy metric_baseline_history_own_read on public.metric_baseline_history
  for select to authenticated
  using (user_id = (select auth.uid()));

revoke all on public.user_baselines, public.metric_baseline_history
  from anon, authenticated;

grant select on public.user_baselines, public.metric_baseline_history
  to authenticated;
