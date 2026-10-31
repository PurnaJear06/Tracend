import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import {
  dataTables,
  exportExclusions,
  keyColumns,
  linkedColumns,
  omittedColumns,
  selectedColumns,
} from "./index.ts";

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
const accountTarget = /references\s+(?:public\.user_accounts|auth\.users)\b/i;

type Table = {
  columns: Map<string, string>;
  primaryKey: string[];
  accountLinks: Set<string>;
};

const columnList = (text: string) =>
  text.split(",").map((name) => name.trim().replaceAll('"', "")).filter((name) => name.length > 0);

export async function parseMigrations(): Promise<Map<string, Table>> {
  const names: string[] = [];
  for await (const entry of Deno.readDir(migrationsDir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) names.push(entry.name);
  }
  names.sort();
  const tables = new Map<string, Table>();
  const addColumn = (table: Table, name: string, definition: string) => {
    table.columns.set(name, definition);
    if (/\bprimary\s+key\b/i.test(definition)) table.primaryKey = [name];
    if (accountTarget.test(definition)) table.accountLinks.add(name);
  };
  for (const name of names) {
    const sql = withoutComments(await Deno.readTextFile(new URL(name, migrationsDir)));
    const create =
      /create\s+table\s+(?:if\s+not\s+exists\s+)?((?:public|private)\.[a-z0-9_]+)\s*\(/gi;
    for (const match of sql.matchAll(create)) {
      const table: Table = { columns: new Map(), primaryKey: [], accountLinks: new Set() };
      tables.set(match[1], table);
      const body = bracketed(sql, match.index + match[0].length - 1);
      for (const item of topLevelItems(body)) {
        if (!constraintStarts.test(item)) {
          const [column, ...rest] = item.split(/\s+/);
          addColumn(table, column.replaceAll('"', ""), rest.join(" "));
          continue;
        }
        const primary = item.match(/primary\s+key\s*\(([^)]*)\)/i);
        if (primary) table.primaryKey = columnList(primary[1]);
        const foreign = item.match(/foreign\s+key\s*\(([^)]*)\)\s*(references[^,]*)/i);
        if (foreign && accountTarget.test(foreign[2])) {
          for (const column of columnList(foreign[1])) table.accountLinks.add(column);
        }
      }
    }
    const alter =
      /alter\s+table\s+(?:if\s+exists\s+)?((?:public|private)\.[a-z0-9_]+)\s+([^;]*);/gi;
    for (const statement of sql.matchAll(alter)) {
      const table = tables.get(statement[1]);
      if (!table) continue;
      const add = /add\s+column\s+(?:if\s+not\s+exists\s+)?"?([a-z0-9_]+)"?\s+([^,]*)/gi;
      for (const column of statement[2].matchAll(add)) addColumn(table, column[1], column[2]);
    }
    const dropped = /drop\s+table\s+(?:if\s+exists\s+)?((?:public|private)\.[a-z0-9_]+)/gi;
    for (const match of sql.matchAll(dropped)) tables.delete(match[1]);
  }
  return tables;
}

const tables = await parseMigrations();
const owned = new Set([...tables].filter(([, t]) => t.columns.has("user_id")).map(([n]) => n));
const all = new Set(tables.keys());
const exported = new Set(dataTables.map((table) => `public.${table}`));
const colsOf = (table: string) => tables.get(`public.${table}`)!;

Deno.test("the migration parser finds the athlete tables it should", () => {
  assert(owned.size >= 55, `found ${owned.size} tables with a user_id`);
  for (const table of ["public.meals", "public.coach_messages", "public.workout_sessions"]) {
    assert(owned.has(table), table);
  }
  assert(!owned.has("public.user_accounts"));
  assert(!owned.has("public.exercise_catalog"));
  assertEquals(colsOf("meals").primaryKey, ["id"]);
  assertEquals(colsOf("health_history_months").primaryKey, ["user_id", "month"]);
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

Deno.test("every exported table pages by a column that is unique among one owner's rows", () => {
  for (const table of dataTables) {
    const key = keyColumns[table] ?? "id";
    const { columns, primaryKey } = colsOf(table);
    assert(columns.has(key), `${table} has no ${key} column to page by`);
    // The owner column is fixed by the filter, so it may sit in front of the key.
    const withoutOwner = primaryKey.length > 1
      ? primaryKey.filter((column) => column !== "user_id")
      : primaryKey;
    assertEquals(
      withoutOwner,
      [key],
      `${table}: pages by ${key} but its primary key is ${primaryKey}`,
    );
  }
});

Deno.test("every key override and omitted column names a column that exists", () => {
  for (const table of Object.keys(keyColumns)) {
    assert(dataTables.includes(table as (typeof dataTables)[number]), `${table} is not exported`);
  }
  for (const [table, omitted] of Object.entries(omittedColumns)) {
    assert(dataTables.includes(table as (typeof dataTables)[number]), `${table} is not exported`);
    for (const column of Object.keys(omitted)) {
      assert(colsOf(table).columns.has(column), `${table}.${column} does not exist`);
    }
  }
});

// A column that ties a row to an account without being the owner column is data the owner-column
// check cannot see. Each one needs a line in linkedColumns saying how its rows reach the export.
Deno.test("every column that points at the account or is named *_by is accounted for", () => {
  const found = new Set<string>();
  for (const [name, table] of tables) {
    for (const [column, definition] of table.columns) {
      const isUuid = /^uuid\b/i.test(definition);
      const links = table.accountLinks.has(column);
      if (column === "user_id" && links) continue;
      if (links || (isUuid && /_by$/.test(column))) found.add(`${name}.${column}`);
    }
  }
  const listed = new Set(Object.keys(linkedColumns));
  assertEquals(
    [...found].filter((column) => !listed.has(column)),
    [],
    "decide how these reach the export and add them to linkedColumns",
  );
  assertEquals(
    [...listed].filter((column) => !found.has(column)),
    [],
    "stale linkedColumns entries",
  );
  for (const [column, how] of Object.entries(linkedColumns)) {
    assert(how.trim().length >= 20, `${column} needs an explanation`);
  }
});

// A table with omitted columns selects an explicit list, so the omitted ones are never downloaded.
// The list must be exactly the migrations' columns minus the omitted ones: a column added later
// fails here until it is added to the list (or to the omitted ones, with a reason).
Deno.test("the select list of a table with omitted columns is its columns minus the omitted ones", () => {
  assertEquals(
    Object.keys(selectedColumns).sort(),
    Object.keys(omittedColumns).sort(),
    "every table with omitted columns has a select list, and only those",
  );
  for (const [table, selected] of Object.entries(selectedColumns)) {
    const omitted = Object.keys(omittedColumns[table]);
    const expected = [...colsOf(table).columns.keys()].filter((column) =>
      !omitted.includes(column)
    );
    assertEquals(
      [...selected].sort(),
      expected.sort(),
      `${table}: select list drifted from the migrations`,
    );
    assertEquals(new Set(selected).size, selected.length, `${table}: a column is listed twice`);
    for (const column of omitted) assert(!selected.includes(column), `${table} selects ${column}`);
  }
});
