export type GoogleCourse = {
  id: string;
  name: string;
};

export type GoogleCourseWork = {
  id: string;
  title: string;
  description?: string | null;
  dueDate?: {
    year?: number | null;
    month?: number | null;
    day?: number | null;
  };
  dueTime?: {
    hours?: number | null;
    minutes?: number | null;
    seconds?: number | null;
    nanos?: number | null;
  };
};

export type NormalizedAssignment = {
  externalId: string;
  source: "google_classroom";
  title: string;
  className: string;
  dueDate: string;
  notes: string;
  estMinutes: number;
  importedAt: string;
};
