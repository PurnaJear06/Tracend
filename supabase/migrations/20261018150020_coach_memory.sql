-- A10 part 2: Coach memory with athlete controls (coaching platform chunk A10, migration code 20).
--
-- Coach keeps two small stores about the athlete, and the athlete owns both:
--   coach_facts   what the athlete confirmed: injuries and limitations, schedule and life
--                 constraints, equipment, food and exercise likes, dislikes and allergies, coaching
--                 style, other stable preferences. Only an athlete action writes one (typed on the
--                 memory screen, or a Coach suggestion the athlete confirmed). Each fact is
--                 versioned: an edit or a re-confirmation adds a version and supersedes the old
--                 one. Injuries and schedule constraints carry a re-confirm date.
--   coach_notes   what Coach noted after a conversation: topics, concerns, advice and commitments,
--                 linked to the messages they came from. The server writes them from structured
--                 fields, never from the Coach's own prose. At most 20 are kept and each lapses
--                 after 60 days. They are the Coach's notes, not the athlete's facts.
--
-- 1. coach_threads.remember         a conversation the athlete chose not to have remembered
--    create_coach_thread_v2         opens one; get_my_coach_threads reports the flag
-- 2. coach_facts                    the confirmed facts, RLS, athlete RPCs and the backfill of the
--                                   confirmed preferences
-- 3. coach_notes                    the notes, RLS, service RPCs, cap and decay, follow-through;
--                                   change_proposals.memory_noted_at and source_remembered
-- 4. get_my_coach_memory_v1 and the athlete's controls (edit, re-confirm, delete, forget all)
-- 5. get_coach_memory_context_v1    what the Coach contributors read (service role)
-- 6. coach_lookup_past_messages_v1  raw message search, a Coach lookup (service role)
-- 7. prepare_coach_chat_v9          the frozen v8 plus the memory controls
--
-- prepare_coach_chat_v8 and build_coach_athlete_context are not touched. Everything is additive:
-- an older app build ignores the new column and functions.

-- 1. Conversations that are not remembered -------------------------------------------------------

alter table public.coach_threads add column remember boolean not null default true;

comment on column public.coach_threads.remember is
  'False when the athlete asked that this conversation is not remembered: no Coach notes, no suggested facts, never searched, never shown to another conversation.';

create function public.create_coach_thread_v2(
  thread_title text default 'New conversation', remember_chat boolean default true)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare new_id uuid;
begin
  if auth.uid() is null then
    raise exception 'authentication required' using errcode = '42501';
  end if;
  if thread_title is null or length(trim(thread_title)) not between 1 and 120 then
    raise exception 'invalid title' using errcode = '22023';
  end if;
  if remember_chat is null then
    raise exception 'remember_chat must be true or false' using errcode = '22023';
  end if;
  insert into public.coach_threads(user_id, title, remember)
  values (auth.uid(), trim(thread_title), remember_chat) returning id into new_id;
  return jsonb_build_object('schema_version', '1.0', 'thread_id', new_id, 'remember', remember_chat);
end $$;
revoke all on function public.create_coach_thread_v2(text, boolean) from public, anon, authenticated;
grant execute on function public.create_coach_thread_v2(text, boolean) to authenticated;

-- The list as in 20260929090000, with one more key per thread.
create or replace function public.get_my_coach_threads()
returns jsonb language sql security definer set search_path = '' stable as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'threads', coalesce(jsonb_agg(jsonb_build_object(
        'id', t.id,
        'title', t.title,
        'last_message_at', t.last_message_at,
        'updated_at', t.updated_at,
        'remember', t.remember)
      order by t.last_message_at desc, t.id), '[]'::jsonb))
  from public.coach_threads t
  where t.user_id = auth.uid()
    and t.status = 'active'
    and exists(select 1 from public.coach_messages m
      where m.thread_id = t.id and m.user_id = t.user_id);
$$;

-- The old full-text search over a user's messages skips conversations that are not remembered.
create or replace function public.search_coach_messages(
  target_user_id uuid, query_text text, max_results integer default 8
) returns jsonb language plpgsql security definer set search_path = '' stable as $$
declare
  results jsonb;
begin
  select coalesce(jsonb_agg(msg order by relevance desc), '[]'::jsonb) into results
  from (
    select jsonb_build_object(
      'id', m.id, 'thread_id', m.thread_id, 'role', m.role,
      'content', m.content, 'created_at', m.created_at,
      'relevance', ts_rank(m.search_vector, plainto_tsquery('english', query_text))
    ) msg,
      ts_rank(m.search_vector, plainto_tsquery('english', query_text)) relevance
    from public.coach_messages m
    join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
    where m.user_id = target_user_id and t.remember
      and plainto_tsquery('english', query_text) @@ m.search_vector
    order by relevance desc
    limit max_results
  ) ranked;
  return coalesce(results, '[]'::jsonb);
