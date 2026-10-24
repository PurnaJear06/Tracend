begin;
select plan(32);

insert into auth.users(id, role) values
  ('a1111111-eeee-4111-8111-111111111111', 'authenticated'),
  ('a2222222-eeee-4222-8222-222222222222', 'authenticated'),
  ('a3333333-eeee-4333-8333-333333333333', 'authenticated'),
  ('a4444444-eeee-4444-8444-444444444444', 'authenticated');

-- Exports ---------------------------------------------------------------------------------

insert into public.data_exports(id, user_id, status, started_at) values
  ('b1111111-eeee-4111-8111-111111111111', 'a1111111-eeee-4111-8111-111111111111',
   'processing', now() - interval '20 minutes'),
  ('b2222222-eeee-4222-8222-222222222222', 'a2222222-eeee-4222-8222-222222222222',
   'processing', now() - interval '2 minutes'),
  ('b3333333-eeee-4333-8333-333333333333', 'a3333333-eeee-4333-8333-333333333333',
   'queued', null);

select is(
  public.claim_data_export('b1111111-eeee-4111-8111-111111111111'),
  'a1111111-eeee-4111-8111-111111111111'::uuid,
  'an export whose worker stopped can be claimed again'
);
select ok(
  (select status = 'processing' and started_at > now() - interval '1 minute'
   from public.data_exports where id = 'b1111111-eeee-4111-8111-111111111111'),
  'the new claim restarts the clock'
);
select is(
  public.claim_data_export('b2222222-eeee-4222-8222-222222222222'),
  null::uuid,
  'an export still running cannot be claimed twice'
);
select is(
  public.claim_data_export('b3333333-eeee-4333-8333-333333333333'),
  'a3333333-eeee-4333-8333-333333333333'::uuid,
  'a queued export is still claimed'
);
select ok(
  not has_function_privilege('authenticated', 'public.claim_data_export(uuid)', 'execute')
  and has_function_privilege('service_role', 'public.claim_data_export(uuid)', 'execute'),
  'only the service role claims exports'
);

-- A stuck export no longer blocks the next request: it is claimed again under the same id.
set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'a1111111-eeee-4111-8111-111111111111', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint,
  'amr', json_build_array(json_build_object('method', 'password',
    'timestamp', extract(epoch from now())::bigint))
)::text, true);
select is(
  public.request_my_data_export(),
  'b1111111-eeee-4111-8111-111111111111'::uuid,
  'a request while an export is processing returns that export'
);
reset role;

-- A ready export that has expired or used its downloads is replaced, not returned.
insert into public.data_exports(id, user_id, status, storage_path, byte_size, completed_at,
  expires_at, download_count) values
  ('b4444444-eeee-4444-8444-444444444444', 'a4444444-eeee-4444-8444-444444444444', 'ready',
   'a4444444-eeee-4444-8444-444444444444/b4444444-eeee-4444-8444-444444444444.tracendexport',
   100, now() - interval '8 days', now() - interval '1 day', 1);

set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'a4444444-eeee-4444-8444-444444444444', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint,
  'amr', json_build_array(json_build_object('method', 'password',
    'timestamp', extract(epoch from now())::bigint))
)::text, true);
create temporary table fresh_request as select public.request_my_data_export() as id;
reset role;
select isnt(
  (select id from fresh_request), 'b4444444-eeee-4444-8444-444444444444'::uuid,
  'an expired ready export is not handed back'
);
select is(
  (select status from public.data_exports where id = 'b4444444-eeee-4444-8444-444444444444'),
  'expired', 'the expired export is marked expired'
);
select ok(
  (select storage_path is not null from public.data_exports
   where id = 'b4444444-eeee-4444-8444-444444444444'),
  'its file stays listed so retention removes it'
);
select is(
  (select status from public.data_exports where id = (select id from fresh_request)),
  'queued', 'a new export is queued in its place'
);
select ok(
  exists(select 1 from public.expire_data_exports()
    where storage_path like 'a4444444-eeee-4444-8444-444444444444/%'),
  'retention still removes the expired export file'
);

