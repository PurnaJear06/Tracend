export interface SentryContext {
  userId?: string;
  functionName?: string;
  correlationId?: string;
  runtime?: string;
  provider?: string;
  model?: string;
  contextKind?: string;
  failureCode?: string;
  attempt?: string;
  finishReason?: string | null;
  coachingDate?: string;
  mealId?: string;
}

interface ParsedDsn {
  publicKey: string;
  url: string;
  projectId: string;
}

function parseDsn(dsn: string): ParsedDsn | null {
  const match = dsn.match(/^https?:\/\/([^@]+)@([^/]+)\/(\d+)$/);
  if (!match) return null;
  return {
    publicKey: match[1],
    url: `https://${match[2]}`,
    projectId: match[3],
  };
}

export function captureException(
  error: unknown,
  context?: SentryContext,
): void {
  const dsn = Deno.env.get("SENTRY_DSN") ?? "";
  if (!dsn) return;

  const parsed = parseDsn(dsn);
  if (!parsed) return;

  const event = buildSentryEvent(error, context);

  fetch(`${parsed.url}/api/${parsed.projectId}/store/`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-Sentry-Auth":
        `Sentry sentry_version=7, sentry_client=tracend-edge/1.0.0, sentry_timestamp=${
          Math.floor(Date.now() / 1000)
        }, sentry_key=${parsed.publicKey}`,
    },
    body: JSON.stringify(event),
  }).catch(() => {
    // Silent — Sentry failures must never affect the caller.
  });
}

export function buildSentryEvent(
  error: unknown,
  context?: SentryContext,
): Record<string, unknown> {
  const stack = error instanceof Error && typeof error.stack === "string"
    ? error.stack.slice(0, 4_000)
    : undefined;

  return {
    event_id: crypto.randomUUID(),
    timestamp: Math.floor(Date.now() / 1000),
    level: "error",
    platform: "javascript",
    exception: {
      values: [
        {
          type: error instanceof Error ? error.name : typeof error,
          value: error instanceof Error ? error.message : String(error),
        },
      ],
    },
    tags: {
      function: context?.functionName ?? "unknown",
      environment: Deno.env.get("TRACEND_ENV") ?? "unknown",
      runtime: context?.runtime ?? "edge",
      provider: context?.provider ?? "unknown",
      model: context?.model ?? "unknown",
      context_kind: context?.contextKind ?? "unknown",
      failure_code: context?.failureCode ?? "unknown",
      attempt: context?.attempt ?? "unknown",
      finish_reason: context?.finishReason ?? "unknown",
    },
    user: context?.userId ? { id: String(context.userId) } : undefined,
    extra: {
      correlationId: context?.correlationId,
      coachingDate: context?.coachingDate,
      mealId: context?.mealId,
      stack,
    },
  };
}
