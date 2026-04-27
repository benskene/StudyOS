import { pgPool } from "../db/postgres";

export async function ensureUser(firebaseUid: string): Promise<string> {
  const client = await pgPool.connect();
  try {
    const insert = await client.query<{ id: string }>(
      `INSERT INTO users (firebase_uid)
       VALUES ($1)
       ON CONFLICT (firebase_uid)
       DO UPDATE SET updated_at = now()
       RETURNING id`,
      [firebaseUid]
    );
    return insert.rows[0].id;
  } finally {
    client.release();
  }
}

export async function upsertDevice(userId: string, deviceId: string, platform?: string | null): Promise<void> {
  if (!deviceId) {
    return;
  }
  await pgPool.query(
    `INSERT INTO devices (user_id, device_id, platform, last_seen_at, updated_at)
     VALUES ($1, $2, $3, now(), now())
     ON CONFLICT (user_id, device_id)
     DO UPDATE SET platform = EXCLUDED.platform, last_seen_at = now(), updated_at = now()`,
    [userId, deviceId, platform ?? null]
  );
}
