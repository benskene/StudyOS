import fs from "fs/promises";
import path from "path";
import { pgPool } from "./postgres";

async function run() {
  const sqlDir = path.resolve(__dirname, "../../sql");
  const files = (await fs.readdir(sqlDir))
    .filter((file) => file.endsWith(".sql"))
    .sort();

  for (const file of files) {
    const sqlPath = path.join(sqlDir, file);
    const sql = await fs.readFile(sqlPath, "utf8");
    await pgPool.query(sql);
    console.info(`Applied migration: ${sqlPath}`);
  }

  await pgPool.end();
}

run().catch(async (error) => {
  console.error("Migration failed", error);
  await pgPool.end();
  process.exit(1);
});
