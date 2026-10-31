// One read for a contributor, with a deadline of its own that is shorter than the host's. A read that
// is slow, fails or returns nothing readable yields a status instead of a value: the contributor
// then renders a "could not be read" block (a gap never reads as "all clear") and the turn goes on.

/** Who answered a contributor's read: the trace reports it, never a value. */
export type ReadStatus = "ok" | "unavailable" | "failed" | "timeout";

export type ReadResult<T> = Readonly<{ value: T | null; status: ReadStatus }>;

/** Reads within `deadlineMs`; never rejects. A late answer after the deadline changes nothing. */
export async function readWithin<T>(
  read: () => Promise<T | null>,
  deadlineMs: number,
): Promise<ReadResult<T>> {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const late = new Promise<"timeout">((resolve) => {
    timer = setTimeout(() => resolve("timeout"), deadlineMs);
  });
  try {
    const value = await Promise.race([Promise.resolve().then(read), late]);
    if (value === "timeout") return { value: null, status: "timeout" };
    return { value, status: value === null ? "unavailable" : "ok" };
  } catch {
    return { value: null, status: "failed" };
  } finally {
    clearTimeout(timer);
  }
}
