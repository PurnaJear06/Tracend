// The owner's own-photo check for the vision features (AI_SAFETY_SPEC §8 and §9). It runs before
// any production route is set: the synthetic drawings in the other evals test the contract and
// refusals, not recognition of real food or real bodies.
//
// It sends the owner's own photos from a local folder to Anthropic through the same gateway
// request the features send: the meal photo goes through analyzeMealWithGateway
// (meal-analyze/vision.ts) and a physique set through handlePhysiqueCheck (physique-check/handler.ts),
// so the instructions, schema, model, settings, JPEG cleaning and the physique contract are the
// features' own code, not a copy. It prints the parsed results for the owner to judge. It stores
// nothing and touches no database, Storage or production setting.
//
//   set -a; . ./.env; set +a    # ANTHROPIC_API_KEY, never printed
//   ./scripts/deno.sh run --allow-env --allow-net=api.anthropic.com --allow-read=<folder> \
//     supabase/functions/_evals/owner_photo_check.ts meal <folder> [--cap-usd 1]
//   ./scripts/deno.sh run --allow-env --allow-net=api.anthropic.com --allow-read=<folder> \
//     supabase/functions/_evals/owner_photo_check.ts physique <folder> [--cap-usd 1]
//
// meal: every .jpg / .jpeg in <folder> is one meal photo.
// physique: every sub-folder of <folder> is one set holding front.jpg, side.jpg and back.jpg.
//
// The route is the cutover's own (docs/runbooks/phase2-claude-cutover.md): meal Haiku 5.5 with
// 1500 output tokens and 30 s, physique Sonnet 5.5 with 800 and 60 s. AI_MEAL_VISION_* and
// AI_PHYSIQUE_VISION_* in the environment override them, so the owner can check the exact
// settings they mean to set. EVALUATED is true in this process only: it is what this check is for.
//
// The photos go only to api.anthropic.com. The check stops before a call whose worst case would
// pass the spend cap (--cap-usd, default 1.00, at most 10). Exit code: 0 the check ran, 2 bad
// arguments or settings, 3 stopped at the cap. The pass or fail judgement is the owner's.

import { type Env, route } from "../_shared/ai/routes.ts";
import type { AiCallDeps, AiRoute } from "../_shared/ai/types.ts";
import { MealVisionBilledError } from "../_shared/providers/gemini_meal_vision_provider.ts";
import {
  type PhysiqueAthlete,
  physiqueCeilingUsd,
} from "../_shared/providers/physique_vision_provider.ts";
import { analyzeMealWithGateway, mealVisionCeilingUsd } from "../meal-analyze/vision.ts";
import { handlePhysiqueCheck, type PhysiqueStore } from "../physique-check/handler.ts";

export type Mode = "meal" | "physique";

export type FolderEntry = Readonly<{ name: string; isDirectory: boolean }>;

/** Everything the check touches outside itself, so a test can run it offline. */
export type CheckIo = Readonly<{
  /** The process environment: only AI_*_VISION_* and ANTHROPIC_API_KEY are read. */
  env: Env;
  fetch?: typeof fetch;
  listDir(path: string): Promise<FolderEntry[]>;
  readFile(path: string): Promise<Uint8Array>;
  log(line: string): void;
}>;

export const defaultCapUsd = 1;
export const maxCapUsd = 10;

const defaults: Record<Mode, Record<string, string>> = {
  meal: {
    AI_MEAL_VISION_PROVIDER: "anthropic",
    AI_MEAL_VISION_MODEL: "claude-haiku-5-5",
    AI_MEAL_VISION_MAX_OUTPUT_TOKENS: "2000",
    AI_MEAL_VISION_TIMEOUT_MS: "30000",
  },
  physique: {
    AI_PHYSIQUE_VISION_PROVIDER: "anthropic",
    AI_PHYSIQUE_VISION_MODEL: "claude-sonnet-5-5",
    AI_PHYSIQUE_VISION_MAX_OUTPUT_TOKENS: "800",
    AI_PHYSIQUE_VISION_TIMEOUT_MS: "60000",
  },
};

const jpegName = /\.jpe?g$/i;
const sorted = (entries: readonly FolderEntry[]) =>
  [...entries].sort((a, b) => a.name.localeCompare(b.name));

function parseArguments(
  args: readonly string[],
): { mode: Mode; folder: string; capUsd: number } | string {
  const [mode, folder, ...rest] = args;
  if (mode !== "meal" && mode !== "physique") return "The first argument is meal or physique.";
  if (!folder) return "The second argument is the folder holding your photos.";
  let capUsd = defaultCapUsd;
  if (rest.length > 0) {
    if (rest.length !== 2 || rest[0] !== "--cap-usd") {
      return `Unexpected arguments: ${rest.join(" ")}`;
    }
    capUsd = Number(rest[1]);
    if (!Number.isFinite(capUsd) || capUsd <= 0 || capUsd > maxCapUsd) {
      return `--cap-usd must be above 0 and at most ${maxCapUsd}.`;
    }
  }
  return { mode, folder, capUsd };
}

