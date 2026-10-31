import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

// The coach-standing-state migration redefines thirteen functions. Each must be its latest earlier
// definition plus the intended hunks and nothing else, so everything else it does is what the earlier
// migration (and its pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../../migrations/${name}`, import.meta.url));
const standing = await read("20261101200000_coach_standing_state.sql");

function between(text: string, start: string, end: string): string {
  const from = text.indexOf(start);
  assert(from >= 0, `missing ${start}`);
  const to = text.indexOf(end, from);
  assert(to > from, `missing ${end}`);
  return text.slice(from, to + end.length);
}

type Hunks = readonly (readonly [string, string])[];
// [was, added]: undoing replaces `added` with `was`.
function undo(redefined: string, hunks: Hunks): string {
  let text = redefined;
  for (const [was, added] of [...hunks].reverse()) {
    assertEquals(
      text.split(added).length - 1,
      1,
      `hunk is in the function once: ${added.slice(0, 70)}`,
    );
    text = text.replace(added, () => was);
  }
  return text;
}

async function pinned(
  file: string,
  start: string,
  redefinedStart: string,
  end: string,
  hunks: Hunks,
) {
  const earlier = between(await read(file), start, end);
  const redefined = between(standing, redefinedStart, end);
  assertEquals(undo(redefined, hunks), earlier);
}

Deno.test("is_valid_coach_proposal_row is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "create function private.is_valid_coach_proposal_row(",
      "create or replace function private.is_valid_coach_proposal_row(",
    ],
    [
      "'goal_or_phase', 'nutrition_targets', 'next_session_adjustment')\n",
      "'goal_or_phase', 'nutrition_targets', 'next_session_adjustment', 'training_pause')\n",
    ],
    [
      "    and (payload ? 'training' or payload ? 'nutrition' or payload ? 'goal')\n",
      "    and (payload ? 'training' or payload ? 'nutrition' or payload ? 'goal' or payload ? 'pause')\n    and ((kind = 'training_pause') = (payload ? 'pause'))\n    and (not payload ? 'pause' or (payload - 'pause' = '{}'::jsonb\n      and private.is_valid_coach_pause(payload -> 'pause')))\n",
    ],
  ];
  await pinned(
    "20261018120018_coach_proposals.sql",
    "create function private.is_valid_coach_proposal_row(",
    "create or replace function private.is_valid_coach_proposal_row(",
    "$$;",
    hunks,
  );
});

Deno.test("coach_proposal_is_current is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "create function private.coach_proposal_is_current(",
      "create or replace function private.coach_proposal_is_current(",
    ],
    [
      "      or p.applied_changes ->> 'goal_id' = private.active_goal_id(p.user_id)::text);\n",
      "      or p.applied_changes ->> 'goal_id' = private.active_goal_id(p.user_id)::text)\n    and (p.applied_changes -> 'pause_id' is null or exists (\n      select 1 from public.training_pauses t\n      where t.id = (p.applied_changes ->> 'pause_id')::uuid and t.user_id = p.user_id\n        and t.ended_on is null and t.end_date >= private.local_date_for(p.user_id)));\n",
    ],
  ];
  await pinned(
    "20261018120018_coach_proposals.sql",
    "create function private.coach_proposal_is_current(",
    "create or replace function private.coach_proposal_is_current(",
    "$$;",
    hunks,
  );
});

Deno.test("persist_coach_proposal_v1 is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "  perform private.assert_screening_allows(p_user_id, p_basis ->> 'screening');\n",
      "  -- A break computes nothing and only rests, so the health check never holds one back.\n  if not p_payload ? 'pause' then\n    perform private.assert_screening_allows(p_user_id, p_basis ->> 'screening');\n  end if;\n",
    ],
    [
      "    raise exception 'the plan changed while the proposal was built' using errcode = '55000';\n  end if;\n",
      "    raise exception 'the plan changed while the proposal was built' using errcode = '55000';\n  end if;\n  -- A break must still fit when it is stored: dates from today to two days ahead, at most 42 days and\n  -- no overlap with another break.\n  if p_payload ? 'pause' and private.training_pause_problem(p_user_id,\n      (p_payload -> 'pause' ->> 'start_date')::date, (p_payload -> 'pause' ->> 'end_date')::date,\n      private.local_date_for(p_user_id)) is not null then\n    raise exception 'the break no longer fits' using errcode = '55000';\n  end if;\n",
    ],
  ];
  await pinned(
    "20261024060425_deload_origin_and_undo_cooldown.sql",
    "create or replace function public.persist_coach_proposal_v1(",
    "create or replace function public.persist_coach_proposal_v1(",
    "end $$;",
    hunks,
  );
});

