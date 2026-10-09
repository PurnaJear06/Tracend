import { assert, assertFalse } from "jsr:@std/assert@1";
import { isSafeStorageKey, isUserStorageKey } from "./storage_keys.ts";

const user = "11111111-1111-4111-8111-111111111111";
const other = "22222222-2222-4222-8222-222222222222";

Deno.test("keys the app writes are accepted", () => {
  assert(isUserStorageKey(user, `${user}/meal/33333333-3333-4333-8333-333333333333.jpg`));
  assert(
    isUserStorageKey(user, `${user}/progress/44444444-4444-4444-8444-444444444444/front.heic`),
  );
  assert(isUserStorageKey(user, `${user}/55555555-5555-4555-8555-555555555555.tracendexport`));
});

Deno.test("keys that could resolve elsewhere are refused", () => {
  for (
    const key of [
      `${user}/meal/../../${other}/meal/a.jpg`,
      `${user}/meal/./a.jpg`,
      `${user}/meal//a.jpg`,
      `${user}/meal/%2e%2e/a.jpg`,
      `${user}/meal/..%2fa.jpg`,
      `${user}\\meal\\a.jpg`,
      `${user}/meal/a.jpg\n`,
      `${user}/meal/.hidden`,
      `/${user}/meal/a.jpg`,
      `${user}/`,
      "",
    ]
  ) {
    assertFalse(isSafeStorageKey(key) && isUserStorageKey(user, key), key);
  }
  assertFalse(isSafeStorageKey(null));
  assertFalse(isSafeStorageKey("a/".repeat(300)));
});

Deno.test("another user's folder is refused", () => {
  assertFalse(isUserStorageKey(user, `${other}/meal/a.jpg`));
  assertFalse(isUserStorageKey(user, `${user}x/meal/a.jpg`));
  assertFalse(isUserStorageKey(user, user));
});
