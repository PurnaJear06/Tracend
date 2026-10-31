import { assertEquals } from "jsr:@std/assert@1.0.14";
import { asciiDigits } from "./ascii_digits.ts";

Deno.test("digits of any script read as ASCII digits", () => {
  assertEquals(asciiDigits("४५ kg"), "45 kg");
  assertEquals(asciiDigits("٤٥ kg and ۴۵ kg"), "45 kg and 45 kg");
  assertEquals(asciiDigits("５０ kg"), "50 kg");
  assertEquals(asciiDigits("𝟓𝟎 kg and 𝟡𝟘"), "50 kg and 90");
  assertEquals(asciiDigits("74.8 kg, 1,900 kcal"), "74.8 kg, 1,900 kcal");
});
