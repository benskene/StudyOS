import { createHash } from "crypto";
import { env } from "../config/env";
import { pgPool } from "../db/postgres";
import { ParsedSyllabus, parsedSyllabusSchema } from "../types/syllabus";
import { logError, logInfo } from "../utils/logger";

/// Content address for an upload. Length-prefixed per file so that the same
/// bytes split across a different number of photos hash differently.
export function hashSyllabusFiles(files: { buffer: Buffer }[]): string {
  const hash = createHash("sha256");
  hash.update(`n=${files.length};`);
  for (const file of files) {
    hash.update(`len=${file.buffer.length};`);
    hash.update(file.buffer);
  }
  return hash.digest("hex");
}

/// Returns a previously parsed result for identical bytes on the same model,
/// or null. Cache problems are never fatal — a miss just costs one parse.
export async function lookupCachedParse(
  contentHash: string,
  model: string
): Promise<ParsedSyllabus | null> {
  try {
    const result = await pgPool.query<{ parsed: unknown }>(
      `SELECT parsed
         FROM syllabus_parse_cache
        WHERE content_hash = $1
          AND model = $2
          AND created_at > now() - ($3 || ' days')::interval`,
      [contentHash, model, String(env.SYLLABUS_CACHE_TTL_DAYS)]
    );

    const row = result.rows[0];
    if (!row) return null;

    // Re-validate: the schema may have changed since the entry was written.
    const validated = parsedSyllabusSchema.safeParse(row.parsed);
    if (!validated.success) {
      logInfo("Discarding syllabus cache entry that no longer validates", { contentHash, model });
      return null;
    }
    return validated.data;
  } catch (error) {
    logError("Syllabus cache lookup failed", error, { contentHash, model });
    return null;
  }
}

export async function storeCachedParse(
  contentHash: string,
  model: string,
  parsed: ParsedSyllabus
): Promise<void> {
  try {
    await pgPool.query(
      `INSERT INTO syllabus_parse_cache (content_hash, model, parsed)
       VALUES ($1, $2, $3)
       ON CONFLICT (content_hash, model)
       DO UPDATE SET parsed = EXCLUDED.parsed, created_at = now()`,
      [contentHash, model, JSON.stringify(parsed)]
    );
  } catch (error) {
    // Losing a cache write only costs a future parse.
    logError("Failed to store syllabus cache entry", error, { contentHash, model });
  }
}

export interface ParseQuota {
  allowed: boolean;
  used: number;
  limit: number;
  windowDays: number;
}

/// Counts billable parses (cache hits excluded) in the rolling window.
///
/// Fails open: if the count can't be read, the import proceeds. A database
/// blip shouldn't take syllabus import down entirely, and the per-user hourly
/// rate limiter still bounds the damage.
export async function checkParseQuota(userId: string): Promise<ParseQuota> {
  const limit = env.SYLLABUS_USER_PARSE_LIMIT;
  const windowDays = env.SYLLABUS_USER_PARSE_WINDOW_DAYS;

  try {
    const result = await pgPool.query<{ count: string }>(
      `SELECT count(*)::text AS count
         FROM syllabus_imports
        WHERE user_id = $1
          AND status = 'succeeded'
          AND cache_hit = false
          AND created_at > now() - ($2 || ' days')::interval`,
      [userId, String(windowDays)]
    );

    const used = Number(result.rows[0]?.count ?? 0);
    return { allowed: used < limit, used, limit, windowDays };
  } catch (error) {
    logError("Syllabus parse quota check failed; allowing request", error, { userId });
    return { allowed: true, used: 0, limit, windowDays };
  }
}
