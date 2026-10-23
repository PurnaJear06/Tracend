import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";

const migration = new URL(
  "../../../migrations/20261023150021_close_stale_workouts.sql",
  import.meta.url,
);
const trainRedesign = new URL(
  "../../../migrations/20261003100000_train_redesign_data.sql",
  import.meta.url,
);
const dayAdjustments = new URL(
  "../../../migrations/20261023140024_day_adjustments.sql",
  import.meta.url,
);
const previous = new URL(
  "../../../migrations/20261015140031_set_timing.sql",
  import.meta.url,
);

const functionText = (sql: string) => {
  const from = sql.indexOf("create or replace function public.get_my_workout_session");
  return sql.slice(from, sql.indexOf("end $$;", from) + "end $$;".length);
};

// get_my_workout_session was redefined only to close the caller's stale sessions first. It is
// set timing's 1.1 text plus exactly these hunks, so the answer's shape and the lookup are
// unchanged and the app needs no new build.
Deno.test("the redefined get_my_workout_session is set timing's function plus the stale close only", async () => {
  const original = functionText(await Deno.readTextFile(previous));
  const redefined = functionText(await Deno.readTextFile(migration));
  const hunks: readonly (readonly [string, string])[] = [
    [
      "returns jsonb language plpgsql security definer set search_path='' as $$",
      "returns jsonb language plpgsql security invoker set search_path='' stable as $$",
    ],
    [
      `errcode='42501'; end if;
  perform private.abandon_stale_workouts(auth.uid());
`,
      `errcode='42501'; end if;
`,
    ],
  ];
  let undone = redefined;
  for (const [added, was] of hunks) {
    assert(undone.includes(added), `missing hunk: ${added.slice(0, 60)}`);
    undone = undone.replace(added, () => was);
  }
  assertEquals(undone.trim(), original.trim());
});

Deno.test("the stale rule closes only an earlier local day past the three hour cap, and deletes nothing", async () => {
  const sql = await Deno.readTextFile(migration);
  const code = sql.split("\n").filter((line) => !line.trimStart().startsWith("--")).join("\n");
  assertStringIncludes(code, "s.local_date < private.local_date_for(s.user_id)");
  assertStringIncludes(code, "statement_timestamp() - interval '10800 seconds'");
  assertStringIncludes(code, "set state = 'abandoned', updated_at = now()");
  assert(!/\bdelete\b/i.test(code), "no delete");
  const rule = code.slice(
    code.indexOf("create function private.abandon_stale_workouts"),
    code.indexOf("revoke all on function private.abandon_stale_workouts"),
  );
  assert(
    !/set[^;]*\b(local_date|actual_ended_at)\s*=/i.test(rule),
    "the close rewrites no date or end time",
  );
});

Deno.test("the migration keeps the grants and the hourly job", async () => {
  const sql = await Deno.readTextFile(migration);
  assertStringIncludes(
    sql,
    "revoke all on function private.abandon_stale_workouts(uuid) from public, anon, authenticated;",
  );
  assertStringIncludes(
    sql,
    "grant execute on function public.get_my_workout_session(uuid, date) to authenticated;",
  );
  assertStringIncludes(sql, "select cron.schedule('tracend-abandon-stale-workouts'");
});

const between = (sql: string, start: string, end: string) => {
  const from = sql.indexOf(start);
  return sql.slice(from, sql.indexOf(end, from) + end.length);
};

// A workout finished offline can reach the server after the rule closed it. The two writers it
// needs are the earlier functions plus exactly these hunks: the discard check lets through a
// session closed by the rule (never one the athlete discarded), and its end is its own start plus
// its own duration.
Deno.test("sync_workout_draft accepts a session the rule closed and nothing else new", async () => {
  const start = "create or replace function public.sync_workout_draft";
  const original = between(await Deno.readTextFile(previous), start, "end $$;");
  const redefined = between(await Deno.readTextFile(migration), start, "end $$;");
  const added = `  if session.state <> 'in_progress'
    and not (session.state = 'abandoned' and private.workout_closed_as_stale(session.id)) then
    raise exception 'session is immutable' using errcode='55000';
  end if;`;
  const was =
    "  if session.state <> 'in_progress' then raise exception 'session is immutable' using errcode='55000'; end if;";
  assert(redefined.includes(added), "missing hunk");
  assertEquals(redefined.replace(added, () => was).trim(), original.trim());
});

Deno.test("complete_workout_session finishes a rule-closed session on its own date and nothing else new", async () => {
  const original = between(
    await Deno.readTextFile(trainRedesign),
    "create function private.complete_workout_session",
    "end $$;",
  );
  const redefined = between(
    await Deno.readTextFile(migration),
    "create or replace function private.complete_workout_session",
    "end $$;",
  );
  const hunks: readonly (readonly [string, string])[] = [
    ["create or replace function", "create function"],
    ["capped_duration integer; closed_as_stale boolean;", "capped_duration integer;"],
    [
      `  closed_as_stale := session.state = 'abandoned' and private.workout_closed_as_stale(session.id);
  if session.state = 'abandoned' and not closed_as_stale then`,
      "  if session.state = 'abandoned' then",
    ],
    [
      `completed_at = now(),
    actual_ended_at = coalesce(actual_ended_at, case when closed_as_stale
      then least(now(), coalesce(actual_started_at, started_at) + capped_duration * interval '1 second')
      else now() end),`,
      "completed_at = now(), actual_ended_at = coalesce(actual_ended_at, now()),",
    ],
  ];
  let undone = redefined;
  for (const [added, was] of hunks) {
    assert(undone.includes(added), `missing hunk: ${added.slice(0, 60)}`);
    undone = undone.replace(added, () => was);
  }
  assertEquals(undone.trim(), original.trim());
});

Deno.test("only the rule's own close can be finished late", async () => {
  const sql = await Deno.readTextFile(migration);
  assertStringIncludes(sql, "e.metadata->>'reason' = 'stale'");
  assertStringIncludes(
    sql,
    "revoke all on function private.workout_closed_as_stale(uuid) from public, anon, authenticated;",
  );
});

// start_workout is the day adjustment migration's function (which keeps its advisory lock first)
// plus the close of the caller's stale sessions right before the open-session lookup.
Deno.test("start_workout is the day adjustment version plus the stale close only", async () => {
  const start = "create or replace function public.start_workout";
  const original = between(await Deno.readTextFile(dayAdjustments), start, "end $$;");
  const redefined = between(await Deno.readTextFile(migration), start, "end $$;");
  const added =
    `  -- A session left open from an earlier day is closed first, so it is never found as today's.
  perform private.abandon_stale_workouts(auth.uid());
`;
  assert(redefined.includes(added), "missing hunk");
  assertEquals(redefined.replace(added, () => "").trim(), original.trim());
  const lock = redefined.indexOf("pg_advisory_xact_lock");
  const close = redefined.indexOf("private.abandon_stale_workouts");
  const lookup = redefined.indexOf("state='in_progress'\n  order by started_at desc limit 1;");
  assert(lock > 0 && lock < close && close < lookup, "lock, then the close, then the lookup");
});
