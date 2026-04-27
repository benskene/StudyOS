import type { GoogleCourseWork } from "../types/classroom";

export function courseworkDueDateToIso(coursework: GoogleCourseWork): string | null {
  const dueDate = coursework.dueDate;
  if (
    dueDate?.year == null ||
    dueDate?.month == null ||
    dueDate?.day == null
  ) {
    return null;
  }

  const dueTime = coursework.dueTime ?? {};
  const utcMillis = Date.UTC(
    dueDate.year,
    dueDate.month - 1,
    dueDate.day,
    dueTime.hours ?? 23,
    dueTime.minutes ?? 59,
    dueTime.seconds ?? 59,
    dueTime.nanos != null ? Math.floor(dueTime.nanos / 1_000_000) : 0
  );

  const utcDate = new Date(utcMillis);

  // Normalize by resolving the UTC instant and returning canonical ISO.
  return utcDate.toISOString();
}
