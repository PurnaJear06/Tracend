-- Onboarding plan telemetry: how the model call went is stored with the
-- onboarding.plan.generated audit event, so production plans can be checked
-- (thinking on or off, latency, attempts, tokens, reasoning tokens and the
-- last finish reason). persist_onboarding_proposal_v3 takes it as one more
-- argument; v2 stays for the Edge Function deployed before this one and
-- stores no telemetry.

create function private.is_integer_between(value jsonb, low bigint, high bigint)
returns boolean language sql immutable set search_path = '' as $$
  select case when jsonb_typeof(value) = 'number' then
    (value #>> '{}')::numeric = trunc((value #>> '{}')::numeric)
    and (value #>> '{}')::numeric between low and high
  else false end;
$$;

-- Missing keys make the checks null; coalesce turns that into invalid.
create function private.is_valid_generation_metadata(metadata jsonb)
returns boolean language sql immutable set search_path = '' as $$
  select metadata is null or coalesce(
    jsonb_typeof(metadata) = 'object'
    and not exists (
      select 1 from jsonb_object_keys(metadata) key
      where key not in ('thinking', 'latency_ms', 'attempts', 'input_units',
        'output_units', 'reasoning_units', 'finish_reason')
    )
    and jsonb_typeof(metadata -> 'thinking') = 'boolean'
    and private.is_integer_between(metadata -> 'latency_ms', 0, 120000)
    and private.is_integer_between(metadata -> 'attempts', 0, 2)
    and private.is_integer_between(metadata -> 'input_units', 0, 1000000)
    and private.is_integer_between(metadata -> 'output_units', 0, 100000)
    and private.is_integer_between(metadata -> 'reasoning_units', 0, 100000)
    and coalesce(jsonb_typeof(metadata -> 'finish_reason'), 'null') in ('null', 'string')
    and length(coalesce(metadata ->> 'finish_reason', '')) <= 40,
    false);
$$;

revoke all on function private.is_integer_between(jsonb, bigint, bigint)
from public, anon, authenticated;
revoke all on function private.is_valid_generation_metadata(jsonb)
from public, anon, authenticated;

create function public.persist_onboarding_proposal_v3(
  target_generation_id uuid,
  target_user_id uuid,
  target_snapshot_hash text,
  snapshot_features jsonb,
  training_payload jsonb,
  nutrition_payload jsonb,
  evidence_payload jsonb,
  proposal_rationale text,
  proposal_benefit text,
  proposal_downside text,
  proposal_confidence text,
  generation_metadata jsonb
) returns uuid language plpgsql security definer set search_path = '' as $$
declare
  generation public.onboarding_generations%rowtype;
  snapshot_id uuid;
  new_proposal_id uuid;
begin
  select * into generation from public.onboarding_generations
    where id = target_generation_id and user_id = target_user_id for update;
  if not found or generation.status <> 'running'
    or generation.snapshot_hash <> target_snapshot_hash then
    raise exception 'generation is not current' using errcode = '55000';
  end if;

  if not exists (
    select 1 from public.user_profiles
    where user_id = target_user_id and eligible is true and adult_attested_at is not null
  ) then
    raise exception 'eligible adult profile required' using errcode = '22023';
  end if;
  if not exists (
    select 1 from public.onboarding_drafts where user_id = target_user_id and path is not null
  ) then
    raise exception 'onboarding draft required' using errcode = '22023';
  end if;
  if exists (
    select 1 from (values ('terms'::public.consent_type), ('privacy'::public.consent_type)) needed(kind)
    where coalesce((
      select c.action = 'granted' from public.consent_records c
      where c.user_id = target_user_id and c.consent_type = needed.kind
      order by c.created_at desc, c.id desc limit 1
    ), false) is false
  ) then
    raise exception 'current terms and privacy consent required' using errcode = '22023';
  end if;
  if not private.is_valid_initial_proposal_v2(training_payload, nutrition_payload)
    or not private.proposal_uses_active_catalog(training_payload)
    or not private.proposal_avoids_patterns(training_payload,
      snapshot_features -> 'answers' -> 'avoid_patterns')
    or jsonb_typeof(evidence_payload) <> 'array'
    or jsonb_typeof(snapshot_features) <> 'object'
    or not private.is_valid_generation_metadata(generation_metadata)
  then
    raise exception 'onboarding proposal is invalid' using errcode = '22023';
  end if;

  insert into public.feature_snapshots(
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    target_user_id, 'onboarding', '2.0', 'onboarding-policy-v1',
    snapshot_features, jsonb_build_object('onboarding', 'complete'), '{}', target_snapshot_hash
  )
  on conflict (user_id, data_hash) do nothing
  returning id into snapshot_id;
  if snapshot_id is null then
    select id into snapshot_id from public.feature_snapshots
      where user_id = target_user_id and data_hash = target_snapshot_hash;
  end if;

  insert into public.change_proposals(
    user_id, feature_snapshot_id, schema_version, proposed_training,
    proposed_nutrition, evidence, rationale, expected_benefit, downside,
    confidence, effective_date, expires_at
  ) values (
    target_user_id, snapshot_id, '2.0', training_payload,
    nutrition_payload, evidence_payload, proposal_rationale, proposal_benefit,
    proposal_downside, proposal_confidence, current_date,
    statement_timestamp() + interval '7 days'
  ) returning id into new_proposal_id;

  update public.onboarding_generations
    set status = 'succeeded', proposal_id = new_proposal_id, updated_at = now()
    where id = target_generation_id;

  insert into public.audit_events(user_id, action_code, target_type, target_id, outcome, metadata)
  values (target_user_id, 'onboarding.plan.generated', 'onboarding_generation',
    target_generation_id, 'succeeded', jsonb_strip_nulls(jsonb_build_object(
      'proposal_id', new_proposal_id,
      'origin', training_payload ->> 'origin',
      'provider', training_payload ->> 'provider',
      'model', training_payload ->> 'model',
      'fallback_reason', training_payload ->> 'fallback_reason',
      'policy_version', training_payload ->> 'policy_version')
      || coalesce(generation_metadata, '{}'::jsonb)));
  return new_proposal_id;
end $$;
revoke all on function public.persist_onboarding_proposal_v3(
  uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text, text, jsonb
) from public, anon, authenticated;
grant execute on function public.persist_onboarding_proposal_v3(
  uuid, uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text, text, jsonb
) to service_role;

-- v2 now stores through v3 without telemetry, so both keep the same checks.
create or replace function public.persist_onboarding_proposal_v2(
  target_generation_id uuid,
  target_user_id uuid,
  target_snapshot_hash text,
  snapshot_features jsonb,
  training_payload jsonb,
  nutrition_payload jsonb,
  evidence_payload jsonb,
  proposal_rationale text,
  proposal_benefit text,
  proposal_downside text,
  proposal_confidence text
) returns uuid language sql security definer set search_path = '' as $$
  select public.persist_onboarding_proposal_v3(
    target_generation_id, target_user_id, target_snapshot_hash, snapshot_features,
    training_payload, nutrition_payload, evidence_payload, proposal_rationale,
    proposal_benefit, proposal_downside, proposal_confidence, null);
$$;
