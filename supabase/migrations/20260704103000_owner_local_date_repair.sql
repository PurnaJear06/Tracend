do $$
declare function_definition text;
begin
  select pg_get_functiondef(
    'public.import_confirmed_continuation(uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])'::regprocedure
  ) into function_definition;
  if position(
    '(exercise_payload->>''measured_on'')::date > current_date'
    in function_definition
  ) = 0 then
    raise exception 'expected measurement-date validation not found';
  end if;
  function_definition := replace(
    function_definition,
    '(exercise_payload->>''measured_on'')::date > current_date',
    '(exercise_payload->>''measured_on'')::date > current_date + 1'
  );
  execute function_definition;
end $$;

revoke all on function public.import_confirmed_continuation(
  uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])
from public,anon,authenticated;
grant execute on function public.import_confirmed_continuation(
  uuid,jsonb,jsonb,jsonb,jsonb,jsonb,uuid[])
to service_role;
