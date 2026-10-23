import { assert, assertEquals } from "jsr:@std/assert@1";
import { librarySources } from "../../../library/index.ts";
import { chunkSource } from "./chunk.ts";
import { retireBlock, retireMarker, sourceBlock } from "./migration_sql.ts";
import { type LibraryLicence, verbatimLicences } from "./types.ts";

const kinds = new Set(["paper", "guideline", "position_stand", "summary"]);
const licences = new Set<LibraryLicence>([
  "CC-BY-2.0",
  "CC-BY-3.0",
  "CC-BY-4.0",
  "CC-BY-NC-4.0",
  "CC-BY-NC-ND-4.0",
  "CC-BY-NC-SA-3.0-IGO",
  "OGL-UK-3.0",
  "public-domain-us-gov",
  "proprietary",
]);

Deno.test("the library holds up to about 150 sources with unique keys", () => {
  assert(librarySources.length >= 30 && librarySources.length <= 150, `${librarySources.length}`);
  const keys = librarySources.map((source) => source.slug);
  assertEquals(new Set(keys).size, keys.length);
  const dois = librarySources.flatMap((source) => source.doi === null ? [] : [source.doi]);
  assertEquals(new Set(dois).size, dois.length);
});

Deno.test("every source records what the database requires, including its licence", () => {
  for (const source of librarySources) {
    const where = source.slug;
    assert(/^[a-z0-9][a-z0-9_.-]{0,119}$/.test(source.slug), where);
    assert(source.title.trim().length > 0 && source.title.length <= 500, where);
    assert(source.label.trim().length > 0, where);
    assert(source.authors.length > 0, where);
    assert(source.year >= 1900 && source.year <= 2100, where);
    assert(source.doi === null || /^10\.\d{4,9}\/\S+$/.test(source.doi), `${where} doi`);
    assert(source.url.startsWith("https://") && source.url.length <= 2000, `${where} url`);
    if (source.doi !== null) assert(source.url === `https://doi.org/${source.doi}`, `${where} url`);
    assert(licences.has(source.licence), `${where} licence`);
    assert(/^\d{4}-\d{2}-\d{2}$/.test(source.lastReviewed), `${where} lastReviewed`);
    assertEquals(
      new Date(`${source.lastReviewed}T00:00:00Z`).toISOString().slice(0, 10),
      source.lastReviewed,
      `${where} lastReviewed`,
    );
    assert(
      /Summarised from the (full text|full document|official summary|abstract only)\b[^.]*\.$/.test(
        source.chosenBecause,
      ),
      `${where} chosenBecause must end with what the summary was written from`,
    );
    assert(source.region.length > 0, where);
    for (const region of source.region) {
      assert(/^(global|[A-Z]{2})$/.test(region), `${where} region`);
    }
    assert(source.topics.length > 0, where);
    assert(source.evidenceLevel.trim().length > 0 && source.evidenceLevel.length <= 100, where);
    assert(kinds.has(source.kind), where);
    assert(source.chosenBecause.trim().length > 0, where);
  }
});

Deno.test("verbatim text is allowed only under CC BY (not NC or ND), OGL or US public domain", () => {
  for (const licence of verbatimLicences) {
    assert(/^(CC-BY-\d\.\d|OGL-UK-3\.0|public-domain-us-gov)$/.test(licence), licence);
  }
  for (const source of librarySources) {
    if (source.verbatimAllowed) {
      assert(verbatimLicences.has(source.licence), `${source.slug}: ${source.licence}`);
    }
  }
  const verbatim = librarySources.filter((source) => source.verbatimAllowed);
  assert(verbatim.every((source) => !/NC|ND|SA|proprietary/.test(source.licence)));
});

Deno.test("a superseded source names a newer source in the library", () => {
  const bySlug = new Map(librarySources.map((source) => [source.slug, source]));
  for (const source of librarySources) {
    if (source.supersededBy === undefined) continue;
    const newer = bySlug.get(source.supersededBy);
    assert(newer !== undefined, `${source.slug} is superseded by a missing source`);
    assert(newer.slug !== source.slug && newer.year >= source.year, source.slug);
    assertEquals(newer.supersededBy, undefined, `${newer.slug} is itself superseded`);
  }
  assertEquals(
    bySlug.get("acsm_2009_progression")?.supersededBy,
    "acsm_2026_resistance_prescription",
  );
});

Deno.test("every source has several chunks that fit the embedding window", () => {
  for (const source of librarySources) {
    const chunks = chunkSource(source);
    assert(chunks.length >= 2, `${source.slug} has ${chunks.length} chunks`);
    for (const chunk of chunks) {
      assert(chunk.body.trim().length > 0 && chunk.body.length <= 1400, source.slug);
      assert(chunk.header.startsWith("Source: "), source.slug);
      assert(chunk.tokenCount >= 1 && chunk.tokenCount <= 512, `${source.slug} tokens`);
    }
  }
});