function routeFor(mode: Mode, io: CheckIo): AiRoute | null {
  const feature = mode === "meal" ? "meal_vision" : "physique_vision";
  const prefix = `AI_${feature.toUpperCase()}_`;
  const env: Env = (name) => {
    if (name === `${prefix}EVALUATED`) return "true";
    return io.env(name) ?? defaults[mode][name];
  };
  return route(feature, env);
}

const dollars = (usd: number) => `USD ${usd.toFixed(4)}`;

export async function runOwnerPhotoCheck(args: readonly string[], io: CheckIo): Promise<number> {
  const parsed = parseArguments(args);
  if (typeof parsed === "string") {
    io.log(`${parsed}\nUsage: owner_photo_check.ts <meal|physique> <folder> [--cap-usd <n>]`);
    return 2;
  }
  const { mode, folder, capUsd } = parsed;
  const gatewayRoute = routeFor(mode, io);
  if (!gatewayRoute) {
    io.log(
      "No route: ANTHROPIC_API_KEY must be set, and any AI_*_VISION_* setting you override valid.",
    );
    return 2;
  }
  const ceilingUsd = mode === "meal"
    ? mealVisionCeilingUsd(gatewayRoute)
    : physiqueCeilingUsd(gatewayRoute);
  if (ceilingUsd === null) {
    io.log("These settings are above what one AI call may reserve: lower the output tokens.");
    return 2;
  }
  io.log(
    `${mode} check: ${gatewayRoute.vendor} ${gatewayRoute.model}, ${gatewayRoute.maxOutputTokens} ` +
      `output tokens, ${gatewayRoute.timeoutMs / 1000} s. Spend cap ${dollars(capUsd)}, worst ` +
      `case ${dollars(ceilingUsd)} a ${
        mode === "meal" ? "photo" : "set"
      }. Photos go to Anthropic only.`,
  );
  const items = mode === "meal" ? await mealItems(folder, io) : await physiqueItems(folder, io);
  if (typeof items === "string") {
    io.log(items);
    return 2;
  }
  let spent = 0;
  const addSpend = (usd: number) => {
    spent += usd;
  };
  for (const [index, item] of items.entries()) {
    if (spent + ceilingUsd > capUsd) {
      io.log(
        `\nStopped before ${item.label}: ${dollars(spent)} spent, and one more could reach ` +
          `${dollars(spent + ceilingUsd)}, over the ${
            dollars(capUsd)
          } cap. ${index} of ${items.length} done.`,
      );
      return 3;
    }
    io.log(`\n[${index + 1}/${items.length}] ${item.label}`);
    await item.run(gatewayRoute, io, addSpend);
  }
  io.log(`\nDone: ${items.length} checked, ${dollars(spent)} spent. Judge the output above.`);
  return 0;
}

type Item = Readonly<{
  label: string;
  run(gatewayRoute: AiRoute, io: CheckIo, addSpend: (usd: number) => void): Promise<void>;
}>;

async function mealItems(folder: string, io: CheckIo): Promise<Item[] | string> {
  const photos = sorted(
    (await io.listDir(folder)).filter((e) => !e.isDirectory && jpegName.test(e.name)),
  );
  if (photos.length === 0) return `No .jpg or .jpeg photos in ${folder}.`;
  return photos.map((entry) => ({
    label: entry.name,
    async run(gatewayRoute, check, addSpend) {
      const bytes = await check.readFile(`${folder}/${entry.name}`);
      const deps: AiCallDeps = { fetch: check.fetch };
      try {
        const result = await analyzeMealWithGateway(gatewayRoute, bytes, "image/jpeg", {
          enabled: true,
          consentVendor: gatewayRoute.vendor,
          deps,
        });
        addSpend(result.estimatedCostUsd);
        check.log(`  ${result.model}, ${dollars(result.estimatedCostUsd)}`);
        if (result.candidates.length === 0) check.log("  no food found");
        for (const food of result.candidates) {
          check.log(
            `  - ${food.name} | ${food.serving_label} | ${food.calories} kcal, ` +
              `P ${food.protein_g} g, C ${food.carbohydrate_g} g, F ${food.fat_g} g | ` +
              `confidence ${food.confidence} | ${food.image_kind}, ${food.source}`,
          );
          if (food.kcal_per_g !== null) {
            check.log(
              `      per gram ${food.kcal_per_g} kcal; serving ${food.serving_g ?? "-"} g, ` +
                `pack ${food.pack_g ?? "-"} g, ${food.servings_per_pack ?? "-"} servings`,
            );
          }
          if (food.label_issues.length > 0) {
            check.log(`      label checks failed: ${food.label_issues.join(", ")}`);
          }
          if (food.assumptions.length > 0) {
            check.log(`      assumed: ${food.assumptions.join("; ")}`);
          }
          if (food.question) check.log(`      asks: ${food.question}`);
        }
      } catch (error) {
        if (error instanceof MealVisionBilledError) addSpend(error.usage.estimatedCostUsd);
        check.log(`  no usable answer: ${error instanceof Error ? error.message : String(error)}`);
      }
    },
  }));
}

