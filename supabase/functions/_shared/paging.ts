// PostgREST returns at most `max_rows` (1000 in config.toml) rows per request, so a list that can
// pass that size is read page by page. The query must have a stable order, or pages overlap.
export const pageSize = 1000;

export type Page<T> = Readonly<{ data: readonly T[] | null; error: unknown }>;

// Reads pages until one comes back short. `failureCode` is the error message thrown on a failed
// page; it never carries the database's own message.
export async function fetchAllPages<T>(
  fetchPage: (from: number, to: number) => PromiseLike<Page<T>>,
  failureCode: string,
  size = pageSize,
): Promise<T[]> {
  const rows: T[] = [];
  for (let from = 0;; from += size) {
    const { data, error } = await fetchPage(from, from + size - 1);
    if (error) throw new Error(failureCode);
    const page = data ?? [];
    rows.push(...page);
    if (page.length !== size) return rows;
  }
}
