-- Pre-exercise screening gate (coaching platform Contract 8, chunk B6).
--
-- 1. public.onboarding_screenings keeps what the athlete answered before the first plan, the
--    outcome and the date. Rows are only added, so every answer the athlete gave stays on record;
--    the newest row is the current one. An athlete who was never screened (an account made before
--    this migration, or an app build that does not ask) has no row, and no row reads as "cleared".
-- 2. record_screening_v1 stores one screening for the caller. The database works out the outcome
--    from the four answers (the same rule as _shared/training/screening/screening.ts), and a check
--    constraint keeps a stored outcome from ever disagreeing with its answers.
-- Server code (service role) reads the newest row of a user directly; the app only records.
-- The outcome only caps the plan's intensity or stops plan building; it never diagnoses anything.
-- Everything is additive.

-- 1. Table ------------------------------------------------------------------------------------

-- Own words, following the ACSM 2015 preparticipation logic: any current sign or symptom, or no
-- regular exercise with a known heart, metabolic or kidney condition and no clearance, means see
-- a professional first; regular exercise with a known condition and no clearance means moderate
-- effort until cleared; everything else is cleared.
create function private.screening_outcome(
  exercises_regularly boolean, known_disease boolean, symptoms boolean, cleared_by_professional boolean)
returns text language sql immutable set search_path = '' as $$
  select case
    when symptoms then 'see_professional'
    when known_disease and not cleared_by_professional and not exercises_regularly
      then 'see_professional'
    when known_disease and not cleared_by_professional then 'moderate_until_cleared'
    else 'cleared'
  end
$$;
revoke all on function private.screening_outcome(boolean, boolean, boolean, boolean)
  from public, anon, authenticated;

create table public.onboarding_screenings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  exercises_regularly boolean not null,
  known_disease boolean not null,
  symptoms boolean not null,
  cleared_by_professional boolean not null default false,
  outcome text not null,
  screened_at timestamptz not null default clock_timestamp(),
  constraint onboarding_screenings_outcome_check check (
    outcome in ('cleared', 'moderate_until_cleared', 'see_professional')),
  constraint onboarding_screenings_outcome_matches_answers check (
    outcome = private.screening_outcome(
      exercises_regularly, known_disease, symptoms, cleared_by_professional))
);

create index onboarding_screenings_user_newest
  on public.onboarding_screenings (user_id, screened_at desc);

comment on table public.onboarding_screenings is
  'Pre-plan screening answers, the outcome (cleared, moderate_until_cleared, see_professional) and the date. Append-only; the newest row per user is current; no row reads as cleared.';
comment on column public.onboarding_screenings.cleared_by_professional is
  'True when a professional has cleared the athlete to exercise. False when not asked (no known condition, or a current symptom).';

alter table public.onboarding_screenings enable row level security;
alter table public.onboarding_screenings force row level security;
create policy onboarding_screenings_own_read on public.onboarding_screenings
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.onboarding_screenings from anon, authenticated;
grant select on public.onboarding_screenings to authenticated;

-- 2. Record -----------------------------------------------------------------------------------

create function public.record_screening_v1(
  exercises_regularly boolean,
  known_disease boolean,
  symptoms boolean,
  cleared_by_professional boolean default false)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  newest public.onboarding_screenings%rowtype;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if exercises_regularly is null or known_disease is null or symptoms is null
    or cleared_by_professional is null then
    raise exception 'every screening answer is required' using errcode = '22023';
  end if;

  select * into newest from public.onboarding_screenings s
  where s.user_id = auth.uid() order by s.screened_at desc, s.id desc limit 1;

  -- Answering the same again adds no row, so passing the step twice keeps one record.
  if not found
    or newest.exercises_regularly is distinct from record_screening_v1.exercises_regularly
    or newest.known_disease is distinct from record_screening_v1.known_disease
    or newest.symptoms is distinct from record_screening_v1.symptoms
    or newest.cleared_by_professional is distinct from record_screening_v1.cleared_by_professional
  then
    insert into public.onboarding_screenings(user_id, exercises_regularly, known_disease, symptoms,
      cleared_by_professional, outcome)
    values (auth.uid(), record_screening_v1.exercises_regularly, record_screening_v1.known_disease,
      record_screening_v1.symptoms, record_screening_v1.cleared_by_professional,
      private.screening_outcome(record_screening_v1.exercises_regularly,
        record_screening_v1.known_disease, record_screening_v1.symptoms,
        record_screening_v1.cleared_by_professional))
    returning * into newest;
    insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
    values (auth.uid(), 'onboarding_screening_recorded', 'onboarding_screening', newest.id,
      'succeeded', jsonb_build_object('screening_outcome', newest.outcome));
  end if;

  return jsonb_build_object('schema_version', '1.0', 'outcome', newest.outcome,
    'screened_at', newest.screened_at);
end $$;
revoke all on function public.record_screening_v1(boolean, boolean, boolean, boolean)
  from public, anon, authenticated;
grant execute on function public.record_screening_v1(boolean, boolean, boolean, boolean)
  to authenticated;
