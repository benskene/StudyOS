import fs from "fs/promises";
import path from "path";
import { pgPool } from "./postgres";

async function run() {
  const sqlPath = path.resolve(__dirname, "../../sql/001_init.sql");
  const sql = await fs.readFile(sqlPath, "utf8");
  await pgPool.query(sql);
  await pgPool.end();
  console.info(`Applied migration: ${sqlPath}`);
}

run().catch(async (error) => {
  console.error("Migration failed", error);
  await pgPool.end();
  process.exit(1);
});
