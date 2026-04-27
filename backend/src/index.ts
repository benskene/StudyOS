import express from "express";
import helmet from "helmet";
import { env } from "./config/env";
import { authRouter } from "./routes/authRoutes";
import { canvasRouter } from "./routes/canvasRoutes";
import { importRouter } from "./routes/importRoutes";
import { syncV1Router } from "./routes/v1/syncRoutes";
import { analyticsV1Router } from "./routes/v1/analyticsRoutes";
import { integrationsV1Router } from "./routes/v1/integrationRoutes";
import { logError, logInfo } from "./utils/logger";

const app = express();

app.use(helmet());
app.use(express.json({ limit: "100kb" }));

app.get("/health", (_req, res) => {
  res.status(200).json({ ok: true });
});

app.use("/auth", authRouter);
app.use("/auth/canvas", canvasRouter);
app.use("/import", importRouter);
app.use("/v1/sync", syncV1Router);
app.use("/v1/analytics", analyticsV1Router);
app.use("/v1/integrations", integrationsV1Router);

app.use((err: unknown, _req: express.Request, res: express.Response, _next: express.NextFunction) => {
  logError("Unhandled backend error", err);
  res.status(500).json({ error: "Internal server error" });
});

app.listen(env.PORT, () => {
  logInfo(`Struc backend listening on port ${env.PORT}`);
});
