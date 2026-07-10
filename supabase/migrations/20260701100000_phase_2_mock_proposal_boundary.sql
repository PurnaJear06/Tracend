create function public.persist_mock_onboarding_proposal(
  target_user_id uuid,
  snapshot_hash text,
  snapshot_features jsonb,
  training_payload jsonb,
  nutrition_payload jsonb,
  evidence_payload jsonb,
  proposal_rationale text,
  proposal_benefit text,
  proposal_downside text
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  snapshot_id uuid;
  proposal_id uuid;
begin
  if not exists (
    select 1 from public.user_profiles
    where user_id = target_user_id and eligible is true and adult_attested_at is not null
  ) then
    raise exception 'eligible adult profile required' using errcode = '22023';
  end if;

  if not exists (
    select 1 from public.onboarding_drafts
    where user_id = target_user_id and path is not null
  ) then
    raise exception 'onboarding draft required' using errcode = '22023';
  end if;

  if not exists (
    select 1
    from public.consent_records c
    where c.user_id = target_user_id
      and c.consent_type = 'terms'
      and c.action = 'granted'
      and c.created_at = (
        select max(latest.created_at)
        from public.consent_records latest
        where latest.user_id = target_user_id and latest.consent_type = 'terms'
      )
  ) or not exists (
    select 1
    from public.consent_records c
    where c.user_id = target_user_id
      and c.consent_type = 'privacy'
      and c.action = 'granted'
      and c.created_at = (
        select max(latest.created_at)
        from public.consent_records latest
        where latest.user_id = target_user_id and latest.consent_type = 'privacy'
      )
  ) then
    raise exception 'current terms and privacy consent required' using errcode = '22023';
  end if;

  if not private.is_valid_initial_proposal(training_payload, nutrition_payload) then
    raise exception 'mock provider payload is invalid' using errcode = '22023';
  end if;

  select id into proposal_id
  from public.change_proposals
  where user_id = target_user_id
    and status = 'pending'
    and expires_at > statement_timestamp()
  order by created_at desc
  limit 1;

  if proposal_id is not null then
    return proposal_id;
  end if;

  insert into public.feature_snapshots (
    user_id, trigger_kind, schema_version, feature_engine_version,
    features, coverage, missing_data, data_hash
  ) values (
    target_user_id, 'onboarding', '1.0', 'onboarding-v1',
    snapshot_features, jsonb_build_object('onboarding', 'complete'), '{}',
    snapshot_hash
  )
  on conflict (user_id, data_hash) do nothing
  returning id into snapshot_id;

  if snapshot_id is null then
    select id into snapshot_id
    from public.feature_snapshots
    where user_id = target_user_id and data_hash = snapshot_hash;
  end if;

  insert into public.change_proposals (
    user_id, feature_snapshot_id, schema_version, proposed_training,
    proposed_nutrition, evidence, rationale, expected_benefit, downside,
    confidence, effective_date, expires_at
  ) values (
    target_user_id, snapshot_id, '1.0', training_payload,
    nutrition_payload, evidence_payload, proposal_rationale, proposal_benefit,
    proposal_downside, 'medium', current_date, statement_timestamp() + interval '7 days'
  ) returning id into proposal_id;

  return proposal_id;
end;
$$;

revoke all on function public.persist_mock_onboarding_proposal(
  uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text
) from public, anon, authenticated;
grant execute on function public.persist_mock_onboarding_proposal(
  uuid, text, jsonb, jsonb, jsonb, jsonb, text, text, text
) to service_role;
