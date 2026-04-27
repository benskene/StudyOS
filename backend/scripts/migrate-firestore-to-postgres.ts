import { randomUUID } from "crypto";
import { FieldPath, Timestamp } from "firebase-admin/firestore";
import { firestore } from "../src/config/firebase";
import { pgPool } from "../src/db/postgres";

type CliOptions = {
  dryRun: boolean;
  userId: string | null;
  batchSize: number;
};

type Counters = {
  usersProcessed: number;
  assignmentsSeen: number;
  sprintsSeen: number;
  assignmentRowsChanged: number;
  sprintRowsChanged: number;
  syncChangesInserted: number;
  integrationRowsChanged: number;
};

function parseArgs(argv: string[]): CliOptions {
  let dryRun = false;
  let userId: string | null = null;
  let batchSize = 100;

  for (const arg of argv) {
    if (arg === "--dry-run") {
      dryRun = true;
      continue;
    }
    if (arg.startsWith("--user=")) {
      userId = arg.slice("--user=".length).trim() || null;
      continue;
    }
    if (arg.startsWith("--batch-size=")) {
      const raw = Number(arg.slice("--batch-size=".length));
      if (Number.isFinite(raw) && raw > 0) {
        batchSize = Math.floor(raw);
      }
    }
  }

  return { dryRun, userId, batchSize };
}

function asDate(value: unknown, fallback: Date): Date {
  if (value instanceof Timestamp) {
    return value.toDate();
  }
  if (value instanceof Date) {
    return value;
  }
  if (typeof value === "string") {
    const parsed = new Date(value);
    if (!Number.isNaN(parsed.getTime())) {
      return parsed;
    }
  }
  return fallback;
}

function asInt(value: unknown, fallback = 0): number {
  if (typeof value === "number" && Number.isFinite(value)) {
    return Math.trunc(value);
  }
  if (typeof value === "string") {
    const parsed = Number(value);
    if (Number.isFinite(parsed)) {
      return Math.trunc(parsed);
    }
  }
  return fallback;
}

function asBool(value: unknown, fallback = false): boolean {
  if (typeof value === "boolean") {
    return value;
  }
  return fallback;
}

function asString(value: unknown, fallback = ""): string {
  if (typeof value === "string") {
    return value;
  }
  return fallback;
}

async function ensureUser(client: Awaited<ReturnType<typeof pgPool.connect>>, firebaseUid: string): Promise<string> {
  const row = await client.query<{ id: string }>(
    `INSERT INTO users (firebase_uid)
     VALUES ($1)
     ON CONFLICT (firebase_uid)
     DO UPDATE SET updated_at = now()
     RETURNING id`,
    [firebaseUid]
  );
  return row.rows[0].id;
}