-- A ready export with downloads left and time left is still returned.
update public.data_exports set status = 'failed' where id = (select id from fresh_request);
insert into public.data_exports(id, user_id, status, storage_path, byte_size, completed_at,
  expires_at, download_count) values
  ('b5555555-eeee-4555-8555-555555555555', 'a4444444-eeee-4444-8444-444444444444', 'ready',
   'a4444444-eeee-4444-8444-444444444444/b5555555-eeee-4555-8555-555555555555.tracendexport',
   100, now(), now() + interval '6 days', 3);
set local role authenticated;
select set_config('request.jwt.claims', json_build_object(
  'sub', 'a4444444-eeee-4444-8444-444444444444', 'role', 'authenticated',
  'iat', extract(epoch from now())::bigint,
  'amr', json_build_array(json_build_object('method', 'password',
    'timestamp', extract(epoch from now())::bigint))
)::text, true);
create temporary table after_downloads as select public.request_my_data_export() as id;
reset role;
select isnt(
  (select id from after_downloads), 'b5555555-eeee-4555-8555-555555555555'::uuid,
  'a ready export with all three downloads used is replaced'
);
select ok(
  has_function_privilege('authenticated', 'public.request_my_data_export()', 'execute')
  and not has_function_privilege('anon', 'public.request_my_data_export()', 'execute'),
  'only signed-in owners request exports'
);

-- Meal media ------------------------------------------------------------------------------

insert into public.media_objects(
  id, user_id, purpose, object_key, content_type, byte_size, checksum,
  retention_deadline, retention_exempt, lifecycle_status, retention_claimed_at
) values
  ('c1111111-eeee-4111-8111-111111111111', 'a1111111-eeee-4111-8111-111111111111',
   'meal_analysis', 'a1111111-eeee-4111-8111-111111111111/meal/stale.jpg', 'image/jpeg', 100,
   repeat('a', 64), now() - interval '2 days', false, 'pending_deletion',
   now() - interval '1 hour'),
  ('c2222222-eeee-4222-8222-222222222222', 'a1111111-eeee-4111-8111-111111111111',
   'meal_analysis', 'a1111111-eeee-4111-8111-111111111111/meal/fresh.jpg', 'image/jpeg', 100,
   repeat('b', 64), now() - interval '2 days', false, 'pending_deletion',
   now() - interval '2 minutes'),
  ('c3333333-eeee-4333-8333-333333333333', 'a1111111-eeee-4111-8111-111111111111',
   'meal_analysis', 'a1111111-eeee-4111-8111-111111111111/meal/legacy.jpg', 'image/jpeg', 100,
   repeat('c', 64), now() - interval '2 days', false, 'pending_deletion', null),
  ('c4444444-eeee-4444-8444-444444444444', 'a1111111-eeee-4111-8111-111111111111',
   'meal_analysis', 'a1111111-eeee-4111-8111-111111111111/meal/saved.jpg', 'image/jpeg', 100,
   repeat('d', 64), now() - interval '2 days', true, 'pending_deletion',
   now() - interval '1 hour'),
  ('c5555555-eeee-4555-8555-555555555555', 'a1111111-eeee-4111-8111-111111111111',
   'meal_analysis', 'a1111111-eeee-4111-8111-111111111111/meal/due.jpg', 'image/jpeg', 100,
   repeat('e', 64), now() - interval '1 day', false, 'active', null);

set local role service_role;
select set_config('request.jwt.claims', '{"role":"service_role"}', true);
create temporary table reclaimed as select * from public.claim_expired_meal_media(50);
reset role;

