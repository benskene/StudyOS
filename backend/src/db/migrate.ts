import { pgPool } from "./postgres";
import { applyMigrations } from "./applyMigrations";

applyMigrations()
  .then(async () => {
    await pgPool.end();
  })
  .catch(async (error) => {
    console.error("Migration failed", error);
    await pgPool.end();
    process.exit(1);
  });
