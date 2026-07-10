create type public.consent_type as enum ('terms', 'privacy');
create type public.consent_action as enum ('granted', 'withdrawn');
create type public.onboarding_path as enum ('beginner', 'experienced');
create type public.experience_level as enum ('beginner', 'intermediate', 'advanced');
create type public.goal_type as enum ('fat_loss', 'muscle_gain', 'recomposition', 'strength', 'aesthetic');
create type public.goal_status as enum ('draft', 'active', 'superseded');
create type public.version_status as enum ('draft', 'proposed', 'active', 'superseded', 'archived');
create type public.proposal_status as enum ('pending', 'accepted', 'rejected', 'revision_requested', 'expired');
create type public.proposal_response_action as enum ('accept', 'reject', 'request_revision');

create table public.user_profiles (
  user_id uuid primary key references public.user_accounts (id) on delete cascade,
  adult_attested_at timestamptz,
  eligible boolean,
  experience_level public.experience_level,
  height_cm numeric(5, 2) check (height_cm between 100 and 250),
  training_days smallint[] not null default '{}',
  session_minutes smallint check (session_minutes between 15 and 180),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version integer not null default 1 check (row_version > 0),
  check (
    training_days <@ array[1, 2, 3, 4, 5, 6, 7]::smallint[]
    and cardinality(training_days) <= 7
  )
);

create table public.consent_records (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  consent_type public.consent_type not null,
  notice_version text not null check (length(notice_version) between 1 and 32),
  action public.consent_action not null,
  source text not null check (source in ('owner_development', 'ios_app')),
  created_at timestamptz not null default now()
);

create table public.onboarding_drafts (
  user_id uuid primary key references public.user_accounts (id) on delete cascade,
  path public.onboarding_path,
  current_section text not null default 'eligibility' check (length(current_section) between 1 and 64),
  payload jsonb not null default '{}'::jsonb check (jsonb_typeof(payload) = 'object'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  row_version integer not null default 1 check (row_version > 0)
);

create table public.user_goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  goal_type public.goal_type not null,
  priority smallint not null default 1 check (priority between 1 and 5),
  status public.goal_status not null default 'draft',
  details jsonb not null default '{}'::jsonb check (jsonb_typeof(details) = 'object'),
  created_at timestamptz not null default now(),
  activated_at timestamptz
);

create unique index user_goals_one_primary_active
on public.user_goals (user_id)
where status = 'active' and priority = 1;

create table public.feature_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  trigger_kind text not null check (trigger_kind = 'onboarding'),
  schema_version text not null check (schema_version = '1.0'),
  feature_engine_version text not null,
  features jsonb not null check (jsonb_typeof(features) = 'object'),
  coverage jsonb not null default '{}'::jsonb check (jsonb_typeof(coverage) = 'object'),
  missing_data text[] not null default '{}',
  data_hash text not null check (length(data_hash) between 16 and 128),
  created_at timestamptz not null default now(),
  unique (user_id, data_hash)
);

alter table public.feature_snapshots
  add constraint feature_snapshots_id_user_unique unique (id, user_id);

create table public.training_plans (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  goal_id uuid references public.user_goals (id),
  title text not null check (length(title) between 1 and 120),
  source text not null check (source in ('mock_ai', 'user', 'imported', 'hybrid')),
  created_at timestamptz not null default now(),
  unique (id, user_id)
);

create table public.training_plan_versions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  plan_id uuid not null,
  version_number integer not null check (version_number > 0),
  status public.version_status not null,
  block_weeks smallint not null check (block_weeks between 1 and 24),
  sessions_per_week smallint not null check (sessions_per_week between 1 and 7),
  prescription jsonb not null check (jsonb_typeof(prescription) = 'object'),
  rationale text not null check (length(rationale) between 1 and 2000),
  source_proposal_id uuid,
  approved_at timestamptz,
  effective_date date,
  created_at timestamptz not null default now(),
  foreign key (plan_id, user_id) references public.training_plans (id, user_id) on delete cascade,
  unique (plan_id, version_number),
  unique (id, user_id)
);

