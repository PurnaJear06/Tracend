import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

// The guidance performance migration replaces five functions. Each must be its latest earlier definition
// plus the one intended hunk (the pg_timezone_names join becomes private.known_timezone), so everything
// else it does is what the earlier migrations (and their pgTAP tests) already proved. The earlier
// definition is found by scanning the migrations before this one, newest first, never by a file name.
const migrations = new URL("../../../../migrations/", import.meta.url);
const read = (name: string) => Deno.readTextFile(new URL(name, migrations));
const perfName = "20261031110000_guidance_perf.sql";
const perf = await read(perfName);

function definitionIn(text: string, signature: string, file: string): string | null {
  const escaped = signature.replace(/[.()]/g, "\\$&");
  const found = new RegExp(`create (?:or replace )?function ${escaped}\\(`).exec(text);
  if (!found) return null;
  const ends = ["\n$$;", "end $$;"]
    .map((end) => ({ end, at: text.indexOf(end, found.index) }))
    .filter((e) => e.at > found.index)
    .sort((a, b) => a.at - b.at);
  assert(ends.length > 0, `${file} ends ${signature}`);
  return text.slice(found.index, ends[0].at + ends[0].end.length);
}

async function priorDefinition(signature: string): Promise<string> {
  const files: string[] = [];
  for await (const entry of Deno.readDir(migrations)) {
    if (entry.isFile && entry.name.endsWith(".sql") && entry.name < perfName) {
      files.push(entry.name);
    }
  }
  for (const file of files.sort().reverse()) {
    const found = definitionIn(await read(file), signature, file);
    if (found) return found;
  }
  throw new Error(`no earlier migration defines ${signature}`);
}

const orReplaceFirst = (text: string) =>
  text.replace(/^create function/, "create or replace function");

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
  return text.trim();
}

const join = "    join pg_catalog.pg_timezone_names z on z.name = a.timezone\n";
const known = (user: string) => `    where a.id = ${user} and private.known_timezone(a.timezone)`;
const was = (user: string) => `${join}    where a.id = ${user}`;

const readers: readonly (readonly [string, string])[] = [
  ["private.local_date_for", "target_user_id"],
  ["private.local_day_of", "p_user"],
  ["private.local_day", "p_user"],
  ["private.user_timezone", "p_user"],
];

for (const [signature, user] of readers) {
  Deno.test(`${signature} is its latest earlier definition with the zone join swapped for known_timezone`, async () => {
    const earlier = await priorDefinition(signature);
    const redefined = definitionIn(perf, signature, perfName);
    assert(redefined !== null, `${perfName} defines ${signature}`);
    assert(redefined.startsWith("create or replace function"), "it replaces, not creates");
    const hunks: Hunks = [[was(user), known(user)]];
    assertEquals(undo(redefined, hunks), orReplaceFirst(earlier).trim());
  });
}

Deno.test("deload_signals is its latest earlier definition with the zone join swapped for known_timezone", async () => {
  const earlier = await priorDefinition("private.deload_signals");
  const redefined = definitionIn(perf, "private.deload_signals", perfName);
  assert(redefined !== null);
  const hunks: Hunks = [[
    "  tz constant text := coalesce((select a.timezone from public.user_accounts a\n    join pg_catalog.pg_timezone_names z on z.name = a.timezone where a.id = p_user), 'UTC');",
    "  tz constant text := coalesce((select a.timezone from public.user_accounts a\n    where a.id = p_user and private.known_timezone(a.timezone)), 'UTC');",
  ]];
  assertEquals(undo(redefined, hunks), earlier.trim());
  // The replaced function keeps its grants: nothing but a revoke follows, as in the earlier one.
  assert(
    perf.includes(
      "revoke all on function private.deload_signals(uuid, date) from public, anon, authenticated;",
    ),
  );
});

Deno.test("known_timezone answers from the table first and from the view only for a name the table lacks", () => {
  const fn = definitionIn(perf, "private.known_timezone", perfName);
  assert(fn !== null);
  assert(fn.includes("security definer set search_path = ''"));
  // The table is asked first and the view only in the else branch, so a known name never reads the view.
  const body = fn.slice(fn.indexOf("select case"));
  assertEquals(
    body.replace(/\s+/g, " ").trim(),
    "select case when exists (select 1 from private.timezone_names t where t.name = zone) then true else exists (select 1 from pg_catalog.pg_timezone_names z where z.name = zone) end; $$;",
  );
  assert(
    perf.includes(
      "revoke all on function private.known_timezone(text) from public, anon, authenticated;",
    ),
  );
});

Deno.test("the zone table is filled from the view, closed to every API role, and nothing else reads the view per call", () => {
  assert(perf.includes("create table private.timezone_names (\n  name text primary key\n);"));
  assert(perf.includes("select z.name from pg_catalog.pg_timezone_names z;"));
  assert(perf.includes("alter table private.timezone_names enable row level security;"));
  assert(perf.includes("alter table private.timezone_names force row level security;"));
  assert(perf.includes("revoke all on private.timezone_names from public, anon, authenticated;"));
  // The view is read in the migration only by the one-time fill and by the fallback in known_timezone.
  const code = perf.split("\n").filter((line) => !line.startsWith("--")).join("\n");
  assertEquals(code.split("pg_catalog.pg_timezone_names").length - 1, 2);
});

Deno.test("the migration creates the table and one helper and replaces five functions, nothing more", () => {
  const code = perf.split("\n").filter((line) => !line.startsWith("--")).join("\n");
  const created = [...code.matchAll(/^create (?:or replace )?(function|table) ([\w.]+)/gm)]
    .map((m) => `${m[1]} ${m[2]}`);
  assertEquals(created, [
    "table private.timezone_names",
    "function private.known_timezone",
    "function private.local_date_for",
    "function private.local_day_of",
    "function private.local_day",
    "function private.user_timezone",
    "function private.deload_signals",
  ]);
});