end $$;

-- 2. Confirmed facts -----------------------------------------------------------------------------

-- Volatile facts are asked about again: an injury after 28 days, a schedule constraint after 90.
-- Every other kind never expires. _shared/coach_memory reads the stored date and holds no copy of
-- these intervals.
create function private.coach_fact_reconfirm_at(fact_kind text, from_ts timestamptz)
returns timestamptz language sql stable set search_path = '' as $$
  select case fact_kind
    when 'injury_limitation' then from_ts + interval '28 days'
    when 'schedule_constraint' then from_ts + interval '90 days'
  end
$$;
revoke all on function private.coach_fact_reconfirm_at(text, timestamptz)
  from public, anon, authenticated;

create table public.coach_facts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  -- The id of the first version; every version of one fact shares it.
  lineage_id uuid not null,
  version integer not null default 1 check (version >= 1),
  kind text not null check (kind in (
    'injury_limitation', 'schedule_constraint', 'equipment', 'food_like', 'food_dislike',
    'allergy', 'exercise_like', 'exercise_dislike', 'coaching_style', 'other_preference')),
  -- A short lower-case label ("left knee", "mushrooms", "weekends"); at most one active fact has
  -- a given kind and subject.
  subject text not null check (subject = lower(subject) and char_length(subject) between 1 and 60),
  -- What the athlete confirmed, in their words, as Coach reads it.
  statement text not null check (char_length(statement) between 1 and 200),
  source text not null check (source in ('athlete_typed', 'coach_suggestion_confirmed', 'onboarding')),
  confirmed_at timestamptz not null default now(),
  reconfirm_at timestamptz,
  superseded_at timestamptz,
  created_at timestamptz not null default now()
);

create unique index coach_facts_one_active on public.coach_facts (user_id, kind, subject)
  where superseded_at is null;
create index coach_facts_lineage on public.coach_facts (user_id, lineage_id, version desc);

comment on table public.coach_facts is
  'Facts the athlete confirmed for Coach, versioned (superseded, never overwritten). Written only by an athlete action; Coach may suggest a fact but nothing is stored until the athlete confirms.';
comment on column public.coach_facts.reconfirm_at is
  'When Coach should ask again (injuries and schedule constraints); null for kinds that do not lapse.';

alter table public.coach_facts enable row level security;
alter table public.coach_facts force row level security;
create policy coach_facts_own_read on public.coach_facts
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.coach_facts from anon, authenticated;
grant select on public.coach_facts to authenticated;

create function private.coach_fact_json(f public.coach_facts)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', f.id, 'lineage_id', f.lineage_id, 'version', f.version, 'kind', f.kind,
    'subject', f.subject, 'statement', f.statement, 'source', f.source,
    'confirmed_at', f.confirmed_at, 'reconfirm_at', f.reconfirm_at,
    'reconfirm_due', coalesce(f.reconfirm_at <= statement_timestamp(), false));
$$;
revoke all on function private.coach_fact_json(public.coach_facts) from public, anon, authenticated;

-- The preferences the athlete already confirmed move across as facts, so the memory screen shows
-- them. The old category does not say whether a food was liked or avoided, so they become "other
-- preference" (schedule stays a schedule constraint) and the athlete can retype them.
insert into public.coach_facts(id, user_id, lineage_id, kind, subject, statement, source,
  confirmed_at, reconfirm_at)
select p.id, p.user_id, p.id,
  case p.category when 'schedule' then 'schedule_constraint' else 'other_preference' end,
  left(lower(btrim(p.key)), 60), left(btrim(p.value), 200),
  case p.provenance when 'onboarding' then 'onboarding' when 'manual' then 'athlete_typed'
    else 'coach_suggestion_confirmed' end,
  p.confirmed_at,
  private.coach_fact_reconfirm_at(
    case p.category when 'schedule' then 'schedule_constraint' else 'other_preference' end,
    p.confirmed_at)
from public.user_preferences p
where p.superseded_at is null and btrim(p.key) <> '' and btrim(p.value) <> ''
on conflict do nothing;

