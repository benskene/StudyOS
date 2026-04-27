import { google } from "googleapis";
import { buildOAuthClient } from "../config/google";
import type { UserAuthRecord } from "../types/auth";
import type {
  GoogleCourse,
  GoogleCourseWork,
  NormalizedAssignment
} from "../types/classroom";
import { courseworkDueDateToIso } from "../utils/date";
import { upsertUserAuthRecord } from "../storage/userAuthRepository";

type AssignmentWithCourse = {
  course: GoogleCourse;
  coursework: GoogleCourseWork;
};

function toAssignment(course: GoogleCourse, coursework: GoogleCourseWork): NormalizedAssignment | null {
  const dueDateIso = courseworkDueDateToIso(coursework);
  if (!dueDateIso) {
    return null;
  }

  return {
    externalId: coursework.id,
    source: "google_classroom",
    title: coursework.title,
    className: course.name,
    dueDate: dueDateIso,
    notes: coursework.description ?? "",
    estMinutes: 30,
    importedAt: new Date().toISOString()
  };
}

export class GoogleClassroomService {
  private readonly userAuth: UserAuthRecord;

  constructor(userAuth: UserAuthRecord) {
    this.userAuth = userAuth;
  }

  private async getAuthorizedClient() {
    const oauthClient = buildOAuthClient();

    oauthClient.setCredentials({
      access_token: this.userAuth.googleAccessToken,
      refresh_token: this.userAuth.googleRefreshToken,
      expiry_date: this.userAuth.tokenExpiry ? new Date(this.userAuth.tokenExpiry).getTime() : undefined
    });

    oauthClient.on("tokens", async (tokens) => {
      const updated: UserAuthRecord = {
        ...this.userAuth,
        googleAccessToken: tokens.access_token ?? this.userAuth.googleAccessToken,
        googleRefreshToken: tokens.refresh_token ?? this.userAuth.googleRefreshToken,
        tokenExpiry: tokens.expiry_date ? new Date(tokens.expiry_date).toISOString() : this.userAuth.tokenExpiry
      };

      await upsertUserAuthRecord(updated);
    });

    // Trigger refresh if token is stale or near expiry.
    if (
      !this.userAuth.tokenExpiry ||
      Date.now() + 60_000 >= new Date(this.userAuth.tokenExpiry).getTime()
    ) {
      await oauthClient.getAccessToken();
    }

    return oauthClient;
  }

  async fetchCourses(): Promise<GoogleCourse[]> {
    const auth = await this.getAuthorizedClient();
    const classroom = google.classroom({ version: "v1", auth });

    const activeCourses: GoogleCourse[] = [];
    let pageToken: string | undefined;

    do {
      const response = await classroom.courses.list({
        pageSize: 100,
        pageToken,
        courseStates: ["ACTIVE"]
      });

      const courses = response.data.courses ?? [];
      for (const course of courses) {
        if (course.id && course.name && course.courseState === "ACTIVE") {
          activeCourses.push({ id: course.id, name: course.name });
        }
      }

      pageToken = response.data.nextPageToken ?? undefined;
    } while (pageToken);

    return activeCourses;
  }

  async fetchAssignmentsForCourse(courseId: string): Promise<GoogleCourseWork[]> {
    const auth = await this.getAuthorizedClient();
    const classroom = google.classroom({ version: "v1", auth });

    const result: GoogleCourseWork[] = [];
    let pageToken: string | undefined;

    do {
      const response = await classroom.courses.courseWork.list({
        courseId,
        pageSize: 100,
        pageToken
      });

      const courseWork = response.data.courseWork ?? [];
      for (const work of courseWork) {
        if (work.id && work.title && work.dueDate) {
          result.push({
            id: work.id,
            title: work.title,
            description: work.description,
            dueDate: work.dueDate,
            dueTime: work.dueTime
          });
        }
      }

      pageToken = response.data.nextPageToken ?? undefined;
    } while (pageToken);

    return result;
  }

  async fetchAndNormalizeAssignments(existingExternalIds: Set<string>): Promise<NormalizedAssignment[]> {
    const courses = await this.fetchCourses();

    const perCourseAssignments = await Promise.all(
      courses.map(async (course): Promise<AssignmentWithCourse[]> => {
        const assignments = await this.fetchAssignmentsForCourse(course.id);
        return assignments.map((coursework) => ({ course, coursework }));
      })
    );

    const flattened = perCourseAssignments.flat();

    const dedupe = new Set(existingExternalIds);
    const normalized: NormalizedAssignment[] = [];

    for (const { course, coursework } of flattened) {
      const normalizedAssignment = toAssignment(course, coursework);
      if (!normalizedAssignment) {
        continue;
      }

      if (dedupe.has(normalizedAssignment.externalId)) {
        continue;
      }

      dedupe.add(normalizedAssignment.externalId);
      normalized.push(normalizedAssignment);
    }

    return normalized;
  }
}
