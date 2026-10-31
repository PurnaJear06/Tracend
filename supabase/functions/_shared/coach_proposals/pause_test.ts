import { assert, assertEquals, assertStringIncludes } from "jsr:@std/assert@1";
import { buildCoachProposal } from "./build.ts";
import { stateFixture } from "./fixtures.ts";
import { parseCoachProposalIntent } from "./intent.ts";
import {
  buildTrainingPause,
  maxPauseDays,
  parsePauseInputs,
  type PauseInputs,
  pauseRange,
} from "./pause.ts";
import { type ProposalRpc, proposeCoachChange } from "./service.ts";
import type { CoachProposalIntent } from "./types.ts";

const today = "2026-10-31";
const inputs = (pauses: PauseInputs["pauses"] = []): PauseInputs => ({
  today,
  screening: "cleared",
  pauses,
});
const pause = (startDate: string, endDate: string, reason = "rest", note?: string) =>
  ({
    kind: "training_pause",
    reason,
    startDate,
    endDate,
    ...(note === undefined ? {} : { note }),
  }) as Extract<CoachProposalIntent, { kind: "training_pause" }>;

Deno.test("a 15-day break from tomorrow is built as an overlay, with no plan change and no number of its own", () => {
  const built = buildTrainingPause(
    pause("2026-11-01", "2026-11-15", "rest", "taking a break"),
    inputs(),
  );
  assert(built.ok);
  const proposal = built.proposal;
  assertEquals(proposal.kind, "training_pause");
  assertEquals(proposal.title, "Break · 1–15 Nov");
  assertEquals(proposal.endsOn, "2026-11-15");
  assertEquals(proposal.payload, {
    pause: {
      start_date: "2026-11-01",
      end_date: "2026-11-15",
      reason: "rest",
      note: "taking a break",
    },
  });
  assertEquals(proposal.basis.training_version_id, null);
  assertEquals(proposal.basis.gates, []);
  assertEquals(proposal.after.rows, [
    { label: "Break", value: "1–15 Nov (15 days)" },
    { label: "Sessions", value: "None due during the break" },
    { label: "Plan resumes", value: "16 Nov" },
  ]);
  assertStringIncludes(proposal.rationale, 'In your words: "taking a break"');
});

Deno.test("a break is refused with a plain reason outside its limits", () => {
  const cases: [Extract<CoachProposalIntent, { kind: "training_pause" }>, string][] = [
    [pause("2026-11-05", "2026-11-01"), "dates_invalid"],
    [pause("2026-10-30", "2026-11-05"), "pause_start_past"],
    [pause("2026-11-03", "2026-11-10"), "pause_start_too_far"],
    [pause("2026-11-01", "2026-12-13"), "pause_too_long"],
    [pause("2026-11-01", "2026-11-05", "plateau"), "pause_reason_not_allowed"],
  ];
  for (const [intent, code] of cases) {
    const built = buildTrainingPause(intent, inputs());
    assert(!built.ok, code);
    assertEquals(built.code, code);
  }
  // The edges: today and two days ahead start; 42 days is the longest.
  assert(buildTrainingPause(pause(today, today), inputs()).ok);
  assert(buildTrainingPause(pause("2026-11-02", "2026-11-02"), inputs()).ok);
  assert(buildTrainingPause(pause("2026-11-01", "2026-12-12"), inputs()).ok);
  assertEquals(maxPauseDays, 42);
  const far = buildTrainingPause(pause("2026-11-03", "2026-11-10"), inputs());
  assert(!far.ok);
  assertStringIncludes(far.reason, "Ask for it again from 1 Nov.");
});

Deno.test("a break that overlaps another is refused; one right after it is not", () => {
  const running = [{ startDate: "2026-10-25", lastDay: "2026-11-02" }];
  const overlap = buildTrainingPause(pause("2026-11-01", "2026-11-05"), inputs(running));
  assert(!overlap.ok);
  assertEquals(overlap.code, "pause_overlaps");
  assertStringIncludes(overlap.reason, "25 Oct to 2 Nov");
  assert(
    buildTrainingPause(
      pause("2026-11-02", "2026-11-05"),
      inputs([
        { startDate: "2026-10-25", lastDay: "2026-11-01" },
      ]),
    ).ok,
  );
});

