-- Status log for the morning-engagement webhook.
-- The Render static site cannot run a timer after the browser closes.
-- pg_cron calls the edge function, and the function writes one row per run.
-- Clients cannot read or write this table. The service role used by the
-- function is the only granted role.

CREATE TABLE IF NOT EXISTS public.cron_executions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  job_name text NOT NULL,
  status text NOT NULL CHECK (status IN ('running', 'succeeded', 'failed', 'dry_run')),
  ist_date date,
  started_at timestamptz NOT NULL DEFAULT now(),
  finished_at timestamptz,
  http_status integer,
  detail text,
  result jsonb NOT NULL DEFAULT '{}'::jsonb
);

COMMENT ON TABLE public.cron_executions IS
  'Server-side cron run log. Written by the morning-engagement edge function after x-cron-secret is accepted.';

CREATE INDEX IF NOT EXISTS cron_executions_job_started_idx
  ON public.cron_executions (job_name, started_at DESC);

ALTER TABLE public.cron_executions ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.cron_executions FROM PUBLIC;
REVOKE ALL ON TABLE public.cron_executions FROM anon;
REVOKE ALL ON TABLE public.cron_executions FROM authenticated;
GRANT SELECT, INSERT, UPDATE ON TABLE public.cron_executions TO service_role;
