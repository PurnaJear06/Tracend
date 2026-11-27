\set off_fixture `cat /contract-fixtures/my_cycle_v1_0_off.json`
\set regular_fixture `cat /contract-fixtures/my_cycle_v1_0_regular.json`
\set late_fixture `cat /contract-fixtures/my_cycle_v1_0_late.json`
\set contraception_fixture `cat /contract-fixtures/my_cycle_v1_0_contraception.json`

begin;
select plan(102);

-- The cycle engine (migration 20261127142651, docs/ALGORITHMS.md section 9). Every case reads
-- private.cycle_state on a fixed local date, so nothing here depends on today. Each athlete is one
-- scenario with a granted cycle_data consent; days are inserted directly (the RPC gates are in
-- cycle_rpcs_test.sql). The contract fixtures are compared whole with answers from real seeds.

create function pg_temp.athlete(p_id text, p_status text, p_typical integer default null,
  p_enabled_at timestamptz default '2025-01-01 12:00:00+00', p_tracking boolean default true)
returns void language sql as $$
  insert into auth.users(id, role) values (p_id::uuid, 'authenticated');
  insert into public.consent_records(user_id, consent_type, notice_version, action, source, created_at)
  values (p_id::uuid, 'cycle_data', '2026-11-27', 'granted', 'ios_app', now() - interval '1 day');
  insert into public.cycle_settings(user_id, tracking_enabled, status, typical_cycle_days,
    tracking_enabled_at)
  values (p_id::uuid, p_tracking, p_status, p_typical, p_enabled_at);
$$;

-- A period of p_days consecutive bleeding days from p_first.
create function pg_temp.period(p_id text, p_first date, p_days integer,
  p_flow text default 'medium', p_source text default 'manual')
returns void language sql as $$
  insert into public.cycle_day_logs(user_id, local_date, flow, source)
  select p_id::uuid, p_first + g, p_flow, p_source from generate_series(0, p_days - 1) g;
$$;

create function pg_temp.day(p_id text, p_date date, p_flow text, p_is_start boolean default false)
returns void language sql as $$
  insert into public.cycle_day_logs(user_id, local_date, flow, is_start, source)
  values (p_id::uuid, p_date, p_flow, p_is_start, 'manual');
$$;

create function pg_temp.st(p_id text, p_date date) returns jsonb language sql as $$
  select private.cycle_state(p_id::uuid, p_date) -> 'state';
$$;

create function pg_temp.cycles(p_id text, p_date date) returns jsonb language sql as $$
  select private.cycle_state(p_id::uuid, p_date) -> 'cycles';
$$;

-- Regular 28-day cycles -------------------------------------------------------------------------------
-- Starts 5 Jan, 2 Feb, 2 Mar, 30 Mar (5 medium days each). She said 30 days; three used lengths of
-- 28 replace that: the next period is expected 25-29 Apr.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000001', 'regular', 30);
select pg_temp.period('c1000000-0000-4000-8000-000000000001', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000001', '2026-02-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000001', '2026-03-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000001', '2026-03-30', 5);

select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000001', '2026-04-10'),
  '[{"start_date":"2026-01-05","length_days":28,"used":true},
    {"start_date":"2026-02-02","length_days":28,"used":true},
    {"start_date":"2026-03-02","length_days":28,"used":true},
    {"start_date":"2026-03-30","length_days":null,"used":false}]'::jsonb,
  'regular: four starts, three used 28-day lengths, the current cycle last');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-10'),
  '{"cycle_day":12,"period_day":null,"phase":"first_half","confidence":"high",
    "expected_from":"2026-04-25","expected_to":"2026-04-29","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'regular: day 12 is the first half, high confidence, the data replaces her stated 30 days');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-12') ->> 'phase', 'first_half',
  'regular: day 14 of 28 is still the first half');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-13') ->> 'phase', 'second_half',
  'regular: day 15 of 28 (typical minus 13) starts the second half');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-19') -> 'weight_water_window',
  'false'::jsonb, 'regular: 6 days before the expected start is outside the water-weight window');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-20') -> 'weight_water_window',
  'true'::jsonb, 'regular: 5 days before the expected start opens the water-weight window');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-25') -> 'weight_water_window',
  'false'::jsonb, 'regular: the window closes the day before the expected range');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-29') ->> 'phase', 'second_half',
  'regular: the last day of the expected range is still the second half');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-01'),
  '{"cycle_day":3,"period_day":3,"phase":"period","confidence":"high",
    "expected_from":"2026-04-25","expected_to":"2026-04-29","late_days":null,
    "no_period_long":false,"weight_water_window":true}'::jsonb,
  'regular: during a period the phase is period and days 1-3 are in the water-weight window');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-04-02') -> 'weight_water_window',
  'false'::jsonb, 'regular: period day 4 is outside the water-weight window');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000001', '2026-03-29'),
  '{"cycle_day":28,"period_day":null,"phase":"second_half","confidence":"medium",
    "expected_from":"2026-03-28","expected_to":"2026-04-01","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'regular: days logged after the date are not read (two lengths, medium confidence)');

