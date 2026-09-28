-- A2: Coach lists only conversations that contain a message.
--
-- Earlier app builds created a thread whenever Coach opened with no threads
-- or the user tapped New, so accounts hold empty "New conversation" threads.
-- `last_message_at` defaults to now(), so an empty thread also won the
-- launch-time pick of the newest conversation. From A2 the app creates a
-- thread on its first send and reads the list from here. Empty threads stay
-- stored (deleting the thread or the account removes them) but are not listed.
-- Additive: the installed app does not call this function.

create or replace function public.get_my_coach_threads()
returns jsonb language sql security definer set search_path = '' stable as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'threads', coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'last_message_at', t.last_message_at,
        'updated_at', t.updated_at)
      order by t.last_message_at desc, t.id), '[]'::jsonb))
  from public.coach_threads t
  where t.user_id = auth.uid()
    and t.status = 'active'
    and exists(select 1 from public.coach_messages m
      where m.thread_id = t.id and m.user_id = t.user_id);
$$;

revoke all on function public.get_my_coach_threads() from public, anon, authenticated;
grant execute on function public.get_my_coach_threads() to authenticated;
