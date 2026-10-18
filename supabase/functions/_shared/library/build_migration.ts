// Prints the SQL blocks that load library sources (see migration_sql.ts). Paste the output
// into a new migration. With no flag every source is printed; --only takes manifest keys.
// --retire takes the keys of sources removed from index.ts and prints their retire blocks.

import { retireBlock, sourceBlocks } from "./migration_sql.ts";
import { librarySources } from "../../../library/index.ts";

const args = Deno.args;
const listAfter = (flag: string) => {
  const index = args.indexOf(flag);
  return index >= 0 ? (args[index + 1] ?? "").split(",").filter((key) => key !== "") : null;
};

const retire = listAfter("--retire");
if (retire !== null) {
  const listed = retire.filter((key) => librarySources.some((source) => source.slug === key));
  if (retire.length === 0 || listed.length > 0) {
    console.error(
      listed.length > 0
        ? `Still in index.ts, so not retired: ${listed.join(", ")}`
        : "--retire needs source keys",
    );
    Deno.exit(1);
  }
  console.log(retire.map(retireBlock).join("\n"));
  Deno.exit(0);
}

const onlyKeys = listAfter("--only");
const only = onlyKeys === null ? null : new Set(onlyKeys);
const selected = librarySources.filter((source) => only === null || only.has(source.slug));
if (only !== null) {
  const missing = [...only].filter((key) => !selected.some((source) => source.slug === key));
  if (missing.length > 0) {
    console.error(`Unknown source keys: ${missing.join(", ")}`);
    Deno.exit(1);
  }
}
console.log(await sourceBlocks(selected));
