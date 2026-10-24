import { assert, assertEquals, assertNotEquals } from "jsr:@std/assert@1.0.14";
import { cardioTypes } from "./cardio.ts";
import { deloadDeclinedCooldownDays } from "./deload.ts";
import { deloadSuppressions } from "../guidance/payload.ts";

// The review-round-1 migration replaces seven functions. Each must be its latest earlier definition
// plus the intended hunks and nothing else, so everything else it does is what the earlier
// migration (and its pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../../migrations/${name}`, import.meta.url));
const fixes = await read("20261024060325_deload_cardio_review_fixes.sql");
const deloads = await read("20261024060125_deloads.sql");
const cardio = await read("20261024060225_cardio_dosing.sql");
const pain = await read("20261024060025_pain_checks.sql");
const proposals = await read("20261018120018_coach_proposals.sql");

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

Deno.test("deload_rules is B5-3's literal plus the cool-down key only", () => {
  const earlier = between(deloads, "create function private.deload_rules()", "$$;");
  const redefined = between(fixes, "create or replace function private.deload_rules()", "$$;");
  assertEquals(
    undo(redefined, [
      orReplace,
      ['"recent_deload_days":28,', '"recent_deload_days":28,"declined_cooldown_days":14,'],
    ]),
    earlier.trim(),
  );
  assertEquals(deloadDeclinedCooldownDays.value, 14);
});

