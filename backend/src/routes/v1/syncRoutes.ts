import { Router } from "express";
import { z } from "zod";
import { requireUserAuthentication } from "../../middleware/authentication";
import { resolveUserContext } from "../../middleware/resolveUserContext";
import { pullChanges, pushMutations } from "../../services/syncService";
import { sendError } from "../../utils/http";
import { parseCursor } from "../../utils/time";

const uuid = z.string().uuid();

const assignmentPayloadSchema = z.object({
  id: uuid,
  title: z.string().min(1),
  className: z.string().min(1),
  dueDate: z.string().datetime(),
  estMinutes: z.number().int().min(0),
  source: z.string().nullable().optional(),
  externalId: z.string().nullable().optional(),
  isCompleted: z.boolean(),
  notes: z.string().default(""),
  totalMinutesWorked: z.number().int().min(0).default(0),
  lastTinyStep: z.string().default(""),
  priorityScore: z.number().default(0),
  isFlexibleDueDate: z.boolean().default(false),
  energyLevel: z.string().default("medium"),
  isDeleted: z.boolean(),
  clientUpdatedAt: z.string().datetime(),
  updatedByDeviceId: z.string().min(1)
});

const sprintPayloadSchema = z.object({
  id: uuid,
  startTime: z.string().datetime(),
  endTime: z.string().datetime(),
  durationSeconds: z.number().int().min(1),
  assignmentId: uuid.nullable().optional(),
  reflectionNote: z.string().nullable().optional(),
  focusRating: z.number().int().min(1).max(5).nullable().optional(),
  isDeleted: z.boolean(),
  clientUpdatedAt: z.string().datetime(),
  updatedByDeviceId: z.string().min(1)
});

const mutationSchema = z
  .object({
    mutationId: uuid,
    entityType: z.enum(["assignment", "sprint"]),
    op: z.enum(["upsert", "tombstone"]),
    entityId: uuid,
    payload: z.union([assignmentPayloadSchema, sprintPayloadSchema]),
    clientUpdatedAt: z.string().datetime(),
    syncVersion: z.number().int().min(0),
    updatedByDeviceId: z.string().min(1)
  })
  .superRefine((value, ctx) => {
    if (value.entityType === "assignment") {
      const parsed = assignmentPayloadSchema.safeParse(value.payload);
      if (!parsed.success) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Assignment payload invalid" });
        return;
      }
      if (parsed.data.id !== value.entityId) {
        ctx.addIssue({ code: z.ZodIssueCode.custom, message: "entityId must match payload.id" });
      }
      return;
    }

    const parsed = sprintPayloadSchema.safeParse(value.payload);
    if (!parsed.success) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "Sprint payload invalid" });
      return;
    }
    if (parsed.data.id !== value.entityId) {
      ctx.addIssue({ code: z.ZodIssueCode.custom, message: "entityId must match payload.id" });
    }
  });

const pushBodySchema = z.object({
  deviceId: z.string().min(1),
  platform: z.string().min(1).optional().nullable(),
  mutations: z.array(mutationSchema).max(100)
});

const pullBodySchema = z.object({
  cursor: z.union([z.string(), z.number()]).optional(),
  limit: z.number().int().min(1).max(500).default(200),
  entityTypes: z.array(z.enum(["assignment", "sprint"])).optional()
});

export const syncV1Router = Router();

syncV1Router.post("/push", requireUserAuthentication, resolveUserContext, async (req, res) => {
  const parsed = pushBodySchema.safeParse(req.body);
  if (!parsed.success) {
    sendError(req, res, 400, "invalid_payload", "Invalid sync push payload", parsed.error.flatten());
    return;
  }

  try {
    const result = await pushMutations(
      req.user!.dbUserId!,
      parsed.data.deviceId,
      parsed.data.platform ?? null,
      parsed.data.mutations
    );
    res.status(200).json(result);
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "sync_push_failed",
      "Failed to process sync push",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});

syncV1Router.post("/pull", requireUserAuthentication, resolveUserContext, async (req, res) => {
  const parsed = pullBodySchema.safeParse(req.body ?? {});
  if (!parsed.success) {
    sendError(req, res, 400, "invalid_payload", "Invalid sync pull payload", parsed.error.flatten());
    return;
  }

  try {
    const result = await pullChanges(
      req.user!.dbUserId!,
      parseCursor(parsed.data.cursor),
      parsed.data.limit,
      parsed.data.entityTypes
    );
    res.status(200).json(result);
  } catch (error) {
    sendError(
      req,
      res,
      500,
      "sync_pull_failed",
      "Failed to process sync pull",
      error instanceof Error ? { message: error.message } : undefined
    );
  }
});
