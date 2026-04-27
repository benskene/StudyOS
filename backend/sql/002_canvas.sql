ALTER TABLE integration_status
  ADD COLUMN IF NOT EXISTS canvas_connected boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS canvas_connected_at timestamptz NULL;
