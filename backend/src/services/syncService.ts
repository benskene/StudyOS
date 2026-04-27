import { randomUUID } from "crypto";
import type { PoolClient } from "pg";
import { pgPool } from "../db/postgres";
import type { AssignmentPayload, SprintPayload, SyncEntityType, SyncOperation } from "../types/api";
import { upsertDevice } from "../storage/userRepositoryPg";
import type { NormalizedAssignment } from "../types/classroom";

const SERVER_IMPORT_DEVICE_ID = "server:google-import";

type MutationInput = {
  mutationId: string;
  entityType: SyncEntityType;
  op: SyncOperation;
  entityId: string;
  payload: AssignmentPayload | SprintPayload;
  clientUpdatedAt: string;
  syncVersion: number;
  updatedByDeviceId: string;
};

type PushResult = {
  accepted: Array<{ mutationId: string; entityId: string; serverVersion: number }>;
  rejected: Array<{
    mutationId: string;
    entityId: string;
    code: string;
    reason: string;
    serverRecord?: Record<string, unknown>;
  }>;
  newCursor: string;
};

function isIncomingNewer(
  remoteUpdatedAt: Date,
  remoteVersion: number,
  remoteDeviceId: string,
  localUpdatedAt: Date,
  localVersion: number,
  localDeviceId: string
): boolean {
  if (remoteUpdatedAt.getTime() !== localUpdatedAt.getTime()) {
    return remoteUpdatedAt.getTime() > localUpdatedAt.getTime();
  }
  if (remoteVersion !== localVersion) {
    return remoteVersion > localVersion;
  }
  return remoteDeviceId > localDeviceId;
}

async function currentVersionFor(client: PoolClient, userId: string, entityType: SyncEntityType, entityId: string) {
  const table = entityType === "assignment" ? "assignments" : "sprints";
  const result = await client.query<{ sync_version: number }>(
    `SELECT sync_version FROM ${table} WHERE user_id = $1 AND id = $2`,
    [userId, entityId]
  );
  return result.rows[0]?.sync_version ?? 0;
}

async function insertSyncChange(
  client: PoolClient,
  userId: string,
  mutationId: string,
  entityType: SyncEntityType,
  entityId: string,
  op: SyncOperation,
  payload: unknown,
  serverVersion: number
): Promise<number> {
  const change = await client.query<{ change_id: string }>(
    `INSERT INTO sync_changes (user_id, entity_type, entity_id, op, payload, server_version, mutation_id)
     VALUES ($1, $2, $3, $4, $5::jsonb, $6, $7)
     RETURNING change_id`,
    [userId, entityType, entityId, op, JSON.stringify(payload), serverVersion, mutationId]
  );
  return Number(change.rows[0].change_id);
}