create unique index training_plan_versions_one_active_per_user
on public.training_plan_versions (user_id)
where status = 'active';

create table public.nutrition_target_sets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  version_number integer not null check (version_number > 0),
  status public.version_status not null,
  calories integer not null check (calories between 1000 and 6000),
  protein_g integer not null check (protein_g between 30 and 400),
  carbohydrate_g integer not null check (carbohydrate_g between 20 and 1000),
  fat_g integer not null check (fat_g between 20 and 300),
  rationale text not null check (length(rationale) between 1 and 2000),
  source_proposal_id uuid,
  approved_at timestamptz,
  effective_date date,
  created_at timestamptz not null default now(),
  unique (user_id, version_number),
  unique (id, user_id)
);

create unique index nutrition_target_sets_one_active_per_user
on public.nutrition_target_sets (user_id)
where status = 'active';

create function private.is_valid_initial_proposal(
  training jsonb,
  nutrition jsonb
)
returns boolean
language sql
immutable
strict
set search_path = ''
as $$
  select
    jsonb_typeof(training) = 'object'
    and jsonb_typeof(training -> 'title') = 'string'
    and jsonb_typeof(training -> 'block_weeks') = 'number'
    and (training ->> 'block_weeks')::integer between 1 and 24
    and jsonb_typeof(training -> 'sessions_per_week') = 'number'
    and (training ->> 'sessions_per_week')::integer between 1 and 7
    and jsonb_typeof(training -> 'weekly_structure') = 'array'
    and jsonb_array_length(training -> 'weekly_structure') between 1 and 7
    and jsonb_typeof(training -> 'prescription') = 'object'
    and jsonb_typeof(nutrition) = 'object'
    and jsonb_typeof(nutrition -> 'calories') = 'number'
    and (nutrition ->> 'calories')::integer between 1000 and 6000
    and jsonb_typeof(nutrition -> 'protein_g') = 'number'
    and (nutrition ->> 'protein_g')::integer between 30 and 400
    and jsonb_typeof(nutrition -> 'carbohydrate_g') = 'number'
    and (nutrition ->> 'carbohydrate_g')::integer between 20 and 1000
    and jsonb_typeof(nutrition -> 'fat_g') = 'number'
    and (nutrition ->> 'fat_g')::integer between 20 and 300;
$$;

revoke all on function private.is_valid_initial_proposal(jsonb, jsonb)
from public, anon, authenticated;

create table public.change_proposals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  feature_snapshot_id uuid not null,
  schema_version text not null check (schema_version = '1.0'),
  proposed_training jsonb not null,
  proposed_nutrition jsonb not null,
  evidence jsonb not null check (jsonb_typeof(evidence) = 'array'),
  rationale text not null check (length(rationale) between 1 and 2000),
  expected_benefit text not null check (length(expected_benefit) between 1 and 1000),
  downside text not null check (length(downside) between 1 and 1000),
  confidence text not null check (confidence in ('low', 'medium', 'high')),
  effective_date date not null,
  expires_at timestamptz not null,
  status public.proposal_status not null default 'pending',
  created_at timestamptz not null default now(),
  foreign key (feature_snapshot_id, user_id) references public.feature_snapshots (id, user_id),
  constraint change_proposals_valid_payload check (
    private.is_valid_initial_proposal(proposed_training, proposed_nutrition)
  ),
  unique (id, user_id)
);

alter table public.training_plan_versions
  add constraint training_plan_versions_source_proposal_fk
  foreign key (source_proposal_id, user_id) references public.change_proposals (id, user_id);
alter table public.nutrition_target_sets
  add constraint nutrition_target_sets_source_proposal_fk
  foreign key (source_proposal_id, user_id) references public.change_proposals (id, user_id);