-- 21-day cycles ---------------------------------------------------------------------------------------
select pg_temp.athlete('c1000000-0000-4000-8000-000000000002', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000002', '2026-01-01', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000002', '2026-01-22', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000002', '2026-02-12', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000002', '2026-03-05', 4);

select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000002', '2026-03-11'),
    '$[*].length_days'), '[21,21,21,null]'::jsonb,
  '21-day cycles: every length is counted (42 would be a missed month, 21 is not)');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000002', '2026-03-11') ->> 'phase', 'first_half',
  '21-day cycles: day 7 is the first half');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000002', '2026-03-12') ->> 'phase', 'second_half',
  '21-day cycles: day 8 (21 minus 13) starts the second half');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000002', '2026-03-12') ->> 'expected_from',
  '2026-03-24', '21-day cycles: the next period is expected from 21 days less 2');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000002', '2026-03-12') ->> 'expected_to',
  '2026-03-28', '21-day cycles: and up to 21 days plus 2');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000002', '2026-03-12') ->> 'confidence', 'high',
  '21-day cycles: three equal lengths give high confidence');

-- An 8-day period ------------------------------------------------------------------------------------
-- One period, 1-8 May (3 medium, 5 light). She said 28 days.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000003', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000003', '2026-05-01', 3);
select pg_temp.period('c1000000-0000-4000-8000-000000000003', '2026-05-04', 5, 'light');

select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000003', '2026-05-20'),
  '[{"start_date":"2026-05-01","length_days":null,"used":false}]'::jsonb,
  '8-day period: eight bleeding days are one period and one start');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000003', '2026-05-08') ->> 'period_day', '8',
  '8-day period: the eighth day is period day 8');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000003', '2026-05-10') ->> 'period_day', '10',
  '8-day period: two days after the last logged day the period may still be going');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000003', '2026-05-11'),
  '{"cycle_day":11,"period_day":null,"phase":"first_half","confidence":"low",
    "expected_from":"2026-05-27","expected_to":"2026-05-31","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  '8-day period: three days after it the period is over; her stated 28 days give the range, low confidence');
select pg_temp.day('c1000000-0000-4000-8000-000000000003', '2026-05-09', null);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000003', '2026-05-09') -> 'period_day', 'null'::jsonb,
  '8-day period: saying "no bleeding today" ends the period at once');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000003', '2026-05-09') ->> 'phase', 'first_half',
  '8-day period: and the phase moves on to the first half');

-- Spotting before a period ----------------------------------------------------------------------------
select pg_temp.athlete('c1000000-0000-4000-8000-000000000004', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000004', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000004', '2026-01-31', 2, 'spotting');
select pg_temp.period('c1000000-0000-4000-8000-000000000004', '2026-02-02', 5);

select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000004', '2026-02-10'),
    '$[*].start_date'), '["2026-01-05","2026-02-02"]'::jsonb,
  'spotting: the period starts on the first bleeding day, not on the spotting before it');
