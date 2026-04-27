import rateLimit from "express-rate-limit";
import { env } from "../config/env";

export const importRateLimiter = rateLimit({
  windowMs: env.IMPORT_RATE_LIMIT_WINDOW_MS,
  max: env.IMPORT_RATE_LIMIT_MAX,
  standardHeaders: true,
  legacyHeaders: false,
  keyGenerator: (req) => req.user?.userId ?? req.ip ?? "unknown",
  message: { error: "Too many import requests. Try again shortly." }
});
