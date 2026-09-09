begin;
select plan(25);

insert into auth.users(id, role) values
  ('eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee', 'authenticated'),
  ('ffffffff-ffff-4fff-8fff-ffffffffffff', 'authenticated');

select ok(
  (select bool_and(relrowsecurity and relforcerowsecurity)
   from pg_class where oid = any(array[
     'public.health_sync_runs'::regclass,
     'public.daily_health_summaries'::regclass
   ])),
  'Phase 4 tables enable and force RLS'
);
select ok(not has_table_privilege('anon', 'public.daily_health_summaries', 'select'),
  'anonymous cannot read health summaries');
select ok(not has_table_privilege('authenticated', 'public.daily_health_summaries', 'insert'),
  'mobile clients cannot write health summaries directly');
select ok(not has_function_privilege(
  'authenticated',
  'public.persist_health_sync(uuid,uuid,date,date,text[],text[],jsonb)',
  'execute'
), 'authenticated clients cannot call service persistence RPC');
select ok(has_function_privilege(
  'service_role',
  'public.persist_health_sync(uuid,uuid,date,date,text[],text[],jsonb)',
  'execute'
), 'service role can call health persistence RPC');

set local role service_role;
select lives_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e1000000-0000-4000-8000-000000000001',
    '2026-06-30', '2026-07-01',
    array['steps','sleep'], array['steps'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "steps":6400,
      "present_types":["steps"],
      "source_refs":[{
        "type":"steps",
        "source_id_hash":"1111111111111111111111111111111111111111111111111111111111111111",
        "sample_id_hash":"2222222222222222222222222222222222222222222222222222222222222222"
      }],
      "source_checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "completeness":"partial",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, 'service boundary persists a validated partial summary');
select is((select count(*) from public.daily_health_summaries), 1::bigint,
  'one daily summary is stored');
select is((select status::text from public.health_sync_runs), 'partial',
  'missing returned types are recorded as partial');
select is(
  (select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e1000000-0000-4000-8000-000000000001',
    '2026-06-30', '2026-07-01',
    array['steps','sleep'], array['steps'], '[]'::jsonb
  )->>'replayed'),
  'true',
  'duplicate idempotency key replays without rewriting'
);
select is((select count(*) from public.health_sync_runs), 1::bigint,
  'duplicate sync does not create another run');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e2000000-0000-4000-8000-000000000002',
    '2026-07-01', '2026-07-01',
    array['steps'], array['steps'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "steps":900000,
      "present_types":["steps"],
      "source_refs":[{
        "type":"steps",
        "source_id_hash":"3333333333333333333333333333333333333333333333333333333333333333",
        "sample_id_hash":"4444444444444444444444444444444444444444444444444444444444444444"
      }],
      "source_checksum":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
      "completeness":"complete",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, '23514', null, 'out-of-range health data is rejected');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e3000000-0000-4000-8000-000000000003',
    '2026-07-01', '2026-07-01',
    array['steps'], array['weight'],
    '[]'::jsonb
  )
$$, '22023', null, 'returned types outside request are rejected');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e4000000-0000-4000-8000-000000000004',
    '2026-07-01', '2026-07-01',
    array['steps','steps'], array['steps'], '[]'::jsonb
  )
