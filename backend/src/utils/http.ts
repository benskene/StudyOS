import type { Request, Response } from "express";
import crypto from "crypto";

export function getRequestId(req: Request): string {
  const value = req.header("x-request-id");
  return value && value.trim().length > 0 ? value : crypto.randomUUID();
}

export function sendError(
  req: Request,
  res: Response,
  status: number,
  code: string,
  message: string,
  details?: unknown
) {
  res.status(status).json({
    error: {
      code,
      message,
      requestId: getRequestId(req),
      details
    }
  });
}