async function upsertAssignmentMutation(
  client: PoolClient,
  userId: string,
  mutation: MutationInput
): Promise<{ accepted?: { serverVersion: number; changeId: number }; rejected?: PushResult["rejected"][number] }> {
  const payload = mutation.payload as AssignmentPayload;

  const existing = await client.query<{
    sync_version: number;
    client_updated_at: Date;
    updated_by_device_id: string;
    is_deleted: boolean;
  }>(
    `SELECT sync_version, client_updated_at, updated_by_device_id, is_deleted
     FROM assignments
     WHERE user_id = $1 AND id = $2
     FOR UPDATE`,
    [userId, mutation.entityId]
  );

  let serverVersion = Math.max(1, mutation.syncVersion);
  if (existing.rows.length > 0) {
    const row = existing.rows[0];
    const incomingNewer = isIncomingNewer(
      new Date(mutation.clientUpdatedAt),
      mutation.syncVersion,
      mutation.updatedByDeviceId,
      new Date(row.client_updated_at),
      row.sync_version,
      row.updated_by_device_id
    );

    if (!incomingNewer) {
      return {
        rejected: {
          mutationId: mutation.mutationId,
          entityId: mutation.entityId,
          code: "conflict_stale_mutation",
          reason: "Incoming assignment mutation is older than server record",
          serverRecord: {
            syncVersion: row.sync_version,
            clientUpdatedAt: new Date(row.client_updated_at).toISOString(),
            updatedByDeviceId: row.updated_by_device_id,
            isDeleted: row.is_deleted
          }
        }
      };
    }

    serverVersion = row.sync_version + 1;
  }

  await client.query(
    `INSERT INTO assignments (
      id, user_id, title, class_name, due_date, est_minutes, source, external_id, is_completed,
      notes, total_minutes_worked, last_tiny_step, priority_score, is_flexible_due_date,
      energy_level, is_deleted, sync_version, client_updated_at, updated_by_device_id, created_at, updated_at
    ) VALUES (
      $1, $2, $3, $4, $5, $6, $7, $8, $9,
      $10, $11, $12, $13, $14,
      $15, $16, $17, $18, $19, now(), now()
    )
    ON CONFLICT (id)
    DO UPDATE SET
      user_id = EXCLUDED.user_id,
      title = EXCLUDED.title,
      class_name = EXCLUDED.class_name,
      due_date = EXCLUDED.due_date,
      est_minutes = EXCLUDED.est_minutes,
      source = EXCLUDED.source,
      external_id = EXCLUDED.external_id,
      is_completed = EXCLUDED.is_completed,
      notes = EXCLUDED.notes,
      total_minutes_worked = EXCLUDED.total_minutes_worked,
      last_tiny_step = EXCLUDED.last_tiny_step,
      priority_score = EXCLUDED.priority_score,
      is_flexible_due_date = EXCLUDED.is_flexible_due_date,
      energy_level = EXCLUDED.energy_level,
      is_deleted = EXCLUDED.is_deleted,
      sync_version = EXCLUDED.sync_version,
      client_updated_at = EXCLUDED.client_updated_at,
      updated_by_device_id = EXCLUDED.updated_by_device_id,
      updated_at = now()`,
    [
      mutation.entityId,
      userId,
      payload.title,
      payload.className,
      payload.dueDate,
      payload.estMinutes,
      payload.source ?? null,
      payload.externalId ?? null,
      payload.isCompleted,
      payload.notes,
      payload.totalMinutesWorked,
      payload.lastTinyStep,
      payload.priorityScore,
      payload.isFlexibleDueDate,
      payload.energyLevel,
      payload.isDeleted || mutation.op === "tombstone",
      serverVersion,
      mutation.clientUpdatedAt,
      mutation.updatedByDeviceId
    ]
  );

  const canonicalPayload = {
    ...payload,
    id: mutation.entityId,
    isDeleted: payload.isDeleted || mutation.op === "tombstone",
    syncVersion: serverVersion,
    clientUpdatedAt: mutation.clientUpdatedAt,
    updatedByDeviceId: mutation.updatedByDeviceId
  };

  const changeId = await insertSyncChange(
    client,
    userId,
    mutation.mutationId,
    "assignment",
    mutation.entityId,
    mutation.op,
    canonicalPayload,
    serverVersion
  );

  return { accepted: { serverVersion, changeId } };
}

async function upsertSprintMutation(
  client: PoolClient,
  userId: string,
  mutation: MutationInput
): Promise<{ accepted?: { serverVersion: number; changeId: number }; rejected?: PushResult["rejected"][number] }> {
  const payload = mutation.payload as SprintPayload;

  const existing = await client.query<{
    sync_version: number;
    client_updated_at: Date;
    updated_by_device_id: string;
    is_deleted: boolean;
  }>(
    `SELECT sync_version, client_updated_at, updated_by_device_id, is_deleted
     FROM sprints
     WHERE user_id = $1 AND id = $2
     FOR UPDATE`,
    [userId, mutation.entityId]
  );

  let serverVersion = Math.max(1, mutation.syncVersion);
  if (existing.rows.length > 0) {
    const row = existing.rows[0];
    const incomingNewer = isIncomingNewer(
      new Date(mutation.clientUpdatedAt),
      mutation.syncVersion,
      mutation.updatedByDeviceId,
      new Date(row.client_updated_at),
      row.sync_version,
      row.updated_by_device_id
    );

    if (!incomingNewer) {
      return {
        rejected: {
          mutationId: mutation.mutationId,
          entityId: mutation.entityId,
          code: "conflict_stale_mutation",
          reason: "Incoming sprint mutation is older than server record",
          serverRecord: {
            syncVersion: row.sync_version,
            clientUpdatedAt: new Date(row.client_updated_at).toISOString(),
            updatedByDeviceId: row.updated_by_device_id,
            isDeleted: row.is_deleted
          }
        }
      };
    }

    serverVersion = row.sync_version + 1;
  }

  await client.query(
    `INSERT INTO sprints (
      id, user_id, assignment_id, start_time, end_time, duration_seconds,
      reflection_note, focus_rating, is_deleted, sync_version, client_updated_at,
      updated_by_device_id, created_at, updated_at
    ) VALUES (
      $1, $2, $3, $4, $5, $6,
      $7, $8, $9, $10, $11,
      $12, now(), now()
    )
    ON CONFLICT (id)
    DO UPDATE SET
      user_id = EXCLUDED.user_id,
      assignment_id = EXCLUDED.assignment_id,
      start_time = EXCLUDED.start_time,
      end_time = EXCLUDED.end_time,
      duration_seconds = EXCLUDED.duration_seconds,
      reflection_note = EXCLUDED.reflection_note,
      focus_rating = EXCLUDED.focus_rating,
      is_deleted = EXCLUDED.is_deleted,
      sync_version = EXCLUDED.sync_version,
      client_updated_at = EXCLUDED.client_updated_at,
      updated_by_device_id = EXCLUDED.updated_by_device_id,
      updated_at = now()`,
    [
      mutation.entityId,
      userId,
      payload.assignmentId ?? null,
      payload.startTime,
      payload.endTime,
      payload.durationSeconds,
      payload.reflectionNote ?? null,
      payload.focusRating ?? null,
      payload.isDeleted || mutation.op === "tombstone",
      serverVersion,
      mutation.clientUpdatedAt,
      mutation.updatedByDeviceId
    ]
  );

  const canonicalPayload = {
    ...payload,
    id: mutation.entityId,
    isDeleted: payload.isDeleted || mutation.op === "tombstone",
    syncVersion: serverVersion,
    clientUpdatedAt: mutation.clientUpdatedAt,
    updatedByDeviceId: mutation.updatedByDeviceId
  };

  const changeId = await insertSyncChange(
    client,
    userId,
    mutation.mutationId,
    "sprint",
    mutation.entityId,
    mutation.op,
    canonicalPayload,
    serverVersion
  );

  return { accepted: { serverVersion, changeId } };
}

