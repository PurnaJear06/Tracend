begin;
select plan(30);

insert into auth.users(id,role) values
 ('11111111-cccc-4111-8111-111111111111','authenticated'),
 ('22222222-cccc-4222-8222-222222222222','authenticated');

select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class where oid=any(array[
 'public.body_measurements'::regclass,'public.progress_photo_sets'::regclass,
 'public.progress_photos'::regclass,'public.progress_reviews'::regclass])),
 'progress tables enable and force RLS');
select ok(not has_table_privilege('authenticated','public.body_measurements','insert'),
 'mobile cannot directly insert measurements');
select ok(has_function_privilege('authenticated','public.save_body_measurement(date,numeric,numeric,numeric,numeric,numeric,numeric)','execute'),
 'authenticated owner can save a measurement through the validated RPC');
select ok(has_function_privilege('authenticated','public.begin_progress_photo_set(date,text)','execute'),'owner can begin a consented photo set');
select ok(has_function_privilege('authenticated','public.register_progress_photo(uuid,text,text,text,integer,text)','execute'),'owner can register uploaded photo metadata');
select ok(has_function_privilege('authenticated','public.delete_my_progress_photo_set(uuid)','execute'),'owner can delete a photo set');
select is((select public from storage.buckets where id='progress-photos'),false,
 'progress bucket is private');
select is((select count(*) from pg_policies where schemaname='storage' and tablename='objects'
 and policyname in ('progress_photos_insert_own','progress_photos_read_own','progress_photos_delete_own')),3::bigint,
 'progress storage has scoped insert read and delete policies');
select ok('progress_photo_storage'::text=any(enum_range(null::public.consent_type)::text[]),
 'progress photo storage consent is separate');
select ok('progress_photo_ai'::text=any(enum_range(null::public.consent_type)::text[]),
 'progress photo AI consent is separate');

set local role authenticated;
set local "request.jwt.claim.sub"='11111111-cccc-4111-8111-111111111111';
select throws_ok($$select public.begin_progress_photo_set('2026-07-02','morning')$$,'42501','progress photo storage consent required','photo storage requires separate consent');
insert into public.consent_records(user_id,consent_type,notice_version,action,source) values
 ('11111111-cccc-4111-8111-111111111111','progress_photo_storage','progress-storage-v1','granted','ios_app');
create temporary table photo_set_result as select public.begin_progress_photo_set('2026-07-02','morning') id;
select is((select count(*) from public.progress_photo_sets),1::bigint,'consented owner creates a private draft set');
select throws_ok(format($$select public.register_progress_photo(%L,'front',%L,'image/jpeg',100,%L)$$,
 (select id from photo_set_result),'11111111-cccc-4111-8111-111111111111/progress/'||(select id from photo_set_result)||'/front.jpg',repeat('a',64)),
 'P0002','uploaded object not found','metadata cannot register before private upload exists');
select ok(public.delete_my_progress_photo_set((select id from photo_set_result)),'owner can delete an empty draft set');
select ok(public.delete_my_progress_photo_set((select id from photo_set_result)),'photo-set deletion is idempotent');
select lives_ok($$select public.save_body_measurement('2026-06-25',80.0,90.0,null,null,null,null)$$,
 'owner can record the first confirmed measurement');
select lives_ok($$select public.save_body_measurement('2026-06-25',79.8,89.8,null,null,null,null)$$,
 'owner can record a same-day correction candidate');
select is((public.get_my_progress_summary()->>'observation_count')::integer,1,
 'same-day entries remain one observation day and do not unlock a trend');
select lives_ok($$select public.save_body_measurement('2026-07-02',79.0,89.0,null,null,null,null)$$,
 'owner can record a second confirmed measurement');
select is((public.get_my_progress_summary()->>'observation_count')::integer,2,
 'summary counts confirmed observations deterministically');
select is((public.get_my_progress_summary()->>'weight_change_kg')::numeric,-0.8::numeric,
 'weight delta uses the latest audited same-day correction');
select is((public.get_my_progress_summary()->>'waist_change_cm')::numeric,-0.8::numeric,
 'waist delta uses the latest audited same-day correction');
select is(public.get_my_progress_summary()->>'trend_status','available',
 'two observations make a deterministic trend available');
select is((select count(*) from public.audit_events where action_code in ('progress.measurement.recorded','progress.measurement.corrected')),3::bigint,
 'measurement records and corrections emit sanitized audit events');
select throws_ok($$select public.save_body_measurement('2026-07-02',10,null,null,null,null,null)$$,
 '23514',null,'invalid measurement range is rejected');

reset role;
insert into public.progress_photo_sets(user_id,captured_on,capture_protocol_version,timing_context)
values('11111111-cccc-4111-8111-111111111111','2026-07-01','standard-v1','morning before training');
set local role authenticated;
set local "request.jwt.claim.sub"='22222222-cccc-4222-8222-222222222222';
select is((select count(*) from public.body_measurements),0::bigint,'cross-user measurement reads are denied');
select is((select count(*) from public.progress_photo_sets),0::bigint,'cross-user photo-set reads are denied');
select is((public.get_my_progress_summary()->>'observation_count')::integer,0,
 'cross-user summary is empty');
select is(public.get_my_progress_summary()->>'trend_status','not_enough_data',
 'empty owner summary reports insufficient evidence');

reset role;
select is((select count(*) from public.progress_photo_sets where processing_consent),0::bigint,
 'photo processing consent defaults off');

select * from finish();
rollback;
