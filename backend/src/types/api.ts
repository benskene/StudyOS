export type SyncEntityType = "assignment" | "sprint";
export type SyncOperation = "upsert" | "tombstone";

export type AssignmentPayload = {
  id: string;
  title: string;
  className: string;
  dueDate: string;
  estMinutes: number;
  source?: string | null;
  externalId?: string | null;
  isCompleted: boolean;
  notes: string;
  totalMinutesWorked: number;
  lastTinyStep: string;
  priorityScore: number;
  isFlexibleDueDate: boolean;
  energyLevel: string;
  isDeleted: boolean;
  clientUpdatedAt: string;
  updatedByDeviceId: string;
};

export type SprintPayload = {
  id: string;
  startTime: string;
  endTime: string;
  durationSeconds: number;
  assignmentId?: string | null;
  reflectionNote?: string | null;
  focusRating?: number | null;
  isDeleted: boolean;
  clientUpdatedAt: string;
  updatedByDeviceId: string;
};