-- Saves a fact for the caller: a new fact, or a new version that supersedes the one it replaces
-- (named by p_supersedes, or the active fact with the same kind and subject). Only the athlete's own
-- action reaches this function, from the memory screen or a confirm chip.
create function public.save_coach_fact_v1(
  p_kind text, p_subject text, p_statement text,
  p_source text default 'athlete_typed', p_supersedes uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  subject_text text := lower(regexp_replace(btrim(coalesce(p_subject, '')), '\s+', ' ', 'g'));
  statement_text text := regexp_replace(btrim(coalesce(p_statement, '')), '\s+', ' ', 'g');
  previous public.coach_facts%rowtype;
  had_previous boolean := false;
  new_id uuid := gen_random_uuid();
  saved public.coach_facts%rowtype;
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  if p_kind is null or p_kind not in ('injury_limitation', 'schedule_constraint', 'equipment',
    'food_like', 'food_dislike', 'allergy', 'exercise_like', 'exercise_dislike',
    'coaching_style', 'other_preference') then
    raise exception 'unknown fact kind' using errcode = '22023';
  end if;
  if p_source is null or p_source not in ('athlete_typed', 'coach_suggestion_confirmed') then
    raise exception 'unknown fact source' using errcode = '22023';
  end if;
  if char_length(subject_text) not between 1 and 60
    or char_length(statement_text) not between 1 and 200 then
    raise exception 'invalid fact' using errcode = '22023';
  end if;

  if p_supersedes is not null then
    select * into previous from public.coach_facts f
    where f.id = p_supersedes and f.user_id = me and f.superseded_at is null for update;
    if not found then raise exception 'fact not found' using errcode = 'P0002'; end if;
    had_previous := true;
  else
    select * into previous from public.coach_facts f
    where f.user_id = me and f.kind = p_kind and f.subject = subject_text
      and f.superseded_at is null for update;
    had_previous := found;
  end if;

  if not had_previous and (select count(*) from public.coach_facts f
    where f.user_id = me and f.superseded_at is null) >= 60 then
    raise exception 'too many saved facts' using errcode = '54000';
  end if;

  if had_previous then
    update public.coach_facts set superseded_at = statement_timestamp() where id = previous.id;
  end if;
  insert into public.coach_facts(id, user_id, lineage_id, version, kind, subject, statement,
    source, confirmed_at, reconfirm_at)
  values (new_id, me, case when had_previous then previous.lineage_id else new_id end,
    case when had_previous then previous.version + 1 else 1 end, p_kind, subject_text,
    statement_text, p_source, statement_timestamp(),
    private.coach_fact_reconfirm_at(p_kind, statement_timestamp()))
  returning * into saved;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (me, 'coach.fact.saved', 'coach_fact', saved.id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'kind', saved.kind, 'source', saved.source,
      'version', saved.version));
  return jsonb_build_object('schema_version', '1.0', 'fact', private.coach_fact_json(saved));
end $$;
revoke all on function public.save_coach_fact_v1(text, text, text, text, uuid)
  from public, anon, authenticated;
grant execute on function public.save_coach_fact_v1(text, text, text, text, uuid) to authenticated;

-- "Still true": the same fact as a new version with a fresh confirmation date.
create function public.reconfirm_coach_fact_v1(p_fact_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  previous public.coach_facts%rowtype;
  saved public.coach_facts%rowtype;
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into previous from public.coach_facts f
  where f.id = p_fact_id and f.user_id = me and f.superseded_at is null for update;
  if not found then raise exception 'fact not found' using errcode = 'P0002'; end if;
  update public.coach_facts set superseded_at = statement_timestamp() where id = previous.id;
  insert into public.coach_facts(user_id, lineage_id, version, kind, subject, statement, source,
    confirmed_at, reconfirm_at)
  values (me, previous.lineage_id, previous.version + 1, previous.kind, previous.subject,
    previous.statement, previous.source, statement_timestamp(),
    private.coach_fact_reconfirm_at(previous.kind, statement_timestamp()))
  returning * into saved;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (me, 'coach.fact.reconfirmed', 'coach_fact', saved.id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'kind', saved.kind, 'version', saved.version));
  return jsonb_build_object('schema_version', '1.0', 'fact', private.coach_fact_json(saved));
end $$;
revoke all on function public.reconfirm_coach_fact_v1(uuid) from public, anon, authenticated;
grant execute on function public.reconfirm_coach_fact_v1(uuid) to authenticated;

-- Deleting a fact deletes every version of it: nothing of it is kept.
create function public.delete_coach_fact_v1(p_fact_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  target public.coach_facts%rowtype;
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  select * into target from public.coach_facts f where f.id = p_fact_id and f.user_id = me;
  if not found then raise exception 'fact not found' using errcode = 'P0002'; end if;
  delete from public.coach_facts where user_id = me and lineage_id = target.lineage_id;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (me, 'coach.fact.deleted', 'coach_fact', target.id, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'kind', target.kind));
  return jsonb_build_object('schema_version', '1.0', 'deleted', true);