create table public.change_responses (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  proposal_id uuid not null,
  action public.proposal_response_action not null,
  created_at timestamptz not null default now(),
  foreign key (proposal_id, user_id) references public.change_proposals (id, user_id),
  unique (proposal_id)
);

create table public.audit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  action_code text not null check (length(action_code) between 1 and 80),
  target_type text not null check (length(target_type) between 1 and 80),
  target_id uuid not null,
  outcome text not null check (outcome in ('succeeded', 'rejected')),
  metadata jsonb not null default '{}'::jsonb check (jsonb_typeof(metadata) = 'object'),
  created_at timestamptz not null default now()
);

create function private.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.user_accounts (id) values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

revoke all on function private.handle_new_auth_user()
from public, anon, authenticated;

create trigger auth_user_create_account
after insert on auth.users
for each row execute function private.handle_new_auth_user();

create trigger user_profiles_set_updated_at_and_version
before update on public.user_profiles
for each row execute function private.set_updated_at_and_version();

create trigger onboarding_drafts_set_updated_at_and_version
before update on public.onboarding_drafts
for each row execute function private.set_updated_at_and_version();

alter table public.user_profiles enable row level security;
alter table public.user_profiles force row level security;
alter table public.consent_records enable row level security;
alter table public.consent_records force row level security;
alter table public.onboarding_drafts enable row level security;
alter table public.onboarding_drafts force row level security;
alter table public.user_goals enable row level security;
alter table public.user_goals force row level security;
alter table public.feature_snapshots enable row level security;
alter table public.feature_snapshots force row level security;
alter table public.training_plans enable row level security;
alter table public.training_plans force row level security;
alter table public.training_plan_versions enable row level security;
alter table public.training_plan_versions force row level security;
alter table public.nutrition_target_sets enable row level security;
alter table public.nutrition_target_sets force row level security;
alter table public.change_proposals enable row level security;
alter table public.change_proposals force row level security;
alter table public.change_responses enable row level security;
alter table public.change_responses force row level security;
alter table public.audit_events enable row level security;
alter table public.audit_events force row level security;

create policy user_profiles_own on public.user_profiles
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy consent_records_select_own on public.consent_records
for select to authenticated using (user_id = (select auth.uid()));
create policy consent_records_insert_own on public.consent_records
for insert to authenticated with check (user_id = (select auth.uid()));
create policy onboarding_drafts_own on public.onboarding_drafts
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy user_goals_own on public.user_goals
for all to authenticated using (user_id = (select auth.uid()))
with check (user_id = (select auth.uid()));
create policy feature_snapshots_select_own on public.feature_snapshots
for select to authenticated using (user_id = (select auth.uid()));
create policy training_plans_select_own on public.training_plans
for select to authenticated using (user_id = (select auth.uid()));
create policy training_plan_versions_select_own on public.training_plan_versions
for select to authenticated using (user_id = (select auth.uid()));
create policy nutrition_target_sets_select_own on public.nutrition_target_sets
for select to authenticated using (user_id = (select auth.uid()));
create policy change_proposals_select_own on public.change_proposals
for select to authenticated using (user_id = (select auth.uid()));
create policy change_responses_select_own on public.change_responses
for select to authenticated using (user_id = (select auth.uid()));
create policy audit_events_select_own on public.audit_events
for select to authenticated using (user_id = (select auth.uid()));

revoke all on public.user_profiles, public.consent_records, public.onboarding_drafts,
  public.user_goals, public.feature_snapshots, public.training_plans,
  public.training_plan_versions, public.nutrition_target_sets,
  public.change_proposals, public.change_responses, public.audit_events
from anon, authenticated;

grant select, insert, update on public.user_profiles to authenticated;
grant select, insert on public.consent_records to authenticated;
grant select, insert, update on public.onboarding_drafts to authenticated;
grant select, insert, update on public.user_goals to authenticated;
grant select on public.feature_snapshots, public.training_plans,
  public.training_plan_versions, public.nutrition_target_sets,
  public.change_proposals, public.change_responses, public.audit_events