select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000004', '2026-02-10') -> 0 -> 'length_days',
  '28'::jsonb, 'spotting: so the cycle is 28 days, not 26');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000004', '2026-02-01') -> 'period_day', 'null'::jsonb,
  'spotting: a spotting day is not a period day');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000004', '2026-02-01') ->> 'cycle_day', '28',
  'spotting: and the cycle count carries on');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000004', '2026-02-03') ->> 'period_day', '2',
  'spotting: the second bleeding day is period day 2');

-- A one-day light bleed mid-cycle -------------------------------------------------------------------
select pg_temp.athlete('c1000000-0000-4000-8000-000000000005', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000005', '2026-01-05', 5);
select pg_temp.day('c1000000-0000-4000-8000-000000000005', '2026-01-19', 'light');
select pg_temp.period('c1000000-0000-4000-8000-000000000005', '2026-02-02', 5);

select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000005', '2026-02-10'),
    '$[*].start_date'), '["2026-01-05","2026-02-02"]'::jsonb,
  'mid-cycle bleed: one light day 14 days in is not a new cycle');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000005', '2026-01-19'),
  '{"cycle_day":15,"period_day":null,"phase":"second_half","confidence":"low",
    "expected_from":"2026-01-31","expected_to":"2026-02-04","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'mid-cycle bleed: that day is not a period day and the cycle count is unchanged');

-- A one-day bleed late enough to be a period is shown as one until it proves otherwise.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000006', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000006', '2026-01-05', 5);
select pg_temp.day('c1000000-0000-4000-8000-000000000006', '2026-01-25', 'light');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000006', '2026-01-25') ->> 'period_day', '1',
  'one light day 20 days in may be a period starting: period day 1');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000006', '2026-01-25') ->> 'phase', 'period',
  'and the phase is period');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000006', '2026-01-28') ->> 'cycle_day', '24',
  'with no second day it never becomes a start: the cycle count goes on from 5 Jan');
select is(jsonb_array_length(pg_temp.cycles('c1000000-0000-4000-8000-000000000006', '2026-01-28')), 1,
  'and there is still one cycle');
-- One medium day that late is a start on its own.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000007', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000007', '2026-01-05', 5);
select pg_temp.day('c1000000-0000-4000-8000-000000000007', '2026-02-01', 'heavy');
select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000007', '2026-02-05'),
    '$[*].start_date'), '["2026-01-05","2026-02-01"]'::jsonb,
  'one heavy day at least 15 days after the last start is a start');

-- A missed log month ----------------------------------------------------------------------------------
-- Starts 5 Jan, 2 Feb, 2 Mar, (30 Mar not logged), 27 Apr, 25 May.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000008', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000008', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000008', '2026-02-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000008', '2026-03-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000008', '2026-04-27', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000008', '2026-05-25', 5);

select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000008', '2026-05-05'),
  '[{"start_date":"2026-01-05","length_days":28,"used":true},
    {"start_date":"2026-02-02","length_days":28,"used":true},
    {"start_date":"2026-03-02","length_days":56,"used":false},
    {"start_date":"2026-04-27","length_days":null,"used":false}]'::jsonb,
  'missed month: 56 days, twice the other lengths, is not used');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000008', '2026-05-05') ->> 'confidence', 'low',
  'missed month: an excluded latest length lowers confidence to low');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000008', '2026-05-05') ->> 'expected_from',
  '2026-05-23', 'missed month: the range still uses 28 days, not the 56');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000008', '2026-05-05') ->> 'phase', 'first_half',
  'missed month: and the phase is read from 28 days');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000008', '2026-06-02') ->> 'confidence', 'high',
  'missed month: after the next normal cycle, three used 28s give high confidence again');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000008', '2026-06-02') ->> 'expected_from',
  '2026-06-20', 'missed month: and the next range is 28 days on');
-- With fewer than two other lengths there is nothing to compare with: both lengths are used.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000009', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000009', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000009', '2026-02-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000009', '2026-03-30', 5);
select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000009', '2026-04-05'),
    '$[*].used'), '[true,true,false]'::jsonb,
  'missed month: the test needs two other lengths, so 28 and 56 are both used');

