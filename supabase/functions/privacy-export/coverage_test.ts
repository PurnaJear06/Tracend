import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { dataTables, exportExclusions } from "./index.ts";

// Every table that holds an athlete's data (a user_id column) must be in the export or in the
// documented exclusion list. The tables come from the migrations, so a new table fails this test
// until someone decides which list it belongs in.
const migrationsDir = new URL("../../migrations/", import.meta.url);

// Removes `--` comments outside single-quoted strings.
function withoutComments(sql: string): string {
  let out = "";
  let quoted = false;
  for (let i = 0; i < sql.length; i++) {
    const c = sql[i];
    if (c === "'") quoted = !quoted;
    if (!quoted && c === "-" && sql[i + 1] === "-") {
      while (i < sql.length && sql[i] !== "\n") i++;
      out += "\n";
      continue;
    }
    out += c;
  }
  return out;
}

// The text between the parenthesis that opens at `open` and its match.
function bracketed(sql: string, open: number): string {
  let depth = 0;
  let quoted = false;
  for (let i = open; i < sql.length; i++) {
    const c = sql[i];
    if (c === "'") quoted = !quoted;
    if (quoted) continue;
    if (c === "(") depth++;
    if (c === ")" && --depth === 0) return sql.slice(open + 1, i);
  }
  throw new Error("unbalanced create table");
}

function topLevelItems(body: string): string[] {
  const items: string[] = [];
  let depth = 0;
  let quoted = false;
  let start = 0;
  for (let i = 0; i < body.length; i++) {
    const c = body[i];
    if (c === "'") quoted = !quoted;
    if (quoted) continue;
    if (c === "(") depth++;
    if (c === ")") depth--;
    if (c === "," && depth === 0) {
      items.push(body.slice(start, i));
      start = i + 1;
    }
  }
  items.push(body.slice(start));
  return items.map((item) => item.trim()).filter((item) => item.length > 0);
}

const constraintStarts = /^(constraint|primary|foreign|unique|check|like|exclude)\b/i;

export async function tablesWithUserId(): Promise<{ owned: Set<string>; all: Set<string> }> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(migrationsDir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) names.push(entry.name);
  }
  names.sort();
  const owned = new Set<string>();
  const all = new Set<string>();
  for (const name of names) {
    const sql = withoutComments(await Deno.readTextFile(new URL(name, migrationsDir)));
    const create =
      /create\s+table\s+(?:if\s+not\s+exists\s+)?((?:public|private)\.[a-z0-9_]+)\s*\(/gi;
    for (const match of sql.matchAll(create)) {
      all.add(match[1]);
      const body = bracketed(sql, match.index + match[0].length - 1);
      const columns = topLevelItems(body).filter((item) => !constraintStarts.test(item))
        .map((item) => item.split(/\s+/)[0].replaceAll('"', ""));
      if (columns.includes("user_id")) owned.add(match[1]);
    }
    const added =
      /alter\s+table\s+(?:if\s+exists\s+)?((?:public|private)\.[a-z0-9_]+)\s+add\s+column\s+(?:if\s+not\s+exists\s+)?"?user_id"?\s/gi;
    for (const match of sql.matchAll(added)) owned.add(match[1]);
    const dropped = /drop\s+table\s+(?:if\s+exists\s+)?((?:public|private)\.[a-z0-9_]+)/gi;
    for (const match of sql.matchAll(dropped)) {
      owned.delete(match[1]);
      all.delete(match[1]);
    }
  }
  return { owned, all };
}

const { owned, all } = await tablesWithUserId();
const exported = new Set(dataTables.map((table) => `public.${table}`));

Deno.test("the migration parser finds the athlete tables it should", () => {
  assert(owned.size >= 55, `found ${owned.size} tables with a user_id`);
  for (const table of ["public.meals", "public.coach_messages", "public.workout_sessions"]) {
    assert(owned.has(table), table);
  }
  assert(!owned.has("public.user_accounts"));
  assert(!owned.has("public.exercise_catalog"));
});

Deno.test("every table with a user_id is exported or excluded with a reason", () => {
  const missing = [...owned].filter((table) =>
    !exported.has(table) && !(table in exportExclusions)
  );
  assertEquals(
    missing,
    [],
    "add these to dataTables in index.ts, or to exportExclusions with a reason",
  );
});

Deno.test("every exclusion has a reason and names a table that still has a user_id", () => {
  for (const [table, reason] of Object.entries(exportExclusions)) {
    assert(reason.trim().length >= 20, `${table} needs a reason`);
    assert(owned.has(table), `${table} no longer has a user_id: remove the exclusion`);
    assert(!exported.has(table), `${table} is both exported and excluded`);
  }
});

Deno.test("every exported table exists in the migrations", () => {
  for (const table of dataTables) {
    assert(all.has(`public.${table}`), `${table} is exported but no migration creates it`);
  }
});
