import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import suggested from "../../../../../test/contract/fixtures/training_guidance_v1_2.json" with {
  type: "json",
};
import coachPending from "../../../../../test/contract/fixtures/training_guidance_v1_2_coach_pending.json" with {
  type: "json",
};
import running from "../../../../../test/contract/fixtures/training_guidance_v1_2_running.json" with {
  type: "json",
};
import { parseTrainingGuidance } from "../guidance/payload.ts";

// The 1.2 migration replaces three functions and adds one. Each replaced function must be its latest
// earlier definition plus the intended hunks and nothing else, so everything else it does is what the
// earlier migrations (and their pgTAP tests) already proved. The earlier definition is found by
// scanning the migrations before this one, newest first, never by a file name.
const migrations = new URL("../../../../migrations/", import.meta.url);
const read = (name: string) => Deno.readTextFile(new URL(name, migrations));
const originName = "20261024060425_deload_origin_and_undo_cooldown.sql";
const origin = await read(originName);

async function priorDefinition(signature: string): Promise<string> {
  const files: string[] = [];
  for await (const entry of Deno.readDir(migrations)) {
    if (entry.isFile && entry.name.endsWith(".sql") && entry.name < originName) {
      files.push(entry.name);
    }
  }
  const escaped = signature.replace(/[.()]/g, "\\$&");
  const pattern = new RegExp(`create (?:or replace )?function ${escaped}\\(`);
  for (const file of files.sort().reverse()) {
    const text = await read(file);
    const found = pattern.exec(text);
    if (found) {
      const end = text.indexOf("end $$;", found.index);
      assert(end > found.index, `${file} ends ${signature}`);
      return text.slice(found.index, end + "end $$;".length);
    }
  }
  throw new Error(`no earlier migration defines ${signature}`);
}

const orReplaceFirst = (text: string) =>
  text.replace(/^create function/, "create or replace function");

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

