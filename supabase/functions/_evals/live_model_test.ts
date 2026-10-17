import { assertEquals } from "jsr:@std/assert@1.0.14";
import { routedFetch } from "./live_model.ts";

Deno.test("a router run changes only the URL and says thinking is off", async () => {
  let sent: { url: string; init?: RequestInit } | undefined;
  const fetcher = routedFetch("https://router.example/v1/", (input, init) => {
    sent = { url: String(input), init };
    return Promise.resolve(new Response("{}"));
  });
  await fetcher("https://api.deepseek.com/v1/chat/completions", {
    method: "POST",
    headers: { Authorization: "Bearer synthetic-key" },
    body: JSON.stringify({ model: "deepseek-v4-flash", thinking: { type: "disabled" } }),
  });
  assertEquals(sent?.url, "https://router.example/v1/chat/completions");
  assertEquals(
    (sent?.init?.headers as Record<string, string>).Authorization,
    "Bearer synthetic-key",
  );
  assertEquals(JSON.parse(String(sent?.init?.body)), {
    model: "deepseek-v4-flash",
    thinking: { type: "disabled" },
    reasoning_effort: "none",
  });
});
