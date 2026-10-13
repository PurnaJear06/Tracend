import { assertEquals } from "jsr:@std/assert@1.0.14";
import { hashToken } from "../_shared/waitlist.ts";
import { fakeDeps, post } from "../_shared/waitlist_fakes.ts";
import { handleConfirm } from "./index.ts";

const token = "A".repeat(43);

Deno.test("a valid link confirms by hash and returns the invite code", async () => {
  const { deps, calls } = fakeDeps({
    rpc: { waitlist_confirm: { data: { status: "confirmed", referral_code: "7K3M9QXZ" } } },
  });
  const res = await handleConfirm(post("waitlist-confirm", { token }), deps);
  assertEquals(res.status, 200);
  assertEquals(await res.json(), { status: "confirmed", referral_code: "7K3M9QXZ" });
  assertEquals(calls[0].args, { token_hash: await hashToken(token) });
});

Deno.test("expired and unsubscribed links pass their status through", async () => {
  for (const status of ["expired", "unsubscribed", "invalid"]) {
    const { deps } = fakeDeps({ rpc: { waitlist_confirm: { data: { status } } } });
    const res = await handleConfirm(post("waitlist-confirm", { token }), deps);
    assertEquals(await res.json(), { status });
  }
});

Deno.test("a malformed token is invalid without touching the database", async () => {
  for (const bad of ["short", "A".repeat(44), "A".repeat(42) + "!", 42]) {
    const { deps, calls } = fakeDeps();
    const res = await handleConfirm(post("waitlist-confirm", { token: bad }), deps);
    assertEquals(await res.json(), { status: "invalid" });
    assertEquals(calls.length, 0);
  }
});

Deno.test("a database error is a 500 the page can retry", async () => {
  const { deps, reports } = fakeDeps({ rpc: { waitlist_confirm: { data: null, error: {} } } });
  const res = await handleConfirm(post("waitlist-confirm", { token }), deps);
  assertEquals(res.status, 500);
  assertEquals(reports, ["confirm_failed"]);
});