async function upsertAssignment(
  client: Awaited<ReturnType<typeof pgPool.connect>>,
  userId: string,
  assignmentId: string,
  raw: Record<string, unknown>
): Promise<{ changed: boolean; syncVersion: number; payload: Record<string, unknown> }> {
  const now = new Date();
  const lastModified = asDate(raw.lastModified, now);
  const clientUpdatedAt = asDate(raw.clientUpdatedAt, lastModified);
  const syncVersion = Math.max(0, asInt(raw.syncVersion, 0));
  const updatedByDeviceId = asString(raw.updatedByDeviceId, "unknown-device");

  const normalized = {
    id: assignmentId,
    title: asString(raw.title, "Untitled"),
    className: asString(raw.className, "General"),
    dueDate: asDate(raw.dueDate, now),
    estMinutes: Math.max(0, asInt(raw.estMinutes, 30)),
    source: raw.source == null ? null : asString(raw.source, "manual"),
    externalId: raw.externalId == null ? null : asString(raw.externalId, ""),
    isCompleted: asBool(raw.isCompleted, false),
    notes: asString(raw.notes, ""),
    totalMinutesWorked: Math.max(0, asInt(raw.totalMinutesWorked, 0)),
    lastTinyStep: asString(raw.lastTinyStep, ""),
    priorityScore: Number(raw.priorityScore ?? 0) || 0,
    isFlexibleDueDate: asBool(raw.isFlexibleDueDate, false),
    energyLevel: asString(raw.energyLevel, "medium"),
    isDeleted: asBool(raw.isDeleted, false),
    syncVersion,
    clientUpdatedAt,
    updatedByDeviceId
  };

  const result = await client.query<{ inserted_or_updated: boolean }>(
    `WITH upserted AS (
      INSERT INTO assignments (
        id, user_id, title, class_name, due_date, est_minutes, source, external_id,
        is_completed, notes, total_minutes_worked, last_tiny_step, priority_score,
        is_flexible_due_date, energy_level, is_deleted, sync_version,
        client_updated_at, updated_by_device_id, created_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6, $7, $8,
        $9, $10, $11, $12, $13,
        $14, $15, $16, $17,
        $18, $19, now(), now()
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
        updated_at = now()
      WHERE
        assignments.user_id = EXCLUDED.user_id
        AND (
          EXCLUDED.client_updated_at > assignments.client_updated_at
          OR (
            EXCLUDED.client_updated_at = assignments.client_updated_at
            AND EXCLUDED.sync_version > assignments.sync_version
          )
          OR (
            EXCLUDED.client_updated_at = assignments.client_updated_at
            AND EXCLUDED.sync_version = assignments.sync_version
            AND EXCLUDED.updated_by_device_id > assignments.updated_by_device_id
          )
        )
      RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM upserted) AS inserted_or_updated`,
    [
      normalized.id,
      userId,
      normalized.title,
      normalized.className,
      normalized.dueDate,
      normalized.estMinutes,
      normalized.source,
      normalized.externalId,
      normalized.isCompleted,
      normalized.notes,
      normalized.totalMinutesWorked,
      normalized.lastTinyStep,
      normalized.priorityScore,
      normalized.isFlexibleDueDate,
      normalized.energyLevel,
      normalized.isDeleted,
      normalized.syncVersion,
      normalized.clientUpdatedAt,
      normalized.updatedByDeviceId
    ]
  );

  return {
    changed: Boolean(result.rows[0]?.inserted_or_updated),
    syncVersion,
    payload: {
      ...normalized,
      dueDate: normalized.dueDate.toISOString(),
      clientUpdatedAt: normalized.clientUpdatedAt.toISOString()
    }
  };
}

