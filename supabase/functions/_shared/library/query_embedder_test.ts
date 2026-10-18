import { assert, assertEquals, assertRejects } from "jsr:@std/assert@1.0.14";
import { renderCoachContext } from "../coach_context/host.ts";
import { embeddingDimensions } from "./embedding.ts";
import { createQueryEmbedder, libraryEmbedPath } from "./query_embedder.ts";
import { createLibraryContributor, type LibrarySearchRequest } from "./retrieval.ts";

const vector = Array.from({ length: embeddingDimensions }, (_, index) => index / 1000);
const ok = (body: unknown = { schema_version: "1.0", embedding: vector }) =>
  Promise.resolve(new Response(JSON.stringify(body), { status: 200 }));

type Call = { url: string; init: RequestInit };
function embedderWith(respond: (call: Call) => Promise<Response>, timeoutMs = 1_000) {
  const calls: Call[] = [];
  let secretReads = 0;
  const embed = createQueryEmbedder({
    baseUrl: () => "https://abcdefghijklmnopqrst.supabase.co/",
    secret: () => {
      secretReads++;
      return Promise.resolve("worker-secret");
    },
    timeoutMs,
    fetch: ((url: string, init: RequestInit) => {
      const call = { url: String(url), init };
      calls.push(call);
      return respond(call);
    }) as unknown as typeof fetch,
  });
  return { embed, calls, secretReads: () => secretReads };
}

Deno.test("the question goes to library-embed with the worker secret, and only the question", async () => {
  const { embed, calls, secretReads } = embedderWith(() => ok());
  assertEquals(await embed("How much protein?"), vector);
  assertEquals(await embed("And on rest days?"), vector);
  assertEquals(calls[0].url, `https://abcdefghijklmnopqrst.supabase.co${libraryEmbedPath}`);
  assertEquals(calls[0].init.method, "POST");
  assertEquals(
    (calls[0].init.headers as Record<string, string>).Authorization,
    "Bearer worker-secret",
  );
  assertEquals(JSON.parse(String(calls[0].init.body)), { query: "How much protein?" });
  assertEquals(secretReads(), 1, "the secret is read once");
});

Deno.test("a refused secret is read again and the call retried once", async () => {
  let reads = 0;
  const bearers: string[] = [];
  const statuses = [401, 200];
  const embed = createQueryEmbedder({
    baseUrl: () => "https://abcdefghijklmnopqrst.supabase.co",
    secret: () => Promise.resolve(`secret-${++reads}`),
    timeoutMs: 1_000,
    fetch: ((_url: string, init: RequestInit) => {
      bearers.push((init.headers as Record<string, string>).Authorization);
      const status = statuses.shift() ?? 200;
      return status === 200 ? ok() : Promise.resolve(new Response("{}", { status }));
    }) as unknown as typeof fetch,
  });
  assertEquals(await embed("q"), vector);
  assertEquals(bearers, ["Bearer secret-1", "Bearer secret-2"]);
  assertEquals(await embed("q"), vector);
  assertEquals(reads, 2, "the new secret is kept");
  // Refused twice in a row: one retry only, then the error.
  statuses.push(401, 401);
  await assertRejects(() => embed("q"), Error, "library_embed_401");
  assertEquals(reads, 3);
});

Deno.test("a non-200, a bad body or an unreadable secret is an error", async () => {
  for (const status of [401, 400, 500, 503]) {
    const { embed } = embedderWith(() => Promise.resolve(new Response("{}", { status })));
    await assertRejects(() => embed("q"), Error, `library_embed_${status}`);
  }
  for (const body of [{}, { embedding: [1, 2, 3] }, { embedding: vector.map(() => "x") }]) {
    const { embed } = embedderWith(() => ok(body));
    await assertRejects(() => embed("q"), Error, "library_embed_shape_invalid");
  }
  const noSecret = createQueryEmbedder({
    baseUrl: () => "https://x.supabase.co",
    secret: () => Promise.reject(new Error("library_worker_secret_unavailable")),
    timeoutMs: 100,
    fetch: (() => ok()) as unknown as typeof fetch,
  });
  await assertRejects(() => noSecret("q"), Error, "library_worker_secret_unavailable");
});

Deno.test("a call that outlasts its timeout is abandoned", async () => {
  const { embed } = embedderWith(
    (call) =>
      new Promise((_, reject) => {
        (call.init.signal as AbortSignal).addEventListener(
          "abort",
          () => reject(new DOMException("aborted", "TimeoutError")),
        );
      }),
    20,
  );
  await assertRejects(() => embed("q"));
});

const rows = [{
  sourceId: "a_2020_one",
  title: "T",
  year: 2020,
  header: "H",
  body: "B",
}];

Deno.test("a 500 or a timeout from library-embed means word search, not a lost block", async () => {
  for (
    const respond of [
      () => Promise.resolve(new Response("boom", { status: 500 })),
      () => new Promise<Response>(() => {}),
    ]
  ) {
    const { embed } = embedderWith(respond, 20);
    const requests: LibrarySearchRequest[] = [];
    const contributor = createLibraryContributor({
      embed: () => embed,
      embedDeadlineMs: 30,
      search: (request) => {
        requests.push(request);
        return Promise.resolve(rows);
      },
    });
    const result = await renderCoachContext([contributor], {
      userId: "u",
      question: "Do I need creatine?",
      localDate: "2026-10-18",
    }, 2_000);
    assertEquals(result.outcomes.map((item) => item.outcome), ["rendered"]);
    assertEquals(requests.map((request) => request.embedding), [null]);
    assert(result.traces?.library.degraded !== "none");
  }
});

Deno.test("a good answer from library-embed gives the search its vector", async () => {
  const { embed } = embedderWith(() => ok());
  const requests: LibrarySearchRequest[] = [];
  const contributor = createLibraryContributor({
    embed: () => embed,
    search: (request) => {
      requests.push(request);
      return Promise.resolve(rows);
    },
  });
  await contributor.render({
    userId: "u",
    question: "Do I need creatine?",
    localDate: "2026-10-18",
  });
  assertEquals(requests[0].embedding, vector);
});
