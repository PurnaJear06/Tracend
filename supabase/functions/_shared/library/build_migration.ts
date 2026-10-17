// Prints the SQL blocks that load library sources (see migration_sql.ts). Paste the output
// into a new migration. With no flag every source is printed; --only takes manifest keys.

import { sourceBlocks } from "./migration_sql.ts";
import { librarySources } from "../../../library/index.ts";

const args = Deno.args;
const onlyIndex = args.indexOf("--only");
const only = onlyIndex >= 0 ? new Set((args[onlyIndex + 1] ?? "").split(",")) : null;
const selected = librarySources.filter((source) => only === null || only.has(source.slug));
if (only !== null) {
  const missing = [...only].filter((key) => !selected.some((source) => source.slug === key));
  if (missing.length > 0) {
    console.error(`Unknown source keys: ${missing.join(", ")}`);
    Deno.exit(1);
  }
}
console.log(await sourceBlocks(selected));
