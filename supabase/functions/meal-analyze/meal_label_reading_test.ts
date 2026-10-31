import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { labelIssues, type StoredMealCandidate } from "../_shared/meal_vision/packaged.ts";
import golden from "../_shared/meal_vision/munch_label_golden.json" with { type: "json" };

// Migration 20261101100000 redefines persist_meal_photo_candidates and confirm_analyzed_meal. Each
// must be its latest earlier definition plus the intended hunks and nothing else, so what it does besides is what the earlier
// migration (and its pgTAP tests) already proved.
const read = (name: string) =>
  Deno.readTextFile(new URL(`../../migrations/${name}`, import.meta.url));
const migration = await read("20261101100000_meal_label_reading.sql");
const providerNeutral = await read("20261015120011_provider_neutral_ai.sql");
const rebuildFoundation = await read("20260704150000_production_rebuild_foundation.sql");

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

const persistStart = "create or replace function public.persist_meal_photo_candidates(";
const orReplace: readonly [string, string] = ["create function", "create or replace function"];

Deno.test("persist_meal_photo_candidates is the provider-neutral version plus the column and audit hunks only", () => {
  const earlier = between(providerNeutral, persistStart, "$$;");
  const redefined = between(migration, persistStart, "$$;");
  assertEquals(
    undo(redefined, [
      [
        "fat_g,confidence)\n",
        "fat_g,confidence,\n      source,image_kind,brand,quantity_unit,kcal_per_unit,protein_per_unit,carbohydrate_per_unit,fat_per_unit,serving_size,servings_per_pack,pack_size,portion_size,assumptions,question,label_issues)\n",
      ],
      [
        "item->>'confidence');",
        "item->>'confidence',\n      item->>'source',item->>'image_kind',coalesce(item->>'brand',''),item->>'quantity_unit',(item->>'kcal_per_unit')::numeric,(item->>'protein_per_unit')::numeric,(item->>'carbohydrate_per_unit')::numeric,(item->>'fat_per_unit')::numeric,\n      (item->>'serving_size')::numeric,(item->>'servings_per_pack')::numeric,(item->>'pack_size')::numeric,(item->>'portion_size')::numeric,\n      private.jsonb_text_array(item->'assumptions'),coalesce(item->>'question',''),private.jsonb_text_array(item->'label_issues'));",
      ],
      [
        "'model',run_model));",
        "'model',run_model,\n      'schema_version',2,'image_kind',candidates->0->>'image_kind'));",
      ],
    ]),
    earlier.trim(),
  );
});

Deno.test("confirm_analyzed_meal is the rebuild-foundation version plus the portion hunk only", () => {
  const earlier = between(
    rebuildFoundation,
    "create function public.confirm_analyzed_meal(",
    "$$;",
  );
  const redefined = between(
    migration,
    "create or replace function public.confirm_analyzed_meal(",
    "$$;",
  );
  assertEquals(
    undo(redefined, [
      orReplace,
      [
        "selected=true\n",
        "selected=true,\n      portion_size=(candidate->>'portion_size')::numeric\n",
      ],
    ]),
    earlier.trim(),
  );
  assert(redefined.includes("security definer set search_path=''"));
  assert(migration.includes(
    "revoke all on function public.confirm_analyzed_meal(uuid, jsonb) from public, anon, authenticated;\ngrant execute on function public.confirm_analyzed_meal(uuid, jsonb) to authenticated;",
  ));
});

Deno.test("the redefinition keeps security definer, an empty search path and the service-role grant", () => {
  const redefined = between(migration, persistStart, "$$;");
  assert(redefined.includes("security definer set search_path=''"));
  assert(migration.includes(
    "revoke all on function public.persist_meal_photo_candidates(uuid, uuid, jsonb, text, text)\nfrom public, anon, authenticated;",
  ));
  assert(migration.includes(
    "grant execute on function public.persist_meal_photo_candidates(uuid, uuid, jsonb, text, text)\nto service_role;",
  ));
  assert(migration.includes(
    "revoke all on function private.jsonb_text_array(jsonb) from public, anon, authenticated;",
  ));
});

Deno.test("every field meal-analyze stores has a column the insert writes, and the checks agree", () => {
  const redefined = between(migration, persistStart, "$$;");
  const stored = golden.stored as unknown as StoredMealCandidate;
  const columns: Record<string, string> = { name: "food_label" };
  for (const field of Object.keys(stored)) {
    assert(
      redefined.includes(`item->>'${field}'`) || redefined.includes(`item->'${field}'`),
      field,
    );
    assert(redefined.includes(columns[field] ?? field), `column for ${field}`);
  }
  // The table accepts exactly the issues code can name.
  for (const issue of labelIssues) assert(migration.includes(`'${issue}'`), issue);
  for (const unit of ["'g'", "'ml'"]) assert(migration.includes(unit), unit);
  for (const source of ["label", "label_unverified", "estimate"]) {
    assert(migration.includes(`'${source}'`), source);
  }
});
