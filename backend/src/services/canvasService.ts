import type { CanvasCourse, CanvasAssignment, CanvasNormalizedAssignment } from "../types/canvas";

function normalizeDomain(raw: string): string {
  return raw.replace(/^https?:\/\//, "").replace(/\/+$/, "").toLowerCase();
}

function stripHtml(html: string): string {
  return html.replace(/<[^>]*>/g, " ").replace(/\s+/g, " ").trim();
}

export class CanvasService {
  private readonly baseURL: string;
  private readonly accessToken: string;

  constructor(domain: string, accessToken: string) {
    this.baseURL = `https://${normalizeDomain(domain)}`;
    this.accessToken = accessToken;
  }

  private async get<T>(path: string): Promise<T> {
    const response = await fetch(`${this.baseURL}${path}`, {
      headers: { Authorization: `Bearer ${this.accessToken}` }
    });

    if (!response.ok) {
      throw new Error(`Canvas API ${response.status}: ${response.statusText}`);
    }

    return response.json() as Promise<T>;
  }

  async validateConnection(): Promise<void> {
    await this.get("/api/v1/users/self/profile");
  }

  async fetchCourses(): Promise<CanvasCourse[]> {
    type RawCourse = { id: number; name: string; workflow_state: string };

    const courses = await this.get<RawCourse[]>(
      "/api/v1/courses?enrollment_type=student&enrollment_state=active&per_page=100&state[]=available"
    );

    return courses
      .filter((c) => c.workflow_state === "available" && c.id && c.name)
      .map((c) => ({ id: String(c.id), name: c.name }));
  }

  async fetchAssignmentsForCourse(courseId: string): Promise<CanvasAssignment[]> {
    type RawAssignment = {
      id: number;
      name: string;
      description: string | null;
      due_at: string | null;
      course_id: number;
    };

    const assignments = await this.get<RawAssignment[]>(
      `/api/v1/courses/${courseId}/assignments?per_page=100&order_by=due_at`
    );

    return assignments
      .filter((a) => a.id && a.name && a.due_at)
      .map((a) => ({
        id: String(a.id),
        name: a.name,
        description: a.description,
        due_at: a.due_at,
        course_id: String(a.course_id)
      }));
  }

  async fetchAndNormalizeAssignments(
    existingExternalIds: Set<string>
  ): Promise<CanvasNormalizedAssignment[]> {
    const courses = await this.fetchCourses();

    const perCourse = await Promise.all(
      courses.map(async (course) => {
        const assignments = await this.fetchAssignmentsForCourse(course.id);
        return assignments.map((a) => ({ course, assignment: a }));
      })
    );

    const flattened = perCourse.flat();
    const dedupe = new Set(existingExternalIds);
    const normalized: CanvasNormalizedAssignment[] = [];

    for (const { course, assignment } of flattened) {
      if (!assignment.due_at) continue;

      const externalId = assignment.id;
      if (dedupe.has(externalId)) continue;

      dedupe.add(externalId);
      normalized.push({
        externalId,
        source: "canvas",
        title: assignment.name,
        className: course.name,
        dueDate: assignment.due_at,
        notes: assignment.description ? stripHtml(assignment.description) : "",
        estMinutes: 30,
        importedAt: new Date().toISOString()
      });
    }

    return normalized;
  }
}