to authenticated;

create function public.respond_to_onboarding_proposal(
  proposal_id uuid,
  response_action public.proposal_response_action
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $$
declare
  proposal public.change_proposals%rowtype;
  plan_id uuid;
  plan_version_id uuid;
  nutrition_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;

  select * into proposal
  from public.change_proposals
  where id = proposal_id and user_id = auth.uid()
  for update;

  if not found then
    raise exception 'proposal not found' using errcode = 'P0002';
  end if;
  if proposal.status <> 'pending' then
    raise exception 'proposal is not pending' using errcode = '55000';
  end if;
  if proposal.expires_at <= statement_timestamp() then
    update public.change_proposals set status = 'expired' where id = proposal.id;
    raise exception 'proposal is stale' using errcode = '55000';
  end if;
  if not private.is_valid_initial_proposal(proposal.proposed_training, proposal.proposed_nutrition) then
    raise exception 'proposal payload is invalid' using errcode = '22023';
  end if;

  if response_action = 'accept' then
    update public.training_plan_versions
      set status = 'superseded'
      where user_id = auth.uid() and status = 'active';
    update public.nutrition_target_sets
      set status = 'superseded'
      where user_id = auth.uid() and status = 'active';

    insert into public.training_plans (user_id, title, source)
    values (auth.uid(), proposal.proposed_training ->> 'title', 'mock_ai')
    returning id into plan_id;

    insert into public.training_plan_versions (
      user_id, plan_id, version_number, status, block_weeks,
      sessions_per_week, prescription, rationale, source_proposal_id,
      approved_at, effective_date
    ) values (
      auth.uid(), plan_id, 1, 'active',
      (proposal.proposed_training ->> 'block_weeks')::smallint,
      (proposal.proposed_training ->> 'sessions_per_week')::smallint,
      proposal.proposed_training -> 'prescription', proposal.rationale,
      proposal.id, statement_timestamp(), proposal.effective_date
    ) returning id into plan_version_id;

    insert into public.nutrition_target_sets (
      user_id, version_number, status, calories, protein_g, carbohydrate_g,
      fat_g, rationale, source_proposal_id, approved_at, effective_date
    ) values (
      auth.uid(),
      coalesce((select max(version_number) + 1 from public.nutrition_target_sets where user_id = auth.uid()), 1),
      'active',
      (proposal.proposed_nutrition ->> 'calories')::integer,
      (proposal.proposed_nutrition ->> 'protein_g')::integer,
      (proposal.proposed_nutrition ->> 'carbohydrate_g')::integer,
      (proposal.proposed_nutrition ->> 'fat_g')::integer,
      proposal.rationale, proposal.id, statement_timestamp(), proposal.effective_date
    ) returning id into nutrition_id;

    update public.change_proposals set status = 'accepted' where id = proposal.id;
    update public.user_accounts set onboarding_state = 'completed' where id = auth.uid();
  elsif response_action = 'reject' then
    update public.change_proposals set status = 'rejected' where id = proposal.id;
  else
    update public.change_proposals set status = 'revision_requested' where id = proposal.id;
  end if;

  insert into public.change_responses (user_id, proposal_id, action)
  values (auth.uid(), proposal.id, response_action);

  insert into public.audit_events (
    user_id, action_code, target_type, target_id, outcome, metadata
  ) values (
    auth.uid(), 'onboarding_proposal_' || response_action::text,
    'change_proposal', proposal.id, 'succeeded',
    jsonb_build_object('schema_version', proposal.schema_version)
  );

  return jsonb_build_object(
    'proposal_id', proposal.id,
    'status', case response_action
      when 'accept' then 'accepted'
      when 'reject' then 'rejected'
      else 'revision_requested'
    end,
    'training_plan_version_id', plan_version_id,
    'nutrition_target_set_id', nutrition_id
  );
end;
$$;

revoke all on function public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)
from public, anon, authenticated;
grant execute on function public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)
to authenticated;
