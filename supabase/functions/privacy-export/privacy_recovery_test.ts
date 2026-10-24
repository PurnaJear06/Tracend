import { assert, assertEquals } from "jsr:@std/assert@1.0.14";

// The recovery migration redefines three functions. Each must be its latest earlier definition plus
// the intended hunks and nothing else, so what it does besides is what the earlier migration (and
// its pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url));
const recovery = await read("20261024070000_privacy_retention_recovery.sql");
const exportBase = await read("20260703150000_phase_8_privacy_export.sql");
const accountBoundary = await read("20261009130000_account_boundary.sql");
const mealRetention = await read("20260702130000_phase_6_meal_corrections_retention.sql");

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
  return text.trim();
}

const orReplace: readonly [string, string] = ["create function", "create or replace function"];

Deno.test("claim_data_export is the original plus the stale-processing hunk only", () => {
  const earlier = between(exportBase, "create function public.claim_data_export(", "$$;");
  const redefined = between(
    recovery,
    "create or replace function public.claim_data_export(",
    "$$;",
  );
  assertEquals(
    undo(redefined, [
      orReplace,
      [
        "  where id = target_export_id and status = 'queued'\n",
        "  where id = target_export_id\n    and (status = 'queued'\n      -- new: a worker that stopped leaves the export processing; take it again after 15 minutes\n      or (status = 'processing'\n        and coalesce(started_at, created_at) < now() - interval '15 minutes'))\n",
      ],
    ]),
    earlier.trim(),
  );
});

Deno.test("request_my_data_export is the account-boundary version plus the dead-export hunk only", () => {
  const earlier = between(
    accountBoundary,
    "create or replace function public.request_my_data_export()",
    "$$;",
  );
  const redefined = between(
    recovery,
    "create or replace function public.request_my_data_export()",
    "$$;",
  );
  assertEquals(
    undo(redefined, [
      [
        "  select id into existing_id from public.data_exports\n",
        "  -- new: a ready export that has expired or used its downloads is not an open export\n  update public.data_exports set status = 'expired'\n  where user_id = auth.uid() and status = 'ready'\n    and (expires_at <= now() or download_count >= 3);\n  select id into existing_id from public.data_exports\n",
      ],
    ]),
    earlier.trim(),
  );
});

Deno.test("claim_expired_meal_media is the original plus the stale-claim hunks only", () => {
  const earlier = between(
    mealRetention,
    "create function public.claim_expired_meal_media(",
    "$$;",
  );
  const redefined = between(
    recovery,
    "create or replace function public.claim_expired_meal_media(",
    "$$;",
  );
  assertEquals(
    undo(redefined, [
      orReplace,
      [
        "    where lifecycle_status = 'active'\n      and not retention_exempt\n      and retention_deadline <= now()\n",
        "    where ((lifecycle_status = 'active'\n      and not retention_exempt\n      and retention_deadline <= now())\n      -- new: a claim whose worker never wrote the result back is handed out again after 30 minutes\n      or (lifecycle_status = 'pending_deletion'\n        and not retention_exempt\n        and coalesce(retention_claimed_at, '-infinity'::timestamptz) < now() - interval '30 minutes'))\n",
      ],
      [
        "  set lifecycle_status = 'pending_deletion'\n",
        "  set lifecycle_status = 'pending_deletion',\n      retention_claimed_at = now()\n",
      ],
    ]),
    earlier.trim(),
  );
});

Deno.test("each redefined function keeps security definer, an empty search_path and its grants", () => {
  for (
    const name of [
      "public.claim_data_export(uuid)",
      "public.request_my_data_export()",
      "public.claim_expired_meal_media(integer)",
    ]
  ) {
    const from = recovery.indexOf(`create or replace function ${name.split("(")[0]}(`);
    assert(from >= 0, name);
    const header = recovery.slice(from, recovery.indexOf("as $$", from));
    assert(header.includes("security definer"), `${name} security definer`);
    assert(header.includes("set search_path = ''"), `${name} search_path`);
    assert(
      recovery.includes(`revoke all on function ${name}`) &&
        recovery.includes(`grant execute on function ${name} to`),
      `${name} grants`,
    );
  }
});

Deno.test("the migration only adds: one nullable column, one index, three function bodies", () => {
  const sql = recovery.split("\n").filter((line) => !line.startsWith("--")).join("\n");
  assert(!/\bdrop\s+(table|column|function)/i.test(sql));
  assert(!/\brename\b/i.test(sql));
  assertEquals(
    sql.match(/alter table public\.media_objects add column retention_claimed_at timestamptz;/g)
      ?.length,
    1,
  );
});

Deno.test("photos already pending deletion are backfilled as claimed at migration time", () => {
  const column = recovery.indexOf("add column retention_claimed_at timestamptz;");
  const backfill = recovery.indexOf(
    "update public.media_objects set retention_claimed_at = now()\nwhere lifecycle_status = 'pending_deletion';",
  );
  assert(column >= 0 && backfill > column, "the backfill follows the new column");
});

Deno.test("the linked-rows export leaves out the invitee note, token hashes and referral link", () => {
  const body = between(recovery, "create function public.export_linked_account_rows_v1(", "$$;");
  for (const left of ["note", "token_hash", "referred_by", "claimed_by,"]) {
    assert(
      !body.includes(`'${left}'`) && !body.includes(`s.${left}`) && !body.includes(`i.${left}`),
      left,
    );
  }
  assert(body.includes("i.claimed_by = target_user_id"));
  assert(/set search_path = ''/.test(body) && /security definer/.test(body));
});

Deno.test("the retention cron job replaces the hand-made one, posts only through Vault and holds no secret", () => {
  assert(recovery.includes("perform cron.unschedule('meal-media-retention-daily')"));
  assert(
    recovery.includes(
      "select cron.schedule(\n  'meal-media-retention-daily',\n  '15 2 * * *',\n  'select private.meal_media_retention_kick()'\n);",
    ),
  );
  const kick = between(recovery, "create function private.meal_media_retention_kick()", "$$;");
  assert(kick.includes("name = 'meal_media_retention_url'"));
  assert(kick.includes("name = 'retention_worker_secret'"));
  assert(kick.includes("'Bearer ' || worker_secret"));
  assert(!/[0-9a-f]{32}/i.test(recovery), "no secret-looking value in the migration");
  assert(!/Bearer\s+[A-Za-z0-9]/.test(recovery.replaceAll("'Bearer '", "")));
});
