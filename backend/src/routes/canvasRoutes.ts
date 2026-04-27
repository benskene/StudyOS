import { Router } from "express";
import { z } from "zod";
import { requireUserAuthentication } from "../middleware/authentication";
import {
  getCanvasAuthRecord,
  upsertCanvasAuthRecord,
  deleteCanvasAuthRecord
} from "../storage/canvasAuthRepository";
import { upsertCanvasIntegrationStatus } from "../storage/integrationStatusRepository";
import { ensureUser } from "../storage/userRepositoryPg";
import { CanvasService } from "../services/canvasService";
import { logError, logInfo } from "../utils/logger";

export const canvasRouter = Router();

const connectSchema = z.object({
  domain: z.string().min(3).max(253),
  accessToken: z.string().min(10)
});

canvasRouter.post("/connect", requireUserAuthentication, async (req, res) => {
  const userId = req.user!.userId;

  const parsed = connectSchema.safeParse(req.body);
  if (!parsed.success) {
    res.status(400).json({ error: "Invalid request body", details: parsed.error.flatten() });
    return;
  }

  const { domain, accessToken } = parsed.data;

  try {
    const service = new CanvasService(domain, accessToken);
    await service.validateConnection();

    const connectedAt = new Date().toISOString();
    await upsertCanvasAuthRecord({ userId, canvasDomain: domain, canvasAccessToken: accessToken, connectedAt });

    const dbUserId = await ensureUser(userId);
    await upsertCanvasIntegrationStatus(dbUserId, true, connectedAt);

    logInfo("Canvas connected", { userId });
    res.status(200).json({ ok: true });
  } catch (error) {
    logError("Canvas connect failed", error, { userId, route: req.originalUrl });
    res.status(400).json({ error: "Could not connect to Canvas. Check your domain and access token." });
  }
});

canvasRouter.delete("/disconnect", requireUserAuthentication, async (req, res) => {
  const userId = req.user!.userId;

  try {
    await deleteCanvasAuthRecord(userId);

    const dbUserId = await ensureUser(userId);
    await upsertCanvasIntegrationStatus(dbUserId, false, null);

    logInfo("Canvas disconnected", { userId });
    res.status(204).send();
  } catch (error) {
    logError("Canvas disconnect failed", error, { userId, route: req.originalUrl });
    res.status(500).json({ error: "Failed to disconnect Canvas" });
  }
});

canvasRouter.get("/status", requireUserAuthentication, async (req, res) => {
  const userId = req.user!.userId;

  try {
    const record = await getCanvasAuthRecord(userId);
    res.status(200).json({ connected: record !== null });
  } catch (error) {
    logError("Canvas status check failed", error, { userId, route: req.originalUrl });
    res.status(500).json({ error: "Failed to check Canvas status" });
  }
});
