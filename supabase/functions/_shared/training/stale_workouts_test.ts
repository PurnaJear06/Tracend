import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";

const migration = new URL(
  "../../../migrations/20261023150021_close_stale_workouts.sql",
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
  assert(
    !/set[^;]*\b(local_date|actual_ended_at)\s*=/i.test(code),
    "no date or end time is rewritten",
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
