// Pins 20261102074318_onboarding_safety_floors.sql. The SQL runs in the database (safety_floors_test
// covers behaviour in CI); these tests keep it from drifting: every redefined function is its latest
// earlier definition plus the intended hunks only, and the floor check uses the onboarding policy's
// own figures.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { dailyActivityFactors, nutritionBounds } from "./policy.ts";
import { goalPhaseThresholds } from "../training/goal_phase/thresholds.ts";

const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../migrations/${name}`, import.meta.url));
const migration = await read("20261102074318_onboarding_safety_floors.sql");
const code = (sql: string) =>
  sql.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");
const flat = (sql: string) => code(sql).replace(/\s+/g, " ");

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
    assertEquals(text.split(added).length - 1, 1, `hunk is in the function once: ${added}`);
    text = text.replace(added, () => was);
  }
  return text;
}

async function pinned(file: string, start: string, redefinedStart: string, hunks: Hunks) {
  const earlier = between(await read(file), start, "\n$$;");
  const redefined = between(migration, redefinedStart, "\n$$;");
  assertEquals(undo(redefined, hunks), earlier);
}

async function pinnedPlpgsql(file: string, start: string, redefinedStart: string, hunks: Hunks) {
  const earlier = between(await read(file), start, "end $$;");
  const redefined = between(migration, redefinedStart, "end $$;");
  assertEquals(undo(redefined, hunks), earlier);
}

Deno.test("respond_to_onboarding_proposal_v2 is its latest definition plus the floor check only", async () => {
  await pinnedPlpgsql(
    "20261017050226_onboarding_screening.sql",
    "create or replace function public.respond_to_onboarding_proposal_v2(",
    "create or replace function public.respond_to_onboarding_proposal_v2(",
    [
      ["  approval_date date;\nbegin", "  approval_date date;\n  floor_rule text;\nbegin"],
      [
        "      where s.id = proposal.feature_snapshot_id and s.user_id = auth.uid();\n    approval_date",
        between(
          migration,
          "      where s.id = proposal.feature_snapshot_id and s.user_id = auth.uid();\n    -- The healthy",
          "    end if;\n    approval_date",
        ),
      ],
    ],
  );
  const check = between(
    migration,
    "    floor_rule := private.onboarding_floor_violation(",
    "end if;",
  );
  assertStringIncludes(check, "set status = 'expired'");
  assertStringIncludes(check, "'reason', floor_rule");
  assertStringIncludes(check, "'status', 'expired'");
});

Deno.test("the floor check runs after the screening and validity checks, before any write", () => {
  const body = between(
    migration,
    "create or replace function public.respond_to_onboarding_proposal_v2(",
    "end $$;",
  );
  const order = [
    "perform private.assert_screening_allows(",
    "private.is_valid_initial_proposal_v2(",
    "floor_rule := private.onboarding_floor_violation(answers, proposal.proposed_nutrition);",
    "update public.training_plan_versions set status = 'superseded'",
  ].map((marker) => body.indexOf(marker));
  assert(order.every((at) => at > 0), "every step is present");
  assertEquals([...order].sort((a, b) => a - b), order);
  assertStringIncludes(body, "security definer set search_path = ''");
});

Deno.test("the floor check uses the onboarding policy's and Coach's figures", () => {
  const rule = flat(
    between(migration, "create function private.onboarding_floor_violation(", "end $$;"),
  );
  assertStringIncludes(rule, "language plpgsql stable set search_path = ''");
  assertStringIncludes(
    rule,
    `target_kg < round(${goalPhaseThresholds.bmiHealthyFloor.value} * height_m * height_m, 1)`,
  );
  assertStringIncludes(
    rule,
    `round(weight_kg / (height_m * height_m), 1) >= ${goalPhaseThresholds.bmiNearFloor.value}`,
  );
  for (const [activity, factor] of Object.entries(dailyActivityFactors)) {
    assertStringIncludes(rule, `when '${activity}' then ${factor}`);
  }
  // Mifflin-St Jeor, the lower (female) equation unless male, and net MET 4 training energy.
  assertStringIncludes(rule, "10 * weight_kg + 6.25 * height_m * 100 - 5 * age");
  assertStringIncludes(rule, "case when answers ->> 'sex' = 'male' then 5 else -161 end");
  assertStringIncludes(
    rule,
    "4 * 3.5 * weight_kg / 200 * (answers ->> 'session_minutes')::numeric",
  );
  assertStringIncludes(rule, "jsonb_array_length(answers -> 'training_weekdays') / 7");
  assertStringIncludes(rule, `calories + 5 < least(maintenance, ${nutritionBounds.calories[1]})`);
  assertStringIncludes(
    flat(migration),
    "revoke all on function private.onboarding_floor_violation(jsonb, jsonb) from public, anon, authenticated;",
  );
});

Deno.test("the screening helpers are their latest definitions plus the unscreened hunks only", async () => {
  await pinned(
    "20261017050226_onboarding_screening.sql",
    "create function private.screening_rank(outcome text)",
    "create or replace function private.screening_rank(outcome text)",
    [
      [
        "create function private.screening_rank(outcome text)",
        "create or replace function private.screening_rank(outcome text)",
      ],
      [
        "when 'moderate_until_cleared' then 1 else 0 end",
        "when 'moderate_until_cleared' then 1\n    when 'unscreened' then 1 else 0 end",
      ],
    ],
  );
  await pinned(
    "20261017050226_onboarding_screening.sql",
    "create function private.current_screening_outcome(target_user_id uuid)",
    "create or replace function private.current_screening_outcome(target_user_id uuid)",
    [
      [
        "create function private.current_screening_outcome(",
        "create or replace function private.current_screening_outcome(",
      ],
      ["  ), 'cleared')", "  ), 'unscreened')"],
    ],
  );
  await pinnedPlpgsql(
    "20261017050226_onboarding_screening.sql",
    "create function private.assert_screening_allows(target_user_id uuid, built_under text)",
    "create or replace function private.assert_screening_allows(target_user_id uuid, built_under text)",
    [
      [
        "create function private.assert_screening_allows(",
        "create or replace function private.assert_screening_allows(",
      ],
      [
        "  end if;\n  if private.screening_rank(",
        "  end if;\n  if current_outcome = 'unscreened' and built_under is distinct from 'unscreened' then\n    raise exception 'the health check must be answered first' using errcode = '55000';\n  end if;\n  if private.screening_rank(",
      ],
    ],
  );
  await pinnedPlpgsql(
    "20261018120018_coach_proposals.sql",
    "create function private.hold_plan_to_screening(p_user uuid, p_version uuid)",
    "create or replace function private.hold_plan_to_screening(p_user uuid, p_version uuid)",
    [
      [
        "create function private.hold_plan_to_screening(",
        "create or replace function private.hold_plan_to_screening(",
      ],
      [
        "private.current_screening_outcome(p_user) = 'moderate_until_cleared' then",
        "private.current_screening_outcome(p_user) in ('moderate_until_cleared', 'unscreened') then",
      ],
    ],
  );
});

Deno.test("the direct writes are narrowed to what the installed app sends", () => {
  const sql = flat(migration);
  for (
    const statement of [
      "revoke insert, update on public.user_goals from authenticated;",
      "grant insert (user_id, goal_type, priority, status) on public.user_goals to authenticated;",
      "grant update (goal_type) on public.user_goals to authenticated;",
      "drop policy user_goals_own on public.user_goals;",
      "with check (user_id = (select auth.uid()) and status = 'draft');",
      "using (user_id = (select auth.uid()) and status = 'draft')",
      "revoke insert (onboarding_state), update (onboarding_state) on public.user_accounts from authenticated;",
      "revoke all on function public.get_healthkit_completion_candidate(date) from public, anon;",
      "grant execute on function public.get_healthkit_completion_candidate(date) to authenticated;",
    ]
  ) {
    assertStringIncludes(sql, statement);
  }
  assert(!/grant[^;]*\bdetails\b/i.test(sql), "no grant names details");
  assert(!/grant[^;]*to anon/i.test(sql), "nothing is granted to anon");
});