Deno.test("the builder entry point reads the breaks from the state; ranges read like the card", () => {
  const built = buildCoachProposal(pause("2026-10-18", "2026-10-20"), {
    ...stateFixture({}),
    pauses: [{ startDate: "2026-10-19", lastDay: "2026-10-21" }],
  });
  assert(!built.ok);
  assertEquals(built.code, "pause_overlaps");
  assertEquals(pauseRange("2026-10-28", "2026-11-03"), "28 Oct–3 Nov");
  assertEquals(pauseRange("2026-11-01", "2026-11-01"), "1 Nov");
});

Deno.test("the inputs payload is read strictly", () => {
  const good = {
    schema_version: "1.0",
    local_date: today,
    screening: "see_professional",
    pauses: [{ id: "p", start_date: "2026-10-25", last_day: "2026-11-02" }],
  };
  assertEquals(parsePauseInputs(good), {
    today,
    screening: "see_professional",
    pauses: [{ startDate: "2026-10-25", lastDay: "2026-11-02" }],
  });
  assertEquals(parsePauseInputs({ ...good, schema_version: "2.0" }), null);
  assertEquals(parsePauseInputs({ ...good, screening: "maybe" }), null);
  assertEquals(parsePauseInputs({ ...good, pauses: [{ start_date: "soon" }] }), null);
});

function pauseRpc(overrides: Record<string, unknown> = {}) {
  const calls: string[] = [];
  const stored: Record<string, unknown>[] = [];
  const rpc: ProposalRpc = (name, params) => {
    calls.push(name);
    if (name === "persist_coach_proposal_v1") stored.push(params);
    const table: Record<string, unknown> = {
      get_training_pause_inputs_v1: {
        schema_version: "1.0",
        local_date: today,
        screening: "see_professional",
        pauses: [],
      },
      persist_coach_proposal_v1: { proposal_id: "p-1", expires_at: "2026-11-01T10:00:00Z" },
      ...overrides,
    };
    return Promise.resolve({ data: table[name] ?? null, error: null });
  };
  return { rpc, calls, stored };
}

Deno.test("a break needs no profile: it never reads the athlete state and the health check never holds it back", async () => {
  const { rpc, calls, stored } = pauseRpc();
  const result = await proposeCoachChange(rpc, {
    userId: "u",
    intent: {
      kind: "training_pause",
      reason: "rest",
      note: "taking 15 days off",
      start_date: "2026-11-01",
      end_date: "2026-11-15",
    },
    athleteMessage: "I'm thinking of taking 15 days off from the gym from tomorrow",
  });
  assert(result.ok, JSON.stringify(result));
  assertEquals(result.kind, "training_pause");
  assertEquals(calls, ["get_training_pause_inputs_v1", "persist_coach_proposal_v1"]);
  assertEquals(stored[0].p_kind, "training_pause");
  assertEquals((stored[0].p_basis as Record<string, unknown>).screening, "see_professional");
  // The note is the athlete's own words, as they wrote them; a digit-free note only.
  assertEquals(
    (stored[0].p_payload as { pause: Record<string, unknown> }).pause.note,
    undefined,
  );
});

Deno.test("a break the database no longer fits is refused in plain words; an unreadable input is unavailable", async () => {
  const refused = await proposeCoachChange(
    ((name: string) =>
      Promise.resolve(
        name === "persist_coach_proposal_v1"
          ? { data: null, error: { code: "55000", message: "the break no longer fits" } }
          : {
            data: { schema_version: "1.0", local_date: today, screening: "cleared", pauses: [] },
            error: null,
          },
      )) as ProposalRpc,
    {
      userId: "u",
      intent: { kind: "training_pause", reason: "rest", start_date: today, end_date: today },
      athleteMessage: "I can't train today",
    },
  );
  assert(!refused.ok);
  assertEquals(refused.code, "pause_overlaps");
  const { rpc } = pauseRpc({ get_training_pause_inputs_v1: { schema_version: "9" } });
  const down = await proposeCoachChange(rpc, {
    userId: "u",
    intent: { kind: "training_pause", reason: "rest", start_date: today, end_date: today },
    athleteMessage: "",
  });
  assert(!down.ok);
  assertEquals(down.code, "unavailable");
  assert(
    parseCoachProposalIntent({ kind: "training_pause", reason: "rest", start_date: today }).ok ===
      false,
  );
});
