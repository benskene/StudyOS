import Anthropic from "@anthropic-ai/sdk";
import { env } from "../config/env";
import {
  ParsedSyllabus,
  parsedSyllabusSchema,
  parsedSyllabusJsonSchema
} from "../types/syllabus";

export type SyllabusFileKind = "pdf" | "image";

export class SyllabusParseError extends Error {
  constructor(
    message: string,
    readonly statusCode: number,
    readonly code: string
  ) {
    super(message);
  }
}

const SUPPORTED_IMAGE_TYPES = new Set(["image/jpeg", "image/png", "image/webp", "image/gif"]);

export function fileKindFor(mimeType: string): SyllabusFileKind | null {
  if (mimeType === "application/pdf") return "pdf";
  if (SUPPORTED_IMAGE_TYPES.has(mimeType)) return "image";
  return null;
}

const SYSTEM_PROMPT = `You extract structured semester data from college and high-school course syllabi.

Rules:
- Extract EVERY dated deliverable: assignments, problem sets, exams (including midterms and finals), quizzes, readings, projects, papers, and presentations. Do not skip readings or minor items.
- Resolve relative dates ("Week 3", "the Tuesday after spring break") into concrete dates using the semester schedule in the document. If the year is not stated, infer it from context (a fall syllabus mentioning "August" through "December" spans one calendar year; spring syllabi start in January). Today's date is {{TODAY}} — syllabi are usually for the current or upcoming term.
- If an item's date genuinely cannot be resolved to a specific day, place it on the most plausible date and mark confidence "low". Mark confidence "low" whenever you had to guess a date, year, or title.
- Grade categories come from the grading/evaluation/assessment section. Weights must be the stated percentages. If grading is described in points, convert to percentages of the total.
- If an individual item's weight is stated (e.g. "each exam is worth 15%") or derivable (category weight divided evenly across its listed items), fill weightPercent; otherwise null.
- Undated recurring items ("weekly quizzes" with no schedule) should NOT be invented as individual deadlines.
- Course name should be short and recognizable (course code and/or title, not the full catalog sentence).`;

type ImageMediaType = "image/jpeg" | "image/png" | "image/webp" | "image/gif";

export async function parseSyllabus(
  files: { buffer: Buffer; mimeType: string }[]
): Promise<ParsedSyllabus> {
  if (!env.ANTHROPIC_API_KEY) {
    throw new SyllabusParseError(
      "Syllabus parsing is not configured on this server.",
      503,
      "parser_not_configured"
    );
  }

  const client = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });

  const mediaBlocks: Anthropic.Messages.ContentBlockParam[] = files.map((file) => {
    const kind = fileKindFor(file.mimeType);
    if (kind === "pdf") {
      return {
        type: "document" as const,
        source: {
          type: "base64" as const,
          media_type: "application/pdf" as const,
          data: file.buffer.toString("base64")
        }
      };
    }
    if (kind === "image") {
      return {
        type: "image" as const,
        source: {
          type: "base64" as const,
          // Safe: fileKindFor only admits the SDK's supported image types.
          media_type: file.mimeType as ImageMediaType,
          data: file.buffer.toString("base64")
        }
      };
    }
    throw new SyllabusParseError(
      `Unsupported file type: ${file.mimeType}. Upload a PDF or a photo (JPEG/PNG/WebP).`,
      400,
      "unsupported_file_type"
    );
  });

  const today = new Date().toISOString().slice(0, 10);

  const response = await client.messages.create({
    model: env.SYLLABUS_MODEL,
    max_tokens: 16000,
    system: SYSTEM_PROMPT.replace("{{TODAY}}", today),
    output_config: {
      format: {
        type: "json_schema",
        schema: parsedSyllabusJsonSchema as unknown as Record<string, unknown>
      }
    },
    messages: [
      {
        role: "user",
        content: [
          ...mediaBlocks,
          {
            type: "text",
            text: "Extract this syllabus into the required structure. Include every dated deadline."
          }
        ]
      }
    ]
  });

  if (response.stop_reason === "refusal") {
    throw new SyllabusParseError(
      "The document could not be processed. Make sure the upload is a course syllabus.",
      422,
      "parse_refused"
    );
  }
  if (response.stop_reason === "max_tokens") {
    throw new SyllabusParseError(
      "This syllabus is too long to parse in one pass. Try uploading just the schedule and grading pages.",
      422,
      "parse_truncated"
    );
  }

  const textBlock = response.content.find((block) => block.type === "text");
  if (!textBlock || textBlock.type !== "text") {
    throw new SyllabusParseError("The parser returned no result. Try again.", 502, "empty_response");
  }

  let raw: unknown;
  try {
    raw = JSON.parse(textBlock.text);
  } catch {
    throw new SyllabusParseError("The parser returned malformed data. Try again.", 502, "invalid_json");
  }

  const validated = parsedSyllabusSchema.safeParse(raw);
  if (!validated.success) {
    throw new SyllabusParseError(
      "The parser result failed validation. Try again with a clearer scan.",
      502,
      "schema_mismatch"
    );
  }

  return validated.data;
}
