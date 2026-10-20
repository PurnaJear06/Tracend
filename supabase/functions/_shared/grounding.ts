// What may ground a figure in a Coach reply, said once. Every surface that shows Coach a stored
// value declares what it is, in the same three words, and a surface that does not declare a value
// grounds nothing with it (fail closed):
//
//   records    the athlete's records, Apple Health, Tracend's calculations, and what the athlete
//              approved or wrote: any figure in a reply may rest on it, including one that states
//              the athlete's own target ("your target is ...")
//   figures    what Tracend built for a proposal (its title, reason, gain and cost, its targets):
//              a figure may rest on it, but never one that states the athlete's own target,
//              because a proposal is not a target
//   modelText  what a model wrote, or Coach's own earlier words: shown, never evidence (a model's
//              words do not show a figure is true, and a reason or decision written on an earlier
//              day states figures that were true on that day)
//
// The surfaces are the athlete file (`providers/context_grounding.ts`), the lookups
// (`coach_lookups/render.ts`) and the contributors (`coach_context/grounding.ts`). A stored column
// that reaches more than one of them has one declaration here, which each of them imports, so the
// same column cannot be a record on one path and model text on another
// (`providers/context_grounding_test.ts` checks the three against each other).
export type Grounding = "records" | "figures" | "modelText";

export const columnGrounding = Object.freeze(
  {
    // The athlete approved the plan, and the app shows these names.
    "training_plans.title": "records",
    "planned_workouts.name": "records",
    "planned_exercises.name": "records",
    // Written with a model's help (the onboarding plan, a proposal, a daily decision).
    "training_plan_versions.rationale": "modelText",
    "nutrition_target_sets.rationale": "modelText",
    "coach_decisions.training_summary": "modelText",
    "coach_decisions.decision": "modelText",
    "coach_messages.coach_content": "modelText",
    // A proposal's text is built by Tracend's rules, and none of it is the athlete's target.
    "change_proposals.title": "figures",
    "change_proposals.rationale": "figures",
    "change_proposals.expected_benefit": "figures",
    "change_proposals.downside": "figures",
  } as const satisfies Record<string, Grounding>,
);

export type GroundedColumn = keyof typeof columnGrounding;

/**
 * The fields of a payload, by path (`a[].b` is the field `b` of each element of the list `a`; a
 * list of plain values is `a[]`), with what each grounds. A path that is a stored column names it
 * in `columns` and takes that column's declaration.
 */
export type Declaration = Readonly<{
  records?: readonly string[];
  figures?: readonly string[];
  modelText?: readonly string[];
  columns?: Readonly<Record<string, GroundedColumn>>;
  /**
   * Fields that only select and position the records (a mode, a key, a flag, a cut): kept when the
   * rows are read again from the declared fields so that they read as they did, and never evidence
   * by themselves.
   */
  controls?: readonly string[];
}>;

export type Resolved = Readonly<Record<Grounding | "controls", ReadonlySet<string>>>;

/** The declaration as three sets of paths. A path declared twice, or two ways, is a mistake. */
export function resolve(declaration: Declaration): Resolved {
  const sets: Record<Grounding | "controls", Set<string>> = {
    records: new Set(),
    figures: new Set(),
    modelText: new Set(),
    controls: new Set(),
  };
  const seen = new Set<string>();
  const put = (path: string, kind: Grounding | "controls") => {
    if (seen.has(path)) throw new Error(`${path} is declared twice`);
    seen.add(path);
    sets[kind].add(path);
  };
  for (const kind of ["records", "figures", "modelText", "controls"] as const) {
    for (const path of declaration[kind] ?? []) put(path, kind);
  }
  for (const [path, column] of Object.entries(declaration.columns ?? {})) {
    put(path, columnGrounding[column]);
  }
  return sets;
}

const primitive = (value: unknown) => value === null || typeof value !== "object";

/**
 * The payload with only the fields in `keep` left, and the shape of the lists as it was, so a
 * renderer can read it as before. A field that is not in `keep` is gone, declared or not.
 */
export function pruneTo(node: unknown, keep: ReadonlySet<string>, path = ""): unknown {
  if (Array.isArray(node)) {
    const item = `${path}[]`;
    return node.flatMap((element) => {
      const kept = primitive(element)
        ? (keep.has(item) ? element : undefined)
        : pruneTo(element, keep, item);
      return kept === undefined ? [] : [kept];
    });
  }
  if (node !== null && typeof node === "object") {
    const out: Record<string, unknown> = {};
    for (const [key, value] of Object.entries(node)) {
      const kept = pruneTo(value, keep, path === "" ? key : `${path}.${key}`);
      if (kept !== undefined) out[key] = kept;
    }
    return out;
  }
  return keep.has(path) ? node : undefined;
}

/** Every leaf of a payload as a path, in the notation of `Declaration`. */
export function leafPaths(node: unknown, path = "", out = new Set<string>()): Set<string> {
  if (Array.isArray(node)) {
    if (node.some(primitive)) out.add(`${path}[]`);
    for (const item of node) if (!primitive(item)) leafPaths(item, `${path}[]`, out);
    return out;
  }
  if (node !== null && typeof node === "object") {
    for (const [key, value] of Object.entries(node)) {
      leafPaths(value, path === "" ? key : `${path}.${key}`, out);
    }
    return out;
  }
  out.add(path);
  return out;
}