Deno.test("deload_signals is the latest earlier function plus the origin, end date and undo cool-down only", async () => {
  const earlier = await priorDefinition("private.deload_signals");
  const redefined = between(
    origin,
    "create or replace function private.deload_signals(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "'weeks_since', null, 'proposal_id', null, 'suppressed_by', 'no_plan');",
      "'weeks_since', null, 'proposal_id', null, 'proposal_origin', null, 'ends_on', null,\n      'suppressed_by', 'no_plan');",
    ],
    [
      "  -- replaced, or that expired for another reason (the plan or profile moved), did not run out.\n",
      "  -- replaced, or that expired for another reason (the plan or profile moved), did not run out. An\n  -- undone deload counts the same, from the day it was undone (the athlete took it back).\n",
    ],
    [
      "          and a.metadata ->> 'reason' is distinct from 'expired')\n  ) e;\n",
      "          and a.metadata ->> 'reason' is distinct from 'expired')\n    union all\n    select cp.undone_at\n    from public.change_proposals cp\n    where cp.user_id = p_user and cp.schema_version = '3.0' and cp.undone_at is not null\n      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)\n  ) e;\n",
    ],
    [
      "      else coalesce(running, pending) end,\n    'suppressed_by', suppressed);\n",
      "      else coalesce(running, pending) end,\n    -- Who made the proposal: only the rules' suggestion (training-proposals) carries DELOAD_SIGNALS in\n    -- its evidence, so any other deload proposal is one the athlete asked Coach for.\n    'proposal_origin', case when suppressed in ('screening', 'block_running') then null\n      else (select case when cp.evidence @> '[{\"code\": \"DELOAD_SIGNALS\"}]'::jsonb\n          then 'tracend' else 'coach' end\n        from public.change_proposals cp\n        where cp.id = coalesce(running, pending) and cp.user_id = p_user) end,\n    'ends_on', case when running is not null then version.ends_on end,\n    'suppressed_by', suppressed);\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("training_guidance is the latest earlier function at 1.2 with proposal_origin cleared on a route day", async () => {
  const earlier = await priorDefinition("private.training_guidance");
  const redefined = between(
    origin,
    "create or replace function private.training_guidance(",
    "end $$;",
  );
  const hunks: Hunks = [
    ["'schema_version', '1.1'", "'schema_version', '1.2'"],
    [
      "      'proposal_id', null, 'suppressed_by', 'safety_route');",
      "      'proposal_id', null, 'proposal_origin', null, 'suppressed_by', 'safety_route');",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

const storeLock =
  "pg_advisory_xact_lock(hashtextextended('tracend.coach_proposal_store:' || p_user_id::text, 0))";

Deno.test("persist_coach_proposal_v1 is its latest earlier definition plus a per-athlete lock only", async () => {
  const earlier = await priorDefinition("public.persist_coach_proposal_v1");
  const redefined = between(
    origin,
    "create or replace function public.persist_coach_proposal_v1(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "    raise exception 'account not found' using errcode = 'P0002';\n  end if;\n",
      `    raise exception 'account not found' using errcode = 'P0002';\n  end if;\n  -- One proposal is stored at a time per athlete: replacing an open one (below) must not race a second\n  -- store (two taps, or a tap and Coach), which could leave two open proposals.\n  perform ${storeLock};\n`,
    ],
  ];
  assertEquals(undo(redefined, hunks), orReplaceFirst(earlier).trim());
  // The lock is taken before the open proposal is replaced.
  assert(redefined.indexOf("pg_advisory_xact_lock") < redefined.indexOf("set status = 'expired'"));
});

Deno.test("persist_suggested_deload_v1 is the rules' store: same arguments, the same lock, the check, then persist", () => {
  const persist = between(
    origin,
    "create or replace function public.persist_coach_proposal_v1(",
    "returns jsonb",
  );
  const wrapper = between(
    origin,
    "create or replace function public.persist_suggested_deload_v1(",
    "end $$;",
  );
  const args = (text: string) => text.slice(text.indexOf("(") + 1, text.lastIndexOf(")"));
  assertEquals(args(wrapper.slice(0, wrapper.indexOf("returns jsonb"))), args(persist));
  // Lock first, then the refusal, then the store, in that order.
  const at = (needle: string) => {
    const found = wrapper.indexOf(needle);
    assert(found >= 0, needle);
    return found;
  };
  assert(at(storeLock) < at("raise exception"));
  assert(at("raise exception") < at("return public.persist_coach_proposal_v1("));
  assert(wrapper.includes("errcode = 'TP001'"));
  // Only a current, unanswered, unexpired plan change that is not a deload blocks.
  for (
    const part of [
      "cp.schema_version = '3.0' and cp.status = 'pending'",
      "cp.expires_at > statement_timestamp()",
      "cp.proposal_payload ? 'training'",
      "not private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)",
      "cp.basis ->> 'training_version_id' = (",
      "v.user_id = p_user_id and v.status = 'active')",
    ]
  ) assert(wrapper.includes(part), part);
  // Every argument is passed on, in order.
  assert(
    wrapper.includes(
      "public.persist_coach_proposal_v1(p_user_id, p_kind, p_title, p_rationale, p_benefit, p_downside,\n    p_confidence, p_evidence, p_before, p_after, p_payload, p_basis, p_ends_on, p_expires_in_hours,\n    p_source_message_id)",
    ),
  );
  // It is the service role's alone.
  const after = origin.slice(
    origin.indexOf("create or replace function public.persist_suggested_deload_v1("),
  );
  assert(
    /revoke all on function public\.persist_suggested_deload_v1\([^)]*\)\s+from public, anon, authenticated;/
      .test(after),
  );
  assert(
    /grant execute on function public\.persist_suggested_deload_v1\([^)]*\)\s+to service_role;/
      .test(after),
  );
});

Deno.test("the migration redefines three functions, adds one, and grants only the new one", () => {
  assertEquals(origin.match(/create or replace function/g)?.length, 4);
  // The redefinitions keep the grants they already have; only the new function is granted here.
  assertEquals(origin.match(/\bgrant execute\b/g)?.length, 1);
});

Deno.test("the 1.2 payloads read, with who made the proposal and when a running week ends", () => {
  const a = parseTrainingGuidance(suggested)!;
  assertEquals([a.schemaVersion, a.deload.proposalOrigin, a.deload.endsOn], ["1.2", null, null]);
  const b = parseTrainingGuidance(coachPending)!;
  assertEquals(b.deload.status, "pending");
  assertEquals(b.deload.proposalOrigin, "coach");
  const c = parseTrainingGuidance(running)!;
  assertEquals([c.deload.proposalOrigin, c.deload.endsOn], ["tracend", "2026-10-31"]);
});

Deno.test("a payload from before 1.2 parses with neither key", () => {
  const old = JSON.parse(JSON.stringify(suggested));
  old.schema_version = "1.1";
  delete old.deload.proposal_origin;
  delete old.deload.ends_on;
  const read = parseTrainingGuidance(old)!;
  assertEquals([read.deload.proposalOrigin, read.deload.endsOn], [null, null]);
});

Deno.test("an origin or an end date that does not fit its status is refused", () => {
  const mutate = (change: (json: typeof coachPending) => void) => {
    const json = JSON.parse(JSON.stringify(coachPending));
    change(json);
    return parseTrainingGuidance(json);
  };
  assertEquals(mutate((j) => (j.deload.proposal_origin = "someone" as "coach")), null);
  assertEquals(mutate((j) => (j.deload.proposal_origin = 7 as unknown as "coach")), null);
  // An origin with no proposal behind it.
  assertEquals(
    mutate((j) => {
      Object.assign(j.deload, { status: "not_due", reasons: [], proposal_id: null });
    }),
    null,
  );
  // An end date on a week that is not running.
  assertEquals(mutate((j) => Object.assign(j.deload, { ends_on: "2026-10-31" })), null);
  assertEquals(mutate((j) => Object.assign(j.deload, { ends_on: "soon" })), null);
});