Deno.test("the sources cover every area the knowledge base was asked to cover", () => {
  const count = (topic: string) =>
    librarySources.filter((source) => source.topics.includes(topic)).length;
  for (
    const topic of [
      "training",
      "hypertrophy",
      "strength",
      "volume",
      "frequency",
      "rest",
      "progression",
      "deload",
      "time-efficient",
      "nutrition",
      "protein",
      "energy-balance",
      "timing",
      "creatine",
      "caffeine",
      "hydration",
      "cardio",
      "activity",
      "sleep",
      "recovery",
      "screening",
      "joint-friendly",
      "diet-break",
      "metabolic-adaptation",
      "low-energy-availability",
      "weight-maintenance",
      "behaviour-change",
      "habits",
      "alcohol",
      "detraining",
      "home-training",
      "older-adults",
      "menstrual-cycle",
      "india",
      "periodisation",
      "autoregulation",
      "rpe",
      "tapering",
      "free-weights",
      "range-of-motion",
      "exercise-substitution",
      "injury-risk",
      "acwr",
      "hiit",
      "cardio-fitness",
      "energy-surplus",
      "recomposition",
      "cold-water-immersion",
      "beta-alanine",
      "nitrate",
      "plant-protein",
      "vegetarian",
      "sleep-loss",
      "sex-differences",
      "oral-contraceptives",
      "bodyweight",
      "minimal-dose",
      "travel",
      "bmi",
      "food-composition",
    ]
  ) {
    assert(count(topic) >= 1, `no source covers ${topic}`);
  }
  assert(count("screening") >= 2 && count("joint-friendly") >= 3 && count("sleep") >= 2);
  assert(count("india") >= 5 && count("older-adults") >= 3 && count("supplements") >= 5);
  const regions = new Set(librarySources.flatMap((source) => source.region));
  for (const region of ["global", "US", "GB", "IN", "AU"]) assert(regions.has(region), region);
});

Deno.test("each regional module has a nutrition source and a body-measure source for its region", () => {
  // Decision D5: India, the United States, the United Kingdom and Australia. A body-measure
  // source covers BMI or waist size, the points that differ by region.
  for (const region of ["IN", "US", "GB", "AU"]) {
    const own = librarySources.filter((source) => source.region.includes(region));
    assert(
      own.some((source) => source.topics.includes("nutrition")),
      `${region} has no nutrition source`,
    );
    assert(
      own.some((source) => source.topics.includes("bmi") || source.topics.includes("waist")),
      `${region} has no body-measure source`,
    );
  }
  const global = librarySources.filter((source) => source.region.includes("global"));
  assert(global.some((source) => source.topics.includes("waist")), "no global waist source");
});

async function migrations(): Promise<{ name: string; sql: string }[]> {
  const dir = new URL("../../../migrations/", import.meta.url);
  const found: { name: string; sql: string }[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      found.push({ name: entry.name, sql: await Deno.readTextFile(new URL(entry.name, dir)) });
    }
  }
  return found.sort((a, b) => a.name.localeCompare(b.name));
}

const loadMarker = (key: string) => `-- library-source: ${key} sha256:`;
/** Index of the newest migration holding the text, or -1. */
const newestWith = (all: readonly { sql: string }[], text: string) =>
  all.findLastIndex((migration) => migration.sql.includes(text));

Deno.test("the newest migration that loads each source carries its current content", async () => {
  const all = await migrations();
  for (const source of librarySources) {
    const newest = newestWith(all, loadMarker(source.slug));
    assert(newest >= 0, `no migration loads ${source.slug}`);
    assert(
      all[newest].sql.includes(await sourceBlock(source)),
      `${source.slug} changed since ${all[newest].name}; add a migration with its new block ` +
        "(see _shared/library/migration_sql.ts)",
    );
    assert(
      newestWith(all, retireMarker(source.slug)) < newest,
      `${source.slug} is retired after its newest load; load it again in a later migration`,
    );
  }
});

Deno.test("a source removed from index.ts is retired by a migration after its last load", async () => {
  const all = await migrations();
  const listed = new Set(librarySources.map((source) => source.slug));
  const loaded = new Set(
    all.flatMap((migration) =>
      [...migration.sql.matchAll(/^-- library-source: ([a-z0-9_.-]+) sha256:/gm)].map((m) => m[1])
    ),
  );
  for (const key of [...loaded].filter((item) => !listed.has(item))) {
    assert(
      newestWith(all, retireBlock(key)) > newestWith(all, loadMarker(key)),
      `${key} is no longer in index.ts; add a migration with its retire block ` +
        `(build_migration.ts --retire ${key})`,
    );
  }
});

Deno.test("a retire block names one manifest key", () => {
  assertEquals(
    retireBlock("old_2019_source"),
    "-- library-retire: old_2019_source\nselect private.library_retire_source('old_2019_source');\n",
  );
  let refused = "";
  try {
    retireBlock("x'); drop table y; --");
  } catch (error) {
    refused = (error as Error).message;
  }
  assert(refused.startsWith("not a manifest key"));
});
