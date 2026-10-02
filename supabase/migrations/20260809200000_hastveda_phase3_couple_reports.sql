-- ============================================================
-- HASTVEDA PHASE 3 — INCREMENTAL MIGRATION
-- Couple Readings + Detailed Reports schema additions
-- Safe to apply on existing deployed schema
-- ============================================================

-- NOTE: This migration is INCREMENTAL.
-- It does NOT drop or recreate existing tables.
-- It only adds new columns and policies where missing.

-- ============================================================
-- 1. ENHANCE couple_readings TABLE
-- ============================================================

-- Add missing columns to couple_readings if they don't exist
DO $$
BEGIN
  -- Add person1_user_id (the initiating user)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'person1_user_id'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN person1_user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;
  END IF;

  -- Add person2_user_id (the partner user, optional — may be NULL if partner is not a registered user)
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'person2_user_id'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN person2_user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'person1_name'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN person1_name TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'person2_name'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN person2_name TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'overall_compatibility_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN overall_compatibility_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'love_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN love_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'emotional_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN emotional_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'communication_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN communication_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'financial_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN financial_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'career_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN career_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'personality_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN personality_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'attraction_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN attraction_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'marriage_score'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN marriage_score INTEGER;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'compatibility_data'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN compatibility_data JSONB DEFAULT '{}'::jsonb;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'language'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN language TEXT DEFAULT 'en';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'couple_readings'
      AND column_name = 'status'
  ) THEN
    ALTER TABLE public.couple_readings ADD COLUMN status TEXT DEFAULT 'completed';
  END IF;
END $$;

-- ============================================================
-- 2. ENHANCE reports TABLE
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'report_type_text'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN report_type_text TEXT DEFAULT 'detailed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'language'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN language TEXT DEFAULT 'en';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'report_status'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN report_status TEXT DEFAULT 'completed';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'sections_data'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN sections_data JSONB DEFAULT '{}'::jsonb;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'export_url'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN export_url TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'ai_model'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN ai_model TEXT;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'reports'
      AND column_name = 'analysis_version'
  ) THEN
    ALTER TABLE public.reports ADD COLUMN analysis_version TEXT DEFAULT '1.0';
  END IF;
END $$;

-- ============================================================
-- 3. RLS POLICIES — couple_readings
-- ============================================================

-- Enable RLS if not already enabled
ALTER TABLE public.couple_readings ENABLE ROW LEVEL SECURITY;

-- Drop existing policies to recreate safely
DROP POLICY IF EXISTS "couple_readings_select_own" ON public.couple_readings;
DROP POLICY IF EXISTS "couple_readings_insert_own" ON public.couple_readings;
DROP POLICY IF EXISTS "couple_readings_update_own" ON public.couple_readings;
DROP POLICY IF EXISTS "couple_readings_delete_own" ON public.couple_readings;
DROP POLICY IF EXISTS "users_manage_own_couple_readings" ON public.couple_readings;

-- Users can only see their own couple readings
-- (as the initiating user via user_id, or as person1 or person2)
CREATE POLICY "couple_readings_select_own"
  ON public.couple_readings
  FOR SELECT
  TO authenticated
  USING (
    auth.uid() = user_id
    OR auth.uid() = person1_user_id
    OR auth.uid() = person2_user_id
  );

-- Users CANNOT insert couple readings directly (backend only)
-- INSERT is blocked for authenticated users — service_role only

-- Users CANNOT update couple readings (backend only)
-- UPDATE is blocked for authenticated users — service_role only

-- Users CANNOT delete couple readings
-- DELETE is blocked for authenticated users — service_role only

-- ============================================================
-- 4. RLS POLICIES — reports
-- ============================================================

ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reports_select_own" ON public.reports;
DROP POLICY IF EXISTS "reports_insert_own" ON public.reports;
DROP POLICY IF EXISTS "reports_update_own" ON public.reports;
DROP POLICY IF EXISTS "users_manage_own_reports" ON public.reports;

-- Users can only read their own reports
CREATE POLICY "reports_select_own"
  ON public.reports
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- Reports are created by backend (service_role) only
-- No INSERT policy for authenticated users

-- ============================================================
-- 5. SECURITY: Verify entitlement functions remain locked
-- ============================================================

-- These functions must remain service_role only (from Phase 2 migration)
-- Verify grant_entitlement is not accessible to authenticated users
DO $$
BEGIN
  -- Revoke from authenticated if somehow re-granted
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.grant_entitlement(UUID, TEXT, INTERVAL) FROM authenticated';
  EXECUTE 'REVOKE EXECUTE ON FUNCTION public.grant_entitlement(UUID, TEXT, INTERVAL) FROM anon';
EXCEPTION
  WHEN undefined_function THEN
    NULL; -- Function may not exist yet, skip
  WHEN insufficient_privilege THEN
    NULL; -- Already revoked
END $$;

-- ============================================================
-- 6. INDEXES for performance
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_couple_readings_person1
  ON public.couple_readings(person1_user_id);

CREATE INDEX IF NOT EXISTS idx_couple_readings_person2
  ON public.couple_readings(person2_user_id);

CREATE INDEX IF NOT EXISTS idx_reports_user_id_phase3
  ON public.reports(user_id);

CREATE INDEX IF NOT EXISTS idx_reports_created_at
  ON public.reports(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_couple_readings_created_at
  ON public.couple_readings(created_at DESC);

-- ============================================================
-- MIGRATION COMPLETE
-- ============================================================
-- Summary of changes:
-- 1. Added person1_user_id and person2_user_id columns to couple_readings
-- 2. Added compatibility score columns to couple_readings
-- 3. Added report metadata columns to reports
-- 4. Enforced RLS: users see only their own couple readings and reports
-- 5. Couple readings INSERT/UPDATE/DELETE blocked for client (service_role only)
-- 6. Reports INSERT/UPDATE blocked for client (service_role only)
-- 7. Added performance indexes
-- 8. No existing data modified or deleted
-- 9. No existing tables dropped or recreated
-- ============================================================
