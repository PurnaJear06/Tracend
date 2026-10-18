// One read of the athlete's memory per turn. The confirmed-facts contributor, the Coach-notes
// contributor and the fact suggestions after the reply all need the same payload, so a read for
// the same athlete, day and question within a few seconds is shared instead of repeated.
import { loadMemoryContext, type MemoryContext } from "../../coach_memory/store.ts";
import { coachServiceRpc, type ServiceRpc } from "../service_source.ts";

export const memoryReadShareMs = 5_000;

type Entry = { at: number; promise: Promise<MemoryContext | null> };

export function createMemorySource(
  rpc: ServiceRpc,
  now: () => number = Date.now,
): (input: Readonly<{ userId: string; localDate: string; question: string }>) => Promise<
  MemoryContext | null
> {
  const reads = new Map<string, Entry>();
  return (input) => {
    const time = now();
    for (const [key, entry] of reads) {
      if (time - entry.at > memoryReadShareMs) reads.delete(key);
    }
    const key = `${input.userId}|${input.localDate}|${input.question}`;
    const shared = reads.get(key);
    if (shared) return shared.promise;
    const promise = loadMemoryContext(rpc, input.userId).then((memory) => {
      // A read that failed is not shared: the next caller tries again.
      if (memory === null) reads.delete(key);
      return memory;
    });
    reads.set(key, { at: time, promise });
    return promise;
  };
}

/** The read the contributors and coach-chat share. */
export const readCoachMemory = createMemorySource(coachServiceRpc);
