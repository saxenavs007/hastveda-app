-- ============================================================
-- HastVeda — Fix service_role write privileges for palm-analysis
--
-- ROOT CAUSE
-- Migration 20260813163044 granted service_role only SELECT + INSERT on
-- public.palm_analysis. It never granted UPDATE, and it granted nothing on
-- the other tables the palm-analysis Edge Function writes to.
--
-- Consequence: the INSERT that creates the row (status='processing') succeeds,
-- but EVERY subsequent write fails with 42501 "permission denied for table".
-- The Edge Function does not check the error on those writes, so the failures
-- are silent. The row is therefore permanently stranded at
-- status='processing', error_message=NULL — for both the success path
-- (status='completed') and every failure path (status='failed').
--
-- NOTE: service_role has BYPASSRLS, but BYPASSRLS does NOT confer table
-- privileges. GRANTs are still required. This project does not have the
-- stock Supabase default privileges in place (which is why 20260813163044
-- had to be written at all).
--
-- SCOPE OF THIS MIGRATION
--   * Table-level GRANTs to service_role ONLY.
--   * No schema changes. No RLS changes. No storage policy changes.
--   * No privileges granted to anon, authenticated, or PUBLIC.
-- ============================================================

-- The missing UPDATE that strands every row at 'processing'.
GRANT UPDATE ON public.palm_analysis TO service_role;

-- Written by the Edge Function at: status->processing, quality_score,
-- status->failed, status->completed.
GRANT SELECT, INSERT, UPDATE ON public.palm_scans TO service_role;

-- Written by the Edge Function after Stage A (feature extraction).
GRANT SELECT, INSERT ON public.palm_features TO service_role;

-- Written by the Edge Function after Stage B (reading persistence).
GRANT SELECT, INSERT ON public.reading_history TO service_role;
GRANT SELECT, INSERT ON public.predictions TO service_role;
GRANT SELECT, INSERT ON public.ai_usage TO service_role;

-- ============================================================
-- Verification (informational only):
--   A. service_role UPDATE on public.palm_analysis: GRANTED  <-- the fix
--   B. service_role write on palm_scans/palm_features:        GRANTED
--   C. service_role write on reading_history/predictions/ai_usage: GRANTED
--   D. RLS status on all tables: UNCHANGED (enabled, policies intact)
--   E. anon / authenticated / PUBLIC privileges: UNCHANGED
--
-- To confirm after applying:
--   SELECT table_name, privilege_type
--     FROM information_schema.role_table_grants
--    WHERE grantee = 'service_role'
--      AND table_schema = 'public'
--      AND table_name IN ('palm_analysis','palm_scans','palm_features',
--                         'reading_history','predictions','ai_usage')
--    ORDER BY table_name, privilege_type;
-- ============================================================
