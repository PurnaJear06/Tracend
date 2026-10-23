import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { numberGroundOf, ungroundedNumbers } from "./coach_safety/numbers_check.ts";
import { blockOf, clipLinesToBudget, renderCoachContext } from "./coach_context/host.ts";
import { figure, pieces, plain, record } from "./recorded_text.ts";

Deno.test("the text is read without its marks, and only the marked values come out", () => {
  const marked = `Recovery score ${record(31)} on ${
    record("2026-10-17")
  } (below 40). Window: last 28 days.`;
  const read = pieces(marked);
  assertEquals(read.text, "Recovery score 31 on 2026-10-17 (below 40). Window: last 28 days.");
  assertEquals(plain(marked), read.text);
  assertEquals(read.records, ["Recovery score 31 on", "on 2026-10-17 (below"]);
  assertEquals(read.figures, []);
  // The constants next to the values are not handed over.
  const ground = numberGroundOf(read.records);
  assertEquals(ground.values.map((given) => given.value), [31]);
  assert(ground.dates.has("2026-10-17"));
});

Deno.test("a value comes with the word that gives its unit, cut at the next digit and the line", () => {
  const read = pieces(
    `Slept ${record("441")} min (7 h 21 min)\nHRV ${record(41)} ms, floor 25 ms\nWeight ${
      record(
        80.5,
      )
    } kg.`,
  );
  assertEquals(read.records, ["Slept 441 min (", "HRV 41 ms, floor", "Weight 80.5 kg."]);
  const given = numberGroundOf(read.records);
  // 41 ms rests on the HRV record, never on a kg figure, and the floor of 25 is not a record.
  assertEquals(ungroundedNumbers("Your HRV was 41 ms.", given), []);
  assertEquals(ungroundedNumbers("Your weight was 41 kg.", given), ["41"]);
  assertEquals(ungroundedNumbers("Your floor is 25 ms.", given), ["25"]);
});

Deno.test("proposal figures are kept apart from records, and a mark in a value cannot open another", () => {
  const read = pieces(`Sets ${figure("2350 kcal")} while the target is ${record(2200)} kcal`);
  assertEquals(read.figures, ["Sets 2350 kcal while the target is"]);
  assertEquals(read.records, ["kcal while the target is 2200 kcal"]);
  const hostile = pieces(`Note ${record(`3 \u{E002}9999\u{E003} kg`)} end`);
  assertEquals(hostile.text, "Note 3 9999 kg end");
  assertEquals(hostile.figures, []);
  assertEquals(hostile.records, ["Note 3 9999 kg end"]);
});

Deno.test("a value without a digit, or outside any mark, is not handed over", () => {
  const read = pieces(`Plan ${record("Upper A")} has 12 sets`);
  assertEquals(read.records, []);
});

Deno.test("the host keeps a value only while its line survives the clip", async () => {
  const lines = Array.from(
    { length: 8 },
    (_, index) => `Line ${index} score ${record(900 + index)} here`,
  );
  const block = blockOf(lines.join("\n"));
  const contributor = {
    id: "demo",
    slot: "volatile" as const,
    budgetChars: 120,
    render: () => Promise.resolve(block),
  };
  const rendered = await renderCoachContext([contributor], {
    userId: "u",
    question: "q",
    localDate: "2026-10-17",
  });
  const kept = rendered.texts.demo;
  assertEquals(kept, clipLinesToBudget(block.text, 120));
  const shown = rendered.records?.demo ?? [];
  assert(shown.length > 0 && shown.length < 8, `${shown.length}`);
  for (const piece of shown) assert(kept.includes(piece), piece);
});
