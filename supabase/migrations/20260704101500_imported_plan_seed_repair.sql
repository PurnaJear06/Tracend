create or replace function private.seed_active_plan_workouts_trigger()
returns trigger language plpgsql security definer set search_path='' as $$
begin
  if new.status='active' and not exists(
    select 1 from public.training_plans
    where id=new.plan_id and user_id=new.user_id and source='imported'
  ) then
    perform private.seed_workouts_for_plan_version(new.id,new.user_id);
  end if;
  return new;
end $$;

revoke all on function private.seed_active_plan_workouts_trigger()
from public,anon,authenticated;
