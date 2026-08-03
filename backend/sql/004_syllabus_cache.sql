-- Cross-user cache of syllabus parses.
--
-- Classmates in the same course upload the byte-identical syllabus PDF, so
-- keying on the content hash means only the first upload of a given file is
-- billable. Keyed by model as well so switching SYLLABUS_MODEL produces fresh
-- parses instead of serving another model's output.
CREATE TABLE IF NOT EXISTS syllabus_parse_cache (
  content_hash text NOT NULL,
  model text NOT NULL,
  parsed jsonb NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (content_hash, model)
);

-- Entries are read with a TTL predicate: the parse prompt interpolates today's
-- date to infer unstated years, so a very old entry could carry a stale year.
CREATE INDEX IF NOT EXISTS idx_syllabus_parse_cache_created
  ON syllabus_parse_cache(created_at DESC);

-- Separates billable parses from free cache hits so the per-user quota limits
-- spend rather than usage.
ALTER TABLE syllabus_imports
  ADD COLUMN IF NOT EXISTS cache_hit boolean NOT NULL DEFAULT false;

-- Supports the rolling-window quota count.
CREATE INDEX IF NOT EXISTS idx_syllabus_imports_user_billable
  ON syllabus_imports(user_id, created_at DESC)
  WHERE status = 'succeeded' AND cache_hit = false;
