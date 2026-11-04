-- One-tap feedback ratings on the daily decision and on Coach replies (PRD section 5.6).
--
-- A tester rates what Coach said as useful, unclear, incorrect or unsafe. The beta gate in PRD
-- section 8 (at least 80% of rated daily decisions marked useful, and every one marked unsafe
-- reviewed) can only be measured when those answers are stored, so each athlete keeps one rating
-- per decision or reply; rating it again replaces the first answer. A rating carries no health
-- value and no text, only which thing was rated and how.
--
--   1. public.feedback_ratings            the ratings, read-only for the athlete
--   2. public.submit_feedback_rating_v1   the one writer: checks the thing rated is the caller's own
--
-- Everything is additive: a new table and a new function. Old app builds never call either.

create table public.feedback_ratings (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts (id) on delete cascade,
  subject_type text not null check (subject_type in ('daily_decision', 'coach_reply')),
  subject_id uuid not null,
  rating text not null check (rating in ('useful', 'unclear', 'incorrect', 'unsafe')),
  created_at timestamptz not null default now(),
  constraint feedback_ratings_one_per_subject unique (user_id, subject_type, subject_id)
);

comment on table public.feedback_ratings is
  'The athlete''s one-tap rating of a daily decision (coach_decisions.id) or a Coach reply (coach_messages.id). One row per athlete and subject; created_at is when the current rating was given. Written only by submit_feedback_rating_v1.';

alter table public.feedback_ratings enable row level security;
alter table public.feedback_ratings force row level security;
create policy feedback_ratings_own_read on public.feedback_ratings
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.feedback_ratings from anon, authenticated;
grant select on public.feedback_ratings to authenticated;

-- Rates a daily decision or a Coach reply. The subject must be the caller's own: a decision of theirs,
-- or a reply (an assistant message) in one of their conversations. A second call for the same subject
-- replaces the rating. Returns {schema_version, subject_type, subject_id, rating}. Errors: 42501
-- signed out; 22023 an unknown subject type or rating, or a subject that is not the caller's.

create function public.submit_feedback_rating_v1(subject_type text, subject_id uuid, rating text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  uid constant uuid := auth.uid();
  owned boolean;
begin
  if uid is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if submit_feedback_rating_v1.rating is null
     or submit_feedback_rating_v1.rating <> all (array['useful', 'unclear', 'incorrect', 'unsafe']) then
    raise exception 'unknown rating' using errcode = '22023';
  end if;
  if submit_feedback_rating_v1.subject_id is null then
    raise exception 'a rating is for one decision or reply' using errcode = '22023';
  end if;
  if submit_feedback_rating_v1.subject_type = 'daily_decision' then
    select exists (select 1 from public.coach_decisions d
      where d.id = submit_feedback_rating_v1.subject_id and d.user_id = uid) into owned;
  elsif submit_feedback_rating_v1.subject_type = 'coach_reply' then
    select exists (select 1 from public.coach_messages m
      where m.id = submit_feedback_rating_v1.subject_id and m.user_id = uid
        and m.role = 'assistant') into owned;
  else
    raise exception 'unknown subject type' using errcode = '22023';
  end if;
  if not owned then
    raise exception 'that is not yours to rate' using errcode = '22023';
  end if;
  insert into public.feedback_ratings (user_id, subject_type, subject_id, rating)
  values (uid, submit_feedback_rating_v1.subject_type, submit_feedback_rating_v1.subject_id,
    submit_feedback_rating_v1.rating)
  on conflict on constraint feedback_ratings_one_per_subject
  do update set rating = excluded.rating, created_at = now();
  return jsonb_build_object('schema_version', '1.0',
    'subject_type', submit_feedback_rating_v1.subject_type,
    'subject_id', submit_feedback_rating_v1.subject_id,
    'rating', submit_feedback_rating_v1.rating);
end $$;
revoke all on function public.submit_feedback_rating_v1(text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.submit_feedback_rating_v1(text, uuid, text) to authenticated;
