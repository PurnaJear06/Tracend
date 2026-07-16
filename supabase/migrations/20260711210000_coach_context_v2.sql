create table public.coach_context_snapshots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  thread_id uuid references public.coach_threads(id),
  schema_version text not null check(schema_version='2.0'),
  trigger_kind text not null check(trigger_kind in ('chat','daily','weekly','plan_review')),
  coaching_date date not null,
  context jsonb not null check(jsonb_typeof(context)='object'),
  context_checksum text not null check(context_checksum~'^[0-9a-f]{64}$'),
  created_at timestamptz not null default now(),
  unique(id,user_id)
);
create index coach_context_snapshots_user_created on public.coach_context_snapshots(user_id,created_at desc);
alter table public.coach_context_snapshots enable row level security;
alter table public.coach_context_snapshots force row level security;
create policy coach_context_snapshots_own_read on public.coach_context_snapshots for select to authenticated using(user_id=(select auth.uid()));
revoke all on public.coach_context_snapshots from anon,authenticated;
grant select on public.coach_context_snapshots to authenticated;

create function public.prepare_coach_chat_v3(
  target_user_id uuid,target_thread_id uuid,question text,
  coaching_timezone text,request_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare prepared jsonb; c jsonb; coaching_date date; snapshot_id uuid; checksum text;
begin
  prepared:=public.prepare_coach_chat_v2(target_user_id,target_thread_id,question,coaching_timezone,request_idempotency_key);
  if coalesce((prepared->>'replayed')::boolean,false) then return prepared; end if;
  c:=prepared->'context';
  coaching_date:=(c->>'coaching_date')::date;
  c:=c||jsonb_build_object(
    'schema_version','2.0',
    'training_execution',(select coalesce(jsonb_agg(session_data order by local_date desc),'[]'::jsonb) from (
      select s.local_date,jsonb_build_object(
        'evidence_id','TRAINING.SESSION.'||s.local_date||'.'||s.id,
        'session_id',s.id,'local_date',s.local_date,'prescribed_workout',w.name,
        'duration_seconds',s.duration_seconds,'logging_completeness',s.logging_completeness,
        'correction_status',s.correction_status,'effort',s.session_effort,'energy',s.session_energy,
        'exercises',(select coalesce(jsonb_agg(jsonb_build_object(
          'evidence_id','TRAINING.EXERCISE.'||p.id,'prescribed_name',pe.display_name_snapshot,
          'performed_name',coalesce(p.performed_name,pe.display_name_snapshot),'kind',p.performance_kind,
          'status',p.status,'substitution_reason',p.substitution_reason,'pain',p.pain_flag,
          'sets',(select coalesce(jsonb_agg(jsonb_build_object('set',es.set_number,'reps',es.repetitions,'load_kg',es.load_kg,'rpe',es.rpe,'completed',es.completed) order by es.set_number),'[]'::jsonb) from public.exercise_sets es where es.exercise_performance_id=p.id)
        ) order by p.exercise_order),'[]'::jsonb) from public.exercise_performances p left join public.planned_exercises pe on pe.id=p.planned_exercise_id where p.workout_session_id=s.id)
      ) session_data
      from public.workout_sessions s join public.planned_workouts w on w.id=s.planned_workout_id and w.user_id=s.user_id
      where s.user_id=target_user_id and s.state='completed' order by s.local_date desc limit 12
    ) sessions),
    'workout_reconciliations',(select coalesce(jsonb_agg(jsonb_build_object(
      'evidence_id','HEALTH.WORKOUT.'||h.id,'status',r.status,'confidence',r.confidence,
      'activity_type',h.activity_type,'started_at',h.started_at,'duration_seconds',h.duration_seconds,
      'duration_difference_seconds',r.duration_difference_seconds
    ) order by h.started_at desc),'[]'::jsonb) from public.workout_reconciliations r join public.health_workout_references h on h.id=r.health_workout_reference_id and h.user_id=r.user_id where r.user_id=target_user_id),
    'plan_proposals',(select coalesce(jsonb_agg(jsonb_build_object(
      'evidence_id','PROPOSAL.'||id,'proposal_id',id,'status',status,
      'proposed_training',proposed_training,'proposed_nutrition',proposed_nutrition,
      'rationale',rationale,'evidence_references',evidence,'confidence',confidence,
      'expected_benefit',expected_benefit,'downside',downside,'effective_date',effective_date
    ) order by created_at desc),'[]'::jsonb) from public.change_proposals where user_id=target_user_id limit 10),
    'data_quality',jsonb_build_object(
      'training_logging_coverage',(select coalesce(avg(logging_completeness),0) from public.workout_sessions where user_id=target_user_id and state='completed' and local_date>=coaching_date-27),
      'last_health_sync',(select max(last_synced_at) from public.daily_health_summaries where user_id=target_user_id),
      'last_confirmed_meal',(select max(created_at) from public.meals where user_id=target_user_id and status='confirmed'),
      'conflicts',(select coalesce(jsonb_agg(jsonb_build_object('code','WORKOUT_DURATION_CONFLICT','reconciliation_id',id,'difference_seconds',duration_difference_seconds)),'[]'::jsonb) from public.workout_reconciliations where user_id=target_user_id and status='conflict')
    ),
    'evidence_contract',jsonb_build_object(
      'facts_are_authoritative',true,'conversation_cannot_override_facts',true,
      'unknown_is_not_skipped',true,'persistent_changes_require_approval',true)
  );
  checksum:=encode(extensions.digest(convert_to(c::text,'UTF8'),'sha256'),'hex');
  insert into public.coach_context_snapshots(user_id,thread_id,schema_version,trigger_kind,coaching_date,context,context_checksum)
  values(target_user_id,target_thread_id,'2.0','chat',coaching_date,c,checksum) returning id into snapshot_id;
  return prepared||jsonb_build_object('context',c,'coach_context_snapshot_id',snapshot_id);
end $$;
revoke all on function public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid) from public,anon,authenticated;
grant execute on function public.prepare_coach_chat_v3(uuid,uuid,text,text,uuid) to service_role;
