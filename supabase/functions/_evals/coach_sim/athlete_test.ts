// What the athlete model's reply becomes: a message, or nothing when it is cut off.
import { assertEquals } from "jsr:@std/assert@1.0.14";
import { parseAthleteMessage } from "./athlete.ts";

Deno.test("a JSON reply gives its message; a speaker label and extra spaces are removed", () => {
  assertEquals(
    parseAthleteMessage('{"message": "Arjun:  Ok,   what now?", "done": true}', "Arjun"),
    { message: "Ok, what now?", done: true },
  );
  assertEquals(parseAthleteMessage("Fine, and then?"), { message: "Fine, and then?", done: false });
});

Deno.test("a reply cut off inside its JSON is no message, so the athlete is asked again", () => {
  assertEquals(
    parseAthleteMessage('{"message": "Only at the bottom of split squats, not on'),
    null,
  );
  assertEquals(parseAthleteMessage('```json\n{"message": "Only at the'), null);
  assertEquals(parseAthleteMessage('{"message": ""}'), null);
});
