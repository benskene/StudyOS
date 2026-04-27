import { Router } from "express";
import { z } from "zod";
import { requireUserAuthentication } from "../../middleware/authentication";
import { resolveUserContext } from "../../middleware/resolveUserContext";
import {
  defaultWeekStartInTz,
  getDashboardAnalytics,
  getEstimatedVsActual,
  getRecentActivity
} from "../../services/analyticsServiceV1";
import { sendError } from "../../utils/http";

const dashboardQuerySchema = z.object({
  weekStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).optional(),
  tz: z.string().min(1).default("UTC")
});

const listQuerySchema = z.object({
  limit: z.coerce.number().int().min(1).max(100).default(10)
});

export const analyticsV1Router = Router();

analyticsV1Router.get("/dashboard", requireUserAuthentication, resolveUserContext, async (req, res) => {
  const parsed = dashboardQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    sendError(req, res, 400, "invalid_query", "Invalid dashboard query", parsed.error.flatten());
    return;
  }

  const tz = parsed.data.tz;
  const weekStart = parsed.data.weekStart ?? defaultWeekStartInTz(tz);

  try {
    const result = await getDashboardAnalytics(req.user!.dbUserId!, weekStart, tz);
    res.status(200).json(result);
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "analytics_dashboard_failed",
      "Failed to load dashboard analytics",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});

analyticsV1Router.get("/estimated-vs-actual", requireUserAuthentication, resolveUserContext, async (req, res) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    sendError(req, res, 400, "invalid_query", "Invalid estimated-vs-actual query", parsed.error.flatten());
    return;
  }

  try {
    const rows = await getEstimatedVsActual(req.user!.dbUserId!, parsed.data.limit);
    res.status(200).json({ items: rows });
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "analytics_estimated_actual_failed",
      "Failed to load estimated-vs-actual analytics",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});

analyticsV1Router.get("/recent-activity", requireUserAuthentication, resolveUserContext, async (req, res) => {
  const parsed = listQuerySchema.safeParse(req.query);
  if (!parsed.success) {
    sendError(req, res, 400, "invalid_query", "Invalid recent-activity query", parsed.error.flatten());
    return;
  }

  try {
    const items = await getRecentActivity(req.user!.dbUserId!, parsed.data.limit);
    res.status(200).json({ items });
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "analytics_recent_activity_failed",
      "Failed to load recent activity",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});
