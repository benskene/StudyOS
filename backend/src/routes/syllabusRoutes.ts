import { Router } from "express";
import multer from "multer";
import rateLimit from "express-rate-limit";
import { env } from "../config/env";
import { requireUserAuthentication } from "../middleware/authentication";
import { pgPool } from "../db/postgres";
import { ensureUser } from "../storage/userRepositoryPg";
import {
  parseSyllabus,
  fileKindFor,
  SyllabusParseError
} from "../services/syllabusParseService";
import {
  checkParseQuota,
  hashSyllabusFiles,
  lookupCachedParse,
  storeCachedParse
} from "../services/syllabusCacheService";
import { logError, logInfo } from "../utils/logger";

// Parsing costs real money per call, so this is tighter than the LMS import
// limiter: per-user, hourly window.
const syllabusRateLimiter = rateLimit({
  windowMs: env.SYLLABUS_RATE_LIMIT_WINDOW_MS,
  max: env.SYLLABUS_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.userId ?? req.ip ?? "unknown",
  message: { error: "Too many syllabus uploads. Try again in a bit." }
});

const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: env.SYLLABUS_MAX_FILE_MB * 1024 * 1024,
    files: 8
  }
});

export const syllabusRouter = Router();

// Accepts one PDF or up to 8 photos of a syllabus under the "syllabus" field.
syllabusRouter.post(
  "/syllabus",
  requireUserAuthentication,
  syllabusRateLimiter,
  upload.array("syllabus", 8),
  async (req, res) => {
    const firebaseUid = req.user!.userId;
    const files = (req.files as Express.Multer.File[] | undefined) ?? [];

    if (files.length === 0) {
      res.status(400).json({ error: "Attach a syllabus PDF or photos under the 'syllabus' field." });
      return;
    }

    const unsupported = files.find((file) => fileKindFor(file.mimetype) === null);
    if (unsupported) {
      res.status(400).json({
        error: `Unsupported file type: ${unsupported.mimetype}. Upload a PDF or JPEG/PNG/WebP photos.`
      });
      return;
    }

    const totalBytes = files.reduce((sum, file) => sum + file.size, 0);
    const fileKind = fileKindFor(files[0].mimetype)!;
    const contentHash = hashSyllabusFiles(files);
    const model = env.SYLLABUS_MODEL;

    // The quota and the imports ledger key off users.id, not the Firebase uid.
    // Resolving it is best-effort: a database blip shouldn't block imports.
    let dbUserId: string | null = null;
    try {
      dbUserId = await ensureUser(firebaseUid);
    } catch (error) {
      logError("Couldn't resolve user for syllabus import; skipping quota", error, { firebaseUid });
    }

    // Classmates upload the same syllabus PDF; serving an identical prior
    // parse costs nothing, so cache hits bypass the quota entirely.
    const cached = await lookupCachedParse(contentHash, model);
    if (cached) {
      logInfo("Syllabus parse served from cache", {
        firebaseUid,
        contentHash,
        model,
        deadlineCount: cached.deadlines.length
      });
      await recordImport(dbUserId, {
        fileKind,
        fileBytes: totalBytes,
        status: "succeeded",
        cacheHit: true,
        courseName: cached.course.name,
        deadlineCount: cached.deadlines.length
      });
      res.status(200).json(cached);
      return;
    }

    const quota = dbUserId ? await checkParseQuota(dbUserId) : null;
    if (quota && !quota.allowed) {
      logInfo("Syllabus parse quota exceeded", { firebaseUid, used: quota.used, limit: quota.limit });
      res.status(429).json({
        error: `You've imported ${quota.limit} syllabi recently, which is the current limit. Existing classes are unaffected — try again later, or remove a class you no longer need.`,
        code: "parse_quota_exceeded"
      });
      return;
    }

    try {
      const parsed = await parseSyllabus(
        files.map((file) => ({ buffer: file.buffer, mimeType: file.mimetype }))
      );

      await storeCachedParse(contentHash, model, parsed);

      await recordImport(dbUserId, {
        fileKind,
        fileBytes: totalBytes,
        status: "succeeded",
        cacheHit: false,
        courseName: parsed.course.name,
        deadlineCount: parsed.deadlines.length
      });

      logInfo("Syllabus parse completed", {
        firebaseUid,
        route: req.originalUrl,
        courseName: parsed.course.name,
        deadlineCount: parsed.deadlines.length,
        categoryCount: parsed.gradeCategories.length
      });

      res.status(200).json(parsed);
    } catch (error) {
      const parseError = error instanceof SyllabusParseError ? error : null;

      await recordImport(dbUserId, {
        fileKind,
        fileBytes: totalBytes,
        status: "failed",
        cacheHit: false,
        errorMessage: parseError?.code ?? "internal_error"
      });

      if (parseError) {
        logError("Syllabus parse failed", error, { firebaseUid, code: parseError.code });
        res.status(parseError.statusCode).json({ error: parseError.message, code: parseError.code });
        return;
      }

      logError("Syllabus parse failed unexpectedly", error, { firebaseUid, route: req.originalUrl });
      res.status(500).json({ error: "Couldn't read that syllabus right now. Please try again." });
    }
  }
);

async function recordImport(
  userId: string | null,
  entry: {
    fileKind: string;
    fileBytes: number;
    status: "succeeded" | "failed";
    cacheHit: boolean;
    errorMessage?: string;
    courseName?: string;
    deadlineCount?: number;
  }
): Promise<void> {
  // No resolved user means the ledger row would be orphaned; the request
  // itself already proceeded without a quota check.
  if (!userId) return;

  try {
    await pgPool.query(
      `INSERT INTO syllabus_imports
         (user_id, file_kind, file_bytes, model, status, error_message, course_name, deadline_count, cache_hit)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)`,
      [
        userId,
        entry.fileKind,
        entry.fileBytes,
        env.SYLLABUS_MODEL,
        entry.status,
        entry.errorMessage ?? null,
        entry.courseName ?? null,
        entry.deadlineCount ?? 0,
        entry.cacheHit
      ]
    );
  } catch (error) {
    // Bookkeeping must never fail the request.
    logError("Failed to record syllabus import", error, { userId });
  }
}
