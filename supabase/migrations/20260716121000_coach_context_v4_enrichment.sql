create or replace function public.prepare_coach_chat_v4(
  target_user_id uuid, target_thread_id uuid, question text,
  coaching_timezone text, request_idempotency_key uuid, context_kind text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare
  prepared jsonb; c jsonb; coaching_date date;
  snapshot_id uuid; checksum text; ctx_kind text;
begin
  ctx_kind := case
    when context_kind in ('daily_action','plan_change','explain_evidence','nutrition_focus','recovery')
      then context_kind
    else 'general'
  end;

  prepared := public.prepare_coach_chat_v2(target_user_id, target_thread_id, question,
    coaching_timezone, request_idempotency_key);
  if coalesce((prepared->>'replayed')::boolean, false) then return prepared; end if;

  c := prepared->'context';
  coaching_date := coalesce((c->>'coaching_date')::date, current_date);
  c := c || jsonb_build_object('schema_version', '2.0', 'context_kind', ctx_kind);

  if ctx_kind = 'daily_action' then
    c := c || jsonb_build_object(
      'focused_execution', (select coalesce(jsonb_agg(session_data order by local_date desc), '[]'::jsonb) from (
        select s.local_date, jsonb_build_object(
          'evidence_id', 'TRAINING.SESSION.' || s.local_date || '.' || s.id,
          'session_id', s.id, 'local_date', s.local_date,
          'prescribed_workout', w.name,
          'duration_seconds', s.duration_seconds,
          'logging_completeness', s.logging_completeness,
          'effort', s.session_effort,
          'exercise_count', (select count(*) from public.exercise_performances ep where ep.workout_session_id = s.id),
          'set_count', (select count(*) from public.exercise_performances ep join public.exercise_sets es on es.exercise_performance_id = ep.id where ep.workout_session_id = s.id),
          'completion_rate', s.logging_completeness
        ) session_data
        from public.workout_sessions s
        join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
        where s.user_id = target_user_id and s.state = 'completed'
        order by s.local_date desc limit 2
      ) sessions),
      'today_healthkit', (select jsonb_build_object(
        'local_date', local_date, 'steps', steps, 'active_energy_kcal', active_energy_kcal,
        'sleep_minutes', sleep_minutes, 'resting_heart_rate_bpm', resting_heart_rate_bpm,
        'hrv_value_ms', hrv_value_ms, 'completeness', completeness
      ) from public.daily_health_summaries where user_id = target_user_id
        order by local_date desc limit 1),
      'latest_measurement', (select jsonb_build_object(
        'measured_on', measured_on, 'weight_kg', weight_kg, 'source', source
      ) from public.body_measurements where user_id = target_user_id
        order by measured_on desc, created_at desc limit 1)
    );

  elsif ctx_kind = 'plan_change' then
    c := c || jsonb_build_object(
      'session_trends', '[]'::jsonb,
      'plan_proposals', '[]'::jsonb,
      'data_quality', jsonb_build_object('placeholder', true)
    );

  elsif ctx_kind = 'explain_evidence' then
    c := c || jsonb_build_object(
      'evidence_freshness', jsonb_build_object(
        'last_health_sync', (select max(last_synced_at) from public.daily_health_summaries where user_id = target_user_id),
        'last_check_in', (select max(local_date) from public.daily_check_ins where user_id = target_user_id and superseded_at is null),
        'last_meal_confirmed', (select max(created_at) from public.meals where user_id = target_user_id and status = 'confirmed'),
        'last_measurement', (select max(measured_on) from public.body_measurements where user_id = target_user_id),
        'last_completed_workout', (select max(local_date) from public.workout_sessions where user_id = target_user_id and state = 'completed')
      ),
      'data_quality', jsonb_build_object(
        'training_logging_coverage', (select coalesce(avg(logging_completeness), 0) from public.workout_sessions where user_id = target_user_id and state = 'completed' and local_date >= coaching_date - 27),
        'last_health_sync', (select max(last_synced_at) from public.daily_health_summaries where user_id = target_user_id),
        'last_confirmed_meal', (select max(created_at) from public.meals where user_id = target_user_id and status = 'confirmed')
      ),
      'evidence_contract', jsonb_build_object(
        'facts_are_authoritative', true,
        'conversation_cannot_override_facts', true,
        'unknown_is_not_skipped', true,
        'persistent_changes_require_approval', true
      )
    );

  elsif ctx_kind = 'nutrition_focus' then
    c := c || jsonb_build_object(
      'today_confirmed_meals', (select coalesce(jsonb_agg(meal_data order by created_at desc), '[]'::jsonb) from (
        select m.created_at, m.local_date,
          (select coalesce(jsonb_agg(jsonb_build_object(
            'food', mi.food_name_override, 'serving', mi.serving_description,
            'calories', mi.calories, 'protein_g', mi.protein_g,
            'carbohydrate_g', mi.carbohydrate_g, 'fat_g', mi.fat_g, 'status', mi.status
          )), '[]'::jsonb)
          from public.meal_items mi where mi.meal_id = m.id and mi.user_id = m.user_id) foods
        from public.meals m
        where m.user_id = target_user_id and m.status = 'confirmed'
          and m.local_date = coaching_date
        order by m.created_at desc limit 2
      ) meals),
      'nutrition_compliance_7day', (select jsonb_build_object(
        'avg_daily_calories', (select round(coalesce(avg(day_cal), 0)::numeric, 0)
          from (select m.local_date, coalesce(sum(mi.calories), 0) day_cal
            from public.meals m join public.meal_items mi on mi.meal_id = m.id and mi.user_id = m.user_id
            where m.user_id = target_user_id and m.status = 'confirmed'
              and m.local_date between coaching_date - 6 and coaching_date
            group by m.local_date) days),
        'avg_daily_protein_g', (select round(coalesce(avg(day_pro), 0)::numeric, 0)
          from (select m.local_date, coalesce(sum(mi.protein_g), 0) day_pro
            from public.meals m join public.meal_items mi on mi.meal_id = m.id and mi.user_id = m.user_id
            where m.user_id = target_user_id and m.status = 'confirmed'
              and m.local_date between coaching_date - 6 and coaching_date
            group by m.local_date) days)
      )),
      'latest_weight', (select jsonb_build_object(
        'measured_on', measured_on, 'weight_kg', weight_kg
      ) from public.body_measurements where user_id = target_user_id
        order by measured_on desc limit 1)
    );

  elsif ctx_kind = 'recovery' then
    c := c || jsonb_build_object(
      'latest_healthkit', (select jsonb_build_object(
        'local_date', local_date, 'resting_heart_rate_bpm', resting_heart_rate_bpm,
        'hrv_value_ms', hrv_value_ms, 'sleep_minutes', sleep_minutes, 'completeness', completeness
      ) from public.daily_health_summaries where user_id = target_user_id
        order by local_date desc limit 1),
      'latest_check_in_detail', (select jsonb_build_object(
        'local_date', local_date, 'sleep_quality', sleep_quality,
        'energy', energy, 'soreness', soreness, 'mood', mood,
        'pain_severity', pain_severity, 'available_to_train', available_to_train, 'hunger', hunger
      ) from public.daily_check_ins where user_id = target_user_id
        and superseded_at is null order by local_date desc limit 1),
      'last_3_sessions_summary', (select coalesce(jsonb_agg(session_data order by local_date desc), '[]'::jsonb) from (
        select s.local_date, jsonb_build_object(
          'local_date', s.local_date, 'prescribed_workout', w.name,
          'duration_seconds', s.duration_seconds, 'effort', s.session_effort,
          'logging_completeness', s.logging_completeness
        ) session_data
        from public.workout_sessions s
        join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
        where s.user_id = target_user_id and s.state = 'completed'
        order by s.local_date desc limit 3
      ) sessions),
      'training_week_structure', (select jsonb_build_object(
        'sessions_per_week', v.sessions_per_week, 'block_weeks', v.block_weeks,
        'planned_workouts', (select coalesce(jsonb_agg(jsonb_build_object(
          'name', pw.name, 'target_day', pw.target_day_of_week, 'target_week', pw.target_week_of_block
        ) order by pw.target_day_of_week, pw.target_week_of_block), '[]'::jsonb)
        from public.planned_workouts pw
        join public.training_plan_versions pv on pv.id = pw.plan_version_id and pv.user_id = pw.user_id
        where pw.user_id = target_user_id and pv.status = 'active')
      ) from public.training_plan_versions v where v.user_id = target_user_id and v.status = 'active' limit 1)
    );

  else
    c := c || jsonb_build_object(
      'brief_sessions', (select coalesce(jsonb_agg(session_data order by local_date desc), '[]'::jsonb) from (
        select s.local_date, jsonb_build_object(
          'local_date', s.local_date, 'prescribed_workout', w.name,
          'duration_seconds', s.duration_seconds, 'logging_completeness', s.logging_completeness
        ) session_data
        from public.workout_sessions s
        join public.planned_workouts w on w.id = s.planned_workout_id and w.user_id = s.user_id
        where s.user_id = target_user_id and s.state = 'completed'
        order by s.local_date desc limit 2
      ) sessions),
      'brief_measurements', (select coalesce(jsonb_agg(measurement order by measured_on desc), '[]'::jsonb) from (
        select measured_on, jsonb_build_object('measured_on', measured_on, 'weight_kg', weight_kg, 'waist_cm', waist_cm) measurement
        from public.body_measurements where user_id = target_user_id order by measured_on desc limit 2
      ) measurements),
      'brief_health', (select coalesce(jsonb_agg(day_data order by local_date desc), '[]'::jsonb) from (
        select local_date, jsonb_build_object(
          'local_date', local_date, 'resting_heart_rate_bpm', resting_heart_rate_bpm,
          'hrv_value_ms', hrv_value_ms, 'sleep_minutes', sleep_minutes, 'completeness', completeness
        ) day_data
        from public.daily_health_summaries where user_id = target_user_id
        order by local_date desc limit 2
      ) health_days),
      'today_meal_schedule', (select coalesce(jsonb_agg(jsonb_build_object(
        'slot_key', i.slot_key, 'label', i.label,
        'local_time', to_char(i.local_time, 'HH24:MI'), 'foods', i.foods
      ) order by i.item_order), '[]'::jsonb)
      from public.nutrition_schedule_items i
      join public.nutrition_schedule_versions v on v.id = i.schedule_version_id and v.user_id = i.user_id
      where i.user_id = target_user_id and v.status = 'active')
    );
  end if;

  checksum := encode(extensions.digest(convert_to(c::text, 'UTF8'), 'sha256'), 'hex');
  insert into public.coach_context_snapshots(user_id, thread_id, schema_version, trigger_kind, coaching_date, context, context_checksum)
  values(target_user_id, target_thread_id, '2.0', 'chat', coaching_date, c, checksum) returning id into snapshot_id;
  return prepared || jsonb_build_object('context', c, 'coach_context_snapshot_id', snapshot_id);
end $$;
