import { parseCoachRequest } from "./coach_request_v1.ts";

Deno.test("coach request accepts bounded identity-free input", () => {
  const parsed = parseCoachRequest({
    schema_version: "1.0",
    local_date: "2026-07-02",
    timezone: "Asia/Kolkata",
    idempotency_key: "7e7d8f27-6d93-4ef7-a331-e0332b16850d",
  });
  if (parsed.timezone !== "Asia/Kolkata") throw new Error("Unexpected timezone");
});

Deno.test("coach request rejects client ownership", () => {
  let rejected = false;
  try {
    parseCoachRequest({
      schema_version: "1.0",
      local_date: "2026-07-02",
      timezone: "Asia/Kolkata",
      idempotency_key: "7e7d8f27-6d93-4ef7-a331-e0332b16850d",
      user_id: "attacker",
    });
  } catch {
    rejected = true;
  }
  if (!rejected) throw new Error("Ownership fields must be rejected");
});