Deno.test("respond_to_coach_proposal_v1 is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "  goal_floor numeric;\nbegin\n",
      "  goal_floor numeric;\n  pause_change jsonb;\n  new_pause_id uuid;\nbegin\n",
    ],
    [
      "  goal_change := proposal.proposal_payload -> 'goal';\n",
      "  goal_change := proposal.proposal_payload -> 'goal';\n  pause_change := proposal.proposal_payload -> 'pause';\n  -- Breaks are set one at a time per athlete (start_training_pause_v1 holds the same lock).\n  if pause_change is not null then\n    perform pg_advisory_xact_lock(hashtextextended('tracend.training_pause:' || auth.uid()::text, 0));\n  end if;\n",
    ],
    [
      "    when proposal.basis -> 'profile_check' is distinct from",
      "    when pause_change is null and proposal.basis -> 'profile_check' is distinct from",
    ],
    [
      "    when proposal.basis ->> 'weight_check_kg' is not null",
      "    when pause_change is null and proposal.basis ->> 'weight_check_kg' is not null",
    ],
    [
      "    else null end;\n",
      "    when pause_change is not null and (pause_change ->> 'start_date')::date < today then 'dates_passed'\n    when pause_change is not null and private.training_pause_problem(auth.uid(),\n      (pause_change ->> 'start_date')::date, (pause_change ->> 'end_date')::date, today) is not null\n      then 'pause_overlaps'\n    else null end;\n",
    ],
    [
      "    perform private.assert_screening_allows(auth.uid(), proposal.basis ->> 'screening');\n",
      "    -- A break only rests, so the health check never holds one back.\n    if pause_change is null then\n      perform private.assert_screening_allows(auth.uid(), proposal.basis ->> 'screening');\n    end if;\n",
    ],
    [
      "    update public.change_proposals set status = 'accepted'",
      "    if pause_change is not null then\n      new_pause_id := private.insert_training_pause(auth.uid(), (pause_change ->> 'start_date')::date,\n        (pause_change ->> 'end_date')::date, pause_change ->> 'reason', pause_change ->> 'note',\n        'coach', proposal.id);\n      applied := applied || jsonb_build_object('pause_id', new_pause_id);\n    end if;\n\n    update public.change_proposals set status = 'accepted'",
    ],
    [
      "        'goal_id', new_goal_id));",
      "        'goal_id', new_goal_id, 'pause_id', new_pause_id));",
    ],
  ];
  await pinned(
    "20261024060325_deload_cardio_review_fixes.sql",
    "create or replace function public.respond_to_coach_proposal_v1(",
    "create or replace function public.respond_to_coach_proposal_v1(",
    "end $$;",
    hunks,
  );
});

Deno.test("undo_coach_proposal_v1 is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "create function public.undo_coach_proposal_v1(",
      "create or replace function public.undo_coach_proposal_v1(",
    ],
    [
      "  update public.change_proposals set undone_at = undone_at_value where id = proposal.id;\n",
      "  if applied ? 'pause_id' then\n    perform pg_advisory_xact_lock(hashtextextended('tracend.training_pause:' || auth.uid()::text, 0));\n    perform private.end_training_pause(auth.uid(), (applied ->> 'pause_id')::uuid, 'undone',\n      private.local_date_for(auth.uid()));\n  end if;\n\n  update public.change_proposals set undone_at = undone_at_value where id = proposal.id;\n",
    ],
    [
      "      'goal_id', restored_goal));",
      "      'goal_id', restored_goal, 'pause_id', applied -> 'pause_id'));",
    ],
  ];
  await pinned(
    "20261018120018_coach_proposals.sql",
    "create function public.undo_coach_proposal_v1(",
    "create or replace function public.undo_coach_proposal_v1(",
    "end $$;",
    hunks,
  );
});

Deno.test("get_my_daily_brief is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "    return jsonb_build_object('schema_version', '1.8',",
      "    return jsonb_build_object('schema_version', '1.9',",
    ],
    [
      "  return jsonb_build_object(\n    'schema_version', '1.8',\n",
      "  return jsonb_build_object(\n    'schema_version', '1.9',\n    'availability', private.availability_on(v_user_id, target_date, false),\n",
    ],
    [
      "        'planned', exists (\n          select 1\n          from public.planned_workouts w\n",
      "        -- A day a break covers is not planned unless a session was logged on it (it then counts\n        -- as planned and trained, as in the hub's adherence); paused says which days it covers.\n        'paused', private.is_paused_on(v_user_id, d.day),\n        'planned', (not private.is_paused_on(v_user_id, d.day) or exists (\n          select 1 from public.workout_sessions s\n          where s.user_id = v_user_id\n            and s.local_date = d.day\n            and s.state = 'completed')) and exists (\n          select 1\n          from public.planned_workouts w\n",
    ],
  ];
  await pinned(
    "20261004160000_recovery_modes.sql",
    "create or replace function public.get_my_daily_brief(",
    "create or replace function public.get_my_daily_brief(",
    "end;\n$$;",
    hunks,
  );
});

