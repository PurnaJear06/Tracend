// Pins the hunks of 20261031100000_onboarding_legacy_and_forms.sql. The SQL runs in the database
// (pgTAP covers behaviour in CI); these tests keep the hunks that must not drift from drifting:
// the retired functions stay closed, the redefined functions keep their security settings and the
// body-fat floor figures are the documented ones.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";

const read = (name: string) =>
  Deno.readTextFile(new URL(`../../../../migrations/${name}`, import.meta.url));
const migration = await read("20261031100000_onboarding_legacy_and_forms.sql");
const original = await read("20261017151527_goal_targets.sql");
const code = (sql: string) =>
  sql.split("\n").filter((line) => !line.trim().startsWith("--")).join("\n");
const sql = code(migration);

const retired = [
  "public.respond_to_onboarding_proposal(uuid, public.proposal_response_action)",
  "public.create_fixture_meal(date, text, text, uuid)",
  "public.confirm_fixture_meal(uuid, uuid[])",
  "public.confirm_fixture_meal_v2(uuid, jsonb)",
  "public.persist_coach_preference(uuid, text, text, text, text)",
];

Deno.test("each retired function is revoked from public, anon and authenticated", () => {
  for (const signature of retired) {
    assertStringIncludes(
      sql.replace(/\s+/g, " "),
      `revoke all on function ${signature} from public, anon, authenticated;`,
    );
  }
});

Deno.test("nothing in the migration grants a function to anyone", () => {
  assert(!/grant\s+execute/i.test(sql), "the migration grants no function");
});

Deno.test("the app role keeps its onboarding_state grant while older builds still write it", () => {
  assert(!/revoke[^;]*\(onboarding_state\)/.test(sql), "no column revoke in this migration");
});

Deno.test("the trigger moves only a not_started account, as a private security definer", () => {
  const trigger = sql.match(
    /create function private\.mark_onboarding_started\(\)[\s\S]*?end \$\$;/,
  );
  assert(trigger, "trigger function found");
  assertStringIncludes(trigger[0], "security definer set search_path = ''");
  assertStringIncludes(trigger[0], "onboarding_state = 'not_started'");
  assertStringIncludes(
    sql,
    "revoke all on function private.mark_onboarding_started() from public, anon, authenticated;",
  );
});

Deno.test("the body-fat floor is 5 for men and 12 for women and for an unknown sex", () => {
  const floor = sql.match(/create function private\.body_fat_floor_pct[\s\S]*?\$\$;/);
  assert(floor, "floor function found");
  assertStringIncludes(floor[0], "'unspecified'");
  assertStringIncludes(floor[0], "when 'male' then 5 else 12 end");
});

Deno.test("the goal target functions keep their security settings and the weight floor", () => {
  for (const name of ["get_goal_target_v1", "set_goal_target_v1"]) {
    const redefined = sql.match(
      new RegExp(`create or replace function public\\.${name}\\([\\s\\S]*?end \\$\\$;`),
    );
    assert(redefined, `${name} redefined`);
    assertStringIncludes(redefined[0], "security definer set search_path = ''");
    assertStringIncludes(redefined[0], "'schema_version', '1.1'");
    assertStringIncludes(redefined[0], "min_target_body_fat_pct");
  }
  // The weight checks are copied unchanged from B7's migration.
  for (
    const hunk of [
      "if p_target_weight_kg is not null and p_target_weight_kg not between 30 and 300 then",
      "raise exception 'target weight is below the healthy range for this height' using errcode = '22023';",
      "p_target_date <= today or p_target_date > today + 1096",
    ]
  ) {
    assertStringIncludes(code(original).replace(/\s+/g, " "), hunk);
    assertStringIncludes(sql.replace(/\s+/g, " "), hunk);
  }
  assertEquals(
    (sql.match(
      /raise exception 'body-fat target is below the healthy range for you' using errcode = '22023'/g,
    ) ?? [])
      .length,
    1,
  );
});

Deno.test("the meal functions return a schema version and keep their guards", () => {
  assertStringIncludes(sql, "jsonb_build_object('schema_version','1.0','local_date',target_date,");
  const draft = sql.match(
    /create or replace function public\.create_meal_photo_draft[\s\S]*?end \$\$;/,
  );
  assert(draft, "draft function found");
  assertStringIncludes(draft[0], "security definer set search_path=''");
  assertStringIncludes(draft[0], "private.is_owned_media_key(auth.uid(), 'meal', object_path)");
  assertEquals((draft[0].match(/'schema_version','1.0'/g) ?? []).length, 2);
});

Deno.test("the migration is additive: it drops nothing", () => {
  assert(!/\bdrop\s+(table|column|function|policy|trigger)\b/i.test(sql));
});
