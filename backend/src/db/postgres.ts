import { Pool } from "pg";
import { env } from "../config/env";

export const pgPool = new Pool({
  connectionString: env.DATABASE_URL,
  max: env.PG_POOL_MAX,
  ssl: env.PG_SSL ? { rejectUnauthorized: false } : undefined
});