-- A late period and the long gap ----------------------------------------------------------------------
-- Starts 5 Jan, 2 Feb, 2 Mar: expected 28 Mar to 1 Apr.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000010', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000010', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000010', '2026-02-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000010', '2026-03-02', 5);

select is(pg_temp.st('c1000000-0000-4000-8000-000000000010', '2026-04-01'),
  '{"cycle_day":31,"period_day":null,"phase":"second_half","confidence":"medium",
    "expected_from":"2026-03-28","expected_to":"2026-04-01","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'late: the last day of the range is not late yet');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000010', '2026-04-05'),
  '{"cycle_day":35,"period_day":null,"phase":null,"confidence":"medium",
    "expected_from":"2026-03-28","expected_to":"2026-04-01","late_days":4,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'late: four days past the range there is no phase and late_days is 4');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000010', '2026-05-30') -> 'no_period_long',
  'false'::jsonb, 'long gap: 89 days after the last start is not flagged');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000010', '2026-05-31') -> 'no_period_long',
  'true'::jsonb, 'long gap: 90 days after the last start (regular, two or more periods) is flagged');
select pg_temp.day('c1000000-0000-4000-8000-000000000010', '2026-05-20', 'light');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000010', '2026-05-31') -> 'no_period_long',
  'false'::jsonb, 'long gap: a bleed she logged since then (not yet a start) resets the count');

-- Irregular: 180 days.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000011', 'irregular');
select pg_temp.period('c1000000-0000-4000-8000-000000000011', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000011', '2026-02-10', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000011', '2026-08-08') -> 'no_period_long',
  'false'::jsonb, 'long gap, irregular: 179 days is not flagged');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000011', '2026-08-09') -> 'no_period_long',
  'true'::jsonb, 'long gap, irregular: 180 days is flagged');

-- Stopped logging: one period only, long ago. Never flagged.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000012', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000012', '2026-01-05', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000012', '2026-09-01') -> 'no_period_long',
  'false'::jsonb, 'stopped logging: one logged period is never flagged, however long ago');

-- Tracking turned on again on 1 May: the gap counts from then.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000013', 'regular', 28, '2026-05-01 12:00:00+00');
select pg_temp.period('c1000000-0000-4000-8000-000000000013', '2026-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000013', '2026-02-02', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000013', '2026-07-29') -> 'no_period_long',
  'false'::jsonb, 'tracking turned on again: 89 days after turning it on is not flagged');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000013', '2026-07-30') -> 'no_period_long',
  'true'::jsonb, 'tracking turned on again: 90 days after turning it on is flagged');

-- Irregular cycles -----------------------------------------------------------------------------------
-- Lengths 25, 35, 30 (spread 10): starts 1 Jan, 26 Jan, 2 Mar, 1 Apr.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000014', 'irregular', 30);
select pg_temp.period('c1000000-0000-4000-8000-000000000014', '2026-01-01', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000014', '2026-01-26', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000014', '2026-03-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000014', '2026-04-01', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000014', '2026-04-15'),
  '{"cycle_day":15,"period_day":null,"phase":null,"confidence":"medium",
    "expected_from":"2026-04-26","expected_to":"2026-05-06","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'irregular: a wide range (median 30, plus or minus 5) and never a phase');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000014', '2026-05-10') -> 'late_days', 'null'::jsonb,
  'irregular: past the range she is not called late');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000014', '2026-04-03') ->> 'period_day', '3',
  'irregular: period days are still counted');

-- Irregular with fewer than three used lengths: no range, even with a stated length.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000015', 'irregular', 30);
select pg_temp.period('c1000000-0000-4000-8000-000000000015', '2026-01-01', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000015', '2026-01-29', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000015', '2026-02-10'),
  '{"cycle_day":13,"period_day":null,"phase":null,"confidence":"low",
    "expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'irregular: with one used length there is no range');

-- Stated regular, but the data spread over more than 9 days: read as irregular.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000016', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000016', '2026-01-01', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000016', '2026-01-26', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000016', '2026-03-02', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000016', '2026-04-01', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000016', '2026-04-15'),
  '{"cycle_day":15,"period_day":null,"phase":null,"confidence":"medium",
    "expected_from":"2026-04-26","expected_to":"2026-05-06","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'stated regular with a 10-day spread: no phase and the irregular range');
