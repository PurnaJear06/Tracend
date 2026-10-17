import { assert, assertEquals } from "jsr:@std/assert@1";
import { librarySources } from "../../../library/index.ts";
import { chunkSource } from "./chunk.ts";
import { sourceBlock } from "./migration_sql.ts";

const kinds = new Set(["paper", "guideline", "position_stand", "summary"]);

Deno.test("the library holds a few dozen sources with unique keys", () => {
  assert(librarySources.length >= 30 && librarySources.length <= 70, `${librarySources.length}`);
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
    assert(source.licence.trim().length > 0 && source.licence.length <= 200, `${where} licence`);
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
    ]
  ) {
    assert(count(topic) >= 1, `no source covers ${topic}`);
  }
  assert(count("screening") >= 2 && count("joint-friendly") >= 3 && count("sleep") >= 2);
});

Deno.test("the newest migration that loads each source carries its current content", async () => {
  const dir = new URL("../../../migrations/", import.meta.url);
  const migrations: { name: string; sql: string }[] = [];
  for await (const entry of Deno.readDir(dir)) {
    if (entry.isFile && entry.name.endsWith(".sql")) {
      migrations.push({ name: entry.name, sql: await Deno.readTextFile(new URL(entry.name, dir)) });
    }
  }
  migrations.sort((a, b) => a.name.localeCompare(b.name));
  for (const source of librarySources) {
    const marker = `-- library-source: ${source.slug} sha256:`;
    const loaders = migrations.filter((migration) => migration.sql.includes(marker));
    assert(loaders.length > 0, `no migration loads ${source.slug}`);
    const newest = loaders[loaders.length - 1];
    assert(
      newest.sql.includes(await sourceBlock(source)),
      `${source.slug} changed since ${newest.name}; add a migration with its new block ` +
        "(see _shared/library/migration_sql.ts)",
    );
  }
});