select is(
  (select array_agg(media_object_id order by media_object_id)
   from reclaimed),
  array['c1111111-eeee-4111-8111-111111111111', 'c3333333-eeee-4333-8333-333333333333',
    'c5555555-eeee-4555-8555-555555555555']::uuid[],
  'retention takes due media and claims that went stale (or predate the claim time), no others'
);
select ok(
  (select bool_and(lifecycle_status = 'pending_deletion'
      and retention_claimed_at > now() - interval '1 minute')
   from public.media_objects where id in (select media_object_id from reclaimed)),
  'a claim restarts its clock'
);
select ok(
  (select retention_claimed_at < now() - interval '1 minute' from public.media_objects
   where id = 'c4444444-eeee-4444-8444-444444444444'),
  'saved media (retention exempt) is never reclaimed'
);
select ok(
  not has_function_privilege('authenticated', 'public.claim_expired_meal_media(integer)', 'execute')
  and has_function_privilege('service_role', 'public.claim_expired_meal_media(integer)', 'execute'),
  'only the service role claims retention work'
);

-- Rows linked to the account without a user_id ---------------------------------------------

insert into private.signup_invites(email, note, claimed_by) values
  ('linked@example.com', 'private note about the invitee', 'a1111111-eeee-4111-8111-111111111111');
insert into private.waitlist_signups(email, unsub_token_hash, referral_code, consent_version)
values ('linked@example.com', repeat('a', 64), 'ABCDEFGH', 'v1');

select ok(
  has_function_privilege('service_role', 'public.export_linked_account_rows_v1(uuid,text)', 'execute')
  and not has_function_privilege('authenticated', 'public.export_linked_account_rows_v1(uuid,text)', 'execute')
  and not has_function_privilege('anon', 'public.export_linked_account_rows_v1(uuid,text)', 'execute'),
  'only the service role reads the linked rows'
);
create temporary table linked as
select public.export_linked_account_rows_v1(
  'a1111111-eeee-4111-8111-111111111111', ' Linked@Example.com ') as body;
select is((select body #>> '{signup_invites,0,email}' from linked), 'linked@example.com',
  'the invite the account claimed is exported');
select ok(
  (select not (body #> '{signup_invites,0}') ?| array['note', 'claimed_by'] from linked),
  'the owner''s private note about the invitee is not'
);
select is((select body #>> '{waitlist_signups,0,status}' from linked), 'pending',
  'the waitlist signup under the account email is exported');
select ok(
  (select not (body #> '{waitlist_signups,0}')
    ?| array['id', 'confirm_token_hash', 'unsub_token_hash', 'referred_by'] from linked),
  'without its token hashes, id or referral link'
);
select is(
  (select public.export_linked_account_rows_v1('a2222222-eeee-4222-8222-222222222222', null)
    -> 'waitlist_signups'),
  '[]'::jsonb, 'another account gets none of them'
);

-- The retention cron job ----------------------------------------------------------------------

select is((select count(*) from cron.job where jobname = 'meal-media-retention-daily'), 1::bigint,
  'one cron job runs the retention worker');
select is((select schedule from cron.job where jobname = 'meal-media-retention-daily'),
  '15 2 * * *', 'at 02:15 UTC');
select is((select command from cron.job where jobname = 'meal-media-retention-daily'),
  'select private.meal_media_retention_kick()', 'through the trigger function');
select throws_ok(
  $$select private.meal_media_retention_set_url('https://example.com/functions/v1/meal-media-retention')$$,
  '22023', null, 'the worker URL must be a project function URL'
);
select lives_ok(
  $$select private.meal_media_retention_set_url('https://abcdefghijklmnopqrst.supabase.co/functions/v1/meal-media-retention')$$,
  'a project function URL is stored'
);
select lives_ok(
  $$select private.meal_media_retention_set_url('https://tsrqponmlkjihgfedcba.supabase.co/functions/v1/meal-media-retention')$$,
  'and can be replaced'
);
select is(
  (select decrypted_secret from vault.decrypted_secrets where name = 'meal_media_retention_url'),
  'https://tsrqponmlkjihgfedcba.supabase.co/functions/v1/meal-media-retention',
  'kept once in Vault'
);
select lives_ok($$select private.meal_media_retention_kick()$$,
  'the trigger does nothing without the worker secret in Vault');
select ok(
  not has_function_privilege('service_role', 'private.meal_media_retention_kick()', 'execute')
  and not has_function_privilege('authenticated', 'private.meal_media_retention_kick()', 'execute'),
  'no API role calls the trigger function'
);

select * from finish();
rollback;
