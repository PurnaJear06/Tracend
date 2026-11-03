import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

// The health-data consent migration redefines four functions. Each must be its latest earlier
// definition plus the consent check and nothing else, so everything else it does is what the
// earlier migration (and its pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url));
const enforced = await read("20261102213907_health_data_consent_enforced.sql");

function between(text: string, start: string, end: string): string {
  const from = text.indexOf(start);
  assert(from >= 0, `missing ${start}`);
  const to = text.indexOf(end, from);
  assert(to > from, `missing ${end}`);
  return text.slice(from, to + end.length);
}

// [was, added]: undoing replaces `added` with `was`.
function undo(redefined: string, hunks: readonly (readonly [string, string])[]): string {
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
  hunks: readonly (readonly [string, string])[],
) {
  const end = "end $$;";
  const earlier = between(await read(file), start, end);
  const redefined = between(enforced, redefinedStart, end);
  assertEquals(undo(redefined, hunks), earlier);
}

Deno.test("persist_health_sync_v2 is its latest earlier definition plus the consent check", async () => {
  const start = "create or replace function public.persist_health_sync_v2(";
  await pinned("20261009140000_abuse_limits.sql", start, start, [[
    "",
    "  if not private.health_data_consent_granted(target_user_id) then\n" +
    "    raise exception 'health data consent required' using errcode='P0403';\n" +
    "  end if;\n",
  ]]);
});

Deno.test("save_health_history is its latest earlier definition plus the consent check", async () => {
  await pinned(
    "20261002110000_coach_intake.sql",
    "create function public.save_health_history(",
    "create or replace function public.save_health_history(",
    [
      ["create function", "create or replace function"],
      [
        "",
        "  if not private.health_data_consent_granted(auth.uid()) then\n" +
        "    raise exception 'health data consent required' using errcode = 'P0403';\n" +
        "  end if;\n",
      ],
    ],
  );
});

Deno.test("persist_set_heart_rate_v1 is its latest earlier definition plus the consent check", async () => {
  await pinned(
    "20261016003032_set_heart_rate.sql",
    "create function public.persist_set_heart_rate_v1(",
    "create or replace function public.persist_set_heart_rate_v1(",
    [
      ["create function", "create or replace function"],
      [
        "",
        "  if not private.health_data_consent_granted(auth.uid()) then\n" +
        "    raise exception 'health data consent required' using errcode = 'P0403';\n" +
        "  end if;\n",
      ],
    ],
  );
});

Deno.test("persist_sleeping_heart_rate_v1 is its latest earlier definition plus the consent check", async () => {
  await pinned(
    "20261017150233_heart_rate_profile.sql",
    "create function public.persist_sleeping_heart_rate_v1(",
    "create or replace function public.persist_sleeping_heart_rate_v1(",
    [
      ["create function", "create or replace function"],
      [
        "",
        "  if not private.health_data_consent_granted(auth.uid()) then\n" +
        "    raise exception 'health data consent required' using errcode = 'P0403';\n" +
        "  end if;\n",
      ],
    ],
  );
});

Deno.test("no health-writing function was redefined after the migration it copies", async () => {
  // A later migration redefining one of them would make the copy above stale.
  const names = [
    "persist_health_sync_v2",
    "save_health_history",
    "persist_set_heart_rate_v1",
    "persist_sleeping_heart_rate_v1",
  ];
  const files: string[] = [];
  for await (const entry of Deno.readDir(new URL("../../migrations/", import.meta.url))) {
    if (entry.name > "20261102213907_health_data_consent_enforced.sql") files.push(entry.name);
  }
  for (const file of files) {
    const text = await read(file);
    for (const name of names) {
      assert(
        !new RegExp(`create (or replace )?function public\\.${name}\\(`, "i").test(text),
        `${file} redefines ${name}; copy its definition into the consent migration first`,
      );
    }
  }
});
