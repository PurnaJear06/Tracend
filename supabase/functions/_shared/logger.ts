export type LogLevel = "debug" | "info" | "warn" | "error";

const LOG_LEVELS: Record<LogLevel, number> = {
  debug: 0,
  info: 1,
  warn: 2,
  error: 3,
};

function getLogLevel(): LogLevel {
  const env = Deno.env.get("LOG_LEVEL");
  if (env && env in LOG_LEVELS) return env as LogLevel;
  return "info";
}

export interface Logger {
  debug(msg: string, data?: Record<string, unknown>): void;
  info(msg: string, data?: Record<string, unknown>): void;
  warn(msg: string, data?: Record<string, unknown>): void;
  error(msg: string, data?: Record<string, unknown>): void;
}

function formatLog(
  level: LogLevel,
  msg: string,
  correlationId: string | undefined,
  data?: Record<string, unknown>,
): string {
  const entry: Record<string, unknown> = {
    level,
    ts: new Date().toISOString(),
    msg,
    ...data,
  };
  if (correlationId) entry.correlation_id = correlationId;
  return JSON.stringify(entry);
}

export function createLogger(correlationId?: string): Logger {
  const threshold = LOG_LEVELS[getLogLevel()];

  return {
    debug(msg, data) {
      if (LOG_LEVELS.debug >= threshold) {
        console.debug(formatLog("debug", msg, correlationId, data));
      }
    },
    info(msg, data) {
      if (LOG_LEVELS.info >= threshold) {
        console.log(formatLog("info", msg, correlationId, data));
      }
    },
    warn(msg, data) {
      if (LOG_LEVELS.warn >= threshold) {
        console.warn(formatLog("warn", msg, correlationId, data));
      }
    },
    error(msg, data) {
      if (LOG_LEVELS.error >= threshold) {
        console.error(formatLog("error", msg, correlationId, data));
      }
    },
  };
}

export function extractCorrelationId(request: Request): string {
  const fromHeader = request.headers.get("X-Correlation-Id");
  if (fromHeader) return fromHeader;
  return crypto.randomUUID();
}