$$, '22023', null, 'duplicate requested types are rejected');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e5000000-0000-4000-8000-000000000005',
    '2026-07-01', '2026-07-01',
    array['steps'], array['steps'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "steps":6400,
      "present_types":["steps"],
      "source_refs":[{
        "type":"steps",
        "source_id_hash":"5555555555555555555555555555555555555555555555555555555555555555",
        "sample_id_hash":"6666666666666666666666666666666666666666666666666666666666666666"
      }],
      "source_checksum":"cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc",
      "completeness":"partial",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, '22023', null, 'inconsistent completeness is rejected');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e6000000-0000-4000-8000-000000000006',
    '2026-07-01', '2026-07-01',
    array['steps'], array['steps'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "steps":6400,
      "present_types":["steps"],
      "source_refs":[],
      "source_checksum":"dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd",
      "completeness":"complete",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, '22023', null, 'missing source provenance is rejected');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e7000000-0000-4000-8000-000000000007',
    '2026-07-01', '2026-07-01',
    array['hrv_sdnn'], array['hrv_sdnn'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "hrv_value_ms":48,
      "hrv_metric":"sdnn",
      "present_types":["hrv_sdnn"],
      "source_refs":[{
        "type":"hrv_sdnn",
        "source_id_hash":"7777777777777777777777777777777777777777777777777777777777777777",
        "sample_id_hash":"8888888888888888888888888888888888888888888888888888888888888888"
      }],
      "source_checksum":"eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
      "completeness":"complete",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, '23514', null, 'HRV without an explicit unit is rejected');

select lives_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e8000000-0000-4000-8000-000000000008',
    '2026-06-30', '2026-07-01',
    array['steps','sleep','resp_rate'], array['steps','resp_rate'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "steps":6400,
      "respiratory_rate_bpm":14.2,
      "present_types":["steps","resp_rate"],
      "source_refs":[{
        "type":"steps",
        "source_id_hash":"1111111111111111111111111111111111111111111111111111111111111111",
        "sample_id_hash":"2222222222222222222222222222222222222222222222222222222222222222"
      },{
        "type":"resp_rate",
        "source_id_hash":"1111111111111111111111111111111111111111111111111111111111111111",
        "sample_id_hash":"9999999999999999999999999999999999999999999999999999999999999999"
      }],
      "source_checksum":"ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff",
      "completeness":"partial",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, 'service boundary persists a respiratory rate summary');
select is(
  (select respiratory_rate_bpm from public.daily_health_summaries
   where local_date = '2026-07-01'),
  14.2::numeric,
  'respiratory rate is stored on the daily summary'
);
select is(
  (select present_types::text[] from public.daily_health_summaries
   where local_date = '2026-07-01' order by local_date desc limit 1),
  array['steps','resp_rate']::text[],
  'present_types gains resp_rate'
);
select is((select count(*) from public.daily_health_summaries), 1::bigint,
  'respiratory sync upserts the existing date row rather than adding one');
select throws_ok($$
  select public.persist_health_sync(
    'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee',
    'e9000000-0000-4000-8000-000000000009',
    '2026-07-01', '2026-07-01',
    array['steps','resp_rate'], array['steps','resp_rate'],
    '[{
      "local_date":"2026-07-01",
      "timezone":"Asia/Kolkata",
      "steps":6400,
      "respiratory_rate_bpm":140,
      "present_types":["steps","resp_rate"],
      "source_refs":[{
        "type":"steps",
        "source_id_hash":"1111111111111111111111111111111111111111111111111111111111111",
        "sample_id_hash":"2222222222222222222222222222222222222222222222222222222222222222"
      },{
        "type":"resp_rate",
        "source_id_hash":"1111111111111111111111111111111111111111111111111111111111111111",
        "sample_id_hash":"9999999999999999999999999999999999999999999999999999999999999999"
      }],
      "source_checksum":"aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
      "completeness":"complete",
      "observed_through":"2026-07-01T08:00:00Z"
    }]'::jsonb
  )
$$, '23514', null, 'out-of-range respiratory rate is rejected');


set local role authenticated;
set local "request.jwt.claim.sub" = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee';
select is((select count(*) from public.daily_health_summaries), 1::bigint,
  'owner can read own health summary');
select is((select count(*) from public.health_sync_runs), 2::bigint,
  'owner can read own sync runs');

set local "request.jwt.claim.sub" = 'ffffffff-ffff-4fff-8fff-ffffffffffff';
select is((select count(*) from public.daily_health_summaries), 0::bigint,
  'another user cannot read health summary');
select is((select count(*) from public.health_sync_runs), 0::bigint,
  'another user cannot read sync run');

select * from finish();
rollback;
