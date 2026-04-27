import { pgPool } from "../db/postgres";
import { addDaysDayKey, dayKeyInTimeZone, dayLabel, isBeforeNow, weekDayKeys } from "../utils/time";

type AssignmentRow = {
  id: string;
  title: string;
  due_date: Date;
  est_minutes: number;
  is_completed: boolean;
  notes: string;
  total_minutes_worked: number;
  last_tiny_step: string;
  last_modified: Date;
  sync_version: number;
  client_updated_at: Date;
  updated_by_device_id: string;
  source: string | null;
  external_id: string | null;
  class_name: string;
  priority_score: number;
  is_flexible_due_date: boolean;
  energy_level: string;
  is_deleted: boolean;
};

type SprintRow = {
  id: string;
  assignment_id: string | null;
  start_time: Date;
  end_time: Date;
  duration_seconds: number;
  reflection_note: string | null;
  focus_rating: number | null;
  is_deleted: boolean;
};

function shortLabel(title: string): string {
  const trimmed = title.trim();
  if (trimmed.length <= 10) {
    return trimmed;
  }
  return `${trimmed.slice(0, 10)}…`;
}

async function fetchAssignments(userId: string): Promise<AssignmentRow[]> {
  const result = await pgPool.query<AssignmentRow>(
    `SELECT
      id, title, class_name, due_date, est_minutes, source, external_id, is_completed, notes,
      total_minutes_worked, last_tiny_step, priority_score, is_flexible_due_date, energy_level,
      is_deleted, sync_version, client_updated_at, updated_by_device_id,
      COALESCE(client_updated_at, updated_at) as last_modified
     FROM assignments
     WHERE user_id = $1 AND is_deleted = false`,
    [userId]
  );
  return result.rows;
}

async function fetchSprints(userId: string): Promise<SprintRow[]> {
  const result = await pgPool.query<SprintRow>(
    `SELECT id, assignment_id, start_time, end_time, duration_seconds, reflection_note, focus_rating, is_deleted
     FROM sprints
     WHERE user_id = $1 AND is_deleted = false`,
    [userId]
  );
  return result.rows;
}

