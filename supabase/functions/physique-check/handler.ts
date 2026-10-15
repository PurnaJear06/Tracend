import { reply } from "../_shared/auth.ts";
import { eatingConcernPattern } from "../_shared/coach_chat_fallback.ts";
import {
  nothingToAssess,
  parsePhysiqueResult,
  type PhysiqueResult,
} from "../_shared/physique/contract.ts";
import { maxPhotoBytes, stripJpegMetadata } from "../_shared/physique/jpeg.ts";
import { type AiVendor, aiVendors } from "../_shared/ai/types.ts";
import {
  callPhysiqueGateway,
  callPhysiqueVision,
  type PhysiqueAthlete,
  type PhysiqueCall,
  physiqueCeilingUsd,
  type PhysiqueGatewayOptions,
  type PhysiquePhotos,
  PhysiqueVisionBilledError,
  PhysiqueVisionError,
  type PhysiqueVisionResolution,
  physiqueVisionRouteUnusable,
} from "../_shared/providers/physique_vision_provider.ts";

// POST physique-check (owner-only experiment, AI_SAFETY_SPEC §9).
//
// {"schema_version":"1.0","mode":"status"}: whether this account can run a
// check, and the provider photos would go to (the app names it). Only accounts in PHYSIQUE_VISION_ALLOWED_USERS, with the provider
// configured, and never when the athlete's own notes mention an eating
// concern. The provider is Groq today, or the AI gateway's route when
// AI_PHYSIQUE_VISION_* is set (then the granted notice must name the route's
// vendor, and the budget holds the route's ceiling for the check).
//
// {"schema_version":"1.0","mode":"check","photo_set_id":…}: sends the front,
// side and back photos of one complete set to the model after checking the
// current photo AI notice is granted and the AI budget allows it. A reply that
// suggests no muscle means the photos show nothing to judge (422
// photo_set_unassessable, no correction asked). A reply that breaks the
// contract gets one text-only correction when the provider's
// minute still has room; otherwise nothing is stored. The stored result is a
// suggestion: only muscles the athlete confirms (set_my_priority_muscles)
// become their focus.

const uuid = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;

/** A text-only correction needs about this many tokens of the minute's budget. */
export const repairTokens = 2_500;

export const checkedPoses = ["front", "side", "back"] as const;

export type PhotoSet = Readonly<{
  status: string;
  photos: readonly Readonly<{ pose: string; objectKey: string }>[];
}>;

export type PhysiqueUsage = Readonly<{
  model: string;
  inputUnits: number;
  outputUnits: number;
  estimatedCostUsd: number;
  latencyMs: number;
}>;

/** The current photo AI notice the athlete granted, and the vendor it names (null: none). */
export type GrantedNotice = Readonly<{ version: string; vendor: string | null }>;

export interface PhysiqueStore {
  /** The current photo AI notice when the athlete granted it, else null. */
  grantedNotice(): Promise<GrantedNotice | null>;
  /** Takes a place in the AI budget: the purpose's own ceiling, or ceilingUsd for the check. */
  budgetAvailable(ceilingUsd?: number): Promise<boolean>;
  /** The athlete's own free-text notes (limitations, nutrition). */
  profileNotes(): Promise<string[]>;
  loadSet(setId: string): Promise<PhotoSet | null>;
  download(objectKey: string): Promise<Uint8Array | null>;
  athlete(): Promise<PhysiqueAthlete>;
  persist(
    setId: string,
    result: PhysiqueResult,
    model: string,
    noticeVersion: string,
    metadata: Record<string, unknown>,
  ): Promise<string>;
  recordUsage(usage: PhysiqueUsage): Promise<void>;
}

export type Observer = Readonly<{
  info(event: string, fields: Record<string, unknown>): void;
  warn(event: string, fields: Record<string, unknown>): void;
}>;

export type PhysiqueDeps = Readonly<{
  userId: string;
  store: PhysiqueStore;
  resolution: PhysiqueVisionResolution;
  allowedUsers: ReadonlySet<string>;
  observer: Observer;
  /** Today's Groq call; tests replace it. */
  call?: typeof callPhysiqueVision;
  /** The gateway call's dependencies; tests pass a fake fetch. */
  gateway?: PhysiqueGatewayOptions;
}>;