select is((select status from public.cycle_settings
    where user_id = 'c1000000-0000-4000-8000-000000000016'), 'regular',
  'the stored status is not changed by the data');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000016', '2026-05-10') -> 'late_days', 'null'::jsonb,
  'read as irregular, she is not called late');

-- A spread of exactly 9 stays regular: lengths 26, 35, 30 (starts 1 Jan, 27 Jan, 3 Mar, 2 Apr).
select pg_temp.athlete('c1000000-0000-4000-8000-000000000017', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000017', '2026-01-01', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000017', '2026-01-27', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000017', '2026-03-03', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000017', '2026-04-02', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000017', '2026-04-20'),
  '{"cycle_day":19,"period_day":null,"phase":"second_half","confidence":"medium",
    "expected_from":"2026-04-27","expected_to":"2026-05-07","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'a 9-day spread stays regular: a phase, and a range of half the spread (5 days)');

-- Hormonal contraception and no periods --------------------------------------------------------------
select pg_temp.athlete('c1000000-0000-4000-8000-000000000018', 'hormonal_contraception', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000018', '2026-01-05', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000018', '2026-02-02', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000018', '2026-03-01', 4, 'light');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000018', '2026-03-02'),
  '{"cycle_day":null,"period_day":2,"phase":null,"confidence":null,
    "expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":true}'::jsonb,
  'contraception: a bleed day is counted, nothing is predicted and there is no phase');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000018', '2026-03-20'),
  '{"cycle_day":null,"period_day":null,"phase":null,"confidence":null,
    "expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'contraception: outside a bleed every value is empty');
select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000018', '2026-03-20'), '[]'::jsonb,
  'contraception: no cycles are listed');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000018', '2026-12-01') -> 'no_period_long',
  'false'::jsonb, 'contraception: never the long-gap flag');

select pg_temp.athlete('c1000000-0000-4000-8000-000000000019', 'no_periods');
select pg_temp.period('c1000000-0000-4000-8000-000000000019', '2025-01-05', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000019', '2025-02-02', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000019', '2026-03-20'),
  '{"cycle_day":null,"period_day":null,"phase":null,"confidence":null,
    "expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'no periods: nothing, and no long-gap flag after a year of old periods');
select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000019', '2026-03-20'), '[]'::jsonb,
  'no periods: no cycles are listed');

-- Tracking off, or never set up --------------------------------------------------------------------
select pg_temp.athlete('c1000000-0000-4000-8000-000000000020', 'regular', 28, null, false);
select pg_temp.period('c1000000-0000-4000-8000-000000000020', '2026-03-01', 5);
select is(private.cycle_state('c1000000-0000-4000-8000-000000000020', '2026-03-02'),
  '{"state":{"cycle_day":null,"period_day":null,"phase":null,"confidence":null,
    "expected_from":null,"expected_to":null,"late_days":null,
    "no_period_long":false,"weight_water_window":false},"cycles":[]}'::jsonb,
  'tracking off: the kept days are not read');
insert into auth.users(id, role) values ('c1000000-0000-4000-8000-000000000021', 'authenticated');
select is(private.cycle_state('c1000000-0000-4000-8000-000000000021', '2026-03-02'),
  private.cycle_state('c1000000-0000-4000-8000-000000000020', '2026-03-02'),
  'no settings row: the same empty state');

-- A withdrawn consent reads as tracking off.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000028', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000028', '2026-03-01', 5);
insert into public.consent_records(user_id, consent_type, notice_version, action, source)
values ('c1000000-0000-4000-8000-000000000028', 'cycle_data', '2026-11-27', 'withdrawn', 'ios_app');
select is(private.cycle_state('c1000000-0000-4000-8000-000000000028', '2026-03-02'),
  private.cycle_state('c1000000-0000-4000-8000-000000000020', '2026-03-02'),
  'consent withdrawn: the same empty state as tracking off, though the settings say on');