Deno.test("deload_signals is B5-3's function plus the cool-down and stale-proposal hunks only", () => {
  const earlier = between(deloads, "create function private.deload_signals(", "end $$;");
  const redefined = between(fixes, "create or replace function private.deload_signals(", "end $$;");
  const hunks: Hunks = [
    orReplace,
    [
      "  pending uuid;\n  dropped integer;\n",
      "  pending uuid;\n  declined_on date;\n  tz constant text := coalesce((select a.timezone from public.user_accounts a\n    join pg_catalog.pg_timezone_names z on z.name = a.timezone where a.id = p_user), 'UTC');\n  dropped integer;\n",
    ],
    [
      "  select max(least(v.ends_on, p_date)) into last_ended\n",
      "  -- The day a deload really ended: the day the block-ended event was written (a block ended early\n  -- ends that day and stays ended that day), never later than its own last day.\n  select max(least(v.ends_on, coalesce((select (a.created_at at time zone tz)::date\n      from public.audit_events a where a.user_id = p_user\n        and a.action_code = 'coach_proposal_block_ended'\n        and a.metadata ->> 'ended_version_id' = v.id::text\n      order by a.created_at desc limit 1), p_date))) into last_ended\n",
    ],
    [
      "    and cp.expires_at > statement_timestamp()\n    and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)\n  order by cp.created_at desc, cp.id desc limit 1;\n",
      "    and cp.expires_at > statement_timestamp()\n    and cp.basis ->> 'training_version_id' = version.id::text\n    and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)\n  order by cp.created_at desc, cp.id desc limit 1;\n",
    ],
    [
      "\n  -- The plan's own first day:",
      "\n  -- A deload proposal the athlete declined, or that ran out unanswered, holds new suggestions back\n  -- for declined_cooldown_days from that day. Only a decline or a timeout counts: a card a newer one\n  -- replaced, or that expired for another reason (the plan or profile moved), did not run out.\n  select max((e.happened at time zone tz)::date) into declined_on\n  from (\n    select cr.created_at as happened\n    from public.change_proposals cp\n    join public.change_responses cr on cr.proposal_id = cp.id and cr.user_id = cp.user_id\n    where cp.user_id = p_user and cp.schema_version = '3.0' and cp.status = 'rejected'\n      and cr.action = 'reject' and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)\n    union all\n    select cp.expires_at\n    from public.change_proposals cp\n    where cp.user_id = p_user and cp.schema_version = '3.0' and cp.status in ('pending', 'expired')\n      and cp.expires_at <= statement_timestamp()\n      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)\n      and not exists (select 1 from public.change_proposals n\n        where n.user_id = cp.user_id and n.schema_version = '3.0'\n          and n.created_at > cp.created_at and n.created_at < cp.expires_at\n          and (n.proposal_kind = cp.proposal_kind or n.proposal_payload ? 'training'))\n      and not exists (select 1 from public.audit_events a\n        where a.user_id = cp.user_id and a.target_type = 'change_proposal' and a.target_id = cp.id\n          and a.action_code = 'coach_proposal_expired'\n          and a.metadata ->> 'reason' is distinct from 'expired')\n  ) e;\n\n  -- The plan's own first day:",
    ],
    [
      "      then 'recent_deload'\n",
      "      then 'recent_deload'\n    when declined_on is not null\n      and p_date - declined_on < (r ->> 'declined_cooldown_days')::integer then 'declined_recently'\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
  assert(deloadSuppressions.includes("declined_recently"), "the parser knows the new reason");
});

Deno.test("cardio_rules is B5-4's literal plus five workout names only", () => {
  const earlier = between(cardio, "create function private.cardio_rules()", "$$;");
  const redefined = between(fixes, "create or replace function private.cardio_rules()", "$$;");
  assertEquals(
    undo(redefined, [
      orReplace,
      [
        '"HIGH_INTENSITY_INTERVAL_TRAINING"]',
        '"HIGH_INTENSITY_INTERVAL_TRAINING","WHEELCHAIR_WALK_PACE","WHEELCHAIR_RUN_PACE","CROSS_COUNTRY_SKIING","PADDLE_SPORTS","SOCIAL_DANCE"]',
      ],
    ]),
    earlier.trim(),
  );
  for (
    const name of [
      "WHEELCHAIR_WALK_PACE",
      "WHEELCHAIR_RUN_PACE",
      "CROSS_COUNTRY_SKIING",
      "PADDLE_SPORTS",
      "SOCIAL_DANCE",
    ]
  ) assert(cardioTypes.value.includes(name), name);
});

Deno.test("cardio_week is B5-4's function plus the check-in and screening-row hunks only", () => {
  const earlier = between(cardio, "create function private.cardio_week(", "end $$;");
  const redefined = between(fixes, "create or replace function private.cardio_week(", "end $$;");
  const hunks: Hunks = [
    orReplace,
    [
      "    'vigorous_allowed', cleared and coalesce(p_band = 'green', false) and not exists (\n      select 1 from jsonb_array_elements(private.joint_states(p_user, p_date)) s\n      where s ->> 'state' in ('held', 'limited')),\n",
      "    'vigorous_allowed', cleared\n      and exists (select 1 from public.onboarding_screenings o where o.user_id = p_user)\n      and coalesce(p_band = 'green', false)\n      and not exists (select 1 from public.daily_check_ins c\n        where c.user_id = p_user and c.local_date = p_date and c.superseded_at is null\n          and c.available_to_train is false)\n      and not exists (\n        select 1 from jsonb_array_elements(private.joint_states(p_user, p_date)) s\n        where s ->> 'state' in ('held', 'limited')),\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
  // current_screening_outcome is not touched: no row still reads as cleared everywhere else.
  assert(!fixes.includes("function private.current_screening_outcome"));
});

Deno.test("training_guidance withholds a pending deload on a route day, and changes nothing else", () => {
  const earlier = between(
    cardio,
    "create or replace function private.training_guidance(",
    "end $$;",
  );
  const redefined = between(
    fixes,
    "create or replace function private.training_guidance(",
    "end $$;",
  );
  const hunks: Hunks = [
    [
      "  if route is not null and deload ->> 'status' = 'suggested' then\n    deload := deload || jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,\n      'suppressed_by', 'safety_route');\n",
      "  if route is not null and deload ->> 'status' in ('suggested', 'pending') then\n    deload := deload || jsonb_build_object('status', 'not_due', 'reasons', '[]'::jsonb,\n      'proposal_id', null, 'suppressed_by', 'safety_route');\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("next_session_targets is the pain-check definition plus the deload hunks only", () => {
  const earlier = between(
    pain,
    "create or replace function private.next_session_targets(",
    "\n$$;",
  );
  const redefined = between(
    fixes,
    "create or replace function private.next_session_targets(",
    "\n$$;",
  );
  const hunks: Hunks = [
    [
      "), today as (\n  select private.local_date_for(p_user) as d\n), planned as (\n",
      "), today as (\n  select private.local_date_for(p_user) as d\n), deloading as (\n  -- The active plan version is a deload week that has not ended (the same test as the signals' running).\n  select exists (\n    select 1 from public.training_plan_versions v\n    join public.change_proposals cp on cp.id = v.source_proposal_id and cp.user_id = v.user_id\n    where v.user_id = p_user and v.status = 'active' and v.block_kind = 'intensity'\n      and v.ends_on >= (select d from today)\n      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)) as active\n), planned as (\n",
    ],
    [
      "  -- answer left alone is judged as ever, however easy the rest of the session was.\n  select s.*, ch.listed is not null as adjusted, ch.sets_planned\n",
      "  -- answer left alone is judged as ever, however easy the rest of the session was. A session done under\n  -- a deload week's plan version is held to the same rule: it is a lighter week on purpose, so it is\n  -- never evidence for lowering a load (its planned set count stays the plan's, so the first session\n  -- after the week reads as incomplete and holds).\n  select s.*, ch.listed is not null or dl.deload is not null as adjusted, ch.sets_planned\n",
    ],
    [
      "        or c ->> 'joint_action' = 'limit') limit 1) ch on true\n), ranked as (\n",
      "        or c ->> 'joint_action' = 'limit') limit 1) ch on true\n  left join lateral (\n    select true as deload from public.training_plan_versions pv\n    join public.change_proposals cp on cp.id = pv.source_proposal_id and cp.user_id = pv.user_id\n    where pv.id = ws.plan_version_id and pv.user_id = p_user and pv.block_kind = 'intensity'\n      and private.is_deload_proposal(cp.proposal_kind, cp.proposal_payload)) dl on true\n), ranked as (\n",
    ],
    [
      "      rc.sess) as decision\n  ) d\n  where d.decision is not null\n",
      "      rc.sess) as decision\n  ) q\n  -- During a deload week a target never steps up: a step in load becomes a hold at the last\n  -- working load.\n  cross join lateral (\n    select case when (select active from deloading) and q.decision ->> 'action' = 'add_load'\n      then q.decision || jsonb_build_object('action', 'hold', 'reason', 'deload',\n        'load_kg', rc.sess -> 0 -> 'load_kg',\n        'reps', least(pl.rep_max, greatest(pl.rep_min, (rc.sess -> 0 ->> 'min_reps')::integer)))\n      else q.decision end as decision\n  ) d\n  where d.decision is not null\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
});

Deno.test("respond_to_coach_proposal_v1 is A8's function plus the route refusal only", () => {
  const earlier = between(
    proposals,
    "create function public.respond_to_coach_proposal_v1(",
    "end $$;",
  );
  const redefined = between(
    fixes,
    "create or replace function public.respond_to_coach_proposal_v1(",
    "end $$;",
  );
  const hunks: Hunks = [
    orReplace,
    [
      "    perform private.assert_screening_allows(auth.uid(), proposal.basis ->> 'screening');\n",
      "    perform private.assert_screening_allows(auth.uid(), proposal.basis ->> 'screening');\n    -- A day with a safety route is never offered a deload, so one cannot be approved on it.\n    if private.is_deload_proposal(proposal.proposal_kind, proposal.proposal_payload)\n       and private.day_adjustment_compute(auth.uid(), today, true) -> 'payload' ->> 'safety_route'\n         is not null then\n      raise exception 'a deload cannot be approved on a day with a safety route'\n        using errcode = '55000';\n    end if;\n",
    ],
  ];
  assertEquals(undo(redefined, hunks), earlier.trim());
  assertNotEquals(redefined.trim(), earlier.trim());
  assert(
    fixes.includes(
      "grant execute on function public.respond_to_coach_proposal_v1(uuid, text, text) to authenticated;",
    ),
    "the grant is stated again",
  );
});

Deno.test("the review migration adds nothing but these seven functions, each revoked from every role", () => {
  const code = fixes.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");
  assert(!/\b(drop|alter|truncate)\b/i.test(code), "no drop, alter or truncate");
  // Only the approval writes (it did before); everything above it in the file reads.
  const readers = code.slice(0, code.indexOf("create or replace function public.respond_to"));
  assert(!/\b(insert into|update|delete from)\b/i.test(readers), "the readers write no data");
  const names = [...code.matchAll(/create or replace function ((?:private|public)\.\w+)\(/g)]
    .map((m) => m[1]);
  assertEquals(names, [
    "private.deload_rules",
    "private.deload_signals",
    "private.cardio_rules",
    "private.cardio_week",
    "private.training_guidance",
    "private.next_session_targets",
    "public.respond_to_coach_proposal_v1",
  ]);
  assertEquals([...code.matchAll(/create function/g)].length, 0, "nothing new is created");
  for (const name of names) {
    assert(
      new RegExp(`revoke all on function ${name.replace(".", "\\.")}\\(`).test(code),
      `${name} is revoked from every role`,
    );
  }
  for (const body of code.split(/create or replace function /).slice(1)) {
    assert(
      /set search_path = ''/.test(body.split("$$")[0]),
      `search_path pinned: ${body.slice(0, 40)}`,
    );
  }
  assert(!/grant execute[^;]*private\./.test(code), "no private function is granted");
});