/** Where a check's photos go and how its calls are made. */
type PhysiqueModel = Readonly<{
  label: string;
  model: string;
  /** null on today's path: the purpose's fixed ceiling. */
  ceilingUsd: number | null;
  /** Whether the granted notice covers this provider. */
  covers(notice: GrantedNotice): boolean;
  ask(
    athlete: PhysiqueAthlete,
    photos: PhysiquePhotos | null,
    repair: Readonly<{ previous: string; rule: string }> | null,
    notice: GrantedNotice,
  ): Promise<PhysiqueCall>;
  /** Whether a correction may follow this first call. */
  canRepair(first: PhysiqueCall): boolean;
}>;

function physiqueModel(deps: PhysiqueDeps): PhysiqueModel | null {
  const resolution = deps.resolution;
  if (resolution.kind === "ready") {
    const config = resolution.config;
    const call = deps.call ?? callPhysiqueVision;
    return {
      label: config.label,
      model: config.model,
      ceilingUsd: null,
      // Today's notices name Groq by their text; the check predates vendor ids.
      covers: () => true,
      ask: (athlete, photos, repair) => call(config, athlete, photos, repair),
      // Groq's free tier: only when its minute still has room.
      canRepair: (first) => first.remainingTokens !== null && first.remainingTokens >= repairTokens,
    };
  }
  if (resolution.kind === "gateway") {
    const gatewayRoute = resolution.route;
    const ceilingUsd = physiqueCeilingUsd(gatewayRoute);
    // Defence in depth: resolvePhysiqueVision already turns such a route off.
    if (ceilingUsd === null) return null;
    return {
      label: gatewayRoute.providerLabel,
      model: gatewayRoute.model,
      ceilingUsd,
      // The notice must name the vendor the route sends to.
      covers: (notice) => notice.vendor === gatewayRoute.vendor,
      ask: (athlete, photos, repair, notice) =>
        callPhysiqueGateway(
          gatewayRoute,
          aiVendors.find((vendor): vendor is AiVendor => vendor === notice.vendor) ?? null,
          athlete,
          photos,
          repair,
          deps.gateway,
        ),
      // The budget holds the correction from the start.
      canRepair: () => true,
    };
  }
  return null;
}

/**
 * Whether a check that failed with this error may give its budget place back. Only a refusal
 * (429) or an HTTP error rules out billing, and an unusable answer's usage is already recorded.
 * A timeout, a dropped connection or an unreadable answer may have been billed with no usage
 * reported, so the reservation stays open and keeps counting.
 */
export function billingSettled(error: unknown): boolean {
  return error instanceof PhysiqueVisionBilledError ||
    (error instanceof PhysiqueVisionError &&
      (error.code === "physique_vision_busy" ||
        error.code.startsWith("physique_vision_request_failed")));
}

async function available(deps: PhysiqueDeps): Promise<boolean> {
  if (!physiqueModel(deps)) return false;
  if (!deps.allowedUsers.has(deps.userId.toLowerCase())) return false;
  const notes = await deps.store.profileNotes();
  return !notes.some((note) => eatingConcernPattern.test(note.toLowerCase()));
}

/** The set's three checked photos as clean JPEGs, or why they cannot be sent. */
async function preparePhotos(
  store: PhysiqueStore,
  set: PhotoSet,
): Promise<PhysiquePhotos | "unsupported" | "unavailable"> {
  const prepared: Partial<Record<typeof checkedPoses[number], Uint8Array>> = {};
  for (const pose of checkedPoses) {
    const photo = set.photos.find((item) => item.pose === pose);
    if (!photo) return "unsupported";
    const bytes = await store.download(photo.objectKey);
    if (!bytes) return "unavailable";
    const clean = stripJpegMetadata(bytes);
    if (!clean || clean.length > maxPhotoBytes) return "unsupported";
    prepared[pose] = clean;
  }
  return prepared as PhysiquePhotos;
}

