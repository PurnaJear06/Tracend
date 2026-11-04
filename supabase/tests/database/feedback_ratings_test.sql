begin;
select plan(29);

-- One-tap ratings on the daily decision and on Coach replies (migration 20261102223417): the table is
-- read-only for the athlete, the RPC rates only the caller's own decision or reply, a second rating of
-- the same subject replaces the first, and deleting the account deletes the ratings.

insert into auth.users(id, role) values
  ('fb000000-0000-4000-8000-000000000001', 'authenticated'),
  ('fb000000-0000-4000-8000-000000000002', 'authenticated');

insert into public.coach_threads(id, user_id, title) values
  ('fb100000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000001', 'Mine'),
  ('fb100000-0000-4000-8000-000000000002', 'fb000000-0000-4000-8000-000000000002', 'Theirs');
insert into public.coach_messages(id, user_id, thread_id, role, content) values
  ('fb200000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000001',
   'fb100000-0000-4000-8000-000000000001', 'user', 'A question'),
  ('fb200000-0000-4000-8000-000000000002', 'fb000000-0000-4000-8000-000000000001',
   'fb100000-0000-4000-8000-000000000001', 'assistant', 'An answer'),
  ('fb200000-0000-4000-8000-000000000003', 'fb000000-0000-4000-8000-000000000002',
   'fb100000-0000-4000-8000-000000000002', 'assistant', 'Their answer');

-- A decision's snapshot, policy and run rows are not the subject of this test.
set local session_replication_role = replica;
insert into public.coach_decisions(id, user_id, feature_snapshot_id, policy_evaluation_id, model_run_id,
  decision_kind, local_date, schema_version, training, nutrition, head_coach, evidence, confidence,
  valid_until) values
  ('fb300000-0000-4000-8000-000000000001', 'fb000000-0000-4000-8000-000000000001', gen_random_uuid(),
   gen_random_uuid(), gen_random_uuid(), 'daily', current_date, '1.0',
   '{"action":"MAINTAIN","summary":"Train as planned"}', '{"action":"MAINTAIN_TARGETS"}',
   '{"final_decision":"Train as planned.","reason":"Recovery is steady"}', '[]', 'high',
   now() + interval '24 hours'),
  ('fb300000-0000-4000-8000-000000000002', 'fb000000-0000-4000-8000-000000000002', gen_random_uuid(),
   gen_random_uuid(), gen_random_uuid(), 'daily', current_date, '1.0',
   '{"action":"MAINTAIN","summary":"Train as planned"}', '{"action":"MAINTAIN_TARGETS"}',
   '{"final_decision":"Train as planned.","reason":"Recovery is steady"}', '[]', 'high',
   now() + interval '24 hours');
set local session_replication_role = origin;

create function pg_temp.as_user(p_uid text) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claim.sub', p_uid, true);
end $$;

-- Shape and privileges ----------------------------------------------------------------------------------

select has_table('public', 'feedback_ratings', 'the ratings table exists');
select ok((select relrowsecurity and relforcerowsecurity from pg_class
    where oid = 'public.feedback_ratings'::regclass), 'row-level security is on and forced');
select ok(has_table_privilege('authenticated', 'public.feedback_ratings', 'select')
  and not has_table_privilege('authenticated', 'public.feedback_ratings', 'insert')
  and not has_table_privilege('authenticated', 'public.feedback_ratings', 'update')
  and not has_table_privilege('authenticated', 'public.feedback_ratings', 'delete')
  and not has_table_privilege('anon', 'public.feedback_ratings', 'select'),
  'athletes read their ratings and cannot write them; signed-out callers read nothing');
select ok(has_function_privilege('authenticated',
    'public.submit_feedback_rating_v1(text, uuid, text)', 'execute')
  and not has_function_privilege('anon', 'public.submit_feedback_rating_v1(text, uuid, text)', 'execute'),
  'athletes can rate; signed-out callers cannot');
select ok((select prosecdef and proconfig = array['search_path=""'] from pg_proc
    where oid = 'public.submit_feedback_rating_v1(text, uuid, text)'::regprocedure),
  'the writer is security definer with an empty search path');

-- The table's own constraints ---------------------------------------------------------------------------
select throws_ok($$insert into public.feedback_ratings(user_id, subject_type, subject_id, rating)
  values ('fb000000-0000-4000-8000-000000000001', 'meal', gen_random_uuid(), 'useful')$$,
  '23514', null, 'a subject type outside the list is refused');
select throws_ok($$insert into public.feedback_ratings(user_id, subject_type, subject_id, rating)
  values ('fb000000-0000-4000-8000-000000000001', 'coach_reply', gen_random_uuid(), 'five stars')$$,
  '23514', null, 'a rating outside the list is refused');

-- Rating as the athlete ---------------------------------------------------------------------------------
select pg_temp.as_user('fb000000-0000-4000-8000-000000000001');

