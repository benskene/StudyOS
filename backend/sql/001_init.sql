CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE TABLE IF NOT EXISTS users (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  firebase_uid text NOT NULL UNIQUE,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS devices (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  device_id text NOT NULL,
  platform text,
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, device_id)
);

CREATE TABLE IF NOT EXISTS assignments (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  title text NOT NULL,
  class_name text NOT NULL,
  due_date timestamptz NOT NULL,
  est_minutes integer NOT NULL,
  source text,
  external_id text,
  is_completed boolean NOT NULL DEFAULT false,
  notes text NOT NULL DEFAULT '',
  total_minutes_worked integer NOT NULL DEFAULT 0,
  last_tiny_step text NOT NULL DEFAULT '',
  priority_score numeric NOT NULL DEFAULT 0,
  is_flexible_due_date boolean NOT NULL DEFAULT false,
  energy_level text NOT NULL DEFAULT 'medium',
  is_deleted boolean NOT NULL DEFAULT false,
  sync_version bigint NOT NULL DEFAULT 0,
  client_updated_at timestamptz NOT NULL,
  updated_by_device_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS sprints (
  id uuid PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  assignment_id uuid NULL,
  start_time timestamptz NOT NULL,
  end_time timestamptz NOT NULL,
  duration_seconds integer NOT NULL,
  reflection_note text,
  focus_rating integer,
  is_deleted boolean NOT NULL DEFAULT false,
  sync_version bigint NOT NULL DEFAULT 0,
  client_updated_at timestamptz NOT NULL,
  updated_by_device_id text NOT NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT sprints_assignment_fk FOREIGN KEY (assignment_id) REFERENCES assignments(id) ON DELETE SET NULL,
  CONSTRAINT sprints_focus_rating_chk CHECK (focus_rating IS NULL OR (focus_rating >= 1 AND focus_rating <= 5))
);

CREATE TABLE IF NOT EXISTS sync_changes (
  change_id bigserial PRIMARY KEY,
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  entity_type text NOT NULL,
  entity_id uuid NOT NULL,
  op text NOT NULL,
  payload jsonb NOT NULL,
  server_version bigint NOT NULL,
  changed_at timestamptz NOT NULL DEFAULT now(),
  mutation_id uuid NULL,
  UNIQUE (user_id, entity_type, entity_id, server_version)
);

CREATE TABLE IF NOT EXISTS sync_mutation_dedup (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  mutation_id uuid NOT NULL,
  processed_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, mutation_id)
);

CREATE TABLE IF NOT EXISTS analytics_daily_user (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  day date NOT NULL,
  tz text NOT NULL,
  focused_minutes integer NOT NULL DEFAULT 0,
  sprints_count integer NOT NULL DEFAULT 0,
  completed_count integer NOT NULL DEFAULT 0,
  missed_count integer NOT NULL DEFAULT 0,
  on_time_count integer NOT NULL DEFAULT 0,
  late_count integer NOT NULL DEFAULT 0,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, day, tz)
);

CREATE TABLE IF NOT EXISTS analytics_weekly_user (
  user_id uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  week_start date NOT NULL,
  tz text NOT NULL,
  focused_minutes integer NOT NULL DEFAULT 0,
  sprints_count integer NOT NULL DEFAULT 0,
  completed_count integer NOT NULL DEFAULT 0,
  missed_count integer NOT NULL DEFAULT 0,
  on_time_count integer NOT NULL DEFAULT 0,
  late_count integer NOT NULL DEFAULT 0,
  most_worked_assignment_id uuid NULL,
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, week_start, tz)
);

CREATE TABLE IF NOT EXISTS integration_status (
  user_id uuid PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
  google_connected boolean NOT NULL DEFAULT false,
  google_connected_at timestamptz NULL,
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_assignments_user_due_date ON assignments(user_id, due_date);
CREATE INDEX IF NOT EXISTS idx_assignments_user_updated_at ON assignments(user_id, updated_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignments_user_completed_active ON assignments(user_id, is_completed) WHERE is_deleted = false;
CREATE INDEX IF NOT EXISTS idx_sprints_user_start_time ON sprints(user_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_sprints_user_assignment_start_time ON sprints(user_id, assignment_id, start_time DESC);
CREATE INDEX IF NOT EXISTS idx_sync_changes_user_change_id ON sync_changes(user_id, change_id);
CREATE INDEX IF NOT EXISTS idx_analytics_daily_user_day ON analytics_daily_user(user_id, day DESC);
CREATE INDEX IF NOT EXISTS idx_analytics_weekly_user_week_start ON analytics_weekly_user(user_id, week_start DESC);
