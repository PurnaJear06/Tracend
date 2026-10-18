import { assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import {
  createReportGate,
  createWorkerAuthorizer,
  failureReportIntervalMs,
  workerAuthCacheMs,
} from "./embed_service.ts";

Deno.test("an accepted secret is trusted for a few minutes; a refused one always asks again", async () => {
  let clock = 0;
  const checked: string[] = [];
  const authorized = createWorkerAuthorizer({
    check: (candidate) => {
      checked.push(candidate);
      return Promise.resolve(candidate === "right");
    },
    now: () => clock,
  });
  assertEquals(await authorized("right"), true);
  assertEquals(await authorized("right"), true);
  assertEquals(checked, ["right"], "the second call skips the database");
  assertEquals(await authorized("wrong"), false);
  assertEquals(await authorized("wrong"), false);
  assertEquals(checked, ["right", "wrong", "wrong"], "a refusal is never remembered");
  assertEquals(await authorized("right"), true, "a refused bearer does not evict the accepted one");
  assertEquals(checked.length, 3);
  clock = workerAuthCacheMs;
  assertEquals(await authorized("right"), true);
  assertEquals(checked.length, 4, "after the cache time the database is asked again");
});

Deno.test("a secret the database no longer accepts stops working once the cache time passes", async () => {
  let clock = 0;
  let current = "old";
  const authorized = createWorkerAuthorizer({
    check: (candidate) => Promise.resolve(candidate === current),
    now: () => clock,
    ttlMs: 1_000,
  });
  assertEquals(await authorized("old"), true);
  current = "new";
  clock = 999;
  assertEquals(await authorized("old"), true);
  clock = 1_000;
  assertEquals(await authorized("old"), false);
  assertEquals(await authorized("new"), true);
});

Deno.test("a failed check is an error, not an acceptance", async () => {
  const authorized = createWorkerAuthorizer({
    check: () => Promise.reject(new Error("authorization_check_failed")),
  });
  await assertRejects(() => authorized("right"), Error, "authorization_check_failed");
});

Deno.test("a lasting failure reaches Sentry once per interval", () => {
  let clock = 0;
  const report = createReportGate(failureReportIntervalMs, () => clock);
  assertEquals(report(), true);
  for (clock = 60_000; clock < failureReportIntervalMs; clock += 60_000) {
    assertEquals(report(), false, `minute ${clock / 60_000}`);
  }
  assertEquals(report(), true);
  assertEquals(report(), false);
});
