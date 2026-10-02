-- Palm Analysis Failure Log
--
-- Every failed palm analysis gets exactly one row here, whatever the cause.
-- Before this table a failure left only `palm_scans.status = 'failed'` and a
-- free-text `palm_analysis.error_message`, so a support question like
-- "why did User C's left palm fail on attempt 1?" was unanswerable after the
-- device logcat rotated.
--
-- The row records the machine-readable reason, the quality numbers Gemini
-- returned, and enough device context to spot per-device capture problems.
-- It never stores the palm image or any reading content.

CREATE TABLE IF NOT EXISTS public.palm_analysis_failures (
  id                UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Nullable: a failure can happen before the scan row exists (quota, upload).
  user_id           UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  scan_id           UUID REFERENCES public.palm_scans(id) ON DELETE CASCADE,
  analysis_id       UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,

  -- ── What was attempted ──────────────────────────────────────────────────
  hand_side         TEXT,                       -- 'left' | 'right'
  language          TEXT,                       -- 'en' | 'hi' | 'hi-Latn'
  attempt_number    INTEGER,                    -- nth attempt by this user for this hand

  -- ── Where it failed ─────────────────────────────────────────────────────
  -- 'quota' | 'upload' | 'stage_a' | 'quality_gate' | 'stage_b' | 'persist' | 'client'
  stage             TEXT NOT NULL,

  -- Machine-readable reason. Drives the user-facing message, so it must stay
  -- a closed set. See failure_reason values in the palm-analysis Edge Function.
  --   NO_PALM_DETECTED, PARTIAL_PALM, TOO_BLURRY, TOO_DARK, TOO_BRIGHT,
  --   TOO_FAR, TOO_CLOSE, OBSTRUCTED, WRONG_SIDE, LOW_QUALITY_IMAGE,
  --   AI_SERVICE_BUSY, AI_TIMEOUT, AI_RESPONSE_TRUNCATED, STAGE_A_FAILED,
  --   STAGE_B_FAILED, FREE_LIMIT_REACHED, UPLOAD_FAILED, NETWORK_ERROR, UNKNOWN
  failure_code      TEXT NOT NULL DEFAULT 'UNKNOWN',

  -- Human-readable, already sanitised. Safe to show to support staff.
  reason            TEXT,

  -- ── Quality gate detail (null when the failure was not quality-related) ──
  quality_score        NUMERIC(4,3),            -- 0.000–1.000 as Gemini returned it
  palm_detected        BOOLEAN,
  suitable_for_analysis BOOLEAN,
  quality_issues       JSONB NOT NULL DEFAULT '[]'::jsonb,

  -- ── Diagnostics ─────────────────────────────────────────────────────────
  http_status       INTEGER,
  image_path        TEXT,                       -- storage path, lets us re-inspect the exact frame
  image_bytes       INTEGER,
  provider_message  TEXT,                       -- sanitised upstream error text
  app_version       TEXT,
  platform          TEXT,
  device_model      TEXT,

  created_at        TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ─────────────────────────────────────────────────────────────────
-- "show me this user's failures" — the individual tracking case.
CREATE INDEX IF NOT EXISTS idx_palm_analysis_failures_user_created
  ON public.palm_analysis_failures(user_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_palm_analysis_failures_scan
  ON public.palm_analysis_failures(scan_id);

-- "which reason is most common this week" — the aggregate case.
CREATE INDEX IF NOT EXISTS idx_palm_analysis_failures_code_created
  ON public.palm_analysis_failures(failure_code, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_palm_analysis_failures_stage
  ON public.palm_analysis_failures(stage);

-- ── RLS ─────────────────────────────────────────────────────────────────────
ALTER TABLE public.palm_analysis_failures ENABLE ROW LEVEL SECURITY;

-- Users read their own failures (lets the app show "last attempt failed because…").
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'palm_analysis_failures'
      AND policyname = 'Users can read own palm analysis failures'
  ) THEN
    CREATE POLICY "Users can read own palm analysis failures"
      ON public.palm_analysis_failures
      FOR SELECT
      USING (auth.uid() = user_id);
  END IF;
END $$;

-- The client logs its own failures (network/upload errors never reach the server).
-- WITH CHECK pins user_id so a client cannot write a row against another user.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'palm_analysis_failures'
      AND policyname = 'Users can log own palm analysis failures'
  ) THEN
    CREATE POLICY "Users can log own palm analysis failures"
      ON public.palm_analysis_failures
      FOR INSERT
      TO authenticated
      WITH CHECK (auth.uid() = user_id);
  END IF;
END $$;

-- Service role (Edge Function) writes every server-side failure.
--
-- Scoped `TO service_role` deliberately. An unrestricted FOR ALL policy with
-- USING(true)/WITH CHECK(true) applies to EVERY role — combined with the
-- INSERT grant below that would let any authenticated user write a failure row
-- attributed to someone else, defeating the per-user check above.
DO $$ BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'palm_analysis_failures'
      AND policyname = 'Service role can manage palm analysis failures'
  ) THEN
    CREATE POLICY "Service role can manage palm analysis failures"
      ON public.palm_analysis_failures
      FOR ALL
      TO service_role
      USING (true)
      WITH CHECK (true);
  END IF;
END $$;

-- ── Grants ──────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT ON public.palm_analysis_failures TO authenticated;
GRANT ALL ON public.palm_analysis_failures TO service_role;

-- ── Convenience view for support / QA ───────────────────────────────────────
-- Answers "what happened on each of this user's attempts, in order".
-- security_invoker is set inline, not via a follow-up ALTER: a view created
-- without it briefly runs as its owner, which would bypass the RLS below.
CREATE OR REPLACE VIEW public.palm_failure_summary
WITH (security_invoker = true) AS
SELECT
  f.id,
  f.user_id,
  f.created_at,
  f.hand_side,
  f.attempt_number,
  f.stage,
  f.failure_code,
  f.reason,
  f.quality_score,
  f.palm_detected,
  f.suitable_for_analysis,
  f.quality_issues,
  f.device_model,
  f.platform,
  f.app_version,
  f.scan_id,
  f.image_path
FROM public.palm_analysis_failures f
ORDER BY f.created_at DESC;

GRANT SELECT ON public.palm_failure_summary TO authenticated;
GRANT SELECT ON public.palm_failure_summary TO service_role;
