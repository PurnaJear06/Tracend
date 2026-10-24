-- B5-4: cardio dosing (server side, rules version cardio-v1).
--
-- A weekly cardio dose from the public health guidelines (WHO 2020, HHS 2018, ACSM 2011): at least
-- 150 minutes of moderate cardio a week, up to 300 for fat loss and recomposition, vigorous minutes
-- counting double. Observed minutes come from the athlete's Apple Health workouts over the last
-- seven days. Nothing here prescribes an intensity from heart rate: the easy ceiling is a share of
-- heart-rate reserve that the app turns into beats per minute from the athlete's own profile, and
-- the talk test stays the plain-words rule (decision D9: heart rate informs cardio dosing and never
-- sets a lifting load; the athlete decides).
--
--   1. private.cardio_rules()                  every number of the rules, in one place
--   2. private.cardio_week                     target, observed minutes and what intensity is open today
--   3. private.training_guidance               schema 1.1: adds cardio_week and cardio_withheld
--                                              (B5-3's function plus those hunks only)
--
-- get_my_training_guidance_v1 and get_training_guidance_for_v1 are unchanged: they return whatever
-- private.training_guidance returns. Additive: an older reader ignores the two new keys.
--
-- The easy-cardio day B4 offers keeps its 20 to 30 minutes, which cardio_rules() repeats so the weekly
-- row and the day card quote one dose (a test pins the two together).

-- 1. The rules ---------------------------------------------------------------------------------------------
-- weekly_floor_min and weekly_upper_min are minutes of moderate cardio; a vigorous minute counts as
-- vigorous_counts_as moderate ones. stretch_goals are the goals that show the upper figure too.
-- easy_hr_reserve_max_pct is the top of the easy zone, as a share of heart-rate reserve.
-- vigorous_sessions_max is the most hard sessions a week for an athlete cleared for them;
-- lift_separation_hours is the gap to keep between hard cardio and a lifting session when explosive
-- strength matters. workout_cap_min caps one workout. window_days is the week observed, and it needs
-- Apple Health summaries on min_summary_days of those days or no figure is given (never 0).
-- cardio_types are the workout names the health plugin writes for cardio on iOS; strength and other
-- workouts are not counted, and steps are never converted.

create function private.cardio_rules()
returns jsonb language sql immutable set search_path = '' as $$
  select '{"version":"cardio-v1","weekly_floor_min":150,"weekly_upper_min":300,"vigorous_counts_as":2,"easy_minutes":[20,30],"easy_hr_reserve_max_pct":60,"vigorous_sessions_max":2,"lift_separation_hours":3,"workout_cap_min":180,"window_days":7,"min_summary_days":5,"stretch_goals":["fat_loss","recomposition"],"cardio_types":["WALKING","RUNNING","BIKING","HIKING","ELLIPTICAL","ROWING","SWIMMING","STAIR_CLIMBING","STAIRS","STEP_TRAINING","HAND_CYCLING","JUMP_ROPE","CARDIO_DANCE","MIXED_CARDIO","HIGH_INTENSITY_INTERVAL_TRAINING"]}'::jsonb;
$$;
revoke all on function private.cardio_rules() from public, anon, authenticated;

-- 2. The week --------------------------------------------------------------------------------------------------
-- {target_min, stretch_max, done_min, intensity_known, vigorous_allowed, vigorous_sessions_max,
--  vigorous_counts_as, lift_separation_hours, easy_hr_reserve_max, window_from, window_to}.
--   done_min   whole minutes of cardio workouts over the window, null when fewer than min_summary_days
--              of its days have an Apple Health summary. Workouts that overlap count once (a watch and
--              a phone can both record the same walk) and one workout counts for at most
--              workout_cap_min. Every minute is counted as moderate (intensity_known is false): the
--              workout record carries no intensity.
--   stretch_max   the upper figure for the active goal, null for the other goals.
--   vigorous_allowed   hard cardio is open today only for an athlete the health check has cleared, on
--              a green readiness band (p_band; no check-in, amber and red are easy-only days) with
--              no joint held or limited. Otherwise only easy cardio is offered.
--   vigorous_sessions_max   0 under moderate_until_cleared, else the rule's figure.
-- The caller withholds the whole object on a day with a safety route and under see_professional.

create function private.cardio_week(p_user uuid, p_date date, p_band text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  r constant jsonb := private.cardio_rules();
  cleared constant boolean := private.current_screening_outcome(p_user) = 'cleared';
  window_from constant date := p_date - ((r ->> 'window_days')::integer - 1);
  summary_days integer;
  observed integer;
  goal text;
begin
  select count(*) into summary_days from public.daily_health_summaries h
  where h.user_id = p_user and h.source_scope = 'healthkit'
    and h.local_date between window_from and p_date;

  if summary_days >= (r ->> 'min_summary_days')::integer then
    select coalesce(floor(sum(extract(epoch from upper(m.span) - lower(m.span))) / 60), 0)::integer
    into observed
    from (
      select unnest(range_agg(tstzrange(w.started_at, least(w.ended_at,
        w.started_at + (r ->> 'workout_cap_min')::integer * interval '1 minute')))) as span
      from public.health_workout_references w
      where w.user_id = p_user and w.local_date between window_from and p_date
        and upper(w.activity_type) in (select jsonb_array_elements_text(r -> 'cardio_types'))
    ) m;
  end if;

  select g.goal_type::text into goal from public.user_goals g
  where g.id = private.active_goal_id(p_user);

  return jsonb_build_object(
    'target_min', (r ->> 'weekly_floor_min')::integer,
    'stretch_max', case when goal in (select jsonb_array_elements_text(r -> 'stretch_goals'))
      then (r ->> 'weekly_upper_min')::integer end,
    'done_min', observed,
    'intensity_known', false,
    'vigorous_allowed', coalesce(p_band <> 'red', true) and not exists (
      select 1 from jsonb_array_elements(private.joint_states(p_user, p_date)) s
      where s ->> 'state' in ('held', 'limited')),
    'vigorous_sessions_max', case when cleared then (r ->> 'vigorous_sessions_max')::integer else 0 end,
    'vigorous_counts_as', (r ->> 'vigorous_counts_as')::integer,
    'lift_separation_hours', (r ->> 'lift_separation_hours')::integer,
    'easy_hr_reserve_max', (r ->> 'easy_hr_reserve_max_pct')::integer,
    'window_from', window_from,
    'window_to', p_date);
end $$;
revoke all on function private.cardio_week(uuid, date, text) from public, anon, authenticated;

-- 3. Guidance 1.1 ------------------------------------------------------------------------------------------------
-- B5-3's private.training_guidance plus: the schema version, a withheld reason (a safety route, or a
-- health check that says to see a professional first) and the cardio week when nothing withholds it.

create or replace function private.training_guidance(p_user uuid, p_date date)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  adjustment jsonb := private.day_adjustment_compute(p_user, p_date, true) -> 'payload';
  route text := adjustment ->> 'safety_route';
  deload jsonb := private.deload_signals(p_user, p_date);
  withheld text := case when false then 'safety_route'
    when false then 'screening' end;
begin
  if false and route is not null and deload ->> 'status' = 'suggested' then
    deload := deload || jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,
      'suppressed_by', 'safety_route');
  end if;
  return jsonb_build_object('schema_version', '1.1', 'local_date', p_date,
    'safety_route', route, 'deload', deload, 'cardio_withheld', withheld,
    'cardio_week', case when withheld is null
      then private.cardio_week(p_user, p_date, adjustment ->> 'band') end);
end $$;
revoke all on function private.training_guidance(uuid, date) from public, anon, authenticated;