async function upsertSprint(
  client: Awaited<ReturnType<typeof pgPool.connect>>,
  userId: string,
  sprintId: string,
  raw: Record<string, unknown>
): Promise<{ changed: boolean; syncVersion: number; payload: Record<string, unknown> }> {
  const now = new Date();
  const lastModified = asDate(raw.lastModified, now);
  const clientUpdatedAt = asDate(raw.clientUpdatedAt, lastModified);
  const syncVersion = Math.max(0, asInt(raw.syncVersion, 0));
  const updatedByDeviceId = asString(raw.updatedByDeviceId, "unknown-device");

  const assignmentIdRaw = raw.assignmentId;
  const assignmentId = assignmentIdRaw == null ? null : asString(assignmentIdRaw, "");
  const reflectionNoteRaw = raw.reflectionNote;
  const focusRatingRaw = raw.focusRating;

  const normalized = {
    id: sprintId,
    startTime: asDate(raw.startTime, now),
    endTime: asDate(raw.endTime, now),
    durationSeconds: Math.max(1, asInt(raw.durationSeconds, 1)),
    assignmentId: assignmentId && assignmentId.length > 0 ? assignmentId : null,
    reflectionNote: reflectionNoteRaw == null ? null : asString(reflectionNoteRaw, ""),
    focusRating:
      focusRatingRaw == null
        ? null
        : Math.max(1, Math.min(5, asInt(focusRatingRaw, 1))),
    isDeleted: asBool(raw.isDeleted, false),
    syncVersion,
    clientUpdatedAt,
    updatedByDeviceId
  };

  const result = await client.query<{ inserted_or_updated: boolean }>(
    `WITH upserted AS (
      INSERT INTO sprints (
        id, user_id, assignment_id, start_time, end_time, duration_seconds,
        reflection_note, focus_rating, is_deleted, sync_version,
        client_updated_at, updated_by_device_id, created_at, updated_at
      ) VALUES (
        $1, $2, $3, $4, $5, $6,
        $7, $8, $9, $10,
        $11, $12, now(), now()
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
        updated_at = now()
      WHERE
        sprints.user_id = EXCLUDED.user_id
        AND (
          EXCLUDED.client_updated_at > sprints.client_updated_at
          OR (
            EXCLUDED.client_updated_at = sprints.client_updated_at
            AND EXCLUDED.sync_version > sprints.sync_version
          )
          OR (
            EXCLUDED.client_updated_at = sprints.client_updated_at
            AND EXCLUDED.sync_version = sprints.sync_version
            AND EXCLUDED.updated_by_device_id > sprints.updated_by_device_id
          )
        )
      RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM upserted) AS inserted_or_updated`,
    [
      normalized.id,
      userId,
      normalized.assignmentId,
      normalized.startTime,
      normalized.endTime,
      normalized.durationSeconds,
      normalized.reflectionNote,
      normalized.focusRating,
      normalized.isDeleted,
      normalized.syncVersion,
      normalized.clientUpdatedAt,
      normalized.updatedByDeviceId
    ]
  );

  return {
    changed: Boolean(result.rows[0]?.inserted_or_updated),
    syncVersion,
    payload: {
      ...normalized,
      startTime: normalized.startTime.toISOString(),
      endTime: normalized.endTime.toISOString(),
      clientUpdatedAt: normalized.clientUpdatedAt.toISOString()
    }
  };
}

async function insertSyncChange(
  client: Awaited<ReturnType<typeof pgPool.connect>>,
  userId: string,
  entityType: "assignment" | "sprint",
  entityId: string,
  payload: Record<string, unknown>,
  syncVersion: number,
  op: "upsert" | "tombstone"
): Promise<boolean> {
  const result = await client.query<{ inserted: boolean }>(
    `WITH inserted AS (
      INSERT INTO sync_changes (
        user_id, entity_type, entity_id, op, payload, server_version, mutation_id, changed_at
      ) VALUES (
        $1, $2, $3, $4, $5::jsonb, $6, $7, now()
      )
      ON CONFLICT (user_id, entity_type, entity_id, server_version)
      DO NOTHING
      RETURNING 1
    )
    SELECT EXISTS (SELECT 1 FROM inserted) AS inserted`,
    [userId, entityType, entityId, op, JSON.stringify(payload), syncVersion, randomUUID()]
  );
  return Boolean(result.rows[0]?.inserted);
}