end $$;
revoke all on function public.delete_coach_fact_v1(uuid) from public, anon, authenticated;
grant execute on function public.delete_coach_fact_v1(uuid) to authenticated;

-- 3. Coach notes ---------------------------------------------------------------------------------

create table public.coach_notes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.user_accounts(id) on delete cascade,
  thread_id uuid,
  -- 'conversation': what a chat turn was about. 'advice': a proposal Coach made and how the athlete
  -- answered it.
  entry_kind text not null check (entry_kind in ('conversation', 'advice')),
  note_date date not null,
  -- One plain sentence built by a template from the fields below, never from the Coach's reply.
  summary text not null check (char_length(summary) between 1 and 400),
  topics text[] not null default '{}'
    check (cardinality(topics) <= 6 and array_to_string(topics, ' ') ~ '^[a-z_ ]*$'),
  concerns text[] not null default '{}'
    check (cardinality(concerns) <= 6 and array_to_string(concerns, ' ') ~ '^[a-z_ ]*$'),
  advice jsonb not null default '[]'
    check (jsonb_typeof(advice) = 'array' and jsonb_array_length(advice) <= 4),
  commitments jsonb not null default '[]'
    check (jsonb_typeof(commitments) = 'array' and jsonb_array_length(commitments) <= 4),
  -- {status: followed | partly | not_followed, checked_on, detail}; null until checked.
  follow_through jsonb check (follow_through is null or (
    jsonb_typeof(follow_through) = 'object'
    and follow_through ->> 'status' in ('followed', 'partly', 'not_followed'))),
  message_ids uuid[] not null default '{}' check (cardinality(message_ids) <= 6),
  proposal_id uuid references public.change_proposals(id) on delete set null,
  created_at timestamptz not null default clock_timestamp(),
  expires_at timestamptz not null default (clock_timestamp() + interval '60 days'),
  foreign key (thread_id, user_id) references public.coach_threads(id, user_id) on delete cascade
);

create unique index coach_notes_one_per_proposal on public.coach_notes (proposal_id)
  where proposal_id is not null;
create index coach_notes_user_recent on public.coach_notes (user_id, created_at desc);

comment on table public.coach_notes is
  'Coach''s own notes about past conversations and advice, written by the server from structured fields. At most 20 per athlete, each lapses after 60 days, never written for a conversation that is not remembered. Untrusted when read back.';

alter table public.coach_notes enable row level security;
alter table public.coach_notes force row level security;
create policy coach_notes_own_read on public.coach_notes
  for select to authenticated using (user_id = (select auth.uid()));
revoke all on public.coach_notes from anon, authenticated;
grant select on public.coach_notes to authenticated;

create function private.coach_note_json(n public.coach_notes)
returns jsonb language sql stable set search_path = '' as $$
  select jsonb_build_object(
    'id', n.id, 'thread_id', n.thread_id, 'entry_kind', n.entry_kind, 'note_date', n.note_date,
    'summary', n.summary, 'topics', to_jsonb(n.topics), 'concerns', to_jsonb(n.concerns),
    'advice', n.advice, 'commitments', n.commitments, 'follow_through', n.follow_through,
    'message_ids', to_jsonb(n.message_ids), 'proposal_id', n.proposal_id,
    'created_at', n.created_at, 'expires_at', n.expires_at);
$$;
revoke all on function private.coach_note_json(public.coach_notes) from public, anon, authenticated;

