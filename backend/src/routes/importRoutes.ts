import { Router } from "express";
import { z } from "zod";
import { requireUserAuthentication } from "../middleware/authentication";
import { importRateLimiter } from "../middleware/importRateLimiter";
import { getUserAuthRecord } from "../storage/userAuthRepository";
import { getCanvasAuthRecord } from "../storage/canvasAuthRepository";
import { GoogleClassroomService } from "../services/googleClassroomService";
import { CanvasService } from "../services/canvasService";
import { logError, logInfo } from "../utils/logger";

const importRequestSchema = z
  .object({
    existingExternalIds: z.array(z.string().min(1)).default([])
  })
  .default({ existingExternalIds: [] });

export const importRouter = Router();

importRouter.post(
  "/google-classroom",
  requireUserAuthentication,
  importRateLimiter,
  async (req, res) => {
    const userId = req.user!.userId;

    try {
      const payload = importRequestSchema.parse(req.body);
      const authRecord = await getUserAuthRecord(userId);

      if (!authRecord) {
        res.status(400).json({ error: "Google Classroom is not connected" });
        return;
      }

      const service = new GoogleClassroomService(authRecord);
      const assignments = await service.fetchAndNormalizeAssignments(
        new Set(payload.existingExternalIds)
      );

      logInfo("Google Classroom import completed", {
        userId,
        route: req.originalUrl,
        importedCount: assignments.length
      });

      res.status(200).json(assignments);
    } catch (error) {
      logError("Google Classroom import failed", error, {
        userId,
        route: req.originalUrl
      });
      res.status(500).json({ error: "Failed to import Google Classroom assignments" });
    }
  }
);

importRouter.post(
  "/canvas",
  requireUserAuthentication,
  importRateLimiter,
  async (req, res) => {
    const userId = req.user!.userId;

    try {
      const payload = importRequestSchema.parse(req.body);
      const authRecord = await getCanvasAuthRecord(userId);

      if (!authRecord) {
        res.status(400).json({ error: "Canvas is not connected" });
        return;
      }

      const service = new CanvasService(authRecord.canvasDomain, authRecord.canvasAccessToken);
      const assignments = await service.fetchAndNormalizeAssignments(
        new Set(payload.existingExternalIds)
      );

      logInfo("Canvas import completed", {
        userId,
        route: req.originalUrl,
        importedCount: assignments.length
      });

      res.status(200).json(assignments);
    } catch (error) {
      logError("Canvas import failed", error, { userId, route: req.originalUrl });
      res.status(500).json({ error: "Failed to import Canvas assignments" });
    }
  }
);