export async function handlePhysiqueCheck(
  deps: PhysiqueDeps,
  body: Record<string, unknown>,
): Promise<Response> {
  if (body.schema_version !== "1.0" || !["status", "check"].includes(body.mode as string)) {
    return reply(422, { error: "invalid_physique_request" });
  }
  if (deps.resolution.kind === "off" && deps.resolution.reason === physiqueVisionRouteUnusable) {
    deps.observer.warn(physiqueVisionRouteUnusable, {});
  }
  const enabled = await available(deps);
  if (body.mode === "status") {
    return reply(200, {
      schema_version: "1.0",
      enabled,
      ...(enabled ? { provider_label: physiqueModel(deps)!.label } : {}),
    });
  }
  if (typeof body.photo_set_id !== "string" || !uuid.test(body.photo_set_id)) {
    return reply(422, { error: "invalid_physique_request" });
  }
  const model = physiqueModel(deps);
  if (!enabled || !model) {
    return reply(403, { error: "physique_check_unavailable" });
  }
  const { store, observer } = deps;
  const notice = await store.grantedNotice();
  // A notice for another provider is no consent for this one: nothing is sent.
  if (!notice || !model.covers(notice)) return reply(403, { error: "photo_ai_consent_required" });
  const budgetAvailable = model.ceilingUsd === null
    ? await store.budgetAvailable()
    : await store.budgetAvailable(model.ceilingUsd);
  if (!budgetAvailable) return reply(429, { error: "ai_usage_limit" });
  const set = await store.loadSet(body.photo_set_id);
  if (!set || set.status !== "complete") return reply(404, { error: "photo_set_not_found" });
  const photos = await preparePhotos(store, set);
  if (photos === "unsupported") return reply(422, { error: "photo_set_unsupported" });
  if (photos === "unavailable") return reply(503, { error: "physique_check_failed" });
  const athlete = await store.athlete();

  const calls: PhysiqueCall[] = [];
  let recorded = 0;
  // Every billed call is recorded once, before anything is stored. A failed
  // record is reported but never turns an answer into a failure: retrying
  // would pay for another call.
  const record = async () => {
    while (recorded < calls.length) {
      const spent = calls[recorded++];
      try {
        await store.recordUsage({
          model: spent.model ?? model.model,
          inputUnits: spent.inputUnits,
          outputUnits: spent.outputUnits,
          estimatedCostUsd: spent.estimatedCostUsd,
          latencyMs: spent.latencyMs,
        });
      } catch {
        observer.warn("physique_check_usage_not_recorded", { attempt: recorded });
      }
    }
  };
  try {
    calls.push(await model.ask(athlete, photos, null, notice));
    let parsed = parsePhysiqueResult(calls[0].content);
    const firstRule = parsed.ok ? null : parsed.rule;
    if (!parsed.ok && parsed.rule !== nothingToAssess && model.canRepair(calls[0])) {
      calls.push(
        await model.ask(athlete, null, { previous: calls[0].content, rule: parsed.rule }, notice),
      );
      parsed = parsePhysiqueResult(calls[1].content);
    }
    const metadata = {
      attempts: calls.length,
      latency_ms: calls.reduce((total, spent) => total + spent.latencyMs, 0),
      input_units: calls.reduce((total, spent) => total + spent.inputUnits, 0),
      output_units: calls.reduce((total, spent) => total + spent.outputUnits, 0),
      ...(firstRule ? { first_rule_broken: firstRule } : {}),
    };
    if (!parsed.ok && parsed.rule === nothingToAssess) {
      // The photos show nothing to judge: tell the athlete to retake them.
      await record();
      observer.info("physique_check_nothing_to_assess", metadata);
      return reply(422, { error: "photo_set_unassessable" });
    }
    if (!parsed.ok) {
      await record();
      observer.warn("physique_check_invalid", { ...metadata, rule: parsed.rule });
      return reply(502, { error: "physique_check_invalid" });
    }
    await record();
    const analysisId = await store.persist(
      body.photo_set_id,
      parsed.result,
      calls[calls.length - 1].model ?? model.model,
      notice.version,
      metadata,
    );
    observer.info("physique_check_complete", metadata);
    return reply(200, { schema_version: "1.0", analysis_id: analysisId, result: parsed.result });
  } catch (error) {
    // An answer that arrived but cannot be used was billed: it counts like the others.
    if (error instanceof PhysiqueVisionBilledError) calls.push(error.spent);
    if (error instanceof PhysiqueVisionError && error.code === "physique_vision_busy") {
      // A refused request is not billed; an earlier answered call in this
      // check still is.
      await record();
      observer.warn("physique_check_busy", { attempts: calls.length });
      return reply(429, { error: "physique_check_busy" });
    }
    await record();
    throw error;
  }
}
