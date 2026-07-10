import { assertEquals } from "jsr:@std/assert@1.0.14";
import { isExactDeletionConfirmation } from "./index.ts";

Deno.test("account deletion requires the exact destructive phrase", () => {
  assertEquals(isExactDeletionConfirmation("DELETE"), true);
  assertEquals(isExactDeletionConfirmation("delete"), false);
  assertEquals(isExactDeletionConfirmation("DELETE "), false);
});
