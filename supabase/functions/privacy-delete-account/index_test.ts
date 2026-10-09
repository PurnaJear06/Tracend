import { assertEquals } from "jsr:@std/assert@1.0.14";
import { deletableKeys, isExactDeletionConfirmation } from "./index.ts";

Deno.test("account deletion requires the exact destructive phrase", () => {
  assertEquals(isExactDeletionConfirmation("DELETE"), true);
  assertEquals(isExactDeletionConfirmation("delete"), false);
  assertEquals(isExactDeletionConfirmation("DELETE "), false);
});

Deno.test("account deletion sends Storage only safe keys in the user's folder", () => {
  const user = "11111111-1111-4111-8111-111111111111";
  assertEquals(
    deletableKeys(user, [
      `${user}/meal/a.jpg`,
      `${user}/meal/../../22222222-2222-4222-8222-222222222222/meal/b.jpg`,
      "22222222-2222-4222-8222-222222222222/meal/c.jpg",
      null,
    ]),
    { keys: [`${user}/meal/a.jpg`], unsafe: 2 },
  );
});

Deno.test("a key listed twice is removed once", () => {
  const user = "11111111-1111-4111-8111-111111111111";
  assertEquals(
    deletableKeys(user, [`${user}/meal/a.jpg`, `${user}/meal/a.jpg`]),
    { keys: [`${user}/meal/a.jpg`], unsafe: 0 },
  );
});
