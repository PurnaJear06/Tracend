-- fix: schema_version check constraint on coach_context_snapshots was never updated
-- to allow '4.0' introduced by prepare_coach_chat_v5 in 20260717110000

alter table public.coach_context_snapshots drop constraint coach_context_snapshots_schema_version_check;
alter table public.coach_context_snapshots add constraint coach_context_snapshots_schema_version_check
  check (schema_version in ('2.0', '3.0', '4.0'));
