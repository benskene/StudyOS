const REDACT_KEYS = new Set([
  "googleAccessToken",
  "googleRefreshToken",
  "access_token",
  "refresh_token",
  "id_token"
]);

function redactValue(key: string, value: unknown): unknown {
  if (REDACT_KEYS.has(key)) {
    return "[REDACTED]";
  }

  if (value && typeof value === "object") {
    if (Array.isArray(value)) {
      return value.map((entry) => redactValue(key, entry));
    }

    return Object.fromEntries(
      Object.entries(value).map(([nestedKey, nestedValue]) => [
        nestedKey,
        redactValue(nestedKey, nestedValue)
      ])
    );
  }

  return value;
}

export function logInfo(message: string, context?: Record<string, unknown>) {
  if (!context) {
    console.info(message);
    return;
  }

  console.info(message, redactValue("context", context));
}

export function logError(message: string, error: unknown, context?: Record<string, unknown>) {
  const safeError =
    error instanceof Error
      ? { name: error.name, message: error.message, stack: error.stack }
      : error;

  console.error(message, {
    error: redactValue("error", safeError),
    context: redactValue("context", context ?? {})
  });
}
