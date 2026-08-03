-- Syllabus-derived semester data: courses with weighted grade categories,
-- and typed/weighted deadlines on assignments.

CREATE TABLE IF NOT EXISTS courses (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name text NOT NULL,
  teacher text NOT NULL DEFAULT '',
  color_hex text NOT NULL DEFAULT '#45B7D1',
  source text NOT NULL DEFAULT 'manual',
  semester_start timestamptz NULL,
  semester_end timestamptz NULL,
  grade_categories jsonb NOT NULL DEFAULT '[]',
  is_deleted boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE assignments
  ADD COLUMN IF NOT EXISTS deadline_type text NOT NULL DEFAULT 'assignment',
  ADD COLUMN IF NOT EXISTS grade_category text NULL,
  ADD COLUMN IF NOT EXISTS weight_percent numeric NULL,
  ADD COLUMN IF NOT EXISTS course_id uuid NULL;

CREATE INDEX IF NOT EXISTS idx_courses_user ON courses(user_id);

-- Tracks each syllabus parse for rate limiting and debugging.
CREATE TABLE IF NOT EXISTS syllabus_imports (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  file_kind text NOT NULL,
  file_bytes integer NOT NULL,
  model text NOT NULL,
  status text NOT NULL,
  error_message text NULL,
  course_name text NULL,
  deadline_count integer NOT NULL DEFAULT 0,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_syllabus_imports_user_created
  ON syllabus_imports(user_id, created_at DESC);