Deno.test("get_my_training_hub is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "  order by dcm.computed_at desc\n  limit 1\n)\nselect jsonb_build_object(",
      "  order by dcm.computed_at desc\n  limit 1\n), paused_sessions as (\n  -- Planned sessions on days a break covers: neither due nor missed, so left out of adherence. A\n  -- day a session was logged on stays planned, so done never passes planned.\n  select count(*)::integer as n\n  from private.paused_days(auth.uid(),\n    (select today from local_day)-greatest(7,least(period_days,365))+1,\n    (select today from local_day)) d\n  join workouts w on w.preferred_weekday=extract(isodow from d)::integer\n  where not exists (select 1 from completed c where c.local_date=d)\n)\nselect jsonb_build_object(",
    ],
    [
      "'schema_version','1.9'",
      "'schema_version','1.10'",
    ],
    [
      "    'planned_sessions',coalesce((select sessions_per_week from active_version),0)\n      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)),\n",
      "    'planned_sessions',greatest(0,coalesce((select sessions_per_week from active_version),0)\n      * greatest(1,ceil(greatest(7,least(period_days,365))/7.0)::integer)\n      - (select n from paused_sessions)),\n    'paused_sessions',(select n from paused_sessions)),\n",
    ],
    [
      "  'next_targets',private.next_session_targets(auth.uid())\n);",
      "  'next_targets',private.next_session_targets(auth.uid()),\n  'availability',private.availability_on(auth.uid(),(select today from local_day),false),\n  'paused_days',coalesce((select jsonb_agg(d order by d) from private.paused_days(auth.uid(),\n    (select today from local_day)-greatest(7,least(period_days,365))+1,\n    (select today from local_day)+13) d),'[]'::jsonb)\n);",
    ],
  ];
  await pinned(
    "20261024090000_training_day_integrity.sql",
    "create or replace function public.get_my_training_hub(",
    "create or replace function public.get_my_training_hub(",
    "\n$$;",
    hunks,
  );
});

Deno.test("day_adjustment_explanation is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "  if p_band = 'unknown' then\n",
      "  if 'paused' = any(p_triggers) then\n    return 'Rest day: you''re on a break, so no session is due today.';\n  end if;\n  if p_band = 'unknown' then\n",
    ],
    [
      "    return 'You said you can''t train today. Nothing in your plan changes.';",
      "    return 'Rest day: you said you can''t train today.';",
    ],
  ];
  await pinned(
    "20261024060025_pain_checks.sql",
    "create or replace function private.day_adjustment_explanation(",
    "create or replace function private.day_adjustment_explanation(",
    "end $$;",
    hunks,
  );
});

Deno.test("day_adjustment_compute is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "  hold_codes text[];\nbegin\n",
      "  hold_codes text[];\n  paused boolean := private.is_paused_on(p_user, p_date);\nbegin\n",
    ],
    [
      "  triggers := array(select jsonb_array_elements_text(assessment -> 'triggers'));\n",
      "  triggers := array(select jsonb_array_elements_text(assessment -> 'triggers'));\n  -- A day in a break the athlete approved is a rest they chose.\n  if paused then triggers := triggers || array['paused']; end if;\n",
    ],
    [
      "  kind := case when unavailable is not null or safety is not null then 'none'",
      "  kind := case when unavailable is not null or safety is not null or paused then 'none'",
    ],
    [
      "    if can_hold and not joint_only then",
      "    if can_hold and not joint_only and not paused then",
    ],
    [
      "    if can_reduce and not joint_only then",
      "    if can_reduce and not joint_only and not paused then",
    ],
    [
      "    if (swap_c ->> 'sets_from')::integer > 0 and not joint_only then",
      "    if (swap_c ->> 'sets_from')::integer > 0 and not joint_only and not paused then",
    ],
  ];
  await pinned(
    "20261024090000_training_day_integrity.sql",
    "create or replace function private.day_adjustment_compute(",
    "create or replace function private.day_adjustment_compute(",
    "end $$;",
    hunks,
  );
});

