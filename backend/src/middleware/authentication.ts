import type { Request, Response, NextFunction } from "express";
import { getAuth } from "firebase-admin/auth";
import crypto from "crypto";
import { logError } from "../utils/logger";
import { sendError } from "../utils/http";

function extractBearerToken(req: Request): string | null {
  const header = req.header("Authorization");
  if (!header) {
    return null;
  }

  const parts = header.split(" ");
  if (parts.length != 2 || parts[0] !== "Bearer" || !parts[1]) {
    return null;
  }
  return parts[1];
}

export async function requireUserAuthentication(req: Request, res: Response, next: NextFunction) {
  const requestId = req.header("x-request-id") ?? crypto.randomUUID();
  const token = extractBearerToken(req);
  if (!token) {
    res.setHeader("x-request-id", requestId);
    sendError(req, res, 401, "missing_bearer_token", "Unauthorized");
    return;
  }

  try {
    const decoded = await getAuth().verifyIdToken(token, true);
    req.user = { userId: decoded.uid };
    next();
  } catch (error) {
    logError("Authentication verification failed", error, {
      requestId,
      route: req.originalUrl,
      method: req.method
    });
    res.setHeader("x-request-id", requestId);
    sendError(req, res, 401, "invalid_bearer_token", "Unauthorized");
  }
}