async function migrateOneUser(firebaseUid: string, dryRun: boolean, counters: Counters): Promise<void> {
  const userDocRef = firestore.collection("users").doc(firebaseUid);
  const [assignmentsSnap, sprintsSnap, authSnap] = await Promise.all([
    userDocRef.collection("assignments").get(),
    userDocRef.collection("sprints").get(),
    firestore.collection("user_auth").doc(firebaseUid).get()
  ]);

  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");

    const userId = await ensureUser(client, firebaseUid);
    counters.usersProcessed += 1;

    for (const doc of assignmentsSnap.docs) {
      const raw = doc.data() as Record<string, unknown>;
      counters.assignmentsSeen += 1;

      const migration = await upsertAssignment(client, userId, doc.id, raw);
      if (migration.changed) {
        counters.assignmentRowsChanged += 1;
      }

      const op = asBool(raw.isDeleted, false) ? "tombstone" : "upsert";
      const insertedChange = await insertSyncChange(
        client,
        userId,
        "assignment",
        doc.id,
        migration.payload,
        migration.syncVersion,
        op
      );
      if (insertedChange) {
        counters.syncChangesInserted += 1;
      }
    }

    for (const doc of sprintsSnap.docs) {
      const raw = doc.data() as Record<string, unknown>;
      counters.sprintsSeen += 1;

      const migration = await upsertSprint(client, userId, doc.id, raw);
      if (migration.changed) {
        counters.sprintRowsChanged += 1;
      }

      const op = asBool(raw.isDeleted, false) ? "tombstone" : "upsert";
      const insertedChange = await insertSyncChange(
        client,
        userId,
        "sprint",
        doc.id,
        migration.payload,
        migration.syncVersion,
        op
      );
      if (insertedChange) {
        counters.syncChangesInserted += 1;
      }
    }

    const googleConnected = authSnap.exists;
    const connectedAtRaw = googleConnected ? (authSnap.data()?.connectedAt as unknown) : null;
    const connectedAt = connectedAtRaw ? asDate(connectedAtRaw, new Date()) : null;

    const integrationRes = await client.query<{ inserted_or_updated: boolean }>(
      `WITH upserted AS (
        INSERT INTO integration_status (user_id, google_connected, google_connected_at, updated_at)
        VALUES ($1, $2, $3, now())
        ON CONFLICT (user_id)
        DO UPDATE SET
          google_connected = EXCLUDED.google_connected,
          google_connected_at = EXCLUDED.google_connected_at,
          updated_at = now()
        WHERE
          integration_status.google_connected IS DISTINCT FROM EXCLUDED.google_connected
          OR integration_status.google_connected_at IS DISTINCT FROM EXCLUDED.google_connected_at
        RETURNING 1
      )
      SELECT EXISTS (SELECT 1 FROM upserted) AS inserted_or_updated`,
      [userId, googleConnected, connectedAt]
    );

    if (integrationRes.rows[0]?.inserted_or_updated) {
      counters.integrationRowsChanged += 1;
    }

    if (dryRun) {
      await client.query("ROLLBACK");
    } else {
      await client.query("COMMIT");
    }
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

async function run() {
  const options = parseArgs(process.argv.slice(2));
  const counters: Counters = {
    usersProcessed: 0,
    assignmentsSeen: 0,
    sprintsSeen: 0,
    assignmentRowsChanged: 0,
    sprintRowsChanged: 0,
    syncChangesInserted: 0,
    integrationRowsChanged: 0
  };

  console.info("Starting Firestore -> Postgres migration", options);
  const processedFirebaseUids = new Set<string>();

  if (options.userId) {
    await migrateOneUser(options.userId, options.dryRun, counters);
    processedFirebaseUids.add(options.userId);
  } else {
    let query = firestore.collection("users").orderBy(FieldPath.documentId()).limit(options.batchSize);
    let lastDocId: string | null = null;

    while (true) {
      const snapshot = lastDocId
        ? await query.startAfter(lastDocId).get()
        : await query.get();

      if (snapshot.empty) {
        break;
      }

      for (const doc of snapshot.docs) {
        await migrateOneUser(doc.id, options.dryRun, counters);
        processedFirebaseUids.add(doc.id);
      }

      lastDocId = snapshot.docs[snapshot.docs.length - 1].id;
      if (snapshot.size < options.batchSize) {
        break;
      }
    }

    const authOnlyUsers = await firestore.collection("user_auth").get();
    for (const doc of authOnlyUsers.docs) {
      if (processedFirebaseUids.has(doc.id)) {
        continue;
      }
      await migrateOneUser(doc.id, options.dryRun, counters);
      processedFirebaseUids.add(doc.id);
    }
  }

  await pgPool.end();

  console.info("Migration finished", {
    dryRun: options.dryRun,
    ...counters
  });
}

run().catch(async (error) => {
  console.error("Firestore migration failed", error);
  await pgPool.end();
  process.exit(1);
});
