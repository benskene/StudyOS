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
    const userId = req.user!.userId;
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

    try {
      const parsed = await parseSyllabus(
        files.map((file) => ({ buffer: file.buffer, mimeType: file.mimetype }))
      );

      await recordImport(userId, {
        fileKind,
        fileBytes: totalBytes,
        status: "succeeded",
        courseName: parsed.course.name,
        deadlineCount: parsed.deadlines.length
      });

      logInfo("Syllabus parse completed", {
        userId,
        route: req.originalUrl,
        courseName: parsed.course.name,
        deadlineCount: parsed.deadlines.length,
        categoryCount: parsed.gradeCategories.length
      });

      res.status(200).json(parsed);
    } catch (error) {
      const parseError = error instanceof SyllabusParseError ? error : null;

      await recordImport(userId, {
        fileKind,
        fileBytes: totalBytes,
        status: "failed",
        errorMessage: parseError?.code ?? "internal_error"
      });

      if (parseError) {
        logError("Syllabus parse failed", error, { userId, code: parseError.code });
        res.status(parseError.statusCode).json({ error: parseError.message, code: parseError.code });
        return;
      }

      logError("Syllabus parse failed unexpectedly", error, { userId, route: req.originalUrl });
      res.status(500).json({ error: "Couldn't read that syllabus right now. Please try again." });
    }
  }
);

async function recordImport(
  firebaseUid: string,
  entry: {
    fileKind: string;
    fileBytes: number;
    status: "succeeded" | "failed";
    errorMessage?: string;
    courseName?: string;
    deadlineCount?: number;
  }
): Promise<void> {
  try {
    const userId = await ensureUser(firebaseUid);
    await pgPool.query(
      `INSERT INTO syllabus_imports
         (user_id, file_kind, file_bytes, model, status, error_message, course_name, deadline_count)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        userId,
        entry.fileKind,
        entry.fileBytes,
        env.SYLLABUS_MODEL,
        entry.status,
        entry.errorMessage ?? null,
        entry.courseName ?? null,
        entry.deadlineCount ?? 0
      ]
    );
  } catch (error) {
    // Bookkeeping must never fail the request.
    logError("Failed to record syllabus import", error, { firebaseUid });
  }
}
