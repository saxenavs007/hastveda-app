-- ============================================================
-- HastVeda Phase 6 — Palm Analysis Schema Additions
-- Adds error_message, analysis_version, ai_provider,
-- summary_hi, overall_score, is_premium columns to palm_analysis
-- Safe incremental migration — idempotent
-- ============================================================

DO $$
BEGIN
  -- Add error_message column to palm_analysis if not present
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'error_message'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN error_message TEXT;
  END IF;

  -- Add analysis_version column if not present
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'analysis_version'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN analysis_version TEXT DEFAULT '1.0';
  END IF;

  -- Add ai_provider column if not present
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'ai_provider'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN ai_provider TEXT DEFAULT 'google';
  END IF;

  -- Add summary_hi column for bilingual history support
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'summary_hi'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN summary_hi TEXT;
  END IF;

  -- Add overall_score column for display in history
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'overall_score'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN overall_score INTEGER DEFAULT 75;
  END IF;

  -- Add is_premium column to track entitlement at time of analysis
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'palm_analysis'
      AND column_name = 'is_premium'
  ) THEN
    ALTER TABLE public.palm_analysis ADD COLUMN is_premium BOOLEAN DEFAULT false;
  END IF;
END $$;

-- ============================================================
-- RLS: palm_analysis — ensure users can only access own records
-- ============================================================

ALTER TABLE public.palm_analysis ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "palm_analysis_select_own" ON public.palm_analysis;
DROP POLICY IF EXISTS "palm_analysis_insert_own" ON public.palm_analysis;
DROP POLICY IF EXISTS "palm_analysis_update_own" ON public.palm_analysis;

CREATE POLICY "palm_analysis_select_own" ON public.palm_analysis
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "palm_analysis_insert_own" ON public.palm_analysis
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "palm_analysis_update_own" ON public.palm_analysis
  FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================
-- RLS: palm_features — ensure users can only access own records
-- ============================================================

ALTER TABLE public.palm_features ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "palm_features_select_own" ON public.palm_features;
DROP POLICY IF EXISTS "palm_features_insert_own" ON public.palm_features;

CREATE POLICY "palm_features_select_own" ON public.palm_features
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "palm_features_insert_own" ON public.palm_features
  FOR INSERT WITH CHECK (auth.uid() = user_id);

-- ============================================================
-- RLS: palm_scans — ensure users can only access own records
-- ============================================================

ALTER TABLE public.palm_scans ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "palm_scans_select_own" ON public.palm_scans;
DROP POLICY IF EXISTS "palm_scans_insert_own" ON public.palm_scans;
DROP POLICY IF EXISTS "palm_scans_update_own" ON public.palm_scans;

CREATE POLICY "palm_scans_select_own" ON public.palm_scans
  FOR SELECT USING (auth.uid() = user_id);

CREATE POLICY "palm_scans_insert_own" ON public.palm_scans
  FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "palm_scans_update_own" ON public.palm_scans
  FOR UPDATE USING (auth.uid() = user_id);

-- ============================================================
-- Storage: palm-images bucket RLS
-- ============================================================

-- Ensure users can only upload to their own path
DO $$
BEGIN
  -- Create bucket if not exists (idempotent)
  INSERT INTO storage.buckets (id, name, public)
  VALUES ('palm-images', 'palm-images', false)
  ON CONFLICT (id) DO NOTHING;
END $$;

-- Drop and recreate storage policies
DROP POLICY IF EXISTS "palm_images_user_upload" ON storage.objects;
DROP POLICY IF EXISTS "palm_images_user_read" ON storage.objects;
DROP POLICY IF EXISTS "palm_images_user_delete" ON storage.objects;

CREATE POLICY "palm_images_user_upload" ON storage.objects
  FOR INSERT WITH CHECK (
    bucket_id = 'palm-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "palm_images_user_read" ON storage.objects
  FOR SELECT USING (
    bucket_id = 'palm-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

CREATE POLICY "palm_images_user_delete" ON storage.objects
  FOR DELETE USING (
    bucket_id = 'palm-images'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );
