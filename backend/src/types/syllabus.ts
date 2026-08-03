import { z } from "zod";

export const deadlineTypeSchema = z.enum([
  "assignment",
  "exam",
  "quiz",
  "reading",
  "project",
  "paper"
]);

export const gradeCategorySchema = z.object({
  name: z.string().min(1),
  weightPercent: z.number().min(0).max(100)
});

export const parsedDeadlineSchema = z.object({
  title: z.string().min(1),
  // ISO date (yyyy-MM-dd). Syllabi rarely give times; the client applies a
  // local end-of-day due time.
  dueDate: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
  type: deadlineTypeSchema,
  gradeCategoryName: z.string().nullable(),
  weightPercent: z.number().min(0).max(100).nullable(),
  notes: z.string(),
  confidence: z.enum(["high", "low"])
});

export const parsedSyllabusSchema = z.object({
  course: z.object({
    name: z.string().min(1),
    teacher: z.string(),
    semesterStart: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable(),
    semesterEnd: z.string().regex(/^\d{4}-\d{2}-\d{2}$/).nullable()
  }),
  gradeCategories: z.array(gradeCategorySchema),
  deadlines: z.array(parsedDeadlineSchema)
});

export type ParsedSyllabus = z.infer<typeof parsedSyllabusSchema>;

/** JSON Schema handed to Claude's structured-output constraint. Kept in sync
 *  with the zod schema above, which re-validates the response server-side. */
export const parsedSyllabusJsonSchema = {
  type: "object",
  additionalProperties: false,
  required: ["course", "gradeCategories", "deadlines"],
  properties: {
    course: {
      type: "object",
      additionalProperties: false,
      required: ["name", "teacher", "semesterStart", "semesterEnd"],
      properties: {
        name: { type: "string", description: "Short course name, e.g. 'BIO 201' or 'AP Biology'" },
        teacher: { type: "string", description: "Instructor name, or empty string if not stated" },
        semesterStart: {
          type: ["string", "null"],
          format: "date",
          description: "First day of the term (yyyy-MM-dd), null if not stated"
        },
        semesterEnd: {
          type: ["string", "null"],
          format: "date",
          description: "Last day of the term or final exam date (yyyy-MM-dd), null if not stated"
        }
      }
    },
    gradeCategories: {
      type: "array",
      description: "Weighted grading buckets from the grading/evaluation section",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["name", "weightPercent"],
        properties: {
          name: { type: "string" },
          weightPercent: { type: "number", description: "Weight as a percentage, 0-100" }
        }
      }
    },
    deadlines: {
      type: "array",
      description: "Every dated assignment, exam, quiz, reading, project, and paper",
      items: {
        type: "object",
        additionalProperties: false,
        required: ["title", "dueDate", "type", "gradeCategoryName", "weightPercent", "notes", "confidence"],
        properties: {
          title: { type: "string" },
          dueDate: { type: "string", format: "date", description: "Due date as yyyy-MM-dd" },
          type: { type: "string", enum: ["assignment", "exam", "quiz", "reading", "project", "paper"] },
          gradeCategoryName: {
            type: ["string", "null"],
            description: "Which grade category this belongs to, matching gradeCategories[].name, or null"
          },
          weightPercent: {
            type: ["number", "null"],
            description: "This item's individual weight of the final grade if stated or derivable, else null"
          },
          notes: { type: "string", description: "Short context from the syllabus (chapter, topic, location). Empty string if none." },
          confidence: {
            type: "string",
            enum: ["high", "low"],
            description: "low when the date or title required guessing (ambiguous week references, unclear year)"
          }
        }
      }
    }
  }
} as const;
