begin;
select plan(4);

insert into auth.users(id, role) values
  ('87777777-eeee-4777-8777-777777777777', 'authenticated'),
  ('88888888-eeee-4888-8888-888888888888', 'authenticated');

insert into public.deletion_requests(id, user_id, status, started_at) values
  ('97777777-eeee-4777-8777-777777777777',
   '87777777-eeee-4777-8777-777777777777', 'processing', now() - interval '2 minutes'),
  ('98888888-eeee-4888-8888-888888888888',
   '88888888-eeee-4888-8888-888888888888', 'processing', now() - interval '11 minutes');

select is(
  public.claim_account_deletion('97777777-eeee-4777-8777-777777777777'),
  null::uuid,
  'a deletion still running cannot be claimed twice'
);
select is(
  public.claim_account_deletion('98888888-eeee-4888-8888-888888888888'),
  '88888888-eeee-4888-8888-888888888888'::uuid,
  'a deletion whose worker stopped can be claimed again'
);
select ok(
  (select started_at > now() - interval '1 minute' from public.deletion_requests
   where id = '98888888-eeee-4888-8888-888888888888'),
  'the new claim restarts the clock'
);
select ok(not has_function_privilege('authenticated',
  'public.claim_account_deletion(uuid)', 'execute'),
  'client still cannot claim deletion work');

select * from finish();
rollback;
