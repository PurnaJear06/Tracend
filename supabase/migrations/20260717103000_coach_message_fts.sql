alter table public.coach_messages add column search_vector tsvector
  generated always as (to_tsvector('english', coalesce(content, ''))) stored;

create index coach_messages_fts on public.coach_messages
  using gin (search_vector);