async function handleMutation(client: PoolClient, userId: string, mutation: MutationInput) {
  const dedup = await client.query(
    `SELECT 1 FROM sync_mutation_dedup WHERE user_id = $1 AND mutation_id = $2`,
    [userId, mutation.mutationId]
  );

  if (dedup.rows.length > 0) {
    const currentVersion = await currentVersionFor(client, userId, mutation.entityType, mutation.entityId);
    return {
      duplicate: true,
      accepted: {
        mutationId: mutation.mutationId,
        entityId: mutation.entityId,
        serverVersion: currentVersion
      },
      changeId: 0
    };
  }

  const result =
    mutation.entityType === "assignment"
      ? await upsertAssignmentMutation(client, userId, mutation)
      : await upsertSprintMutation(client, userId, mutation);

  if (result.rejected) {
    return {
      duplicate: false,
      rejected: result.rejected,
      changeId: 0
    };
  }

  await client.query(
    `INSERT INTO sync_mutation_dedup (user_id, mutation_id, processed_at)
     VALUES ($1, $2, now())`,
    [userId, mutation.mutationId]
  );

  return {
    duplicate: false,
    accepted: {
      mutationId: mutation.mutationId,
      entityId: mutation.entityId,
      serverVersion: result.accepted!.serverVersion
    },
    changeId: result.accepted!.changeId
  };
}

export async function pushMutations(
  userId: string,
  deviceId: string,
  platform: string | null,
  mutations: MutationInput[]
): Promise<PushResult> {
  await upsertDevice(userId, deviceId, platform);

  const client = await pgPool.connect();
  const accepted: PushResult["accepted"] = [];
  const rejected: PushResult["rejected"] = [];
  let maxCursor = 0;

  try {
    for (const mutation of mutations) {
      await client.query("BEGIN");
      try {
        const result = await handleMutation(client, userId, mutation);
        if (result.accepted) {
          accepted.push(result.accepted);
        }
        if (result.rejected) {
          rejected.push(result.rejected);
        }
        maxCursor = Math.max(maxCursor, result.changeId);
        await client.query("COMMIT");
      } catch (error) {
        await client.query("ROLLBACK");
        rejected.push({
          mutationId: mutation.mutationId,
          entityId: mutation.entityId,
          code: "mutation_failed",
          reason: error instanceof Error ? error.message : "Mutation failed"
        });
      }
    }

    if (maxCursor === 0) {
      const cursorRow = await client.query<{ max: string | null }>(
        `SELECT MAX(change_id) as max FROM sync_changes WHERE user_id = $1`,
        [userId]
      );
      maxCursor = Number(cursorRow.rows[0]?.max ?? 0);
    }

    return {
      accepted,
      rejected,
      newCursor: String(maxCursor)
    };
  } finally {
    client.release();
  }
}

