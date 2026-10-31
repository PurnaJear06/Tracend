import { assert, assertEquals, assertThrows } from "jsr:@std/assert@1.0.14";
import {
  buildOnboardingProposal,
  type OnboardingPlan,
  OnboardingPlanValidationError,
  parseOnboardingPlan,
  type PlanLibraryContext,
  type PlanPolicies,
  validateOnboardingPlan,
} from "./plan_contract.ts";
import { buildRulesPlan } from "./rules_plan.ts";
import { answersFor, equipmentSets, policiesFor } from "./test_helpers.ts";

// Plans that cite the research library (chunk E5): the contract refuses a source the prompt did
// not show, the server labels a citation from the retrieved title, and a plan that cites nothing
// says so, and a search that found nothing lowers confidence.

const base = policiesFor(answersFor({ equipment: equipmentSets.dumbbells }));
const found: PlanLibraryContext = {
  status: "found",
  labels: {
    schoenfeld_2017_weekly_volume: "Schoenfeld et al. 2017, weekly volume (2017)",
    morton_2018_protein: "Morton et al. 2018, protein (2018)",
  },
};
const withLibrary = (library: PlanLibraryContext): PlanPolicies => ({ ...base, library });
const rules = buildRulesPlan(base);
const aiOrigin = { origin: "ai", provider: "anthropic", model: "m", fallbackReason: null } as const;
const rulesOrigin = {
  origin: "rules",
  provider: null,
  model: null,
  fallbackReason: "provider_timeout",
} as const;
const citing = (...sources: string[]): OnboardingPlan => ({
  ...rules,
  confidence: "high",
  sources,
});

Deno.test("sources are optional in the model's JSON and default to none", () => {
  const { sources: _sources, ...withoutSources } = rules;
  assertEquals(parseOnboardingPlan(JSON.stringify(withoutSources)).sources, []);
  const parsed = parseOnboardingPlan(
    JSON.stringify({ ...rules, sources: ["morton_2018_protein", "morton_2018_protein"] }),
  );
  assertEquals(parsed.sources, ["morton_2018_protein"]);
});

Deno.test("sources must be a list of at most four short texts", () => {
  const rule = (sources: unknown) =>
    assertThrows(
      () => parseOnboardingPlan(JSON.stringify({ ...rules, sources })),
      OnboardingPlanValidationError,
    ).rule;
  assertEquals(rule("morton_2018_protein"), "invalid_type");
  assertEquals(rule([1]), "invalid_type");
  assertEquals(rule(["a_2018_a", "b_2018_b", "c_2018_c", "d_2018_d", "e_2018_e"]), "list_too_long");
  assertEquals(rule([""]), "missing_field");
});

Deno.test("a source the prompt did not show is refused, with the path of the citation", () => {
  const error = assertThrows(
    () =>
      validateOnboardingPlan(
        citing("morton_2018_protein", "invented_2020_topic"),
        withLibrary(found),
      ),
    OnboardingPlanValidationError,
  );
  assertEquals(error.rule, "source_not_retrieved");
  assertEquals(error.path, "$.sources[1]");
  // With no library at all, nothing can be cited.
  assertEquals(
    assertThrows(
      () => validateOnboardingPlan(citing("morton_2018_protein"), base),
      OnboardingPlanValidationError,
    ).rule,
    "source_not_retrieved",
  );
  // Object.prototype names are not sources.
  assertEquals(
    assertThrows(
      () => validateOnboardingPlan(citing("constructor"), withLibrary(found)),
      OnboardingPlanValidationError,
    ).rule,
    "source_not_retrieved",
  );
  validateOnboardingPlan(citing("morton_2018_protein"), withLibrary(found));
});

Deno.test("a cited source becomes library evidence labelled from the retrieval", () => {
  const policies = withLibrary(found);
  const proposal = buildOnboardingProposal(
    citing("schoenfeld_2017_weekly_volume", "morton_2018_protein"),
    policies,
    aiOrigin,
  );
  assertEquals(proposal.evidence.slice(-2), [
    {
      code: "schoenfeld_2017_weekly_volume",
      label: "Schoenfeld et al. 2017, weekly volume (2017)",
      source: "library",
    },
    { code: "morton_2018_protein", label: "Morton et al. 2018, protein (2018)", source: "library" },
  ]);
  // The athlete's own evidence stays first, and nothing is added about a missing source.
  assertEquals(proposal.evidence[0].code, "ONBOARDING_ANSWERS_CONFIRMED");
  assertEquals(
    proposal.confidence,
    buildOnboardingProposal(citing(), base, aiOrigin).confidence,
  );
  assert(
    !(proposal.training.missing_information as string[]).some((line) => line.includes("research")),
  );
});

Deno.test("a plan that cites nothing says so in the not-known list", () => {
  const baseline = buildOnboardingProposal(citing(), base, aiOrigin).confidence;
  const proposal = buildOnboardingProposal(citing(), withLibrary(found), aiOrigin);
  // Excerpts were shown and none was cited: the note, and the confidence as it was.
  assertEquals(proposal.confidence, baseline);
  assert(
    (proposal.training.missing_information as string[]).includes(
      "No research source is cited for this plan; its numbers come from Tracend's safe ranges and your answers.",
    ),
  );
  assertEquals(proposal.evidence.some((item) => item.source === "library"), false);
});

Deno.test("a search that found nothing, or failed, lowers confidence and says so", () => {
  for (const status of ["none", "unavailable"] as const) {
    const proposal = buildOnboardingProposal(
      { ...citing(), confidence: "medium" },
      withLibrary({ status, labels: {} }),
      aiOrigin,
    );
    assertEquals(proposal.confidence, "low", status);
    const missing = proposal.training.missing_information as string[];
    assert(
      missing.some((line) =>
        status === "none"
          ? line.startsWith("No research source is cited for this plan")
          : line.startsWith("The research library could not be searched for this plan")
      ),
      status,
    );
  }
});

Deno.test("the note is not pushed out by the model's own list", () => {
  const proposal = buildOnboardingProposal(
    { ...citing(), confidence: "low", missing_information: ["a", "b", "c", "d"] },
    withLibrary({ status: "none", labels: {} }),
    aiOrigin,
  );
  const missing = proposal.training.missing_information as string[];
  assertEquals(missing.length, 4);
  assert(missing.some((line) => line.startsWith("No research source is cited")));
});

Deno.test("the rules plan and a plan built without the library are unchanged", () => {
  const unchanged = buildOnboardingProposal(rules, base, rulesOrigin);
  const viaLibrary = buildOnboardingProposal(
    rules,
    withLibrary({ status: "unavailable", labels: {} }),
    rulesOrigin,
  );
  assertEquals(viaLibrary, unchanged);
  // An AI plan built where the library was never searched (the settings path) adds no note.
  const settings = buildOnboardingProposal({ ...rules, confidence: "high" }, base, aiOrigin);
  assert(
    !(settings.training.missing_information as string[]).some((line) => line.includes("research")),
  );
  assertEquals(settings.evidence.some((item) => item.source === "library"), false);
  assertEquals(rules.sources, []);
});
