create function public.prepare_coach_chat_v2(
  target_user_id uuid,target_thread_id uuid,question text,
  coaching_timezone text,request_idempotency_key uuid
) returns jsonb language plpgsql security definer set search_path='' as $$
declare prepared jsonb; context_payload jsonb; missing jsonb; permitted jsonb;
  other_thread_history jsonb; coaching_date date; has_recent_health boolean;
  has_today_check_in boolean;
begin
  prepared:=public.prepare_coach_chat(target_user_id,target_thread_id,question,
    coaching_timezone,request_idempotency_key);
  if coalesce((prepared->>'replayed')::boolean,false) then return prepared; end if;
  context_payload:=prepared->'context';
  coaching_date:=coalesce((context_payload->>'coaching_date')::date,current_date);
  select exists(select 1 from public.daily_health_summaries
    where user_id=target_user_id and local_date between coaching_date-2 and coaching_date),
    exists(select 1 from public.daily_check_ins where user_id=target_user_id
      and local_date=coaching_date and superseded_at is null)
  into has_recent_health,has_today_check_in;
  select coalesce(jsonb_agg(value),'[]'::jsonb) into missing
  from jsonb_array_elements_text(coalesce(context_payload->'missing_data','[]'::jsonb)) value
  where not (value='health_context' and has_recent_health)
    and not (value='recovery_check_in' and has_today_check_in);
  select coalesce(jsonb_agg(value),'[]'::jsonb) into permitted
  from jsonb_array_elements_text(coalesce(context_payload->'permitted_evidence','[]'::jsonb)) value
  where value<>'HEALTH_CONTEXT_AVAILABLE' or has_recent_health;
  if has_recent_health and not permitted @> '["HEALTH_CONTEXT_AVAILABLE"]'::jsonb then
    permitted:=permitted||'"HEALTH_CONTEXT_AVAILABLE"'::jsonb;
  end if;
  select coalesce(jsonb_agg(message order by created_at),'[]'::jsonb)
  into other_thread_history from (
    select jsonb_build_object('role',role,'content',content) message,created_at
    from public.coach_messages where user_id=target_user_id
      and thread_id<>target_thread_id order by created_at desc limit 20
  ) other_messages;
  context_payload:=context_payload||jsonb_build_object(
    'missing_data',missing,
    'permitted_evidence',permitted,
    'recent_other_conversations',other_thread_history,
    'context_coverage',jsonb_build_object(
      'approved_plan',context_payload->'active_plan'<>'null'::jsonb,
      'active_goal',context_payload->'active_goal'<>'null'::jsonb,
      'profile',context_payload->'profile_context'<>'null'::jsonb,
      'healthkit_recent',has_recent_health,
      'today_check_in',has_today_check_in,
      'confirmed_nutrition',jsonb_array_length(coalesce(context_payload->'confirmed_nutrition_history','[]'::jsonb))>0,
      'completed_workouts',jsonb_array_length(coalesce(context_payload->'recent_execution','[]'::jsonb))>0,
      'measurements',jsonb_array_length(coalesce(context_payload->'measurement_history','[]'::jsonb))>0,
      'conversation_messages',jsonb_array_length(coalesce(context_payload->'recent_messages','[]'::jsonb))));
  return prepared||jsonb_build_object('context',context_payload);
end $$;

create function public.get_my_coach_context_status()
returns jsonb language sql security definer set search_path='' stable as $$
select jsonb_build_object('sources',jsonb_build_array(
  jsonb_build_object('key','approved_plan','label','Approved training plan',
    'available',exists(select 1 from public.training_plan_versions where user_id=auth.uid() and status='active')),
  jsonb_build_object('key','goal_profile','label','Goal and profile schedule',
    'available',exists(select 1 from public.user_goals where user_id=auth.uid() and status='active')
      and exists(select 1 from public.user_profiles where user_id=auth.uid())),
  jsonb_build_object('key','healthkit','label','Apple Health summaries',
    'available',exists(select 1 from public.daily_health_summaries where user_id=auth.uid()),
    'records',(select count(*) from public.daily_health_summaries where user_id=auth.uid()),
    'latest_date',(select max(local_date) from public.daily_health_summaries where user_id=auth.uid())),
  jsonb_build_object('key','check_in','label','Recovery check-ins',
    'available',exists(select 1 from public.daily_check_ins where user_id=auth.uid() and superseded_at is null),
    'records',(select count(*) from public.daily_check_ins where user_id=auth.uid() and superseded_at is null),
    'latest_date',(select max(local_date) from public.daily_check_ins where user_id=auth.uid() and superseded_at is null)),
  jsonb_build_object('key','nutrition','label','Confirmed nutrition',
    'available',exists(select 1 from public.meals where user_id=auth.uid() and status='confirmed'),
    'records',(select count(*) from public.meals where user_id=auth.uid() and status='confirmed'),
    'latest_date',(select max(local_date) from public.meals where user_id=auth.uid() and status='confirmed')),
  jsonb_build_object('key','workouts','label','Completed Tracend workouts',
    'available',exists(select 1 from public.workout_sessions where user_id=auth.uid() and state='completed'),
    'records',(select count(*) from public.workout_sessions where user_id=auth.uid() and state='completed'),
    'latest_date',(select max(local_date) from public.workout_sessions where user_id=auth.uid() and state='completed')),
  jsonb_build_object('key','measurements','label','Body measurements',
    'available',exists(select 1 from public.body_measurements where user_id=auth.uid()),
    'records',(select count(*) from public.body_measurements where user_id=auth.uid()),
    'latest_date',(select max(measured_on) from public.body_measurements where user_id=auth.uid())),
  jsonb_build_object('key','conversation','label','Saved Coach conversation history',
    'available',exists(select 1 from public.coach_messages where user_id=auth.uid()),
    'records',(select count(*) from public.coach_messages where user_id=auth.uid()))));
$$;

revoke all on function public.prepare_coach_chat_v2(uuid,uuid,text,text,uuid)
from public,anon,authenticated;
grant execute on function public.prepare_coach_chat_v2(uuid,uuid,text,text,uuid)
to service_role;
revoke all on function public.get_my_coach_context_status()
from public,anon,authenticated;
grant execute on function public.get_my_coach_context_status()
to authenticated;