export async function pullChanges(
  userId: string,
  cursor: number,
  limit: number,
  entityTypes?: SyncEntityType[]
): Promise<{ changes: unknown[]; nextCursor: string; hasMore: boolean }> {
  const safeLimit = Math.max(1, Math.min(limit, 500));

  const withEntityFilter = Array.isArray(entityTypes) && entityTypes.length > 0;
  const query = withEntityFilter
    ? `SELECT change_id, entity_type, entity_id, op, payload, server_version, changed_at
       FROM sync_changes
       WHERE user_id = $1 AND change_id > $2 AND entity_type = ANY($3)
       ORDER BY change_id ASC
       LIMIT $4`
    : `SELECT change_id, entity_type, entity_id, op, payload, server_version, changed_at
       FROM sync_changes
       WHERE user_id = $1 AND change_id > $2
       ORDER BY change_id ASC
       LIMIT $3`;

  const result = withEntityFilter
    ? await pgPool.query<{
        change_id: string;
        entity_type: string;
        entity_id: string;
        op: string;
        payload: unknown;
        server_version: number;
        changed_at: Date;
      }>(query, [userId, cursor, entityTypes, safeLimit + 1])
    : await pgPool.query<{
        change_id: string;
        entity_type: string;
        entity_id: string;
        op: string;
        payload: unknown;
        server_version: number;
        changed_at: Date;
      }>(query, [userId, cursor, safeLimit + 1]);

  const hasMore = result.rows.length > safeLimit;
  const rows = hasMore ? result.rows.slice(0, safeLimit) : result.rows;
  const nextCursor = rows.length ? Number(rows[rows.length - 1].change_id) : cursor;

  return {
    changes: rows.map((row) => ({
      changeId: Number(row.change_id),
      entityType: row.entity_type,
      entityId: row.entity_id,
      op: row.op,
      payload: row.payload,
      serverVersion: row.server_version,
      changedAt: row.changed_at.toISOString()
    })),
    nextCursor: String(nextCursor),
    hasMore
  };
}

export async function upsertImportedAssignments(userId: string, normalized: NormalizedAssignment[]): Promise<number> {
  if (normalized.length === 0) {
    return 0;
  }

  const client = await pgPool.connect();
  let insertedOrUpdated = 0;

  try {
    for (const item of normalized) {
      await client.query("BEGIN");
      try {
        const existing = await client.query<{ id: string; sync_version: number }>(
          `SELECT id, sync_version
           FROM assignments
           WHERE user_id = $1 AND source = 'google_classroom' AND external_id = $2
           LIMIT 1
           FOR UPDATE`,
          [userId, item.externalId]
        );

        const id = existing.rows[0]?.id ?? randomUUID();
        const serverVersion = (existing.rows[0]?.sync_version ?? 0) + 1;
        const nowIso = new Date().toISOString();

        await client.query(
          `INSERT INTO assignments (
            id, user_id, title, class_name, due_date, est_minutes, source, external_id, is_completed,
            notes, total_minutes_worked, last_tiny_step, priority_score, is_flexible_due_date,
            energy_level, is_deleted, sync_version, client_updated_at, updated_by_device_id, created_at, updated_at
          ) VALUES (
            $1, $2, $3, $4, $5, $6, 'google_classroom', $7, false,
            $8, 0, '', 0, false,
            'medium', false, $9, $10, $11, now(), now()
          )
          ON CONFLICT (id)
          DO UPDATE SET
            title = EXCLUDED.title,
            class_name = EXCLUDED.class_name,
            due_date = EXCLUDED.due_date,
            est_minutes = EXCLUDED.est_minutes,
            notes = EXCLUDED.notes,
            is_deleted = false,
            sync_version = EXCLUDED.sync_version,
            client_updated_at = EXCLUDED.client_updated_at,
            updated_by_device_id = EXCLUDED.updated_by_device_id,
            updated_at = now()`,
          [
            id,
            userId,
            item.title,
            item.className,
            item.dueDate,
            item.estMinutes,
            item.externalId,
            item.notes,
            serverVersion,
            nowIso,
            SERVER_IMPORT_DEVICE_ID
          ]
        );

        await insertSyncChange(
          client,
          userId,
          randomUUID(),
          "assignment",
          id,
          "upsert",
          {
            id,
            title: item.title,
            className: item.className,
            dueDate: item.dueDate,
            estMinutes: item.estMinutes,
            source: "google_classroom",
            externalId: item.externalId,
            isCompleted: false,
            notes: item.notes,
            totalMinutesWorked: 0,
            lastTinyStep: "",
            priorityScore: 0,
            isFlexibleDueDate: false,
            energyLevel: "medium",
            isDeleted: false,
            syncVersion: serverVersion,
            clientUpdatedAt: nowIso,
            updatedByDeviceId: SERVER_IMPORT_DEVICE_ID
          },
          serverVersion
        );

        insertedOrUpdated += 1;
        await client.query("COMMIT");
      } catch (error) {
        await client.query("ROLLBACK");
        throw error;
      }
    }

    return insertedOrUpdated;
  } finally {
    client.release();
  }
}