-- Starts flagged by her or by Apple Health ------------------------------------------------------------
-- The onboarding answer "my last period started on 10 Mar" is one unspecified day flagged as a start.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000022', 'regular', 28);
select pg_temp.day('c1000000-0000-4000-8000-000000000022', '2026-03-10', 'unspecified', true);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000022', '2026-03-20'),
  '{"cycle_day":11,"period_day":null,"phase":"first_half","confidence":"low",
    "expected_from":"2026-04-05","expected_to":"2026-04-09","late_days":null,
    "no_period_long":false,"weight_water_window":false}'::jsonb,
  'a single day flagged as a start is a start; her stated 28 days give the range');
select pg_temp.day('c1000000-0000-4000-8000-000000000022', '2026-03-16', 'light', true);
select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000022', '2026-03-20'),
    '$[*].start_date'), '["2026-03-10"]'::jsonb,
  'a second start flag 6 days later is a duplicate, not a new cycle');
select pg_temp.day('c1000000-0000-4000-8000-000000000022', '2026-03-21', 'light', true);
select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000022', '2026-03-25'),
    '$[*].start_date'), '["2026-03-10","2026-03-21"]'::jsonb,
  'a start flag 10 or more days after the last start begins a new cycle');
select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000022', '2026-03-25') -> 0 -> 'used',
  'false'::jsonb, 'and its 11-day length is outside 15-60, so it is not used');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000022', '2026-03-25') ->> 'confidence', 'low',
  'an unused latest length means low confidence');

-- The onboarding guess "my last period started on 28 Oct" (one unspecified day) is replaced by her
-- real period from Apple Health 6 days later.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000029', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000029', '2026-10-01', 5);
select pg_temp.day('c1000000-0000-4000-8000-000000000029', '2026-10-28', 'unspecified', true);
insert into public.cycle_day_logs(user_id, local_date, flow, is_start, source)
select 'c1000000-0000-4000-8000-000000000029', '2026-11-03'::date + g,
  (array['light', 'medium', 'heavy', 'medium', 'light'])[g + 1], g = 0, 'apple_health'
from generate_series(0, 4) g;
select is(pg_temp.st('c1000000-0000-4000-8000-000000000029', '2026-10-30') ->> 'cycle_day', '3',
  'guessed start: until her real period, the guess is the start');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000029', '2026-11-03') ->> 'period_day', '1',
  'guessed start: the first real bleeding day, 6 days later, is period day 1');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000029', '2026-11-03') ->> 'cycle_day', '1',
  'guessed start: and cycle day 1');
select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000029', '2026-11-10'),
  '[{"start_date":"2026-10-01","length_days":33,"used":true},
    {"start_date":"2026-11-03","length_days":null,"used":false}]'::jsonb,
  'guessed start: the cycle is measured to her real start, and the guess is no start');
-- A guess followed by one light day: a start while it may still be a period, the guess again after.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000031', 'regular', 28);
select pg_temp.day('c1000000-0000-4000-8000-000000000031', '2026-10-28', 'unspecified', true);
select pg_temp.day('c1000000-0000-4000-8000-000000000031', '2026-11-03', 'light');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000031', '2026-11-03') ->> 'period_day', '1',
  'guessed start: one light day 6 days later is period day 1 on the day');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000031', '2026-11-07') ->> 'cycle_day', '11',
  'guessed start: with no second day the guess is the start again');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000031', '2026-11-07') -> 'period_day', 'null'::jsonb,
  'guessed start: and the light day was bleeding inside the cycle');
-- A flagged run of two or more days is never replaced.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000030', 'regular', 28);
select pg_temp.day('c1000000-0000-4000-8000-000000000030', '2026-10-28', 'medium', true);
select pg_temp.day('c1000000-0000-4000-8000-000000000030', '2026-10-29', 'light');
select pg_temp.period('c1000000-0000-4000-8000-000000000030', '2026-11-03', 5);
select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000030', '2026-11-10'),
    '$[*].start_date'), '["2026-10-28"]'::jsonb,
  'a two-day flagged period stays the start; bleeding 6 days later is inside the cycle');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000030', '2026-11-03') -> 'period_day', 'null'::jsonb,
  'and is not a period day');

