import express from "express";
import helmet from "helmet";
import { env } from "./config/env";
import { authRouter } from "./routes/authRoutes";
import { canvasRouter } from "./routes/canvasRoutes";
import { importRouter } from "./routes/importRoutes";
import { syllabusRouter } from "./routes/syllabusRoutes";
import { syncV1Router } from "./routes/v1/syncRoutes";
import { analyticsV1Router } from "./routes/v1/analyticsRoutes";
import { integrationsV1Router } from "./routes/v1/integrationRoutes";
import { applyMigrations } from "./db/applyMigrations";
import { logError, logInfo } from "./utils/logger";

const app = express();

// Behind Railway's proxy: required so req.protocol/req.ip reflect the real
// request — express-rate-limit v7 rejects X-Forwarded-For without this.
app.set("trust proxy", 1);

app.use(helmet());
app.use(express.json({ limit: "100kb" }));

app.get("/health", (_req, res) => {
  res.status(200).json({ ok: true });
});

app.use("/auth", authRouter);
app.use("/auth/canvas", canvasRouter);
app.use("/import", importRouter);
app.use("/import", syllabusRouter);
app.use("/v1/sync", syncV1Router);
app.use("/v1/analytics", analyticsV1Router);
app.use("/v1/integrations", integrationsV1Router);

app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logError("Unhandled backend error", err);
  res.status(500).json({ error: "Internal server error" });
});

async function start() {
  try {
    await applyMigrations();
  } catch (error) {
    // Serve /health regardless; DB-backed routes will surface their own errors.
    logError("Failed to apply migrations on boot", error);
  }

  app.listen(env.PORT, () => {
    logInfo(`Struc backend listening on port ${env.PORT}`);
  });
}

void start();
