import { config as loadEnv } from "dotenv";
import { z } from "zod";

loadEnv();

const envSchema = z.object({
  PORT: z.coerce.number().default(8080),
  DATABASE_URL: z.string().min(1),
  PG_SSL: z
    .union([z.literal("true"), z.literal("false")])
    .optional()
    .transform((value) => value === "true"),
  PG_POOL_MAX: z.coerce.number().default(20),
  GOOGLE_CLIENT_ID: z.string().min(1),
  GOOGLE_CLIENT_SECRET: z.string().min(1),
  GOOGLE_REDIRECT_URI: z.string().url(),
  GOOGLE_OAUTH_SUCCESS_REDIRECT: z.string().min(1),
  GOOGLE_OAUTH_FAILURE_REDIRECT: z.string().min(1),
  FIREBASE_PROJECT_ID: z.string().min(1),
  FIREBASE_CLIENT_EMAIL: z.string().min(1),
  FIREBASE_PRIVATE_KEY: z.string().min(1),
  OAUTH_STATE_TTL_MS: z.coerce.number().default(10 * 60 * 1000),
  IMPORT_RATE_LIMIT_MAX: z.coerce.number().default(10),
  IMPORT_RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60 * 1000),
  // Syllabus parsing. ANTHROPIC_API_KEY is optional so the server still boots
  // without it; the /import/syllabus route returns 503 until it's configured.
  ANTHROPIC_API_KEY: z.string().min(1).optional(),
  // Sonnet 5 matches Opus 5's high-resolution vision tier (2576px), which is
  // what scanned/photographed syllabi actually depend on, at ~40% of the cost.
  SYLLABUS_MODEL: z.string().default("claude-sonnet-5"),
  SYLLABUS_MAX_FILE_MB: z.coerce.number().default(20),
  SYLLABUS_RATE_LIMIT_MAX: z.coerce.number().default(12),
  SYLLABUS_RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60 * 60 * 1000),
  // Cached parses go stale slowly: the prompt infers unstated years from
  // today's date, so bound reuse to roughly one academic year.
  SYLLABUS_CACHE_TTL_DAYS: z.coerce.number().default(180),
  // Billable-parse quota per user. Most students carry <= 6 courses, so this
  // is invisible in normal use and exists to cap runaway spend. Cache hits
  // are free and do not count against it.
  SYLLABUS_USER_PARSE_LIMIT: z.coerce.number().default(15),
  SYLLABUS_USER_PARSE_WINDOW_DAYS: z.coerce.number().default(120)
});

export const env = envSchema.parse({
  PORT: process.env.PORT,
  DATABASE_URL: process.env.DATABASE_URL,
  PG_SSL: process.env.PG_SSL,
  PG_POOL_MAX: process.env.PG_POOL_MAX,
  GOOGLE_CLIENT_ID: process.env.GOOGLE_CLIENT_ID,
  GOOGLE_CLIENT_SECRET: process.env.GOOGLE_CLIENT_SECRET,
  GOOGLE_REDIRECT_URI: process.env.GOOGLE_REDIRECT_URI,
  GOOGLE_OAUTH_SUCCESS_REDIRECT: process.env.GOOGLE_OAUTH_SUCCESS_REDIRECT,
  GOOGLE_OAUTH_FAILURE_REDIRECT: process.env.GOOGLE_OAUTH_FAILURE_REDIRECT,
  FIREBASE_PROJECT_ID: process.env.FIREBASE_PROJECT_ID,
  FIREBASE_CLIENT_EMAIL: process.env.FIREBASE_CLIENT_EMAIL,
  FIREBASE_PRIVATE_KEY: process.env.FIREBASE_PRIVATE_KEY,
  OAUTH_STATE_TTL_MS: process.env.OAUTH_STATE_TTL_MS,
  IMPORT_RATE_LIMIT_MAX: process.env.IMPORT_RATE_LIMIT_MAX,
  IMPORT_RATE_LIMIT_WINDOW_MS: process.env.IMPORT_RATE_LIMIT_WINDOW_MS,
  ANTHROPIC_API_KEY: process.env.ANTHROPIC_API_KEY,
  SYLLABUS_MODEL: process.env.SYLLABUS_MODEL,
  SYLLABUS_MAX_FILE_MB: process.env.SYLLABUS_MAX_FILE_MB,
  SYLLABUS_RATE_LIMIT_MAX: process.env.SYLLABUS_RATE_LIMIT_MAX,
  SYLLABUS_RATE_LIMIT_WINDOW_MS: process.env.SYLLABUS_RATE_LIMIT_WINDOW_MS,
  SYLLABUS_CACHE_TTL_DAYS: process.env.SYLLABUS_CACHE_TTL_DAYS,
  SYLLABUS_USER_PARSE_LIMIT: process.env.SYLLABUS_USER_PARSE_LIMIT,
  SYLLABUS_USER_PARSE_WINDOW_DAYS: process.env.SYLLABUS_USER_PARSE_WINDOW_DAYS
});
