-- Server enforcement of AI coaching consent. The app already asks and gates
-- its own calls; this makes coach-chat and coach-decide honour the answer for
-- every caller, including app builds from before the consent screen.
--
-- The current choice is the newest ai_coaching record. Only a grant of the
-- current notice version counts, matching aiCoachingNoticeVersion in the app
-- (lib/features/consent/ai_coaching_consent.dart); change both together.
create function public.has_ai_coaching_consent(target_user_id uuid)
returns boolean language sql stable security definer set search_path='' as $$
  select coalesce((
    select record.action = 'granted' and record.notice_version = 'ai-coaching-v1'
    from public.consent_records record
    where record.user_id = target_user_id and record.consent_type = 'ai_coaching'
    order by record.created_at desc, record.id desc
    limit 1
  ), false);
$$;

revoke all on function public.has_ai_coaching_consent(uuid) from public, anon, authenticated;
grant execute on function public.has_ai_coaching_consent(uuid) to service_role;
