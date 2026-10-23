// Test helper for what a contributor's text grounds in a reply's numbers check. A contributor mixes
// fixed wording (windows, thresholds, definitions, an id) with the values it was given. The probe
// renders a contributor on fixture data, takes every number in its text that is not one of the
// values it marked, and asserts that none of them grounds, for the figures a reply may cite
// (`ground`) and for what a reply may state as the athlete's own data or target (`athleteGround`).
// It also asserts the other way round: every value the contributor marked is a value of the fixture
// (or one of the values the test lists as calculated from it), so a constant marked as a record
// fails, and every marked value grounds.
import { assert, assertEquals } from "jsr:@std/assert@1.0.14";
import { numberGroundOf } from "../../coach_safety/numbers_check.ts";
import { replyCheckInputsFor } from "../../providers/coach_chat_provider.ts";
import { noCoachContributions, type RenderedBlock } from "../host.ts";
import { groundingOf } from "../grounding.ts";

type Given = Readonly<{ value: number; unit: string }>;
const keyOf = (given: Given) => `${given.value}|${given.unit}`;

/** The numbers in a fixture, written as numbers; dates are left out (they are checked as dates). */
export function numbersIn(fixture: unknown): Set<number> {
  const json = JSON.stringify(fixture).replace(/\d{4}-\d{2}-\d{2}(?:T[\d:.]+Z?)?/g, " ");
  return new Set([...json.matchAll(/\d+(?:\.\d+)?/g)].map((match) => Number(match[0])));
}

export type Probe = Readonly<{
  id: string;
  block: RenderedBlock;
  /** The data the block was made from: the numbers in it are the block's record values. */
  fixture: unknown;
  /** The record values the block states that are calculated from the fixture, not in it. */
  calculated?: readonly number[];
  /**
   * Every number in the text that is not a record value, as `value|unit` ("28|d"): the fixed
   * wording. Listed in full, so a new constant in a contributor has to be classified here.
   */
  fixed: readonly string[];
}>;

export type ProbeResult = ReturnType<typeof replyCheckInputsFor>;

export function probeContributor(probe: Probe): ProbeResult {
  const { id, block } = probe;
  assertEquals(groundingOf(id), "records", `${id} is declared records`);
  assert((block.records?.length ?? 0) > 0, `${id} hands the host no record values`);
  const inputs = replyCheckInputsFor(
    { coaching_date: "2026-10-17", permitted_evidence: [] },
    "Status?",
    {
      ...noCoachContributions,
      texts: { [id]: block.text },
      records: { [id]: block.records ?? [] },
      figures: { [id]: block.figures ?? [] },
    },
  );
  const textGround = numberGroundOf([block.text]);
  const recordGround = numberGroundOf(block.records ?? []);
  const figureGround = numberGroundOf(block.figures ?? []);
  // A number counts as marked by its value: the unit the numbers check reads for a value can differ
  // between the text (a line break after it) and the words around it that the contributor handed
  // over, and only the fixture's own numbers are chosen to keep the two apart.
  const marked = new Set(
    [...recordGround.values, ...figureGround.values].map((given) => given.value),
  );
  const fixed = textGround.values.filter((given) => !marked.has(given.value));
  assertEquals(
    fixed.map(keyOf).sort(),
    [...probe.fixed].sort(),
    `${id}: the numbers in the text that are not record values`,
  );
  // Fixed wording grounds nothing, whichever way the reply uses it.
  const grounds = (side: "ground" | "athleteGround", given: Given) =>
    inputs[side]!.values.some((have) => keyOf(have) === keyOf(given));
  for (const given of fixed) {
    assert(!grounds("ground", given), `${id}: fixed ${keyOf(given)} grounds a figure`);
    assert(!grounds("athleteGround", given), `${id}: fixed ${keyOf(given)} grounds athlete data`);
  }
  // A marked value is a value of the fixture; and it grounds, as a record or as a proposal figure.
  const known = numbersIn(probe.fixture);
  for (const value of probe.calculated ?? []) known.add(value);
  for (const given of [...recordGround.values, ...figureGround.values]) {
    assert(known.has(given.value), `${id}: ${keyOf(given)} is marked but is not in the fixture`);
    assert(grounds("ground", given), `${id}: ${keyOf(given)} does not ground`);
  }
  for (const given of recordGround.values) {
    assert(grounds("athleteGround", given), `${id}: record ${keyOf(given)} does not ground`);
  }
  for (const given of figureGround.values) {
    if (recordGround.values.some((have) => keyOf(have) === keyOf(given))) continue;
    assert(
      !grounds("athleteGround", given),
      `${id}: proposal figure ${keyOf(given)} is the athlete's`,
    );
  }
  // Every date in the text is a record: the fixed wording of a contributor holds none.
  for (const date of textGround.dates) {
    assert(recordGround.dates.has(date) || figureGround.dates.has(date), `${id}: ${date}`);
    assert(inputs.ground.dates.has(date), `${id}: date ${date} does not ground`);
  }
  return inputs;
}
