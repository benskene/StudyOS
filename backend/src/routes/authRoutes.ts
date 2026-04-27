import { Router } from "express";
import { GaxiosError } from "gaxios";
import { env } from "../config/env";
import { buildOAuthClient, GOOGLE_CLASSROOM_SCOPES } from "../config/google";
import { requireUserAuthentication } from "../middleware/authentication";
import {
  deleteUserAuthRecord,
  getUserAuthRecord,
  upsertUserAuthRecord
} from "../storage/userAuthRepository";
import { ensureUser } from "../storage/userRepositoryPg";
import { upsertGoogleIntegrationStatus } from "../storage/integrationStatusRepository";
import { createOAuthState, verifyOAuthState } from "../utils/oauthState";
import { logError, logInfo } from "../utils/logger";
import type { UserAuthRecord } from "../types/auth";

export const authRouter = Router();

authRouter.post("/google/start", requireUserAuthentication, async (req, res) => {
  try {
    const userId = req.user!.userId;
    const state = createOAuthState(userId);
    const oauthURL = new URL("/auth/google", `${req.protocol}://${req.get("host")}`);
    oauthURL.searchParams.set("state", state);
    res.status(200).json({ authUrl: oauthURL.toString() });
  } catch (error) {
    logError("Failed to create Google OAuth start URL", error, {
      route: req.originalUrl,
      uid: req.user?.userId
    });
    res.status(500).json({ error: "Failed to create OAuth URL" });
  }
});

authRouter.get("/google", async (req, res) => {
  try {
    const requestedState = typeof req.query.state === "string" ? req.query.state : null;
    if (!requestedState) {
      res.redirect(env.GOOGLE_OAUTH_FAILURE_REDIRECT);
      return;
    }
    const statePayload = verifyOAuthState(requestedState);
    if (!statePayload) {
      res.redirect(env.GOOGLE_OAUTH_FAILURE_REDIRECT);
      return;
    }

    const oauthClient = buildOAuthClient();
    const url = oauthClient.generateAuthUrl({
      access_type: "offline",
      scope: [...GOOGLE_CLASSROOM_SCOPES],
      include_granted_scopes: false,
      prompt: "consent",
      state: requestedState
    });

    res.redirect(url);
  } catch (error) {
    logError("Failed to generate Google OAuth URL", error, { route: req.originalUrl });
    res.redirect(env.GOOGLE_OAUTH_FAILURE_REDIRECT);
  }
});

authRouter.get("/callback", async (req, res) => {
  const code = req.query.code;
  const state = req.query.state;

  if (typeof code !== "string" || typeof state !== "string") {
    const reason = typeof code !== "string" ? "missing_code" : "missing_state";
    logError("OAuth callback missing params", new Error(reason), { route: req.originalUrl });
    res.redirect(`${env.GOOGLE_OAUTH_FAILURE_REDIRECT}?reason=${reason}`);
    return;
  }

  const statePayload = verifyOAuthState(state);
  if (!statePayload) {
    logError("OAuth state verification failed", new Error("invalid_state"), { route: req.originalUrl });
    res.status(400).redirect(`${env.GOOGLE_OAUTH_FAILURE_REDIRECT}?reason=invalid_state`);
    return;
  }

  const oauthClient = buildOAuthClient();

  try {
    const tokenResponse = await oauthClient.getToken(code);
    const credentials = tokenResponse.tokens;

    if (!credentials.access_token || !credentials.refresh_token) {
      throw new Error("Missing access or refresh token");
    }

    const newRecord: UserAuthRecord = {
      userId: statePayload.userId,
      googleAccessToken: credentials.access_token,
      googleRefreshToken: credentials.refresh_token,
      tokenExpiry: credentials.expiry_date
        ? new Date(credentials.expiry_date).toISOString()
        : null,
      connectedAt: new Date().toISOString()
    };

    await upsertUserAuthRecord(newRecord);
    const dbUserId = await ensureUser(statePayload.userId);
    await upsertGoogleIntegrationStatus(dbUserId, true, newRecord.connectedAt);
    logInfo("Google Classroom connected", { userId: statePayload.userId });

    res.redirect(env.GOOGLE_OAUTH_SUCCESS_REDIRECT);
  } catch (error) {
    const status = error instanceof GaxiosError ? error.status : undefined;
    const reason = error instanceof GaxiosError
      ? (error.message ?? "gaxios_error")
      : (error instanceof Error ? error.message : "unknown");
    logError("Failed during Google OAuth callback", error, { status, route: req.originalUrl });
    res.redirect(`${env.GOOGLE_OAUTH_FAILURE_REDIRECT}?reason=${encodeURIComponent(reason)}`);
  }
});

authRouter.delete("/google/disconnect", requireUserAuthentication, async (req, res) => {
  const userId = req.user!.userId;

  try {
    const existing = await getUserAuthRecord(userId);
    const dbUserId = await ensureUser(userId);
    if (!existing) {
      await upsertGoogleIntegrationStatus(dbUserId, false, null);
      res.status(204).send();
      return;
    }

    const oauthClient = buildOAuthClient();
    oauthClient.setCredentials({
      access_token: existing.googleAccessToken,
      refresh_token: existing.googleRefreshToken
    });

    await oauthClient.revokeToken(existing.googleRefreshToken);
    await deleteUserAuthRecord(userId);
    await upsertGoogleIntegrationStatus(dbUserId, false, null);

    logInfo("Google Classroom disconnected", { userId });
    res.status(204).send();
  } catch (error) {
    logError("Failed to disconnect Google Classroom", error, {
      userId,
      route: req.originalUrl
    });
    res.status(500).json({ error: "Failed to disconnect Google Classroom" });
  }
});