select is(public.submit_feedback_rating_v1('daily_decision', 'fb300000-0000-4000-8000-000000000001', 'useful'),
  jsonb_build_object('schema_version', '1.0', 'subject_type', 'daily_decision',
    'subject_id', 'fb300000-0000-4000-8000-000000000001', 'rating', 'useful'),
  'rating a decision answers with the schema version and what was stored');
select is((select rating from public.feedback_ratings
    where subject_id = 'fb300000-0000-4000-8000-000000000001'), 'useful', 'and stores it');
select is((select array_agg(k order by k) from jsonb_object_keys(
    public.submit_feedback_rating_v1('daily_decision', 'fb300000-0000-4000-8000-000000000001',
      'useful')) k),
  array['rating', 'schema_version', 'subject_id', 'subject_type'],
  'the answer carries exactly the contract keys (test/contract/fixtures/feedback_rating_v1_0.json)');
select lives_ok($$select public.submit_feedback_rating_v1('daily_decision',
  'fb300000-0000-4000-8000-000000000001', 'unclear')$$, 'rating it again is allowed');
select is((select count(*) from public.feedback_ratings
    where subject_id = 'fb300000-0000-4000-8000-000000000001'), 1::bigint,
  'and keeps one rating per athlete and subject');
select is((select rating from public.feedback_ratings
    where subject_id = 'fb300000-0000-4000-8000-000000000001'), 'unclear',
  'the second rating replaces the first');
select lives_ok($$select public.submit_feedback_rating_v1('coach_reply',
  'fb200000-0000-4000-8000-000000000002', 'unsafe')$$, 'a Coach reply can be rated');
select is((select rating from public.feedback_ratings
    where subject_type = 'coach_reply'), 'unsafe', 'and is stored under its own type');
select lives_ok($$select public.submit_feedback_rating_v1('coach_reply',
  'fb200000-0000-4000-8000-000000000002', 'incorrect')$$, 'incorrect is a rating');

-- What cannot be rated ----------------------------------------------------------------------------------
select throws_ok($$select public.submit_feedback_rating_v1('daily_decision',
  'fb300000-0000-4000-8000-000000000002', 'useful')$$,
  '22023', 'that is not yours to rate', 'another athlete''s decision is refused');
select throws_ok($$select public.submit_feedback_rating_v1('coach_reply',
  'fb200000-0000-4000-8000-000000000003', 'useful')$$,
  '22023', 'that is not yours to rate', 'so is another athlete''s reply');
select throws_ok($$select public.submit_feedback_rating_v1('coach_reply',
  'fb200000-0000-4000-8000-000000000001', 'useful')$$,
  '22023', 'that is not yours to rate', 'and so is the athlete''s own question, which is not a reply');
select throws_ok($$select public.submit_feedback_rating_v1('coach_reply',
  'fb300000-0000-4000-8000-000000000001', 'useful')$$,
  '22023', 'that is not yours to rate', 'a decision is not a reply');
select throws_ok($$select public.submit_feedback_rating_v1('coach_reply', gen_random_uuid(), 'useful')$$,
  '22023', 'that is not yours to rate', 'a subject that does not exist is refused');
select throws_ok($$select public.submit_feedback_rating_v1('daily_decision',
  'fb300000-0000-4000-8000-000000000001', 'great')$$,
  '22023', 'unknown rating', 'a rating outside the list is refused');
select throws_ok($$select public.submit_feedback_rating_v1('meal',
  'fb300000-0000-4000-8000-000000000001', 'useful')$$,
  '22023', 'unknown subject type', 'a subject type outside the list is refused');
select throws_ok($$select public.submit_feedback_rating_v1('coach_reply', null, 'useful')$$,
  '22023', null, 'a missing subject is refused');
select pg_temp.as_user('');
select throws_ok($$select public.submit_feedback_rating_v1('daily_decision',
  'fb300000-0000-4000-8000-000000000001', 'useful')$$,
  '42501', 'authentication required', 'a signed-out caller is refused');

-- Reading -------------------------------------------------------------------------------------------------
select pg_temp.as_user('fb000000-0000-4000-8000-000000000002');
set local role authenticated;
select is((select count(*) from public.feedback_ratings), 0::bigint,
  'another athlete sees none of these ratings');
reset role;
select pg_temp.as_user('fb000000-0000-4000-8000-000000000001');
set local role authenticated;
select is((select count(*) from public.feedback_ratings), 2::bigint, 'the athlete sees their own two');
reset role;

-- Deleting the account -----------------------------------------------------------------------------------
select lives_ok($$delete from auth.users where id = 'fb000000-0000-4000-8000-000000000001'$$,
  'the account can be deleted');
select is((select count(*) from public.feedback_ratings), 0::bigint,
  'and its ratings go with it');

select * from finish();
rollback;