Deno.test("get_readiness_context_v1 is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "create function public.get_readiness_context_v1(",
      "create or replace function public.get_readiness_context_v1(",
    ],
    [
      "    'rules_version', presented -> 'rules_version');",
      "    'rules_version', presented -> 'rules_version',\n    'athlete_unavailable', coalesce(presented -> 'triggers' ? 'not_available', false));",
    ],
  ];
  await pinned(
    "20261024060025_pain_checks.sql",
    "create function public.get_readiness_context_v1(",
    "create or replace function public.get_readiness_context_v1(",
    "end $$;",
    hunks,
  );
});

Deno.test("prepare_daily_coaching_core is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "create function private.prepare_daily_coaching_core(",
      "create or replace function private.prepare_daily_coaching_core(",
    ],
    [
      "  snapshot_hash text; metrics_jsonb jsonb; eligibility_jsonb jsonb;\n",
      "  snapshot_hash text; metrics_jsonb jsonb; eligibility_jsonb jsonb;\n  paused boolean;\n",
    ],
    [
      "  if health.id is null then missing := missing || array['health_context']; end if;\n",
      "  if health.id is null then missing := missing || array['health_context']; end if;\n  -- A rest the athlete chose (a break they approved, or today's check-in saying they cannot train)\n  -- is honoured: the decision rests as chosen and never proceeds with the planned session.\n  -- Escalation keeps its precedence.\n  paused := private.is_paused_on(target_user_id, coaching_date);\n  if outcome <> 'escalate' and (paused or check_in.available_to_train is false) then\n    outcome := 'rest_as_chosen';\n    rules := array[case when paused then 'TRAINING_PAUSED' else 'ATHLETE_UNAVAILABLE_TODAY' end];\n  end if;\n",
    ],
    [
      "    health.id is not null\n  );\n",
      "    health.id is not null\n  );\n  if outcome = 'rest_as_chosen' then evidence := evidence || rules; end if;\n",
    ],
    [
      "case outcome when 'escalate' then array['ESCALATE'] when 'request_data'",
      "case outcome when 'escalate' then array['ESCALATE'] when 'rest_as_chosen' then array['REST_AS_CHOSEN','MAINTAIN_TARGETS','PRIORITIZE_PROTEIN'] when 'request_data'",
    ],
  ];
  await pinned(
    "20261017170019_coach_chat_local_date_no_plan.sql",
    "create function private.prepare_daily_coaching_core(",
    "create or replace function private.prepare_daily_coaching_core(",
    "end $$;",
    hunks,
  );
});

Deno.test("persist_daily_coaching_result_v2 is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "    'DATA_CONFIDENCE_HIGH','DATA_CONFIDENCE_LOW'])))",
      "    'DATA_CONFIDENCE_HIGH','DATA_CONFIDENCE_LOW',\n    'ATHLETE_UNAVAILABLE_TODAY','TRAINING_PAUSED'])))",
    ],
  ];
  await pinned(
    "20261015120011_provider_neutral_ai.sql",
    "create or replace function public.persist_daily_coaching_result_v2(",
    "create or replace function public.persist_daily_coaching_result_v2(",
    "end $$;",
    hunks,
  );
});

Deno.test("prepare_coach_chat_v5 is its latest earlier definition plus the standing-state hunks only", async () => {
  const hunks: Hunks = [
    [
      "  narrative jsonb; preferences jsonb; journal jsonb;\n",
      "  narrative jsonb; preferences jsonb;\n",
    ],
    [
      "  c := c || jsonb_build_object('active_preferences', preferences);\n\n  select coalesce(jsonb_agg(entry), '[]'::jsonb) into journal\n    from (\n      select jsonb_build_object('coaching_date', s.coaching_date, 'summary', s.summary, 'thread_id', s.thread_id) entry\n      from public.coach_session_summaries s where s.user_id = target_user_id\n      order by s.coaching_date desc limit 5\n    ) sub;\n  c := c || jsonb_build_object('session_journal', journal);\n\n",
      "  c := c || jsonb_build_object('active_preferences', preferences);\n\n",
    ],
    [
      "       from (select jsonb_array_elements(c->'recent_other_conversations') elem limit 10) s),\n      'session_journal',\n      (select coalesce(jsonb_agg(elem), '[]'::jsonb)\n       from (select jsonb_array_elements(c->'session_journal') elem limit 5) s),\n",
      "       from (select jsonb_array_elements(c->'recent_other_conversations') elem limit 10) s),\n",
    ],
  ];
  await pinned(
    "20260719090000_context_budget_guard.sql",
    "create or replace function public.prepare_coach_chat_v5(",
    "create or replace function public.prepare_coach_chat_v5(",
    "end $$;",
    hunks,
  );
});
