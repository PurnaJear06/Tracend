import { assertEquals } from "jsr:@std/assert@1";
import { AiBudget } from "./ai_budget.ts";

function fakeRpc(refuse = false) {
  const calls: Array<[string, Record<string, unknown>]> = [];
  let next = 0;
  const rpc = (fn: string, args: Record<string, unknown>) => {
    calls.push([fn, args]);
    if (fn === "reserve_ai_budget") {
      return Promise.resolve(
        refuse
          ? { data: null, error: { message: "daily rate limit reached" } }
          : { data: `reservation-${++next}`, error: null },
      );
    }
    return Promise.resolve({ data: null, error: null });
  };
  return { rpc, calls };
}

Deno.test("a reservation is released after the call", async () => {
  const { rpc, calls } = fakeRpc();
  const budget = new AiBudget(rpc, "user-1");
  assertEquals(await budget.reserve("meal_vision"), true);
  await budget.release();
  await budget.release();
  assertEquals(calls, [
    ["reserve_ai_budget", { target_user_id: "user-1", run_purpose: "meal_vision" }],
    ["settle_ai_budget", { reservation_id: "reservation-1" }],
  ]);
});

Deno.test("a refused reservation means no call", async () => {
  const { rpc, calls } = fakeRpc(true);
  const budget = new AiBudget(rpc, "user-1");
  assertEquals(await budget.reserve("coach_chat"), false);
  await budget.release();
  assertEquals(calls.length, 1);
});

Deno.test("a kept reservation stays open", async () => {
  const { rpc, calls } = fakeRpc();
  const budget = new AiBudget(rpc, "user-1");
  await budget.reserve("coach_chat");
  budget.keep();
  await budget.release();
  assertEquals(calls.map(([fn]) => fn), ["reserve_ai_budget"]);
});

Deno.test("a failed settle never throws", async () => {
  const budget = new AiBudget(
    (fn) =>
      fn === "reserve_ai_budget"
        ? Promise.resolve({ data: "reservation-1", error: null })
        : Promise.reject(new Error("network")),
    "user-1",
  );
  await budget.reserve("meal_vision");
  await budget.release();
});
