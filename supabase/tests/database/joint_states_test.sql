begin;
select no_plan();

-- B5-1: how an athlete's pain reports become each joint's state (held, limited, watch, none) and when a
-- pain counts as lasting. One athlete per scenario; reports are dated relative to the athlete's today and
-- stored in the order written (the helper stamps each with the clock, so two reports of a day keep
-- their order).

insert into auth.users(id, role)
select ('b5100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid, 'authenticated'
from generate_series(1, 46) n;

create temporary table t as
  select private.local_date_for('b5100000-0000-4000-8000-000000000001') as today;

create function pg_temp.u(n integer) returns uuid language sql as $$
  select ('b5100000-0000-4000-8000-' || lpad(n::text, 12, '0'))::uuid;
$$;

-- A report p_days_ago days ago; flags null means the red-flag question was not asked.
create function pg_temp.rep(n integer, p_days_ago integer, p_area text, p_sev integer,
  p_flags text[] default null, p_cleared boolean default false) returns void language sql as $$
  insert into public.pain_reports(user_id, local_date, source, area, severity, red_flags,
    cleared_by_clinician, outcome, created_at)
  values (pg_temp.u(n), (select today from t) - p_days_ago, 'workout', p_area, p_sev, p_flags,
    p_cleared, private.pain_outcome(p_sev, p_flags), clock_timestamp());
$$;

-- "state:persistent" for one area as of p_back days before today, or none.
create function pg_temp.js(n integer, p_area text, p_back integer default 0) returns text language sql as $$
  select coalesce((select (s ->> 'state') || ':' || (s ->> 'persistent')
    from jsonb_array_elements(private.joint_states(pg_temp.u(n), (select today from t) - p_back)) s
    where s ->> 'area' = p_area), 'none');
$$;

select is(private.joint_states(pg_temp.u(1), (select today from t)), '[]'::jsonb, 'no reports, no state');

-- Limited, and the week it lasts ----------------------------------------------------------------------------
select pg_temp.rep(2, 0, 'knee', 5);
select is(pg_temp.js(2, 'knee'), 'limited:false', 'a 5 today limits the knee');
select is((select s from jsonb_array_elements(private.joint_states(pg_temp.u(2), (select today from t))) s),
  jsonb_build_object('area', 'knee', 'state', 'limited', 'since', (select today from t), 'severity', 5,
    'persistent', false, 'hold_outcome', null),
  'with its area, state, day, severity, flag and (not held) no hold outcome');
select pg_temp.rep(3, 6, 'knee', 5);
select is(pg_temp.js(3, 'knee'), 'limited:false', 'a 5 six days ago still limits');
select pg_temp.rep(4, 7, 'knee', 5);
select is(pg_temp.js(4, 'knee'), 'limited:false', 'and seven days ago');
select pg_temp.rep(5, 8, 'knee', 5);
select is(pg_temp.js(5, 'knee'), 'none', 'eight days ago it has lapsed');

-- Watch ------------------------------------------------------------------------------------------------------
select pg_temp.rep(6, 7, 'shoulder', 2);
select is(pg_temp.js(6, 'shoulder'), 'watch:false', 'a 2 seven days ago is on watch');
select pg_temp.rep(7, 8, 'shoulder', 2);
select is(pg_temp.js(7, 'shoulder'), 'none', 'and not eight days ago');
select pg_temp.rep(8, 0, 'back', 3);
select is(pg_temp.js(8, 'back'), 'watch:false', 'a 3 is the top of watch');
select pg_temp.rep(9, 0, 'back', 4);
select is(pg_temp.js(9, 'back'), 'limited:false', 'and a 4 is the bottom of limited');

-- Pain that is gone ----------------------------------------------------------------------------------------
select pg_temp.rep(10, 3, 'knee', 5);
select pg_temp.rep(10, 1, 'knee', 0);
select is(pg_temp.js(10, 'knee'), 'none', 'a report of 0 ends a limit');
select pg_temp.rep(11, 0, 'knee', 0);
select is(pg_temp.js(11, 'knee'), 'none', 'a lone 0 is no state');

-- Held: a severity of 7 or more, or a red flag; it never lapses ----------------------------------------------
select pg_temp.rep(12, 20, 'knee', 7);
select is(pg_temp.js(12, 'knee'), 'held:true', 'a 7 twenty days ago still holds the knee, and it has lasted');
select pg_temp.rep(13, 14, 'knee', 7);
select is(pg_temp.js(13, 'knee'), 'held:true', 'held for 14 days: lasting');
select pg_temp.rep(14, 13, 'knee', 7);
select is(pg_temp.js(14, 'knee'), 'held:false', 'held for 13 days: not yet');
select pg_temp.rep(15, 60, 'knee', 9);
select is(pg_temp.js(15, 'knee'), 'held:true', 'a hold from two months ago has not lapsed');
select pg_temp.rep(16, 2, 'knee', 3, array['locks_gives_way']);
select is(pg_temp.js(16, 'knee'), 'held:false', 'a red flag on a mild pain holds the knee');
select is((select s ->> 'since' from jsonb_array_elements(private.joint_states(pg_temp.u(16), (select today from t))) s),
  ((select today from t) - 2)::text, 'since the day of the flag');

-- Clearance: only the athlete's word, only at 3 or less, and a new symptom wins ----------------------------------
select pg_temp.rep(17, 10, 'knee', 8);
select pg_temp.rep(17, 5, 'knee', 2, '{}', true);
select is(pg_temp.js(17, 'knee'), 'watch:false', 'cleared by a clinician: on watch, no longer held');
select pg_temp.rep(18, 20, 'knee', 8);
select pg_temp.rep(18, 9, 'knee', 2, '{}', true);
select is(pg_temp.js(18, 'knee'), 'none', 'the watch after a clearance ends after seven days');
select is(pg_temp.js(18, 'knee', 3), 'watch:false', 'and was on while it lasted');
select pg_temp.rep(19, 10, 'knee', 8);
select pg_temp.rep(19, 3, 'knee', 0, '{}', true);
select is(pg_temp.js(19, 'knee'), 'watch:false', 'a clearance with no pain still leaves a week on watch');
select pg_temp.rep(20, 10, 'knee', 8);
select pg_temp.rep(20, 3, 'knee', 0, '{}', true);
select pg_temp.rep(20, 1, 'knee', 0);
select is(pg_temp.js(20, 'knee'), 'none', 'and a later report of 0 ends that watch');
select pg_temp.rep(21, 10, 'knee', 8);
select pg_temp.rep(21, 1, 'knee', 5);
select is(pg_temp.js(21, 'knee'), 'held:false', 'a hold stays through reports that are not a clearance');
select is((select s ->> 'since' from jsonb_array_elements(private.joint_states(pg_temp.u(21), (select today from t))) s),
  ((select today from t) - 10)::text, 'since the day it began');
select pg_temp.rep(22, 10, 'knee', 8);
select pg_temp.rep(22, 2, 'knee', 5, '{}', true);
select is(pg_temp.js(22, 'knee'), 'held:false', 'a clearance with a pain above 3 does not lift a hold');
select pg_temp.rep(23, 10, 'knee', 8);
select pg_temp.rep(23, 2, 'knee', 2, array['night_pain'], true);
select is(pg_temp.js(23, 'knee'), 'held:false', 'a clearance with a red flag does not either');
select pg_temp.rep(24, 20, 'knee', 8);
select pg_temp.rep(24, 15, 'knee', 1, '{}', true);
select pg_temp.rep(24, 2, 'knee', 5);
select is(pg_temp.js(24, 'knee'), 'limited:false', 'after a clearance, a new 5 limits the knee and does not hold it');
select pg_temp.rep(25, 20, 'knee', 8);
select pg_temp.rep(25, 15, 'knee', 1, '{}', true);
select pg_temp.rep(25, 1, 'knee', 2, array['numb_weak_limb']);
select is(pg_temp.js(25, 'knee'), 'held:false', 'after a clearance a new red flag holds the knee again');
select is((select s ->> 'since' from jsonb_array_elements(private.joint_states(pg_temp.u(25), (select today from t))) s),
  ((select today from t) - 1)::text, 'counted from the new hold, not the old one');
select pg_temp.rep(38, 30, 'knee', 8);
select pg_temp.rep(38, 20, 'knee', 1, '{}', true);
select pg_temp.rep(38, 15, 'knee', 8);
select is(pg_temp.js(38, 'knee'), 'held:true', 'a second hold of 15 days has lasted by itself');
select pg_temp.rep(39, 30, 'knee', 8);
select pg_temp.rep(39, 20, 'knee', 1, '{}', true);
select pg_temp.rep(39, 5, 'knee', 8);
select is(pg_temp.js(39, 'knee'), 'held:false', 'and one of 5 days has not, whatever came before the clearance');

-- Pain that lasts (limited, not held) --------------------------------------------------------------------------
select pg_temp.rep(26, 14, 'knee', 5);
select pg_temp.rep(26, 0, 'knee', 5);
select is(pg_temp.js(26, 'knee'), 'limited:true', 'two reports of 4 or more, the first 14 days ago: lasting');
select pg_temp.rep(27, 13, 'knee', 5);
select pg_temp.rep(27, 0, 'knee', 5);
select is(pg_temp.js(27, 'knee'), 'limited:false', 'the first 13 days ago: not yet');
select pg_temp.rep(28, 20, 'knee', 5);
select pg_temp.rep(28, 10, 'knee', 0);
select pg_temp.rep(28, 0, 'knee', 5);
select is(pg_temp.js(28, 'knee'), 'limited:false', 'a report of 0 starts a new episode');
select pg_temp.rep(29, 14, 'knee', 5);
select pg_temp.rep(29, 7, 'knee', 5);
select pg_temp.rep(29, 0, 'knee', 5);
select is(pg_temp.js(29, 'knee'), 'limited:true', 'reports a week apart for two weeks: lasting');
select pg_temp.rep(40, 14, 'knee', 3);
select pg_temp.rep(40, 0, 'knee', 3);
select is(pg_temp.js(40, 'knee'), 'watch:false', 'mild pain on and off is never lasting');

-- Areas are independent, and the other area counts too ----------------------------------------------------------
select pg_temp.rep(31, 1, 'knee', 8);
select pg_temp.rep(31, 0, 'back', 5);
select is(array(select s ->> 'area' || ':' || (s ->> 'state')
    from jsonb_array_elements(private.joint_states(pg_temp.u(31), (select today from t))) s),
  array['knee:held', 'back:limited'], 'a held knee and a limited back, in the order knee, back, shoulder, other');
select is(pg_temp.js(31, 'shoulder'), 'none', 'and the shoulder is untouched');
select pg_temp.rep(32, 0, 'other', 8);
select is(pg_temp.js(32, 'other'), 'held:false', 'somewhere else is held too (it never changes an exercise)');

-- Only what has happened by the day asked about ------------------------------------------------------------------
select pg_temp.rep(33, 0, 'knee', 5);
select is(pg_temp.js(33, 'knee', 1), 'none', 'a report of today does not exist yesterday');

-- Order within a day -------------------------------------------------------------------------------------------
select pg_temp.rep(34, 0, 'knee', 8);
select pg_temp.rep(34, 0, 'knee', 1, '{}', true);
select is(pg_temp.js(34, 'knee'), 'watch:false', 'a clearance stored after the hold, the same day, lifts it');
select pg_temp.rep(35, 0, 'knee', 1, '{}', true);
select pg_temp.rep(35, 0, 'knee', 8);
select is(pg_temp.js(35, 'knee'), 'held:false', 'a clearance stored before the hold does not');
select pg_temp.rep(36, 0, 'knee', 0, '{}', true);
select is(pg_temp.js(36, 'knee'), 'none', 'a clearance with nothing to clear is no state');
select pg_temp.rep(37, 5, 'shoulder', 2, '{}', true);
select is(pg_temp.js(37, 'shoulder'), 'watch:false', 'a mild report that says cleared, with no hold before it, is judged by its severity');

-- The outcome of the hold in force: the strictest of its reports, and only those after the last clearance ----
create function pg_temp.ho(n integer, p_area text) returns text language sql as $$
  select coalesce((select s ->> 'hold_outcome' from jsonb_array_elements(
    private.joint_states(pg_temp.u(n), (select today from t))) s where s ->> 'area' = p_area), 'none');
$$;
select pg_temp.rep(41, 3, 'knee', 3, array['chest_or_breath']);
select pg_temp.rep(41, 1, 'knee', 8);
select is(pg_temp.ho(41, 'knee'), 'urgent', 'an urgent flag and a later 8: the hold is urgent, the strictest');
select pg_temp.rep(42, 2, 'back', 3, array['night_pain']);
select is(pg_temp.ho(42, 'back'), 'clinician', 'a clinician flag alone: a clinician hold');
select pg_temp.rep(43, 10, 'knee', 3, array['chest_or_breath']);
select pg_temp.rep(43, 5, 'knee', 2, '{}', true);
select pg_temp.rep(43, 1, 'knee', 3, array['locks_gives_way']);
select is(pg_temp.ho(43, 'knee'), 'clinician', 'after a clearance only the new hold counts: the old urgent one is over');
select pg_temp.rep(44, 0, 'knee', 5);
select is(pg_temp.ho(44, 'knee'), 'none', 'a limited area has no hold outcome');
select pg_temp.rep(45, 4, 'other', 4, array['chest_or_breath']);
select is(pg_temp.ho(45, 'other'), 'urgent', 'the area "other" holds too, and keeps its outcome on later days');
select is((select array(select k from jsonb_object_keys(s) k order by k collate "C")
    from jsonb_array_elements(private.joint_states(pg_temp.u(41), (select today from t))) s limit 1),
  array['area', 'hold_outcome', 'persistent', 'severity', 'since', 'state'],
  'the joint state carries exactly six keys');
select is((select array(select k from jsonb_object_keys(s) k order by k collate "C")
    from jsonb_array_elements(private.joint_states_detail(pg_temp.u(41), (select today from t))) s limit 1),
  array['area', 'hold_codes', 'hold_outcome', 'hold_severe', 'persistent', 'severity', 'since', 'state'],
  'and the detail adds the codes and the severe flag for the day''s trigger codes');
select is((select s -> 'hold_codes' from jsonb_array_elements(private.joint_states_detail(pg_temp.u(41),
    (select today from t))) s limit 1), '["chest_or_breath"]'::jsonb, 'the codes of the hold''s reports');
select is((select (s ->> 'hold_severe')::boolean from jsonb_array_elements(private.joint_states_detail(
    pg_temp.u(41), (select today from t))) s limit 1), true, 'and that one of them was a 7 or more');
select is((select (s ->> 'hold_severe')::boolean from jsonb_array_elements(private.joint_states_detail(
    pg_temp.u(45), (select today from t))) s limit 1), false, 'not for a flag on a milder pain');

select * from finish();
rollback;
