// The cycle cases test what they say they test: the athlete's turn carries the cycle block (her
// notice names cycle data), each bad reply is caught by the cycle rule it is there for, and the
// same athlete under the live notice gets no cycle block at all.
import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1.0.14";
import { cycleLongGapIn } from "../../_shared/coach_context/contributors/cycle.ts";
import { cycleCases, cycleGuardCases } from "./cases_cycle.ts";
import { guardRules } from "./graders.ts";
import { prepare, renderTurn } from "./harness.ts";

const ruleOf: Readonly<Record<string, string>> = {
  "cycle-fertile-window": "fertility_or_contraception_claim",
  "cycle-late-period": "fertility_or_contraception_claim",
  "cycle-condition-not-named": "cycle_condition_named",
  "cycle-long-gap-cut": "deficit_advice_with_long_gap",
  "cycle-contraception-advice": "fertility_or_contraception_claim",
};

Deno.test("every cycle guard case renders the cycle block and its bad reply breaks the rule it is for", async () => {
  assertEquals(cycleGuardCases.map((item) => item.id).sort(), Object.keys(ruleOf).sort());
  for (const bank of cycleGuardCases) {
    const run = await prepare(bank);
    assertStringIncludes(run.firstRound.texts.cycle ?? "", "Menstrual cycle", bank.id);
    assertEquals(cycleLongGapIn(run.firstRound), bank.id === "cycle-long-gap-cut", bank.id);
    for (const bad of bank.bad ?? []) {
      const rules = guardRules(run.context, bank.question, run.contributions, bad.reply, []);
      assert(rules.includes(ruleOf[bank.id]), `${bank.id}: ${rules.join(", ")}`);
    }
    for (const good of bank.good ?? []) {
      assertEquals(
        guardRules(run.context, bank.question, run.contributions, good, []),
        [],
        bank.id,
      );
    }
  }
});

Deno.test("the same athletes under the live notice get no cycle block, and the deeper cut is not refused for it", async () => {
  for (const bank of cycleCases) {
    const athlete = bank.athlete();
    const live = {
      ...athlete,
      contributors: { ...athlete.contributors, noticeVersion: undefined },
    };
    const turn = await renderTurn(live, bank.question);
    assertEquals(turn.texts.cycle, undefined, bank.id);
    assert(!/menstrual cycle/i.test(turn.volatile), bank.id);
  }
  const gap = cycleGuardCases.find((item) => item.id === "cycle-long-gap-cut")!;
  const athlete = gap.athlete();
  const live = { ...athlete, contributors: { ...athlete.contributors, noticeVersion: undefined } };
  const turn = await renderTurn(live, gap.question);
  const rules = guardRules(
    athlete.context,
    gap.question,
    turn,
    "Keep your deficit going, it's working.",
    [],
  );
  assert(!rules.includes("deficit_advice_with_long_gap"), rules.join(", "));
});
