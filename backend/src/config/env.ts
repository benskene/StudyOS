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
  IMPORT_RATE_LIMIT_WINDOW_MS: z.coerce.number().default(60 * 1000)
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
  IMPORT_RATE_LIMIT_WINDOW_MS: process.env.IMPORT_RATE_LIMIT_WINDOW_MS
});