-- Apple Health days and her own days are read the same way.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000023', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000023', '2026-01-05', 5, 'medium', 'apple_health');
select pg_temp.period('c1000000-0000-4000-8000-000000000023', '2026-02-02', 5, 'medium', 'manual');
select pg_temp.period('c1000000-0000-4000-8000-000000000023', '2026-03-02', 5, 'light', 'apple_health');
select is(jsonb_path_query_array(pg_temp.cycles('c1000000-0000-4000-8000-000000000023', '2026-03-10'),
    '$[*].length_days'), '[28,28,null]'::jsonb,
  'Apple Health and manual periods together make one cycle history');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000023', '2026-03-10') ->> 'confidence', 'medium',
  'two used lengths from mixed sources give medium confidence');

-- Gaps inside a period --------------------------------------------------------------------------------
-- Bleeding on 1, 2, 5 and 9 Jun: a 2-day gap joins, a 3-day gap splits.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000024', 'regular', 28);
select pg_temp.day('c1000000-0000-4000-8000-000000000024', '2026-06-01', 'medium');
select pg_temp.day('c1000000-0000-4000-8000-000000000024', '2026-06-02', 'medium');
select pg_temp.day('c1000000-0000-4000-8000-000000000024', '2026-06-05', 'light');
select pg_temp.day('c1000000-0000-4000-8000-000000000024', '2026-06-09', 'light');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000024', '2026-06-05') ->> 'period_day', '5',
  'a 2-day gap is inside the period: 5 Jun is period day 5');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000024', '2026-06-09') -> 'period_day', 'null'::jsonb,
  'after a 3-day gap a single light day 8 days in is bleeding inside the cycle, not a period day');
select is(jsonb_array_length(pg_temp.cycles('c1000000-0000-4000-8000-000000000024', '2026-06-10')), 1,
  'and not a start');

-- Bad input --------------------------------------------------------------------------------------------
select throws_ok($$select private.cycle_state(null, '2026-03-01')$$, '22023', null,
  'the engine needs an athlete');
select throws_ok($$select private.cycle_state('c1000000-0000-4000-8000-000000000001', null)$$,
  '22023', null, 'and a date');

-- The median used for typical lengths and the missed-month test.
select is(private.cycle_median(array[28, 30]), 29::numeric, 'the median of an even count is the mean of the middle two');
select is(private.cycle_median(array[25, 35, 30]), 30::numeric, 'the median of an odd count is the middle one');
select is(private.cycle_median('{}'::integer[]), null::numeric, 'an empty list has no median');

-- A typical length between whole days rounds half up: lengths 28 and 29 give 29.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000025', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000025', '2026-01-01', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000025', '2026-01-29', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000025', '2026-02-27', 5);
select is(pg_temp.st('c1000000-0000-4000-8000-000000000025', '2026-03-05') ->> 'expected_from',
  '2026-03-26', 'a 28.5-day median rounds to 29: expected from 27 Feb plus 29 less 2');

-- Only the last six used lengths count: six of 30 after one of 20 give spread 0 and high confidence.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000026', 'regular');
select pg_temp.period('c1000000-0000-4000-8000-000000000026', '2025-06-01', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000026', '2025-06-21', 4);
select pg_temp.period('c1000000-0000-4000-8000-000000000026', ('2025-06-21'::date + 30 * g), 4)
from generate_series(1, 6) g;
select is(jsonb_array_length(pg_temp.cycles('c1000000-0000-4000-8000-000000000026', '2026-01-01')), 7,
  'the cycles list holds the last seven starts');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000026', '2026-01-01') ->> 'confidence', 'high',
  'the oldest length (20) is outside the last six used, so the spread is 0');

-- Lengths outside 15-60 are not used.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000027', 'regular', 28);
select pg_temp.period('c1000000-0000-4000-8000-000000000027', '2025-10-01', 5);
select pg_temp.period('c1000000-0000-4000-8000-000000000027', '2026-01-05', 5);
select is(pg_temp.cycles('c1000000-0000-4000-8000-000000000027', '2026-01-10') -> 0,
  '{"start_date":"2025-10-01","length_days":96,"used":false}'::jsonb,
  'a 96-day length (a long gap in logging) is listed but not used');
