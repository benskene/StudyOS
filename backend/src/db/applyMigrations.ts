import fs from "fs/promises";
import path from "path";
import { pgPool } from "./postgres";
import { logInfo } from "../utils/logger";

/// Applies every .sql file in backend/sql in name order. All migration files
/// are idempotent (IF NOT EXISTS), so this is safe to run on every boot.
export async function applyMigrations(): Promise<void> {
  const sqlDir = path.resolve(__dirname, "../../sql");
  const files = (await fs.readdir(sqlDir))
    .filter((file) => file.endsWith(".sql"))
    .sort();

  for (const file of files) {
    const sqlPath = path.join(sqlDir, file);
    const sql = await fs.readFile(sqlPath, "utf8");
    await pgPool.query(sql);
    logInfo(`Applied migration: ${file}`);
  }
}
