import type { Request, Response, NextFunction } from "express";
import { ensureUser } from "../storage/userRepositoryPg";
import { sendError } from "../utils/http";

export async function resolveUserContext(req: Request, res: Response, next: NextFunction) {
  try {
    if (!req.user?.userId) {
      sendError(req, res, 401, "unauthorized", "Missing authenticated user");
      return;
    }

    const dbUserId = await ensureUser(req.user.userId);
    req.user.dbUserId = dbUserId;
    next();
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "user_context_failed",
      "Failed to resolve user context",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
}