select is(pg_temp.st('c1000000-0000-4000-8000-000000000027', '2026-01-10') ->> 'expected_from',
  '2026-01-31', 'and her stated 28 days give the range');

-- The contract fixtures, whole ----------------------------------------------------------------------
-- Each fixture is the answer get_my_cycle_v1 gives on 27 Nov 2026 (recent days 29 Sep to 28 Nov) for
-- the seed below.
create function pg_temp.answer(p_id text) returns jsonb language sql as $$
  select private.cycle_answer(p_id::uuid, '2026-11-27', '2026-09-29', '2026-11-28');
$$;

insert into auth.users(id, role) values ('c1000000-0000-4000-8000-000000000040', 'authenticated');
select is(pg_temp.answer('c1000000-0000-4000-8000-000000000040'), :'off_fixture'::jsonb,
  'no settings: exactly my_cycle_v1_0_off.json');

-- Starts 15 Sep, 13 Oct, 10 Nov (4 days each, logged by hand).
select pg_temp.athlete('c1000000-0000-4000-8000-000000000041', 'regular', 28, '2026-09-01 08:00:00+00');
insert into public.cycle_day_logs(user_id, local_date, flow, cramps, is_start, source)
select 'c1000000-0000-4000-8000-000000000041', d.local_date::date, d.flow, d.cramps, d.is_start, 'manual'
from (values
  ('2026-09-15', 'medium', 'mild', true), ('2026-09-16', 'medium', null, false),
  ('2026-09-17', 'light', null, false), ('2026-09-18', 'light', null, false),
  ('2026-10-13', 'medium', 'mild', true), ('2026-10-14', 'heavy', 'strong', false),
  ('2026-10-15', 'medium', 'mild', false), ('2026-10-16', 'light', 'none', false),
  ('2026-11-10', 'medium', 'mild', true), ('2026-11-11', 'heavy', 'strong', false),
  ('2026-11-12', 'medium', null, false), ('2026-11-13', 'light', 'none', false)
) d(local_date, flow, cramps, is_start);
select is(pg_temp.answer('c1000000-0000-4000-8000-000000000041'), :'regular_fixture'::jsonb,
  'regular, day 18: exactly my_cycle_v1_0_regular.json');

-- Starts 29 Aug, 26 Sep, 24 Oct (4 days each, from Apple Health): 4 days past the range.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000042', 'regular', 28, '2026-08-01 08:00:00+00');
update public.cycle_settings set apple_health_enabled = true
  where user_id = 'c1000000-0000-4000-8000-000000000042';
insert into public.cycle_day_logs(user_id, local_date, flow, is_start, source)
select 'c1000000-0000-4000-8000-000000000042', s.first_day + g,
  (array['medium', 'heavy', 'medium', 'light'])[g + 1], g = 0, 'apple_health'
from (values ('2026-08-29'::date), ('2026-09-26'::date), ('2026-10-24'::date)) s(first_day),
  generate_series(0, 3) g;
select is(pg_temp.answer('c1000000-0000-4000-8000-000000000042'), :'late_fixture'::jsonb,
  'regular, 4 days late: exactly my_cycle_v1_0_late.json');

-- Hormonal contraception with a bleed on 26 and 27 Nov.
select pg_temp.athlete('c1000000-0000-4000-8000-000000000043', 'hormonal_contraception', null,
  '2026-09-01 08:00:00+00');
insert into public.cycle_day_logs(user_id, local_date, flow, cramps, is_start, source) values
  ('c1000000-0000-4000-8000-000000000043', '2026-11-26', 'light', 'none', false, 'manual'),
  ('c1000000-0000-4000-8000-000000000043', '2026-11-27', 'light', null, false, 'manual');
select is(pg_temp.answer('c1000000-0000-4000-8000-000000000043'), :'contraception_fixture'::jsonb,
  'contraception, bleed day 2: exactly my_cycle_v1_0_contraception.json');

select * from finish();
rollback;
