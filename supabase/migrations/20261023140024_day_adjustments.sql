-- B4-1: readiness rules and the same-day adjustment (server side).
--
-- Today's session can be eased for one day. The rules read today's check-in (they lead), last
-- night's sleep and the recovery score, and propose one of three things for today's scheduled
-- workout only: hold last time's loads, one set fewer, or easy cardio instead. The athlete answers
-- with one tap; the answer is stored with an audit event. Nothing in training_plan_versions changes:
-- a same-day adjustment is an overlay that expires with the day (AI_SAFETY_SPEC section 5).
--
--   1. public.day_adjustments               the athlete's answers; owner read, no client write
--   2. workout_sessions.day_adjustment_id   the answer a session was started under
--   3. private.readiness_rules()            every number of the rules, in one place
--   4. private.readiness_rank, readiness_assessment
--                                           the pure decision: band, triggers, points, kind
--   5. private.day_adjustment_changes       what each kind changes in today's session
--   6. private.day_adjustment_explanation   fixed sentences keyed by trigger and kind (no model)
--   7. private.day_adjustment_compute, _stands, _present, _refresh_metrics
--   8. public.get_my_day_adjustment_v1, public.respond_to_day_adjustment_v1
--   9. private.progression_decision, private.next_session_targets
--                                           a session done under an adjustment never lowers a load
--  10. public.start_workout                 builds the session with the adjusted set count
--
-- A poor check-in alone is enough; the recovery score never applies or picks an adjustment by
-- itself (decision D9, owner 2026-10-23): it adds a point only next to a point from the check-in, and
-- otherwise only tells the athlete what it shows. The athlete may choose any adjustment that would
-- change today's session; the choice is theirs and is stored as such (origin 'chosen').
-- A pain of 7 or more routes out (no change, a safety route) and applies even on a rest day. Missing
-- data lowers confidence and is never invented. Old app builds never call these functions, so
-- nothing is accepted for them and start_workout builds the plan as written.

-- 1. The answers ------------------------------------------------------------------------------------

create table public.day_adjustments (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  local_date date not null,
  planned_workout_id uuid not null,
  plan_version_id uuid not null,
  rules_version text not null check (length(rules_version) between 1 and 40),
  band text not null check (band in ('green', 'amber', 'red', 'unknown')),
  kind text not null check (kind in ('hold_load', 'reduce_sets', 'swap_to_easy_cardio')),
  origin text not null check (origin in ('proposed', 'chosen')),
  rules_kind text not null check (
    rules_kind in ('none', 'hold_load', 'reduce_sets', 'swap_to_easy_cardio')),
  triggers text[] not null check (triggers <@ array[
    'not_available', 'no_check_in', 'sleep_very_poor', 'sleep_poor', 'sleep_short',
    'energy_very_low', 'energy_low', 'very_sore', 'sore', 'mood_very_low', 'pain_moderate',
    'pain_mild', 'recovery_low']::text[]),
  changes jsonb not null check (
    jsonb_typeof(changes) = 'array' and jsonb_array_length(changes) <= 30),
  cardio jsonb check (cardio is null or jsonb_typeof(cardio) = 'object'),
  inputs jsonb not null check (jsonb_typeof(inputs) = 'object'),
  inputs_hash text not null check (inputs_hash ~ '^[0-9a-f]{64}$'),
  status text not null check (status in ('accepted', 'declined')),
  answered_at timestamptz not null default now(),
  superseded_at timestamptz,
  created_at timestamptz not null default now(),
  foreign key (plan_version_id, user_id)
    references public.training_plan_versions (id, user_id),
  foreign key (planned_workout_id, user_id)
    references public.planned_workouts (id, user_id),
  unique (id, user_id),
  check ((kind = 'swap_to_easy_cardio') = (cardio is not null))
);

create unique index day_adjustments_one_current
  on public.day_adjustments (user_id, local_date) where superseded_at is null;
create index day_adjustments_user_date
  on public.day_adjustments (user_id, local_date, answered_at desc);

comment on table public.day_adjustments is
  'The athlete''s answers to the same-day readiness adjustment (rules readiness-v1). An overlay for one day: it never changes a plan version. Rows are only added; the current answer per day is the one not superseded.';
comment on column public.day_adjustments.inputs is
  'The values the rules read when the answer was given (check-in id and revision, sleep minutes, recovery score and confidence, screening outcome). Restricted health data.';
comment on column public.day_adjustments.origin is
  'proposed: the kind the rules computed. chosen: a kind the athlete picked themselves.';
comment on column public.day_adjustments.rules_kind is
  'The kind the rules proposed when the answer was given (none when they proposed nothing). The answer stands until the rules ask for something stricter than this or than the answered kind.';

alter table public.day_adjustments enable row level security;
alter table public.day_adjustments force row level security;
create policy day_adjustments_own_read on public.day_adjustments
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.day_adjustments from anon, authenticated;
grant select on public.day_adjustments to authenticated;

-- 2. The session remembers the answer it was started under -------------------------------------------

alter table public.workout_sessions
  add column day_adjustment_id uuid,
  add constraint workout_sessions_day_adjustment_fkey
    foreign key (day_adjustment_id, user_id)
    references public.day_adjustments (id, user_id);

create index workout_sessions_day_adjustment
  on public.workout_sessions (day_adjustment_id) where day_adjustment_id is not null;

-- 3. The rules --------------------------------------------------------------------------------------
-- Check-in scales are 1 to 5: sleep quality, energy and mood run poor to good; soreness runs good to
-- very sore (5). Sleep minutes count when 1 to 960 (0 means no sleep was recorded). Points:
-- subjective = sleep quality, energy, soreness, mood, pain; sleep_short and recovery_low are the two
-- other sources, and recovery_low adds its point only next to a subjective point.

create function private.readiness_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"readiness-v1","points":{"sleep_very_poor":2,"sleep_poor":1,"energy_very_low":2,"energy_low":1,"very_sore":2,"sore":1,"mood_very_low":1,"pain_moderate":2,"pain_mild":0,"sleep_short":1,"recovery_low":1},"pain_referral_from":7,"pain_moderate_from":4,"pain_mild_from":1,"sleep_short_below_minutes":360,"sleep_valid_max_minutes":960,"recovery_low_below":35,"amber_from_points":1,"reduce_from_points":2,"red_from_points":4,"reduce_min_sets":3,"reduce_sets_cut":1,"reduce_rpe_drop":1,"reduce_rpe_floor":6,"easy_cardio_minutes":[20,30],"answers_per_day":20}'::jsonb;
$$;
revoke all on function private.readiness_rules() from public, anon, authenticated;

-- How strict a kind is, for comparing an earlier answer with what the rules say now. A safety
-- route is stricter than any kind.
create function private.readiness_rank(p_kind text, p_safety_route text)
returns integer language sql immutable set search_path = '' as $$
  select case when p_safety_route is not null then 4
    else case p_kind when 'hold_load' then 1 when 'reduce_sets' then 2
      when 'swap_to_easy_cardio' then 3 else 0 end end;
