import { pgPool } from "../db/postgres";

export async function upsertGoogleIntegrationStatus(
  userId: string,
  connected: boolean,
  connectedAt?: string | null
): Promise<void> {
  await pgPool.query(
    `INSERT INTO integration_status (user_id, google_connected, google_connected_at, updated_at)
     VALUES ($1, $2, $3, now())
     ON CONFLICT (user_id)
     DO UPDATE SET
       google_connected = EXCLUDED.google_connected,
       google_connected_at = EXCLUDED.google_connected_at,
       updated_at = now()`,
    [userId, connected, connected ? connectedAt ?? new Date().toISOString() : null]
  );
}

export async function getGoogleIntegrationStatus(userId: string): Promise<{ googleConnected: boolean; googleConnectedAt: string | null }> {
  const result = await pgPool.query<{ google_connected: boolean; google_connected_at: Date | null }>(
    `SELECT google_connected, google_connected_at
     FROM integration_status
     WHERE user_id = $1`,
    [userId]
  );

  if (result.rows.length === 0) {
    return { googleConnected: false, googleConnectedAt: null };
  }

  return {
    googleConnected: result.rows[0].google_connected,
    googleConnectedAt: result.rows[0].google_connected_at ? result.rows[0].google_connected_at.toISOString() : null
  };
}

export async function upsertCanvasIntegrationStatus(
  userId: string,
  connected: boolean,
  connectedAt?: string | null
): Promise<void> {
  await pgPool.query(
    `INSERT INTO integration_status (user_id, canvas_connected, canvas_connected_at, updated_at)
     VALUES ($1, $2, $3, now())
     ON CONFLICT (user_id)
     DO UPDATE SET
       canvas_connected = EXCLUDED.canvas_connected,
       canvas_connected_at = EXCLUDED.canvas_connected_at,
       updated_at = now()`,
    [userId, connected, connected ? connectedAt ?? new Date().toISOString() : null]
  );
}

export async function getCanvasIntegrationStatus(userId: string): Promise<{ canvasConnected: boolean; canvasConnectedAt: string | null }> {
  const result = await pgPool.query<{ canvas_connected: boolean; canvas_connected_at: Date | null }>(
    `SELECT canvas_connected, canvas_connected_at
     FROM integration_status
     WHERE user_id = $1`,
    [userId]
  );

  if (result.rows.length === 0) {
    return { canvasConnected: false, canvasConnectedAt: null };
  }

  return {
    canvasConnected: result.rows[0].canvas_connected,
    canvasConnectedAt: result.rows[0].canvas_connected_at ? result.rows[0].canvas_connected_at.toISOString() : null
  };
}