const poses = ["front", "side", "back"] as const;
const owner = "0f6b3a1e-1111-4111-8111-111111111111";
const setId = "5a1c2b3d-2222-4222-8222-222222222222";

// The athlete data line only carries what the owner's account would; none is invented here.
const noAthleteData: PhysiqueAthlete = {
  sex: null,
  height_cm: null,
  weight_kg: null,
  waist_cm: null,
  chest_cm: null,
  hip_cm: null,
  arm_cm: null,
  thigh_cm: null,
  goal: null,
};

async function physiqueItems(folder: string, io: CheckIo): Promise<Item[] | string> {
  const sets = sorted((await io.listDir(folder)).filter((e) => e.isDirectory));
  if (sets.length === 0) {
    return `No sets in ${folder}: put each set in its own sub-folder with front.jpg, side.jpg and back.jpg.`;
  }
  const items: Item[] = [];
  for (const set of sets) {
    const files = await io.listDir(`${folder}/${set.name}`);
    const byPose = new Map<string, string>();
    for (const pose of poses) {
      const match = files.find((e) =>
        !e.isDirectory && e.name.toLowerCase().replace(jpegName, "") === pose &&
        jpegName.test(e.name)
      );
      if (match) byPose.set(pose, `${folder}/${set.name}/${match.name}`);
    }
    if (byPose.size !== poses.length) {
      return `Set ${set.name} needs front.jpg, side.jpg and back.jpg.`;
    }
    items.push({
      label: `set ${set.name}`,
      async run(gatewayRoute, check, addSpend) {
        const events: Record<string, unknown>[] = [];
        let stored: unknown = null;
        const store: PhysiqueStore = {
          grantedNotice: () =>
            Promise.resolve({ version: "owner-check", vendor: gatewayRoute.vendor }),
          budgetAvailable: () => Promise.resolve(true),
          profileNotes: () => Promise.resolve([]),
          loadSet: () =>
            Promise.resolve({
              status: "complete",
              photos: poses.map((pose) => ({ pose, objectKey: byPose.get(pose)! })),
            }),
          download: (path) => check.readFile(path),
          athlete: () => Promise.resolve(noAthleteData),
          persist: (_set, result) => {
            stored = result;
            return Promise.resolve("owner-check");
          },
          recordUsage: (usage) => {
            addSpend(usage.estimatedCostUsd);
            check.log(
              `  call: ${usage.model}, ${usage.inputUnits} in, ${usage.outputUnits} out, ` +
                `${dollars(usage.estimatedCostUsd)}`,
            );
            return Promise.resolve();
          },
        };
        const response = await handlePhysiqueCheck({
          userId: owner,
          store,
          resolution: { kind: "gateway", route: gatewayRoute },
          allowedUsers: new Set([owner]),
          observer: {
            info: (event, fields) => events.push({ event, ...fields }),
            warn: (event, fields) => events.push({ event, ...fields }),
          },
          gateway: { deps: { fetch: check.fetch } },
        }, { schema_version: "1.0", mode: "check", photo_set_id: setId });
        const body = await response.json().catch(() => ({})) as Record<string, unknown>;
        if (stored !== null) {
          check.log(JSON.stringify(stored, null, 2).split("\n").map((l) => `  ${l}`).join("\n"));
          return;
        }
        check.log(`  no result stored: ${response.status} ${String(body.error ?? "")}`.trimEnd());
        const broken = events.find((e) => e.first_rule_broken)?.first_rule_broken;
        if (broken) check.log(`  rule the first reply broke: ${String(broken)}`);
      },
    });
  }
  return items;
}

if (import.meta.main) {
  const code = await runOwnerPhotoCheck(Deno.args, {
    env: (name) => Deno.env.get(name),
    listDir: async (path) => {
      const entries: FolderEntry[] = [];
      for await (const entry of Deno.readDir(path)) {
        entries.push({ name: entry.name, isDirectory: entry.isDirectory });
      }
      return entries;
    },
    readFile: (path) => Deno.readFile(path),
    log: (line) => console.log(line),
  });
  Deno.exit(code);
}