export async function refreshAnalyticsCache(userId: string, tz: string, weekStart: string): Promise<void> {
  const [assignments, sprints] = await Promise.all([fetchAssignments(userId), fetchSprints(userId)]);
  const dayKeys = weekDayKeys(weekStart);
  const daySet = new Set(dayKeys);
  const completed = assignments.filter((a) => a.is_completed);

  const daily = dayKeys.map((day) => {
    const dayCompleted = completed.filter((a) => dayKeyInTimeZone(a.last_modified, tz) === day);
    const daySprints = sprints.filter((s) => dayKeyInTimeZone(s.start_time, tz) === day);

    const onTimeCount = dayCompleted.filter((a) => a.last_modified.getTime() <= a.due_date.getTime()).length;
    const lateCount = Math.max(0, dayCompleted.length - onTimeCount);
    const missedCount = assignments.filter((a) => !a.is_completed && dayKeyInTimeZone(a.due_date, tz) === day).length;

    return {
      day,
      focusedMinutes: Math.round(daySprints.reduce((sum, s) => sum + s.duration_seconds, 0) / 60),
      sprintsCount: daySprints.length,
      completedCount: dayCompleted.length,
      missedCount,
      onTimeCount,
      lateCount
    };
  });

  const weekSprints = sprints.filter((s) => daySet.has(dayKeyInTimeZone(s.start_time, tz)));
  const weekCompleted = completed.filter((a) => daySet.has(dayKeyInTimeZone(a.last_modified, tz)));
  const weeklyOnTimeCount = weekCompleted.filter((a) => a.last_modified.getTime() <= a.due_date.getTime()).length;
  const weeklyLateCount = Math.max(0, weekCompleted.length - weeklyOnTimeCount);
  const weeklyMissedCount = assignments.filter((a) => !a.is_completed && daySet.has(dayKeyInTimeZone(a.due_date, tz))).length;

  const assignmentCounts = new Map<string, number>();
  for (const sprint of weekSprints) {
    if (!sprint.assignment_id) {
      continue;
    }
    assignmentCounts.set(sprint.assignment_id, (assignmentCounts.get(sprint.assignment_id) ?? 0) + 1);
  }

  let mostWorkedAssignmentId: string | null = null;
  let bestCount = -1;
  for (const [assignmentId, count] of assignmentCounts.entries()) {
    if (count > bestCount) {
      mostWorkedAssignmentId = assignmentId;
      bestCount = count;
    }
  }

  const client = await pgPool.connect();
  try {
    await client.query("BEGIN");

    for (const row of daily) {
      await client.query(
        `INSERT INTO analytics_daily_user (
          user_id, day, tz, focused_minutes, sprints_count, completed_count,
          missed_count, on_time_count, late_count, updated_at
        ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, now())
        ON CONFLICT (user_id, day, tz)
        DO UPDATE SET
          focused_minutes = EXCLUDED.focused_minutes,
          sprints_count = EXCLUDED.sprints_count,
          completed_count = EXCLUDED.completed_count,
          missed_count = EXCLUDED.missed_count,
          on_time_count = EXCLUDED.on_time_count,
          late_count = EXCLUDED.late_count,
          updated_at = now()`,
        [
          userId,
          row.day,
          tz,
          row.focusedMinutes,
          row.sprintsCount,
          row.completedCount,
          row.missedCount,
          row.onTimeCount,
          row.lateCount
        ]
      );
    }

    await client.query(
      `INSERT INTO analytics_weekly_user (
        user_id, week_start, tz, focused_minutes, sprints_count, completed_count,
        missed_count, on_time_count, late_count, most_worked_assignment_id, updated_at
      ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now())
      ON CONFLICT (user_id, week_start, tz)
      DO UPDATE SET
        focused_minutes = EXCLUDED.focused_minutes,
        sprints_count = EXCLUDED.sprints_count,
        completed_count = EXCLUDED.completed_count,
        missed_count = EXCLUDED.missed_count,
        on_time_count = EXCLUDED.on_time_count,
        late_count = EXCLUDED.late_count,
        most_worked_assignment_id = EXCLUDED.most_worked_assignment_id,
        updated_at = now()`,
      [
        userId,
        weekStart,
        tz,
        Math.round(weekSprints.reduce((sum, s) => sum + s.duration_seconds, 0) / 60),
        weekSprints.length,
        weekCompleted.length,
        weeklyMissedCount,
        weeklyOnTimeCount,
        weeklyLateCount,
        mostWorkedAssignmentId
      ]
    );

    await client.query("COMMIT");
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function getDashboardAnalytics(userId: string, weekStart: string, tz: string) {
  await refreshAnalyticsCache(userId, tz, weekStart);

  const [assignments, sprints] = await Promise.all([fetchAssignments(userId), fetchSprints(userId)]);
  const dayKeys = weekDayKeys(weekStart);
  const daySet = new Set(dayKeys);

  const completed = assignments.filter((a) => a.is_completed);
  const completedCount = completed.length;
  const missedCount = assignments.filter((a) => !a.is_completed && isBeforeNow(a.due_date.toISOString())).length;

  const onTimeCount = completed.filter((a) => a.last_modified.getTime() <= a.due_date.getTime()).length;
  const lateCount = Math.max(0, completedCount - onTimeCount);
  const onTimePercent = completedCount > 0 ? Math.floor((onTimeCount / completedCount) * 100) : null;

  const weekSprints = sprints.filter((s) => daySet.has(dayKeyInTimeZone(s.start_time, tz)));
  const sprintsThisWeek = weekSprints.length;
  const focusedMinutesThisWeek = Math.round(weekSprints.reduce((sum, sprint) => sum + sprint.duration_seconds, 0) / 60);

  const byAssignment = new Map<string, number>();
  for (const sprint of weekSprints) {
    if (!sprint.assignment_id) {
      continue;
    }
    byAssignment.set(sprint.assignment_id, (byAssignment.get(sprint.assignment_id) ?? 0) + 1);
  }

  let mostWorkedTask: { id: string; title: string } | null = null;
  let maxCount = -1;
  for (const [assignmentId, count] of byAssignment.entries()) {
    if (count > maxCount) {
      const found = assignments.find((a) => a.id === assignmentId);
      mostWorkedTask = found ? { id: found.id, title: found.title } : null;
      maxCount = count;
    }
  }

  const workloadByDay = dayKeys.map((day) => {
    const totalMinutes = completed
      .filter((assignment) => dayKeyInTimeZone(assignment.last_modified, tz) === day)
      .reduce((sum, assignment) => sum + Math.max(0, assignment.total_minutes_worked), 0);

    return {
      day,
      label: dayLabel(day),
      totalMinutes
    };
  });

  return {
    completedCount,
    missedCount,
    onTimePercent,
    sprintsThisWeek,
    focusedMinutesThisWeek,
    mostWorkedTask,
    workloadByDay,
    onTimeVsLate: {
      onTimeCount,
      lateCount,
      totalCompleted: completedCount
    }
  };
}

export async function getEstimatedVsActual(userId: string, limit: number) {
  const safeLimit = Math.max(1, Math.min(limit, 50));
  const assignments = await fetchAssignments(userId);

  return assignments
    .filter((a) => a.is_completed && a.total_minutes_worked > 0)
    .sort((a, b) => b.last_modified.getTime() - a.last_modified.getTime())
    .slice(0, safeLimit)
    .map((a) => ({
      assignmentId: a.id,
      label: shortLabel(a.title),
      title: a.title,
      estimatedMinutes: a.est_minutes,
      actualMinutes: a.total_minutes_worked,
      completedAt: a.last_modified.toISOString()
    }));
}

export async function getRecentActivity(userId: string, limit: number) {
  const safeLimit = Math.max(1, Math.min(limit, 100));
  const assignments = await fetchAssignments(userId);

  return assignments
    .sort((a, b) => b.last_modified.getTime() - a.last_modified.getTime())
    .slice(0, safeLimit)
    .map((a) => ({
      assignmentId: a.id,
      title: a.title,
      className: a.class_name,
      isCompleted: a.is_completed,
      lastModified: a.last_modified.toISOString()
    }));
}

export function defaultWeekStartInTz(tz: string): string {
  const todayKey = dayKeyInTimeZone(new Date(), tz);
  const date = new Date(`${todayKey}T00:00:00Z`);
  const day = date.getUTCDay();
  const diffToMonday = (day + 6) % 7;
  return addDaysDayKey(todayKey, -diffToMonday);
}
