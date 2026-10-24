// PostgREST returns at most `max_rows` (1000 in config.toml) rows per request, so a list that can
// pass that size is read in pages. Pages are keyset pages: each asks for the rows after the last key
// of the one before, in key order, so a row inserted or deleted while the list is being read can
// neither repeat a row nor skip one that was there all along (offset pages shift by one for every
// row that appears or goes behind the page).
export const pageSize = 1000;

export type Page<T> = Readonly<{ data: readonly T[] | null; error: unknown }>;

// Reads pages until one comes back empty. A short page is not the end: the server may cap a response
// below the size asked for, and the next key tells where to go on. `fetchPage(after, size)` returns
// the rows whose key is greater than `after` (all rows when it is null), in key order, at most
// `size` of them. `failureCode` is the error message thrown on a failed page; it never carries the
// database's own message.
export async function fetchAllByKey<T>(
  fetchPage: (after: string | null, size: number) => PromiseLike<Page<T>>,
  keyOf: (row: T) => unknown,
  failureCode: string,
  size = pageSize,
  onPage?: (page: readonly T[]) => void,
): Promise<T[]> {
  const rows: T[] = [];
  let after: string | null = null;
  for (;;) {
    const { data, error } = await fetchPage(after, size);
    if (error) throw new Error(failureCode);
    const page = data ?? [];
    if (page.length === 0) return rows;
    const last = keyOf(page[page.length - 1]);
    // A key that does not move forward would ask for the same page again for ever.
    if (typeof last !== "string" || last.length === 0 || last === after) {
      throw new Error(failureCode);
    }
    // Lets the caller stop a read that has grown too large before the next page is fetched.
    onPage?.(page);
    rows.push(...page);
    after = last;
  }
}