-- Stores one note. Nothing is stored for a conversation that is not remembered (the answer says
-- why), and the caller's message ids must be the athlete's own messages in that conversation. After
-- the insert the athlete keeps their 20 newest unexpired notes.
create function public.persist_coach_note_v1(
  p_user_id uuid, p_thread_id uuid, p_entry_kind text, p_note_date date, p_summary text,
  p_topics text[], p_concerns text[], p_advice jsonb, p_commitments jsonb,
  p_message_ids uuid[], p_proposal_id uuid default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  thread public.coach_threads%rowtype;
  new_id uuid;
begin
  if p_user_id is null or not exists (select 1 from public.user_accounts where id = p_user_id) then
    raise exception 'account not found' using errcode = 'P0002';
  end if;
  if p_entry_kind is null or p_entry_kind not in ('conversation', 'advice') then
    raise exception 'unknown note kind' using errcode = '22023';
  end if;
  if p_thread_id is not null then
    select * into thread from public.coach_threads t where t.id = p_thread_id and t.user_id = p_user_id;
    if not found then raise exception 'thread not found' using errcode = 'P0002'; end if;
    if not thread.remember then
      return jsonb_build_object('schema_version', '1.0', 'stored', false, 'reason', 'not_remembered');
    end if;
  elsif p_entry_kind = 'conversation' then
    raise exception 'a conversation note needs its thread' using errcode = '22023';
  end if;
  if exists (
    select 1 from unnest(coalesce(p_message_ids, '{}'::uuid[])) as linked(id)
    where not exists (select 1 from public.coach_messages m
      where m.id = linked.id and m.user_id = p_user_id
        and (p_thread_id is null or m.thread_id = p_thread_id))
  ) then
    raise exception 'a linked message is not the athlete''s' using errcode = '22023';
  end if;

  insert into public.coach_notes(user_id, thread_id, entry_kind, note_date, summary, topics,
    concerns, advice, commitments, message_ids, proposal_id)
  values (p_user_id, p_thread_id, p_entry_kind, p_note_date, btrim(p_summary),
    coalesce(p_topics, '{}'), coalesce(p_concerns, '{}'), coalesce(p_advice, '[]'::jsonb),
    coalesce(p_commitments, '[]'::jsonb), coalesce(p_message_ids, '{}'::uuid[]), p_proposal_id)
  on conflict (proposal_id) where proposal_id is not null do nothing
  returning id into new_id;

  if p_proposal_id is not null then
    update public.change_proposals set memory_noted_at = coalesce(memory_noted_at, now())
    where id = p_proposal_id and user_id = p_user_id;
  end if;

  -- At most 20 notes stay. A note still waiting for its follow-through check (a training-days
  -- commitment whose check can still run: under 28 days old) is kept before any other, so a busy
  -- athlete's commitments are not pushed out before the week they promised has been checked; the
  -- oldest other notes go first, and only if 20 are waiting does a waiting one go.
  delete from public.coach_notes n
  where n.user_id = p_user_id and (
    n.expires_at <= statement_timestamp()
    or n.id in (
      select ranked.id from (
        select k.id,
          row_number() over (order by k.waiting desc, k.created_at desc, k.id desc) as place
        from (
          select c.id, c.created_at,
            (c.follow_through is null and c.note_date >= statement_timestamp()::date - 28
              and exists (select 1 from jsonb_array_elements(c.commitments || c.advice) e
                where e ->> 'kind' = 'train_days')) as waiting
          from public.coach_notes c where c.user_id = p_user_id) k
      ) ranked
      where ranked.place > 20));

  return jsonb_build_object('schema_version', '1.0', 'stored', new_id is not null,
    'note_id', new_id, 'reason', case when new_id is null then 'already_noted' end);
end $$;
revoke all on function public.persist_coach_note_v1(uuid, uuid, text, date, text, text[], text[],
  jsonb, jsonb, uuid[], uuid) from public, anon, authenticated;
grant execute on function public.persist_coach_note_v1(uuid, uuid, text, date, text, text[], text[],
  jsonb, jsonb, uuid[], uuid) to service_role;

-- Whether a proposal has been turned into a note, and whether it was made in a conversation Coach
-- may remember. memory_noted_at is set when the note is first written (or when the athlete forgets
-- everything) and never cleared, so deleting a note, the 20-note cap or "Forget everything" can
-- never bring a note back. source_remembered is copied from the conversation when the proposal is
-- linked to its reply, so it still holds after the conversation is deleted. Proposals that exist
-- now were all made in conversations that Coach remembered, so they start as true; a proposal made
-- from now on starts as false and becomes true only when its reply is in a remembered conversation,
-- so one that never gets linked (the reply failed to store, the conversation was deleted mid-reply)
-- is never turned into a note.
alter table public.change_proposals
  add column memory_noted_at timestamptz,
  add column source_remembered boolean not null default true;
alter table public.change_proposals alter column source_remembered set default false;

create function private.copy_proposal_source_remembered()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.source_message_id is not null then
    new.source_remembered := coalesce((
      select t.remember from public.coach_messages m
      join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
      where m.id = new.source_message_id and m.user_id = new.user_id), new.source_remembered);
  end if;
  return new;
end $$;
revoke all on function private.copy_proposal_source_remembered() from public, anon, authenticated;

create trigger change_proposals_source_remembered
  before insert or update of source_message_id on public.change_proposals
  for each row execute function private.copy_proposal_source_remembered();

-- Proposals the athlete has answered (or that lapsed) in the last 30 days and that have not been
-- turned into a note, newest first. A proposal made in a conversation that is not remembered is
-- skipped, even after that conversation is deleted.
create function public.get_unnoted_coach_proposals_v1(p_user_id uuid, p_limit integer default 5)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('schema_version', '1.0', 'proposals', coalesce(jsonb_agg(
    jsonb_build_object(
      'id', r.id, 'kind', r.kind, 'title', r.title, 'outcome', r.outcome,
      'answered_on', r.answered_on, 'days_per_week', r.days_per_week,
      'source_message_id', r.source_message_id)
    order by r.created_at desc), '[]'::jsonb))
  from (
    select c.id, c.proposal_kind as kind, c.proposed_training ->> 'title' as title,
      case
        when c.undone_at is not null then 'undone'
        when c.status = 'accepted' then 'accepted'
        when c.status = 'rejected' then 'declined'
        when c.status = 'revision_requested' then 'changed'
        else 'expired' end as outcome,
      private.local_day(c.user_id, coalesce(c.undone_at, resp.created_at, c.expires_at))
        as answered_on,
      case when jsonb_typeof(c.proposal_payload -> 'training' -> 'profile' -> 'training_days') = 'array'
        then jsonb_array_length(c.proposal_payload -> 'training' -> 'profile' -> 'training_days')
      end as days_per_week,
      case when m.id is not null then m.id end as source_message_id,
      c.created_at
    from public.change_proposals c
    left join public.change_responses resp on resp.proposal_id = c.id and resp.user_id = c.user_id
    left join public.coach_messages m on m.id = c.source_message_id and m.user_id = c.user_id
    where c.user_id = p_user_id and c.schema_version = '3.0'
      and (c.status <> 'pending' or c.expires_at <= statement_timestamp())
      and c.created_at > statement_timestamp() - interval '30 days'
      and c.memory_noted_at is null and c.source_remembered
    order by c.created_at desc
    limit greatest(1, least(coalesce(p_limit, 5), 10))
  ) r;
$$;
revoke all on function public.get_unnoted_coach_proposals_v1(uuid, integer)
  from public, anon, authenticated;
grant execute on function public.get_unnoted_coach_proposals_v1(uuid, integer) to service_role;

-- Notes that carry a checkable training commitment (the athlete's "I'll train 4 days" or an approved
-- schedule), whose week after the note has fully passed, not yet checked, with the sessions completed in the week after the
-- note. Only training days are checked; every other commitment stays unchecked.
create function public.get_coach_follow_through_inputs_v1(p_user_id uuid, p_today date)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object('schema_version', '1.0', 'checks', coalesce(jsonb_agg(
    jsonb_build_object(
      'note_id', c.id, 'kind', 'train_days', 'target', c.target,
      'window_from', c.note_date + 1, 'window_to', c.note_date + 7,
      'sessions_completed', (
        select count(*) from public.workout_sessions s
        where s.user_id = p_user_id and s.state = 'completed'
          and s.local_date between c.note_date + 1 and c.note_date + 7))
    order by c.note_date), '[]'::jsonb))
  from (
    select n.id, n.note_date, t.target
    from public.coach_notes n
    cross join lateral (
      select min(case when e ->> 'target' ~ '^[1-7]$' then (e ->> 'target')::integer end) as target
      from jsonb_array_elements(n.commitments || n.advice) e
      where e ->> 'kind' = 'train_days') t
    where t.target is not null
      and n.user_id = p_user_id and n.follow_through is null
      and n.expires_at > statement_timestamp()
      and n.note_date + 7 < p_today and n.note_date >= p_today - 28
    order by n.note_date
    limit 5
  ) c;
$$;
revoke all on function public.get_coach_follow_through_inputs_v1(uuid, date)
  from public, anon, authenticated;
grant execute on function public.get_coach_follow_through_inputs_v1(uuid, date) to service_role;

create function public.record_coach_note_follow_through_v1(
  p_user_id uuid, p_note_id uuid, p_status text, p_checked_on date, p_detail text)
returns jsonb language plpgsql security definer set search_path = '' as $$
begin
  if p_status is null or p_status not in ('followed', 'partly', 'not_followed') then
    raise exception 'unknown follow-through status' using errcode = '22023';
  end if;
  update public.coach_notes set follow_through = jsonb_build_object(
    'status', p_status, 'checked_on', p_checked_on, 'detail', left(btrim(coalesce(p_detail, '')), 160))
  where id = p_note_id and user_id = p_user_id and follow_through is null;
  return jsonb_build_object('schema_version', '1.0', 'recorded', found);
end $$;
revoke all on function public.record_coach_note_follow_through_v1(uuid, uuid, text, date, text)
  from public, anon, authenticated;
grant execute on function public.record_coach_note_follow_through_v1(uuid, uuid, text, date, text)
  to service_role;

-- 4. The athlete's view and controls -------------------------------------------------------------

create function public.get_my_coach_memory_v1()
returns jsonb language plpgsql stable security definer set search_path = '' as $$
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'schema_version', '1.0',
    'facts', coalesce((
      select jsonb_agg(private.coach_fact_json(f) order by f.kind, f.confirmed_at desc, f.id)
      from public.coach_facts f where f.user_id = auth.uid() and f.superseded_at is null),
      '[]'::jsonb),
    'notes', coalesce((
      select jsonb_agg(private.coach_note_json(n) order by n.created_at desc, n.id)
      from public.coach_notes n
      where n.user_id = auth.uid() and n.expires_at > statement_timestamp()), '[]'::jsonb),
    'limits', jsonb_build_object('max_facts', 60, 'max_notes', 20, 'note_days', 60));