$$;
revoke all on function private.readiness_rank(text, text) from public, anon, authenticated;

-- 4. The assessment: pure, no table is read ---------------------------------------------------------
-- p_can_hold / p_can_reduce say whether holding loads or cutting a set would change anything in
-- today's session; a kind that would change nothing falls back to the milder one, then to none.
-- Returns {band, kind, points, subjective_points, triggers, safety_route, confidence, missing,
-- recovery_low}. Gate order: pain of 7 or more; no check-in; the athlete cannot train; points.
create function private.readiness_assessment(
  p_has_check_in boolean,
  p_sleep_quality integer,
  p_energy integer,
  p_soreness integer,
  p_mood integer,
  p_pain integer,
  p_available_to_train boolean,
  p_sleep_minutes integer,
  p_recovery_score integer,
  p_recovery_confidence text,
  p_recovery_mode text,
  p_can_hold boolean,
  p_can_reduce boolean
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  r constant jsonb := private.readiness_rules();
  pts constant jsonb := r -> 'points';
  sleep_ok constant boolean := coalesce(
    p_sleep_minutes between 1 and (r ->> 'sleep_valid_max_minutes')::integer, false);
  recovery_ok constant boolean := coalesce(
    p_recovery_score is not null and p_recovery_confidence in ('high', 'medium'), false);
  recovery_low constant boolean := recovery_ok
    and p_recovery_score < (r ->> 'recovery_low_below')::integer;
  triggers text[] := '{}';
  subjective integer := 0;
  total integer;
  band text;
  kind text;
  confidence text;
  missing text[] := '{}';
begin
  if not sleep_ok then missing := array_append(missing, 'sleep'); end if;
  if not recovery_ok then missing := array_append(missing, 'recovery'); end if;
  confidence := case
    when sleep_ok and recovery_ok and p_recovery_confidence = 'high' and p_recovery_mode = 'night'
      then 'high'
    when sleep_ok or recovery_ok then 'medium'
    else 'low' end;

  if not coalesce(p_has_check_in, false) then
    return jsonb_build_object('band', 'unknown', 'kind', 'none', 'points', 0,
      'subjective_points', 0,
      'triggers', to_jsonb(case when recovery_low then array['no_check_in', 'recovery_low']
        else array['no_check_in'] end),
      'safety_route', null, 'confidence', null, 'missing', to_jsonb(missing),
      'recovery_low', recovery_low);
  end if;

  if p_pain >= (r ->> 'pain_referral_from')::integer then
    return jsonb_build_object('band', 'red', 'kind', 'none', 'points', 0,
      'subjective_points', 0, 'triggers', '["pain_severe"]'::jsonb,
      'safety_route', 'pain_referral',
      'confidence', confidence, 'missing', to_jsonb(missing), 'recovery_low', recovery_low);
  end if;

  if p_sleep_quality = 1 then
    triggers := array_append(triggers, 'sleep_very_poor'); subjective := subjective + (pts ->> 'sleep_very_poor')::integer;
  elsif p_sleep_quality = 2 then
    triggers := array_append(triggers, 'sleep_poor'); subjective := subjective + (pts ->> 'sleep_poor')::integer;
  end if;
  if sleep_ok and p_sleep_minutes < (r ->> 'sleep_short_below_minutes')::integer then
    triggers := array_append(triggers, 'sleep_short');
  end if;
  if p_energy = 1 then
    triggers := array_append(triggers, 'energy_very_low'); subjective := subjective + (pts ->> 'energy_very_low')::integer;
  elsif p_energy = 2 then
    triggers := array_append(triggers, 'energy_low'); subjective := subjective + (pts ->> 'energy_low')::integer;
  end if;
  if p_soreness = 5 then
    triggers := array_append(triggers, 'very_sore'); subjective := subjective + (pts ->> 'very_sore')::integer;
  elsif p_soreness = 4 then
    triggers := array_append(triggers, 'sore'); subjective := subjective + (pts ->> 'sore')::integer;
  end if;
  if p_mood = 1 then
    triggers := array_append(triggers, 'mood_very_low'); subjective := subjective + (pts ->> 'mood_very_low')::integer;
  end if;
  if p_pain >= (r ->> 'pain_moderate_from')::integer then
    triggers := array_append(triggers, 'pain_moderate'); subjective := subjective + (pts ->> 'pain_moderate')::integer;
  elsif p_pain >= (r ->> 'pain_mild_from')::integer then
    triggers := array_append(triggers, 'pain_mild');
  end if;

  total := subjective;
  if 'sleep_short' = any(triggers) then total := total + (pts ->> 'sleep_short')::integer; end if;
  if recovery_low then
    triggers := array_append(triggers, 'recovery_low');
    -- A score from the body's own signals never adjusts a session alone (D9).
    if subjective >= 1 then total := total + (pts ->> 'recovery_low')::integer; end if;
  end if;

  band := case when total >= (r ->> 'red_from_points')::integer then 'red'
    when total >= (r ->> 'amber_from_points')::integer then 'amber' else 'green' end;
  kind := case
    when not coalesce(p_available_to_train, false) then 'none'
    when total >= (r ->> 'red_from_points')::integer then 'swap_to_easy_cardio'
    when total >= (r ->> 'reduce_from_points')::integer then
      case when p_can_reduce then 'reduce_sets' when p_can_hold then 'hold_load' else 'none' end
    when total >= (r ->> 'amber_from_points')::integer then
      case when p_can_hold then 'hold_load' else 'none' end
    else 'none' end;
  if not coalesce(p_available_to_train, false) then triggers := array_prepend('not_available', triggers); end if;

  return jsonb_build_object('band', band, 'kind', kind, 'points', total,
    'subjective_points', subjective, 'triggers', to_jsonb(triggers), 'safety_route', null,
    'confidence', confidence, 'missing', to_jsonb(missing), 'recovery_low', recovery_low);
end $$;
revoke all on function private.readiness_assessment(
  boolean, integer, integer, integer, integer, integer, boolean, integer, integer, text, text,
  boolean, boolean) from public, anon, authenticated;

-- 5. What a kind changes in today's session -----------------------------------------------------------
-- p_targets: private.next_session_targets (B3). One entry per exercise that changes; the others are
-- left out. Returns {changes, sets_from, sets_to} where the sets are totals over the whole workout.
--   hold_load    where B3 says add load or add reps: the last working load (for an assisted
--                exercise the help) and the last fewest reps, clamped into the range
--   reduce_sets  one set fewer on an exercise with 3 or more, effort one point lower (not below 6,
--                never above the plan's), and hold_load's loads
--   swap_to_easy_cardio  every exercise to 0 sets
-- The rest of the week is untouched. A load never goes above the last logged one.
create function private.day_adjustment_changes(
  p_user uuid, p_workout uuid, p_kind text, p_targets jsonb
) returns jsonb language sql stable security definer set search_path = '' as $$
with rules as (
  select private.readiness_rules() as r
), ex as (
  select e.id, e.exercise_order, e.display_name_snapshot as name, e.set_count, e.rep_min, e.rep_max,
    e.target_rpe,
    coalesce(e.exercise_slug like 'assisted-%',
      private.exercise_name_key(e.display_name_snapshot) like 'assisted %') as assisted,
    (select x from jsonb_array_elements(coalesce(p_targets, '[]'::jsonb)) x
      where x ->> 'planned_exercise_id' = e.id::text limit 1) as tg
  from public.planned_exercises e
  where e.planned_workout_id = p_workout and e.user_id = p_user
), calc as (
  select ex.*,
    p_kind in ('hold_load', 'reduce_sets')
      and coalesce(ex.tg ->> 'action' in ('add_load', 'add_reps'), false) as holds,
    ex.tg ->> 'action' = 'add_load' as holds_load,
    nullif(ex.tg #>> '{basis,recent,0,load_kg}', '')::numeric as last_load,
    nullif(ex.tg #>> '{basis,recent,0,min_reps}', '')::integer as last_reps,
    nullif(ex.tg ->> 'load_kg', '')::numeric as target_load,
    nullif(ex.tg ->> 'reps', '')::integer as target_reps,
    case p_kind
      when 'swap_to_easy_cardio' then 0
      when 'reduce_sets' then
        case when ex.set_count >= (rules.r ->> 'reduce_min_sets')::integer
          then ex.set_count - (rules.r ->> 'reduce_sets_cut')::integer else ex.set_count end
      else ex.set_count end as sets_to,
    case when p_kind = 'reduce_sets' and ex.target_rpe is not null
      then least(ex.target_rpe, greatest((rules.r ->> 'reduce_rpe_floor')::numeric,
        ex.target_rpe - (rules.r ->> 'reduce_rpe_drop')::numeric)) end as rpe_to
  from ex cross join rules
), entry as (
  select c.*,
    case when c.holds then least(c.rep_max, greatest(c.rep_min, c.last_reps)) end as reps_to
  from calc c
)
select jsonb_build_object(
  'changes', coalesce(jsonb_agg(jsonb_build_object(
    'exercise_order', e.exercise_order,
    'planned_exercise_id', e.id,
    'name', e.name,
    'sets_from', e.set_count,
    'sets_to', e.sets_to,
    'load_note', case when e.holds_load and e.holds and e.last_load is not null then
      case when e.assisted
        then 'Keep last time''s ' || trim_scale(e.last_load)::text || ' kg of help'
        else 'Keep last time''s ' || trim_scale(e.last_load)::text || ' kg' end end,
    'load_kg_from', case when e.holds then e.target_load end,
    'load_kg_to', case when e.holds then e.last_load end,
    'reps_from', case when e.holds then e.target_reps end,
    'reps_to', e.reps_to,
    'rpe_to', e.rpe_to
  ) order by e.exercise_order) filter (
    where e.sets_to <> e.set_count or e.holds
      or (e.rpe_to is not null and e.rpe_to <> e.target_rpe)
  ), '[]'::jsonb),
  'sets_from', coalesce(sum(e.set_count), 0)::integer,
  'sets_to', coalesce(sum(e.sets_to), 0)::integer)
from entry e;
$$;
revoke all on function private.day_adjustment_changes(uuid, uuid, text, jsonb)
  from public, anon, authenticated;

-- 6. The words: fixed sentences, composed from the triggers and the kind. No model writes them. -------
create function private.day_adjustment_explanation(
  p_band text, p_kind text, p_triggers text[], p_safety_route text, p_changes jsonb,
  p_with_reasons boolean
) returns text language plpgsql immutable set search_path = '' as $$
declare
  r constant jsonb := private.readiness_rules();
  codes constant text[] := array['sleep_very_poor', 'sleep_poor', 'sleep_short', 'energy_very_low',
    'energy_low', 'very_sore', 'sore', 'mood_very_low', 'pain_moderate', 'recovery_low'];
  phrases constant text[] := array['you slept very poorly', 'you slept poorly',
    'you slept under 6 hours', 'your energy is very low', 'your energy is low', 'you''re very sore',
    'you''re sore', 'your mood is very low', 'you have some pain', 'your recovery reads low'];
  parts text[] := '{}';
  reasons text := '';
  action text;
  note text := '';
  cut integer;
  loads boolean;
  i integer;
  n integer;
begin
  if p_safety_route = 'pain_referral' then
    return 'Pain of 7 or more is too high to train through. Rest the area and see a doctor or physio before you train it again.';
  end if;
  if p_band = 'unknown' then
    return case when 'recovery_low' = any(p_triggers)
      then 'Your recovery reads low. Check in and Tracend will say whether to adjust today.'
      else 'Check in to see if today''s session needs adjusting.' end;
  end if;
  if 'not_available' = any(p_triggers) then
    return 'You said you can''t train today. Nothing in your plan changes.';
  end if;
  if 'pain_mild' = any(p_triggers) then
    note := ' Keep any pain at 3 or below, and stop if it builds from set to set.';
  end if;

  for i in 1..array_length(codes, 1) loop
    if codes[i] = any(p_triggers) then parts := parts || phrases[i]; end if;
  end loop;
  n := coalesce(array_length(parts, 1), 0);
  if n = 1 then reasons := parts[1];
  elsif n >= 2 then
    reasons := array_to_string(parts[1:n - 1], ', ') || ' and ' || parts[n];
  end if;

  if p_kind = 'none' then
    if p_band = 'green' then
      return case when 'recovery_low' = any(p_triggers)
        then 'Your recovery reads low, but your check-in looks fine. You can train as planned or choose a lighter session.'
        else 'Your check-in looks fine. Train as planned.' end || note;
    end if;
    return case when n = 0 then 'Nothing in today''s session needs to change.'
      else upper(left(reasons, 1)) || substr(reasons, 2)
        || '. Nothing in today''s session needs to change.' end || note;
  end if;

  select count(*) filter (where (c ->> 'sets_to')::integer < (c ->> 'sets_from')::integer),
    coalesce(bool_or(c ->> 'load_note' is not null), false)
  into cut, loads
  from jsonb_array_elements(coalesce(p_changes, '[]'::jsonb)) c;

  action := case p_kind
    when 'hold_load' then case when loads
      then 'Keep last time''s weights instead of adding more.'
      else 'Repeat last time''s reps instead of adding more.' end
    when 'reduce_sets' then 'One set fewer on ' || cut || case when cut = 1 then ' exercise' else ' exercises' end
      || case when loads then ' and last time''s weights.' else '.' end
    else format('Try %s to %s minutes of easy walking, cycling or swimming at a pace you can talk through. It keeps you moving without adding strain.',
      r -> 'easy_cardio_minutes' -> 0, r -> 'easy_cardio_minutes' -> 1) end;

  return case when p_with_reasons and n > 0
    then upper(left(reasons, 1)) || substr(reasons, 2) || '. ' else '' end || action || note;
end $$;
revoke all on function private.day_adjustment_explanation(text, text, text[], text, jsonb, boolean)
  from public, anon, authenticated;

-- 7. Computing the day ------------------------------------------------------------------------------

-- Today's scores are made once a day if none exist. A failure leaves the recovery score missing; it
-- never blocks the adjustment (the same guard prepare_daily_coaching uses).
create function private.day_adjustment_refresh_metrics(p_user uuid, p_date date)
returns void language plpgsql security definer set search_path = '' as $$
begin
  if not exists (select 1 from public.daily_computed_metrics m
      where m.user_id = p_user and m.local_date = p_date) then
    begin
      perform public.compute_daily_metrics(p_user, p_date, coalesce((
        select z.name from public.user_accounts a
        join pg_catalog.pg_timezone_names z on z.name = a.timezone
        where a.id = p_user), 'UTC'));
    exception when others then
      null;
    end;
  end if;
end $$;
revoke all on function private.day_adjustment_refresh_metrics(uuid, date)
  from public, anon, authenticated;

-- Reads the day and returns {payload, inputs, plan_version_id}: the get_my_day_adjustment_v1 object
-- with status 'proposed' or 'none', no stored answer applied, and the values the rules read.
create function private.day_adjustment_compute(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r constant jsonb := private.readiness_rules();
  version_id uuid;
  version_block text;
  version_ends date;
  workout jsonb;
  workout_id uuid;
  check_in public.daily_check_ins%rowtype;
  sleep_minutes integer;
  recovery_score integer;
  recovery_confidence text;
  recovery_mode text;
  screening text := private.current_screening_outcome(p_user);
  targets jsonb;
  hold_c jsonb := jsonb_build_object('changes', '[]'::jsonb, 'sets_from', 0, 'sets_to', 0);
  reduce_c jsonb := hold_c;
  swap_c jsonb := hold_c;
  can_hold boolean := false;
  can_reduce boolean := false;
  unavailable text;
  assessment jsonb;
  kind text;
  chosen_c jsonb;
  options jsonb := '[]'::jsonb;
  cardio jsonb := null;
  safety text;
  band text;
  triggers text[];
  inputs jsonb;
begin
  select v.id, v.block_kind, v.ends_on into version_id, version_block, version_ends
  from public.training_plan_versions v where v.user_id = p_user and v.status = 'active' limit 1;
  workout := case when version_id is null then null
    else private.planned_workout_for_date(p_user, p_date) end;
  workout_id := (workout ->> 'id')::uuid;

  select * into check_in from public.daily_check_ins c
  where c.user_id = p_user and c.local_date = p_date and c.superseded_at is null;
  select h.sleep_minutes into sleep_minutes from public.daily_health_summaries h
  where h.user_id = p_user and h.local_date = p_date and h.source_scope = 'healthkit';
  select m.recovery_score, m.data_confidence, m.scores_jsonb ->> 'recovery_mode'
  into recovery_score, recovery_confidence, recovery_mode
  from public.daily_computed_metrics m where m.user_id = p_user and m.local_date = p_date;

  unavailable := case
    when version_id is null then 'no_plan'
    when workout_id is null then 'rest_day'
    when exists (select 1 from public.workout_sessions s where s.user_id = p_user
        and s.planned_workout_id = workout_id and s.state = 'in_progress') then 'session_started'
    when exists (select 1 from public.workout_sessions s where s.user_id = p_user
        and s.planned_workout_id = workout_id and s.local_date = p_date
        and s.state = 'completed') then 'session_done'
    when version_block = 'next_session' and version_ends = p_date then 'coach_adjusted'
  end;

  if workout_id is not null then
    targets := private.next_session_targets(p_user);
    hold_c := private.day_adjustment_changes(p_user, workout_id, 'hold_load', targets);
    reduce_c := private.day_adjustment_changes(p_user, workout_id, 'reduce_sets', targets);
    swap_c := private.day_adjustment_changes(p_user, workout_id, 'swap_to_easy_cardio', targets);
    can_hold := jsonb_array_length(hold_c -> 'changes') > 0;
    can_reduce := (reduce_c ->> 'sets_to')::integer < (reduce_c ->> 'sets_from')::integer;
  end if;

  assessment := private.readiness_assessment(check_in.id is not null, check_in.sleep_quality::integer,
    check_in.energy::integer, check_in.soreness::integer, check_in.mood::integer,
    check_in.pain_severity::integer, check_in.available_to_train, sleep_minutes, recovery_score,
    recovery_confidence, recovery_mode, can_hold, can_reduce);
  safety := assessment ->> 'safety_route';
  band := assessment ->> 'band';
  triggers := array(select jsonb_array_elements_text(assessment -> 'triggers'));
  kind := case when unavailable is not null or safety is not null then 'none'
    else assessment ->> 'kind' end;

  chosen_c := case kind when 'hold_load' then hold_c when 'reduce_sets' then reduce_c
    when 'swap_to_easy_cardio' then swap_c else
      jsonb_build_object('changes', '[]'::jsonb, 'sets_from', (swap_c ->> 'sets_from')::integer,
        'sets_to', (swap_c ->> 'sets_from')::integer) end;

  cardio := jsonb_build_object('minutes_min', (r -> 'easy_cardio_minutes' ->> 0)::integer,
    'minutes_max', (r -> 'easy_cardio_minutes' ->> 1)::integer, 'effort', 'easy',
    'talk_test', true, 'vigorous_allowed', false);

  -- What the athlete may choose themselves: every kind that would change today's session, unless
  -- the day is unavailable, carries a safety route or the athlete said they cannot train.
  if unavailable is null and safety is null and coalesce(check_in.available_to_train, true)
     and workout_id is not null then
    if can_hold then
      options := options || jsonb_build_object('kind', 'hold_load',
        'explanation', private.day_adjustment_explanation(band, 'hold_load', '{}', null,
          hold_c -> 'changes', false),
        'sets_total_to', (hold_c ->> 'sets_to')::integer, 'changes', hold_c -> 'changes',
        'cardio', null);
    end if;
    if can_reduce then
      options := options || jsonb_build_object('kind', 'reduce_sets',
        'explanation', private.day_adjustment_explanation(band, 'reduce_sets', '{}', null,
          reduce_c -> 'changes', false),
        'sets_total_to', (reduce_c ->> 'sets_to')::integer, 'changes', reduce_c -> 'changes',
        'cardio', null);
    end if;
    if (swap_c ->> 'sets_from')::integer > 0 then
      options := options || jsonb_build_object('kind', 'swap_to_easy_cardio',
        'explanation', private.day_adjustment_explanation(band, 'swap_to_easy_cardio', '{}', null,
          swap_c -> 'changes', false),
        'sets_total_to', 0, 'changes', swap_c -> 'changes', 'cardio', cardio);
    end if;
  end if;

  inputs := jsonb_build_object('check_in_id', check_in.id, 'check_in_revision', check_in.revision,
    'sleep_minutes', sleep_minutes, 'recovery_score', recovery_score,
    'data_confidence', recovery_confidence, 'recovery_mode', recovery_mode,
    'screening', screening);

  return jsonb_build_object(
    'plan_version_id', version_id,
    'inputs', inputs,
    'payload', jsonb_build_object(
      'schema_version', '1.0',
      'local_date', p_date,
      'band', band,
      'triggers', to_jsonb(triggers),
      'kind', kind,
      'changes', chosen_c -> 'changes',
      'explanation', private.day_adjustment_explanation(band, kind, triggers, safety,
        chosen_c -> 'changes', true),
      'status', case when kind = 'none' then 'none' else 'proposed' end,
      'available', unavailable is null,
      'unavailable_reason', unavailable,
      'safety_route', safety,
      'confidence', assessment -> 'confidence',
      'missing', assessment -> 'missing',
      'cardio', case when kind = 'swap_to_easy_cardio' then cardio end,
      'planned_workout_id', workout_id,
      'workout_name', workout ->> 'name',
      'sets_total_from', (swap_c ->> 'sets_from')::integer,
      'sets_total_to', (chosen_c ->> 'sets_to')::integer,
      'previous_answer', null,
      'answered_at', null,
      'rules_version', r ->> 'version',
      'origin', null,
      'options', options,
      'signals', jsonb_build_object('recovery_score', recovery_score,
        'recovery_confidence', recovery_confidence, 'recovery_mode', recovery_mode,
        'recovery_low', (assessment ->> 'recovery_low')::boolean, 'sleep_minutes', sleep_minutes)));
end $$;
revoke all on function private.day_adjustment_compute(uuid, date) from public, anon, authenticated;

-- A stored answer stands while it belongs to today's workout and the rules do not now ask for
-- something stricter than what they asked for when it was given or than what the athlete answered.
-- Once the session has started or is done, it stands as it is.
create function private.day_adjustment_stands(p_row public.day_adjustments, p_payload jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select p_row.id is not null
    and p_row.planned_workout_id::text = p_payload ->> 'planned_workout_id'
    and (p_payload ->> 'unavailable_reason' in ('session_started', 'session_done')
      or private.readiness_rank(p_payload ->> 'kind', p_payload ->> 'safety_route')
        <= greatest(private.readiness_rank(p_row.rules_kind, null),
          private.readiness_rank(p_row.kind, null)));
$$;
revoke all on function private.day_adjustment_stands(public.day_adjustments, jsonb)
  from public, anon, authenticated;

-- The object the app reads: the computed day with the athlete's stored answer laid over it.
create function private.day_adjustment_present(
  p_row public.day_adjustments, p_payload jsonb, p_stands boolean
) returns jsonb language sql immutable set search_path = '' as $$
  select case
    when p_row.id is null then p_payload
    when p_stands then p_payload || jsonb_build_object(
      'status', p_row.status, 'kind', p_row.kind, 'band', p_row.band,
      'triggers', to_jsonb(p_row.triggers), 'changes', p_row.changes, 'cardio', p_row.cardio,
      'sets_total_to', (p_payload ->> 'sets_total_from')::integer - coalesce((
        select sum((c ->> 'sets_from')::integer - (c ->> 'sets_to')::integer)
        from jsonb_array_elements(p_row.changes) c), 0)::integer,
      'explanation', private.day_adjustment_explanation(p_row.band, p_row.kind, p_row.triggers,
        null, p_row.changes, p_row.origin = 'proposed'),
      'origin', p_row.origin, 'answered_at', p_row.answered_at)
    when p_row.planned_workout_id::text = p_payload ->> 'planned_workout_id'
      then p_payload || jsonb_build_object('previous_answer', jsonb_build_object(
        'kind', p_row.kind, 'status', p_row.status, 'answered_at', p_row.answered_at))
    else p_payload end;
$$;
revoke all on function private.day_adjustment_present(public.day_adjustments, jsonb, boolean)
  from public, anon, authenticated;

-- 8. The two RPCs -----------------------------------------------------------------------------------

-- Today's adjustment. Only the athlete's own local today can be read; another date is refused.
create function public.get_my_day_adjustment_v1(local_date date)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  today date;
  payload jsonb;
  cur public.day_adjustments%rowtype;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  today := private.local_date_for(uid);
  if get_my_day_adjustment_v1.local_date is distinct from today then
    raise exception 'only today can be read' using errcode = '22023';
  end if;
  perform private.day_adjustment_refresh_metrics(uid, today);
  payload := private.day_adjustment_compute(uid, today) -> 'payload';
  select * into cur from public.day_adjustments a
  where a.user_id = uid and a.local_date = today and a.superseded_at is null;
  return private.day_adjustment_present(cur, payload, private.day_adjustment_stands(cur, payload));
end $$;
revoke all on function public.get_my_day_adjustment_v1(date) from public, anon, authenticated;
grant execute on function public.get_my_day_adjustment_v1(date) to authenticated;

-- The athlete's answer. accept = true applies the kind the rules proposed, or chosen_kind when the
-- athlete picked another one; accept = false declines (or undoes an accepted answer). The answer can
-- be changed until the session starts. Errors: 42501 signed out; 22023 another date, nothing to
-- answer, a kind that would change nothing, or a day with a safety route; 55000 the day is
-- unavailable (rest day, session started, done, coach-adjusted); P0001 too many answers today.
create function public.respond_to_day_adjustment_v1(
  local_date date, accept boolean, chosen_kind text default null
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  today date;
  computed jsonb;
  payload jsonb;
  cur public.day_adjustments%rowtype;
  stands boolean;
  target_kind text;
  target_origin text;
  target_status text;
  chosen_option jsonb;
  target_changes jsonb;
  target_cardio jsonb;
  target_band text;
  target_triggers text[];
  new_row public.day_adjustments%rowtype;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if accept is null then
    raise exception 'accept must be true or false' using errcode = '22023';
  end if;
  today := private.local_date_for(uid);
  if respond_to_day_adjustment_v1.local_date is distinct from today then
    raise exception 'only today can be answered' using errcode = '22023';
  end if;
  perform pg_advisory_xact_lock(hashtextextended('day_adjustment:' || uid::text || today::text, 0));
  perform private.day_adjustment_refresh_metrics(uid, today);
  computed := private.day_adjustment_compute(uid, today);
  payload := computed -> 'payload';
  select * into cur from public.day_adjustments a
  where a.user_id = uid and a.local_date = today and a.superseded_at is null;
  stands := private.day_adjustment_stands(cur, payload);

  if payload ->> 'safety_route' is not null then
    raise exception 'no adjustment is offered on a day with a safety route' using errcode = '22023';
  end if;
  if not (payload ->> 'available')::boolean then
    raise exception 'today cannot be adjusted: %', payload ->> 'unavailable_reason'
      using errcode = '55000';
  end if;

  if accept then
    target_kind := coalesce(respond_to_day_adjustment_v1.chosen_kind, payload ->> 'kind');
    if target_kind is null or target_kind = 'none' then
      raise exception 'there is nothing to accept today' using errcode = '22023';
    end if;
    select o into chosen_option from jsonb_array_elements(payload -> 'options') o
    where o ->> 'kind' = target_kind;
    if chosen_option is null then
      raise exception 'that adjustment would not change today''s session' using errcode = '22023';
    end if;
    target_origin := case when target_kind = payload ->> 'kind' then 'proposed' else 'chosen' end;
    target_changes := chosen_option -> 'changes';
    target_cardio := nullif(chosen_option -> 'cardio', 'null'::jsonb);
    target_band := payload ->> 'band';
    target_triggers := array(select jsonb_array_elements_text(payload -> 'triggers'));
  elsif stands then
    target_kind := cur.kind; target_origin := cur.origin; target_changes := cur.changes;
    target_cardio := cur.cardio; target_band := cur.band; target_triggers := cur.triggers;
  elsif payload ->> 'kind' <> 'none' then
    target_kind := payload ->> 'kind'; target_origin := 'proposed';
    target_changes := payload -> 'changes'; target_cardio := nullif(payload -> 'cardio', 'null'::jsonb);
    target_band := payload ->> 'band';
    target_triggers := array(select jsonb_array_elements_text(payload -> 'triggers'));
  else
    raise exception 'there is nothing to decline today' using errcode = '22023';
  end if;

  -- The same answer again is not a new answer.
  target_status := case when accept then 'accepted' else 'declined' end;
  if stands and cur.kind = target_kind and cur.status = target_status then
    return private.day_adjustment_present(cur, payload, true);
  end if;

  if (select count(*) from public.day_adjustments a
      where a.user_id = uid and a.local_date = today)
     >= (private.readiness_rules() ->> 'answers_per_day')::integer then
    raise exception 'too many answers today' using errcode = 'P0001';
  end if;

  update public.day_adjustments a set superseded_at = now()
  where a.user_id = uid and a.local_date = today and a.superseded_at is null;
  insert into public.day_adjustments(user_id, local_date, planned_workout_id, plan_version_id,
    rules_version, band, kind, origin, rules_kind, triggers, changes, cardio, inputs, inputs_hash,
    status)
  values (uid, today, (payload ->> 'planned_workout_id')::uuid,
    (computed ->> 'plan_version_id')::uuid, payload ->> 'rules_version', target_band, target_kind,
    target_origin, payload ->> 'kind', target_triggers, target_changes, target_cardio, computed -> 'inputs',
    encode(sha256(convert_to((computed -> 'inputs')::text, 'UTF8')), 'hex'),
    target_status)
  returning * into new_row;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (uid, 'day_adjustment_answered', 'day_adjustment', new_row.id, 'succeeded',
    jsonb_build_object('kind', target_kind, 'accepted', accept, 'band', target_band,
      'origin', target_origin, 'rules_version', payload ->> 'rules_version'));

  return private.day_adjustment_present(new_row, payload, true);
end $$;
revoke all on function public.respond_to_day_adjustment_v1(date, boolean, text)
  from public, anon, authenticated;
grant execute on function public.respond_to_day_adjustment_v1(date, boolean, text)
  to authenticated;

-- 9. B3 meets the adjustment ------------------------------------------------------------------------
-- A session done under an accepted hold_load or reduce_sets answer is not evidence for lowering a
-- load or for a stall (a single poor workout must not restructure training), and its planned set
-- count is the adjusted one. Each session summary gains `adjusted` (boolean) and `sets_planned`
-- (the adjusted set count of the exercise, else null). Everything else is as in
-- 20261017140023_progression_targets.sql and 20261023100050_advanced_level_catalog.sql.

create or replace function private.progression_decision(
  p_set_count integer,
  p_rep_min integer,
  p_rep_max integer,
  p_target_rpe numeric,
  p_step_kg numeric,
  p_gap_days integer,
  p_skipped_since boolean,
  p_pain_since boolean,
  p_assisted boolean,
  p_sessions jsonb
) returns jsonb language plpgsql immutable set search_path = '' as $$
declare
  rules constant jsonb := private.progression_rules();
  s1 jsonb := p_sessions -> 0;
  s2 jsonb := p_sessions -> 1;
  s3 jsonb := p_sessions -> 2;
  v_load numeric := nullif(s1 ->> 'load_kg', '')::numeric;
  v_sets integer := (s1 ->> 'sets')::integer;
  v_min_reps integer := (s1 ->> 'min_reps')::integer;
  v_min_rir integer := nullif(s1 ->> 'min_rir', '')::integer;
  v_step numeric := case when p_step_kg > 0 then p_step_kg end;
  v_rir_target integer := case when p_target_rpe is null then 2
    else greatest(0, least(5, round(10 - p_target_rpe)::integer)) end;
  v_can_lower boolean;
  v_hold_reps integer;
  v_action text;
  v_reason text;
  v_load_out numeric;
  v_reps integer;
  v_lower_load numeric;
begin
  if p_sessions is null or jsonb_typeof(p_sessions) <> 'array'
     or jsonb_array_length(p_sessions) = 0 then
    return null;
  end if;
  -- Assisted: lowering adds help (always possible); otherwise the load must stay above 0.
  v_can_lower := v_load is not null and v_step is not null
    and (coalesce(p_assisted, false) or v_load - v_step > 0);
  v_lower_load := case when coalesce(p_assisted, false) then v_load + v_step else v_load - v_step end;
  v_hold_reps := least(p_rep_max, greatest(p_rep_min, v_min_reps));
  v_load_out := v_load;
  v_reps := v_hold_reps;

  if coalesce((s1 ->> 'pain')::boolean, false) or coalesce(p_pain_since, false) then
    v_action := 'hold'; v_reason := 'pain';
  elsif p_gap_days >= (rules ->> 'lower_after_gap_days')::integer and v_can_lower then
    v_action := 'lower'; v_reason := 'away';
    v_load_out := v_lower_load; v_reps := p_rep_min;
  elsif p_gap_days >= (rules ->> 'hold_after_gap_days')::integer then
    v_action := 'hold'; v_reason := 'away';
  elsif p_skipped_since then
    v_action := 'hold'; v_reason := 'skipped';
  elsif v_min_reps < p_rep_min then
    if s2 is not null and (s2 ->> 'min_reps')::integer < p_rep_min
       and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load and v_can_lower
       and not coalesce((s1 ->> 'adjusted')::boolean, false)
       and not coalesce((s2 ->> 'adjusted')::boolean, false) then
      v_action := 'lower'; v_reason := 'below_range';
      v_load_out := v_lower_load; v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'below_range'; v_reps := p_rep_min;
    end if;
  elsif v_sets < coalesce((s1 ->> 'sets_planned')::integer, p_set_count) then
    v_action := 'hold'; v_reason := 'incomplete';
  -- A cut-short session is not a stall (handled above); the comparison is reps per set.
  elsif s3 is not null and v_min_reps < p_rep_max
        and not coalesce((s1 ->> 'adjusted')::boolean, false)
        and not coalesce((s2 ->> 'adjusted')::boolean, false)
        and not coalesce((s3 ->> 'adjusted')::boolean, false)
        and nullif(s2 ->> 'load_kg', '')::numeric is not distinct from v_load
        and nullif(s3 ->> 'load_kg', '')::numeric is not distinct from v_load
        and (s1 ->> 'total_reps')::integer * (s3 ->> 'sets')::integer
          <= (s3 ->> 'total_reps')::integer * (s1 ->> 'sets')::integer then
    if v_can_lower then
      v_action := 'lower'; v_reason := 'stall';
      v_load_out := v_lower_load; v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'stall';
    end if;
  elsif v_min_rir is not null and v_min_rir < v_rir_target then
    v_action := 'hold'; v_reason := 'effort';
  elsif v_min_reps >= p_rep_max then
    if v_step is not null and v_load is not null and (not coalesce(p_assisted, false) or v_load > 0) then
      v_action := 'add_load'; v_reason := 'top_of_range';
      v_load_out := case when coalesce(p_assisted, false) then greatest(0, v_load - v_step)
        else v_load + v_step end;
      v_reps := p_rep_min;
    else
      v_action := 'hold'; v_reason := 'top_no_step'; v_reps := p_rep_max;
    end if;
  else
    v_action := 'add_reps'; v_reason := 'within_range';
    v_reps := least(p_rep_max, v_min_reps + (rules ->> 'reps_added_per_session')::integer);
  end if;

  return jsonb_build_object(
    'action', v_action, 'reason', v_reason,
    'load_kg', v_load_out, 'reps', v_reps, 'sets', p_set_count,
    'confidence', case when coalesce((s1 ->> 'effort_known')::boolean, false)
      then 'high' else 'low' end);
end $$;
revoke all on function private.progression_decision(
  integer, integer, integer, numeric, numeric, integer, boolean, boolean, boolean, jsonb)
  from public, anon, authenticated;

create or replace function private.next_session_targets(p_user uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
with rules as (
  select private.progression_rules() as r
), today as (
  select private.local_date_for(p_user) as d
), planned as (
  select e.id as planned_exercise_id, w.workout_order, e.exercise_order,
    e.exercise_slug, e.display_name_snapshot as name,
    e.set_count, e.rep_min, e.rep_max, e.target_rpe,
    private.exercise_name_key(e.display_name_snapshot) as name_key,
    private.exercise_name_key(c.name) as catalog_name_key,
    coalesce(e.exercise_slug like 'assisted-%',
      private.exercise_name_key(e.display_name_snapshot) like 'assisted %') as assisted,
    c.load_step_kg as step_kg,
    coalesce(c.added_load, false) as added_load,
    -- The same lift planned more than once with different rep ranges (an advanced plan's heavy
    -- and light days): each range keeps its own history, so a heavy 100 kg x 9 is never read
    -- as a light day's 100 kg x 10.
    e.exercise_slug is not null and exists (
      select 1 from public.planned_exercises o
      join public.planned_workouts ow on ow.id = o.planned_workout_id and ow.user_id = o.user_id
      where ow.plan_version_id = v.id and o.user_id = e.user_id
        and o.exercise_slug = e.exercise_slug
        and (o.rep_min, o.rep_max) is distinct from (e.rep_min, e.rep_max)) as split_range
  from public.training_plan_versions v
  join public.planned_workouts w on w.plan_version_id = v.id and w.user_id = v.user_id
  join public.planned_exercises e on e.planned_workout_id = w.id and e.user_id = w.user_id
  left join public.exercise_catalog c on c.slug = e.exercise_slug
  where v.user_id = p_user and v.status = 'active'
), perf as (
  select pl.planned_exercise_id, pl.assisted, pl.added_load, p.id as performance_id, p.status, p.pain_flag,
    s.local_date, s.completed_at, s.id as session_id, p.planned_exercise_id as logged_exercise_id
  from planned pl
  join public.exercise_performances p on p.user_id = p_user
  left join public.planned_exercises pe on pe.id = p.planned_exercise_id and pe.user_id = p.user_id
  join public.workout_sessions s on s.id = p.workout_session_id and s.user_id = p.user_id
    and s.state = 'completed'
    and s.local_date >= (select d from today) - (select (r ->> 'lookback_days')::integer from rules)
  where ((pl.exercise_slug is not null and p.exercise_slug = pl.exercise_slug)
    or (pl.exercise_slug is not null and p.exercise_slug is null
        and p.performance_kind = 'prescribed'
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.catalog_name_key)
    or (pl.exercise_slug is null and p.exercise_slug is null
        and private.exercise_name_key(coalesce(p.performed_name, pe.display_name_snapshot))
            = pl.name_key))
    -- A lift planned with several ranges counts only the performances logged against a planned
    -- exercise with this range, whichever plan version it came from.
    and (not pl.split_range
      or (pe.rep_min is not distinct from pl.rep_min and pe.rep_max is not distinct from pl.rep_max))
), logged as (
  select pf.planned_exercise_id, pf.assisted, pf.session_id, pf.local_date, pf.completed_at,
    pf.pain_flag, pf.logged_exercise_id,
    -- Assisted: the load is machine help and 0 is unassisted, so it is kept. Added load (a weighted
    -- pull-up): the load is the weight added to the body, so no load and 0 both mean none added,
    -- a real starting point for the first step.
    case when pf.assisted then es.load_kg
      when pf.added_load then coalesce(es.load_kg, 0)
      else nullif(es.load_kg, 0) end as load_kg,
    es.repetitions,
    case when es.rir is not null then es.rir::integer
      when es.rpe is not null then greatest(0, least(5, round(10 - es.rpe)::integer)) end as rir
  from perf pf
  join public.exercise_sets es on es.exercise_performance_id = pf.performance_id
    and es.user_id = p_user and es.completed and es.repetitions > 0
  where pf.status <> 'skipped' and (not pf.assisted or es.load_kg is not null)
), topped as (
  -- The top load is the heaviest; for an assisted exercise the least help.
  select l.*, case when l.assisted
      then min(l.load_kg) over (partition by l.planned_exercise_id, l.session_id)
      else max(l.load_kg) over (partition by l.planned_exercise_id, l.session_id) end as top_load
  from logged l
), sessions as (
  select t.planned_exercise_id, t.session_id, t.local_date, t.completed_at, t.top_load,
    count(*)::integer as sets,
    min(t.repetitions)::integer as min_reps,
    sum(t.repetitions)::integer as total_reps,
    min(t.rir) as min_rir,
    count(t.rir) = count(*) as effort_known,
    bool_or(t.pain_flag) as pain,
    max(t.logged_exercise_id::text)::uuid as logged_exercise_id
  from topped t
  where t.load_kg is not distinct from t.top_load
  group by t.planned_exercise_id, t.session_id, t.local_date, t.completed_at, t.top_load
), marked as (
  -- Done under an accepted hold_load or reduce_sets answer (B4): not evidence for lowering a load,
  -- and the planned set count is the adjusted one.
  select s.*, a.id is not null as adjusted,
    case when a.id is not null then (
      select (c ->> 'sets_to')::integer from jsonb_array_elements(a.changes) c
      where c ->> 'planned_exercise_id' = s.logged_exercise_id::text limit 1) end as sets_planned
  from sessions s
  join public.workout_sessions ws on ws.id = s.session_id and ws.user_id = p_user
  left join public.day_adjustments a on a.id = ws.day_adjustment_id and a.user_id = p_user
    and a.status = 'accepted' and a.kind in ('hold_load', 'reduce_sets')
), ranked as (
  select s.*, row_number() over (partition by s.planned_exercise_id
    order by s.local_date desc, s.completed_at desc) as rn
  from marked s
), recent as (
  select r.planned_exercise_id, max(r.local_date) filter (where r.rn = 1) as latest_date,
    max(r.completed_at) filter (where r.rn = 1) as latest_completed_at,
    jsonb_agg(jsonb_build_object(
      'local_date', r.local_date, 'load_kg', r.top_load, 'sets', r.sets,
      'min_reps', r.min_reps, 'total_reps', r.total_reps, 'min_rir', r.min_rir,
      'effort_known', r.effort_known, 'pain', r.pain, 'adjusted', r.adjusted,
      'sets_planned', r.sets_planned) order by r.rn) as sess
  from ranked r where r.rn <= 3 group by r.planned_exercise_id
)
select coalesce(jsonb_agg(x.target order by x.workout_order, x.exercise_order), '[]'::jsonb)
from (
  select pl.workout_order, pl.exercise_order,
    jsonb_build_object('planned_exercise_id', pl.planned_exercise_id,
      'exercise_key', coalesce(pl.exercise_slug, pl.name_key), 'name', pl.name)
    || d.decision
    || jsonb_build_object('basis', jsonb_build_object(
      'last_date', rc.latest_date, 'recent', rc.sess)) as target
  from planned pl
  join recent rc on rc.planned_exercise_id = pl.planned_exercise_id
  cross join lateral (
    select private.progression_decision(pl.set_count, pl.rep_min, pl.rep_max, pl.target_rpe,
      pl.step_kg, (select d from today) - rc.latest_date,
      exists (select 1 from perf sk where sk.planned_exercise_id = pl.planned_exercise_id
        and sk.status = 'skipped'
        and (sk.local_date, sk.completed_at) > (rc.latest_date, rc.latest_completed_at)),
      -- (workout_sessions.completed_at is never null for a completed session: a check
      -- constraint ties them, so the row comparisons are never null.)
      -- Pain on a later performance counts even when no set was logged that day.
      exists (select 1 from perf pn where pn.planned_exercise_id = pl.planned_exercise_id
        and pn.pain_flag
        and (pn.local_date, pn.completed_at) > (rc.latest_date, rc.latest_completed_at)),
      pl.assisted,
      rc.sess) as decision
  ) d
  where d.decision is not null
) x;
$$;
revoke all on function private.next_session_targets(uuid) from public, anon, authenticated;

-- 10. Starting the workout --------------------------------------------------------------------------
-- The definition of 20260711190000_workout_truth_repair.sql plus: an accepted, still-standing answer
-- for this workout and day is linked to the session, and reduce_sets builds the session with the
-- adjusted set counts. An easy-cardio answer links only: starting the strength workout stays
-- allowed and its sets are the plan's (the plan must remain usable). Loads are not written; the app
-- pre-fills them.

create or replace function public.start_workout(
  p_planned_workout_id uuid,
  p_local_date date,
  p_timezone text,
  p_idempotency_key uuid
)
returns uuid language plpgsql security definer set search_path='' as $$
declare result_id uuid; version_id uuid; exercise record; performance_id uuid; n integer;
  adjustment public.day_adjustments%rowtype; adjusted boolean := false; set_total integer;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select w.plan_version_id into version_id
  from public.planned_workouts w
  join public.training_plan_versions v on v.id=w.plan_version_id and v.user_id=w.user_id
  where w.id=p_planned_workout_id and w.user_id=auth.uid() and v.status='active';
  if not found then raise exception 'planned workout not found' using errcode='P0002'; end if;

  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and idempotency_key=p_idempotency_key;
  if result_id is not null then return result_id; end if;

  select id into result_id from public.workout_sessions
  where user_id=auth.uid() and planned_workout_id=p_planned_workout_id and state='in_progress'
  order by started_at desc limit 1;
  if result_id is not null then return result_id; end if;

  if exists (
    select 1 from public.workout_sessions
    where user_id=auth.uid() and planned_workout_id=p_planned_workout_id
      and local_date=p_local_date and state='completed'
  ) then
    raise exception 'workout already completed for this coaching day' using errcode='55000';
  end if;

  select * into adjustment from public.day_adjustments a
  where a.user_id=auth.uid() and a.local_date=p_local_date
    and a.planned_workout_id=p_planned_workout_id and a.superseded_at is null
    and a.status='accepted';
  if found then
    adjusted := private.day_adjustment_stands(adjustment,
      private.day_adjustment_compute(auth.uid(), p_local_date) -> 'payload');
  end if;

  insert into public.workout_sessions(
    user_id,plan_version_id,planned_workout_id,local_date,timezone,idempotency_key,actual_started_at,
    day_adjustment_id
  ) values(
    auth.uid(),version_id,p_planned_workout_id,p_local_date,p_timezone,p_idempotency_key,now(),
    case when adjusted then adjustment.id end
  ) returning id into result_id;

  for exercise in select * from public.planned_exercises pe
    where pe.planned_workout_id=p_planned_workout_id order by exercise_order loop
    insert into public.exercise_performances(
      user_id,workout_session_id,planned_exercise_id,exercise_order,status,
      performance_kind,performed_name,rest_seconds
    ) values(
      auth.uid(),result_id,exercise.id,exercise.exercise_order,'unknown',
      'prescribed',exercise.display_name_snapshot,exercise.rest_seconds
    ) returning id into performance_id;
    set_total := exercise.set_count;
    if adjusted and adjustment.kind='reduce_sets' then
      select (c ->> 'sets_to')::integer into set_total
      from jsonb_array_elements(adjustment.changes) c
      where c ->> 'planned_exercise_id' = exercise.id::text;
      set_total := coalesce(set_total, exercise.set_count);
    end if;
    for n in 1..set_total loop
      insert into public.exercise_sets(user_id,exercise_performance_id,set_number)
      values(auth.uid(),performance_id,n);
    end loop;
  end loop;
  return result_id;
end $$;
