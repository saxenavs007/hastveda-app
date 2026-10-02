-- ============================================================
-- HastVeda — Add daily_insight columns to palm_analysis
-- Stores the personalized Today's Insight directly on the
-- analysis record so it can be retrieved from reading history
-- without joining the predictions table.
-- Safe incremental migration — idempotent
-- ============================================================

DO $$
BEGIN
  -- Add daily_insight_en column if not present
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'daily_insight_en'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN daily_insight_en TEXT;
  END IF;

  -- Add daily_insight_hi column if not present
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'daily_insight_hi'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN daily_insight_hi TEXT;
  END IF;

  -- Add hand_side column if not present (mirrors palm_scans.hand_type for convenience)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'hand_side'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN hand_side TEXT DEFAULT 'right';
  END IF;
END $$;

-- Grant service role write access to the new columns
-- (the existing RLS policies already cover authenticated users)
GRANT UPDATE (daily_insight_en, daily_insight_hi, hand_side)
  ON public.palm_analysis TO service_role;