end $$;
revoke all on function public.get_my_coach_memory_v1() from public, anon, authenticated;
grant execute on function public.get_my_coach_memory_v1() to authenticated;

create function public.delete_coach_note_v1(p_note_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  removed uuid;
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  delete from public.coach_notes where id = p_note_id and user_id = me returning id into removed;
  if removed is null then raise exception 'note not found' using errcode = 'P0002'; end if;
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (me, 'coach.note.deleted', 'coach_note', removed, 'succeeded',
    jsonb_build_object('schema_version', '1.0'));
  return jsonb_build_object('schema_version', '1.0', 'deleted', true);
end $$;
revoke all on function public.delete_coach_note_v1(uuid) from public, anon, authenticated;
grant execute on function public.delete_coach_note_v1(uuid) to authenticated;

-- "Forget everything": every fact and note, and the older preference, journal and narrative rows
-- the memory replaces. Conversations stay; the athlete deletes those under Coach conversations.
create function public.forget_coach_memory_v1()
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  me uuid := auth.uid();
  facts_removed integer;
  notes_removed integer;
begin
  if me is null then raise exception 'authentication required' using errcode = '42501'; end if;
  delete from public.coach_facts where user_id = me;
  get diagnostics facts_removed = row_count;
  delete from public.coach_notes where user_id = me;
  get diagnostics notes_removed = row_count;
  delete from public.user_preferences where user_id = me;
  delete from public.coach_session_summaries where user_id = me;
  delete from public.coach_narrative_entries where user_id = me;
  -- Every proposal made so far is marked noted, answered or still pending, so none of them is
  -- turned into a note later (not even by expiring unanswered); a proposal made after this
  -- is noted as usual. The stored copies of the older memory sections are removed from the
  -- athlete's prepared contexts.
  update public.change_proposals set memory_noted_at = coalesce(memory_noted_at, now())
  where user_id = me and schema_version = '3.0' and memory_noted_at is null;
  update public.coach_context_snapshots s
  set context = s.context - 'session_journal' - 'active_preferences' - 'coaching_narrative',
    context_checksum = encode(extensions.digest(convert_to(
      (s.context - 'session_journal' - 'active_preferences' - 'coaching_narrative')::text,
      'UTF8'), 'sha256'), 'hex')
  where s.user_id = me and s.context ?| array['session_journal', 'active_preferences',
    'coaching_narrative'];
  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (me, 'coach.memory.forgotten', 'coach_memory', me, 'succeeded',
    jsonb_build_object('schema_version', '1.0', 'facts', facts_removed, 'notes', notes_removed));
  return jsonb_build_object('schema_version', '1.0', 'facts_deleted', facts_removed,
    'notes_deleted', notes_removed);
end $$;
revoke all on function public.forget_coach_memory_v1() from public, anon, authenticated;
grant execute on function public.forget_coach_memory_v1() to authenticated;

-- 5. What the Coach reads ------------------------------------------------------------------------

-- The athlete's active facts and unexpired notes (newest 20) for the two Coach contributors.
create function public.get_coach_memory_context_v1(p_user_id uuid)
returns jsonb language sql stable security definer set search_path = '' as $$
  select jsonb_build_object(
    'schema_version', '1.0',
    'local_date', private.local_date_for(p_user_id),
    'facts', coalesce((
      select jsonb_agg(private.coach_fact_json(f) order by f.kind, f.confirmed_at desc, f.id)
      from public.coach_facts f where f.user_id = p_user_id and f.superseded_at is null),
      '[]'::jsonb),
    'notes', coalesce((
      select jsonb_agg(private.coach_note_json(n) order by n.created_at desc, n.id)
      from public.coach_notes n
      where n.user_id = p_user_id and n.expires_at > statement_timestamp()
        and n.id in (select k.id from public.coach_notes k
          where k.user_id = p_user_id and k.expires_at > statement_timestamp()
          order by k.created_at desc, k.id desc limit 20)), '[]'::jsonb));
$$;
revoke all on function public.get_coach_memory_context_v1(uuid) from public, anon, authenticated;
grant execute on function public.get_coach_memory_context_v1(uuid) to service_role;

-- 6. Raw message search --------------------------------------------------------------------------

-- The athlete's own questions in conversations that are remembered, matching any of the words in
-- the filter, newest local day first among equal matches; at most 12 rows of 300 characters. It
-- backs the notes up: extraction loses detail. Coach's own replies are not searched, so a wrong
-- claim of the Coach's never returns as memory.
create function public.coach_lookup_past_messages_v1(
  p_user_id uuid, p_from date, p_to date, p_filter text default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare
  lo date := greatest(p_from, p_to - 399);
  search_query tsquery;
begin
  if p_filter is null or btrim(p_filter) = '' then
    raise exception 'a search phrase is required' using errcode = '22023';
  end if;
  search_query := replace(plainto_tsquery('english', p_filter)::text, ' & ', ' | ')::tsquery;
  return (
    with rows_all as (
      select m.id, private.local_day(p_user_id, m.created_at) as local_date, m.content,
        ts_rank(m.search_vector, search_query) as rank
      from public.coach_messages m
      join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
      where m.user_id = p_user_id and m.role = 'user' and t.remember
        and m.safety_state <> 'unavailable'
        and private.local_day(p_user_id, m.created_at) between lo and p_to
        and m.search_vector @@ search_query
      order by rank desc, m.created_at desc
      limit 13
    )
    select jsonb_build_object(
      'schema_version', '1.0', 'lookup', 'past_messages', 'from', lo, 'to', p_to,
      'truncated', (select count(*) > 12 from rows_all),
      'messages', coalesce((select jsonb_agg(jsonb_build_object(
          'message_id', r.id, 'local_date', r.local_date, 'content', left(r.content, 300))
          order by r.rank desc, r.local_date desc)
        from (select * from rows_all order by rank desc, local_date desc limit 12) r), '[]'::jsonb)));
end $$;
revoke all on function public.coach_lookup_past_messages_v1(uuid, date, date, text)
  from public, anon, authenticated;
grant execute on function public.coach_lookup_past_messages_v1(uuid, date, date, text)
  to service_role;

-- 7. The context with the memory controls --------------------------------------------------------

-- v8 builds the athlete file unchanged. v9 then (1) shows a conversation only the messages of other
-- conversations the athlete let Coach remember, and (2) leaves out the older preference, journal and
-- narrative sections, which the confirmed facts and Coach notes replace. It rewrites the stored
-- snapshot to match what the Coach is given.
create function public.prepare_coach_chat_v9(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  prepared jsonb;
  c jsonb;
begin
  prepared := public.prepare_coach_chat_v8(target_user_id, target_thread_id, question,
    coaching_timezone, request_idempotency_key, context_kind);
  if coalesce((prepared ->> 'replayed')::boolean, false) or not (prepared ? 'context') then
    return prepared;
  end if;
  c := prepared -> 'context';
  if c ? 'recent_other_conversations' then
    c := c || jsonb_build_object('recent_other_conversations', (
      select coalesce(jsonb_agg(message order by created_at, turn_rank), '[]'::jsonb) from (
        select jsonb_build_object('role', m.role, 'content', case when length(m.content) > 2000
            then left(m.content, 500) || ' … ' || right(m.content, 1400) else m.content end) message,
          m.created_at, case m.role when 'user' then 0 else 1 end turn_rank
        from public.coach_messages m
        join public.coach_threads t on t.id = m.thread_id and t.user_id = m.user_id
        where m.user_id = target_user_id and m.thread_id <> target_thread_id and t.remember
          and m.answer_source is distinct from 'data_summary'
        order by m.created_at desc, turn_rank desc limit 10
      ) other));
  end if;
  c := c - 'session_journal' - 'active_preferences' - 'coaching_narrative';
  if prepared ? 'coach_context_snapshot_id' then
    update public.coach_context_snapshots
    set context = c,
      context_checksum = encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex')
    where id = (prepared ->> 'coach_context_snapshot_id')::uuid and user_id = target_user_id;
  end if;
  return prepared || jsonb_build_object('context', c);
end $$;
revoke all on function public.prepare_coach_chat_v9(uuid, uuid, text, text, uuid, text)
  from public, anon, authenticated;
grant execute on function public.prepare_coach_chat_v9(uuid, uuid, text, text, uuid, text)
  to service_role;
