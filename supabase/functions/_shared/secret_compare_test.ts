import { assertEquals } from "jsr:@std/assert@1.0.14";
import { bearerMatches, secretsMatch } from "./secret_compare.ts";

Deno.test("a secret matches only itself", async () => {
  assertEquals(await secretsMatch("alpha", "alpha"), true);
  assertEquals(await secretsMatch("alpha", "alphb"), false);
  assertEquals(await secretsMatch("alpha", "alph"), false);
  assertEquals(await secretsMatch("", "alpha"), false);
});

Deno.test("a bearer header must be exactly Bearer plus the secret", async () => {
  assertEquals(await bearerMatches("Bearer s3cret", "s3cret"), true);
  assertEquals(await bearerMatches("bearer s3cret", "s3cret"), false);
  assertEquals(await bearerMatches("Bearer s3cret ", "s3cret"), false);
  assertEquals(await bearerMatches("s3cret", "s3cret"), false);
  assertEquals(await bearerMatches(null, "s3cret"), false);
});
