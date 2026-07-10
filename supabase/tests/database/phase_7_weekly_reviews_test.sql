begin;
select plan(29);

insert into auth.users(id, role) values
  ('11111111-dddd-4111-8111-111111111111', 'authenticated'),
  ('22222222-dddd-4222-8222-222222222222', 'authenticated');
update public.user_accounts
set onboarding_state = 'completed', timezone = 'UTC'
where id in (
  '11111111-dddd-4111-8111-111111111111',
  '22222222-dddd-4222-8222-222222222222'
);

insert into public.training_plans(id, user_id, title, source) values (
  'aaaaaaaa-dddd-4111-8111-111111111111',
  '11111111-dddd-4111-8111-111111111111',
  'Weekly review test plan', 'user'
);
insert into public.training_plan_versions(
  id, user_id, plan_id, version_number, status, block_weeks,
  sessions_per_week, prescription, rationale, approved_at, effective_date
) values (
  'bbbbbbbb-dddd-4111-8111-111111111111',
  '11111111-dddd-4111-8111-111111111111',
  'aaaaaaaa-dddd-4111-8111-111111111111', 1, 'active', 6, 3,
  '{}'::jsonb, 'Test-only approved plan.', now(), current_date - 14
);

select ok(
  (select relrowsecurity and relforcerowsecurity from pg_class
   where oid = 'public.weekly_review_jobs'::regclass),
  'weekly review jobs enable and force RLS'
);
select ok(
  has_function_privilege(
    'authenticated', 'public.request_my_weekly_review(date)', 'execute'
  ), 'authenticated users can request an owned weekly review'
);
select ok(
  not has_function_privilege(
    'authenticated', 'public.process_weekly_progress_reviews(integer)', 'execute'
  ), 'mobile cannot run the queue worker'
);
select ok(
  has_function_privilege(
    'service_role', 'public.process_weekly_progress_reviews(integer)', 'execute'
  ), 'service role can run the queue worker'
);
select ok(
  not has_table_privilege(
    'authenticated', 'public.weekly_review_jobs', 'insert'
  ), 'mobile cannot insert queue jobs directly'
);
select is(
  (select count(*) from cron.job where jobname in (
    'tracend-schedule-weekly-progress-reviews',
    'tracend-process-weekly-progress-reviews'
  )), 2::bigint, 'scheduler and worker Cron jobs exist'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-dddd-4111-8111-111111111111';
create temporary table requested_job as
select public.request_my_weekly_review(
  current_date - (extract(isodow from current_date)::integer - 1)
) id;
select is(
  (select status::text from public.weekly_review_jobs
   where id = (select id from requested_job)),
  'queued', 'owned request creates a queued job'
);
select is(
  public.request_my_weekly_review(
    current_date - (extract(isodow from current_date)::integer - 1)
  ), (select id from requested_job),
  'repeat request is idempotent'
);
select is(
  (select count(*) from public.weekly_review_jobs),
  1::bigint, 'owner sees one deduplicated job'
);
select throws_ok(
  $$select public.request_my_weekly_review(current_date - 1)$$,
  '22023', 'invalid review week', 'non-Monday review is rejected'
);

set local "request.jwt.claim.sub" = '22222222-dddd-4222-8222-222222222222';
select is(
  (select count(*) from public.weekly_review_jobs),
  0::bigint, 'cross-user queue jobs are hidden by RLS'
);
select is(
  (select count(*) from public.progress_reviews),
  0::bigint, 'cross-user reviews are hidden before processing'
);

reset role;
select is(
  (select count(*) from pgmq.q_weekly_reviews
   where message ?& array['schema_version', 'job_id']
     and (select count(*) from jsonb_object_keys(message)) = 2),
  1::bigint, 'queue payload contains only schema version and opaque job ID'
);

set local role service_role;
select is(
  (public.process_weekly_progress_reviews(10)->>'completed')::integer,
  1, 'worker consumes and completes the queued review'
);
reset role;
select is(
  (select status::text from public.weekly_review_jobs
   where id = (select id from requested_job)),
  'completed', 'job reaches completed state'
);
select is(
  (select count(*) from public.progress_reviews
   where user_id = '11111111-dddd-4111-8111-111111111111'),
  1::bigint, 'worker persists one owner review'
);
select is(
  (select trigger_kind from public.feature_snapshots
   where id = (select feature_snapshot_id from public.progress_reviews
     where user_id = '11111111-dddd-4111-8111-111111111111')),
  'weekly', 'review references an immutable weekly feature snapshot'
);
select is(
  (select (summary->'training'->>'planned_sessions')::integer
   from public.progress_reviews
   where user_id = '11111111-dddd-4111-8111-111111111111'),
  3, 'training expectation is calculated deterministically'
);
select is(
  (select jsonb_array_length(summary->'proposal_ids')
   from public.progress_reviews
   where user_id = '11111111-dddd-4111-8111-111111111111'),
  0, 'weekly review cannot create a persistent change proposal'
);
select is(
  (select count(*) from public.audit_events
   where action_code = 'progress.weekly_review.created'),
  1::bigint, 'successful review emits a sanitized audit event'
);

set local role authenticated;
set local "request.jwt.claim.sub" = '11111111-dddd-4111-8111-111111111111';
select ok(
  public.acknowledge_my_progress_review(
    (select id from public.progress_reviews limit 1)
  ), 'owner can acknowledge the review'
);
select ok(
  (select acknowledged_at is not null from public.progress_reviews limit 1),
  'acknowledgement is persisted'
);

set local "request.jwt.claim.sub" = '22222222-dddd-4222-8222-222222222222';
select ok(
  not public.acknowledge_my_progress_review(
    (select id from public.progress_reviews
     where user_id = '11111111-dddd-4111-8111-111111111111')
  ), 'cross-user acknowledgement is denied'
);

create temporary table cancelled_job as
select public.request_my_weekly_review(
  current_date - (extract(isodow from current_date)::integer - 1)
) id;
reset role;
update public.user_accounts set account_status = 'deletion_pending'
where id = '22222222-dddd-4222-8222-222222222222';
set local role service_role;
select lives_ok(
  $$select public.process_weekly_progress_reviews(10)$$,
  'worker safely rechecks account eligibility'
);
reset role;
select is(
  (select status::text from public.weekly_review_jobs
   where id = (select id from cancelled_job)),
  'cancelled', 'ineligible account job is cancelled before generation'
);

update public.weekly_review_jobs
set status = 'processing', attempts = 0, completed_at = null
where id = (select id from cancelled_job);
select is(
  private.record_weekly_review_failure(
    (select id from cancelled_job), 'synthetic_failure'
  )::text, 'retryable', 'first failed attempt returns to the durable queue'
);
select is(
  (select attempts from public.weekly_review_jobs
   where id = (select id from cancelled_job)),
  1::smallint, 'retry count is persisted outside the failed generation'
);
update public.weekly_review_jobs
set status = 'processing', attempts = 2
where id = (select id from cancelled_job);
select is(
  private.record_weekly_review_failure(
    (select id from cancelled_job), 'synthetic_failure'
  )::text, 'failed', 'third failed attempt becomes terminal'
);
select is(
  (select status::text from public.weekly_review_jobs
   where id = (select id from cancelled_job)),
  'failed', 'terminal failure state is persisted'
);

select * from finish();
rollback;
