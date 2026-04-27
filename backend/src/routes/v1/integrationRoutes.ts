import { Router } from "express";
import { requireUserAuthentication } from "../../middleware/authentication";
import { resolveUserContext } from "../../middleware/resolveUserContext";
import { getUserAuthRecord, deleteUserAuthRecord } from "../../storage/userAuthRepository";
import { getGoogleIntegrationStatus, upsertGoogleIntegrationStatus } from "../../storage/integrationStatusRepository";
import { GoogleClassroomService } from "../../services/googleClassroomService";
import { upsertImportedAssignments } from "../../services/syncService";
import { refreshAnalyticsCache, defaultWeekStartInTz } from "../../services/analyticsServiceV1";
import { sendError } from "../../utils/http";
import { buildOAuthClient } from "../../config/google";

export const integrationsV1Router = Router();

integrationsV1Router.get("/google-classroom/status", requireUserAuthentication, resolveUserContext, async (req, res) => {
  try {
    const auth = await getUserAuthRecord(req.user!.userId);
    const status = await getGoogleIntegrationStatus(req.user!.dbUserId!);

    res.status(200).json({
      googleConnected: Boolean(auth) || status.googleConnected,
      googleConnectedAt: auth?.connectedAt ?? status.googleConnectedAt
    });
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "integration_status_failed",
      "Failed to load integration status",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});

integrationsV1Router.post("/google-classroom/import", requireUserAuthentication, resolveUserContext, async (req, res) => {
  try {
    const authRecord = await getUserAuthRecord(req.user!.userId);
    if (!authRecord) {
      sendError(req, res, 400, "google_not_connected", "Google Classroom is not connected");
      return;
    }

    const service = new GoogleClassroomService(authRecord);
    const assignments = await service.fetchAndNormalizeAssignments(new Set<string>());
    const upsertedCount = await upsertImportedAssignments(req.user!.dbUserId!, assignments);

    const tz = "UTC";
    await refreshAnalyticsCache(req.user!.dbUserId!, tz, defaultWeekStartInTz(tz));

    res.status(200).json({
      importedCount: assignments.length,
      upsertedCount
    });
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "integration_import_failed",
      "Failed to import Google Classroom assignments",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});

integrationsV1Router.delete(
  "/google-classroom/disconnect",
  requireUserAuthentication,
  resolveUserContext,
  async (req, res) => {
    try {
      const existing = await getUserAuthRecord(req.user!.userId);
      if (existing) {
        const oauthClient = buildOAuthClient();
        oauthClient.setCredentials({
          access_token: existing.googleAccessToken,
          refresh_token: existing.googleRefreshToken
        });
        await oauthClient.revokeToken(existing.googleRefreshToken);
        await deleteUserAuthRecord(req.user!.userId);
      }

      await upsertGoogleIntegrationStatus(req.user!.dbUserId!, false, null);
      res.status(204).send();
    } catch (error) {
      sendError(
        req,
        res,
        500,
        "integration_disconnect_failed",
        "Failed to disconnect Google Classroom",
        error instanceof Error ? { message: error.message } : undefined
      );
    }
  }
);
