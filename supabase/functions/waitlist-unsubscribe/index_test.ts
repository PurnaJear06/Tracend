import { assertEquals } from "jsr:@std/assert@1.0.14";
import { hashToken } from "../_shared/waitlist.ts";
import { fakeDeps, post } from "../_shared/waitlist_fakes.ts";
import { handleUnsubscribe } from "./index.ts";

const token = "B".repeat(43);
const done = { waitlist_unsubscribe: { data: { status: "unsubscribed" } } };

Deno.test("the unsubscribe page unsubscribes by token hash", async () => {
  const { deps, calls } = fakeDeps({ rpc: done });
  const res = await handleUnsubscribe(post("waitlist-unsubscribe", { token }), deps);
  assertEquals(await res.json(), { status: "unsubscribed" });
  assertEquals(calls[0].args, { token_hash: await hashToken(token) });
});

Deno.test("mail apps' one-tap unsubscribe works from the query string", async () => {
  const { deps, calls } = fakeDeps({ rpc: done });
  const res = await handleUnsubscribe(
    new Request(`https://ref.supabase.co/functions/v1/waitlist-unsubscribe?token=${token}`, {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: "List-Unsubscribe=One-Click",
    }),
    deps,
  );
  assertEquals(res.status, 200);
  assertEquals(calls[0].args, { token_hash: await hashToken(token) });
});

Deno.test("a malformed token is invalid without touching the database", async () => {
  const { deps, calls } = fakeDeps({ rpc: done });
  const res = await handleUnsubscribe(post("waitlist-unsubscribe", { token: "nope" }), deps);
  assertEquals(await res.json(), { status: "invalid" });
  assertEquals(calls.length, 0);
});

Deno.test("a GET (link preview or scanner) never unsubscribes", async () => {
  const { deps, calls } = fakeDeps({ rpc: done });
  const res = await handleUnsubscribe(
    new Request(`https://ref.supabase.co/functions/v1/waitlist-unsubscribe?token=${token}`),
    deps,
  );
  assertEquals(res.status, 405);
  assertEquals(calls.length, 0);
});
