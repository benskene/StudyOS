export type CanvasCourse = {
  id: string;
  name: string;
};

export type CanvasAssignment = {
  id: string;
  name: string;
  description: string | null;
  due_at: string | null;
  course_id: string;
};

export type CanvasNormalizedAssignment = {
  externalId: string;
  source: "canvas";
  title: string;
  className: string;
  dueDate: string;
  notes: string;
  estMinutes: number;
  importedAt: string;
};
