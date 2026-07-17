alter table public.coach_context_snapshots drop constraint coach_context_snapshots_schema_version_check;
alter table public.coach_context_snapshots add constraint coach_context_snapshots_schema_version_check
  check (schema_version in ('2.0', '3.0'));
