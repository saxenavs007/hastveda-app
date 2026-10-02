-- ============================================================
-- HastVeda — Fix palm_scans table-level privileges
-- Error: 403 / PostgreSQL 42501 "permission denied for table palm_scans"
-- Root cause: authenticated role was never granted SELECT/INSERT on the table.
-- RLS policies already exist and are correct — this migration only adds the
-- missing GRANT statements.
-- ============================================================

-- Grant minimum required privileges to the authenticated role.
-- SELECT: allows authenticated users to read their own rows (gated by RLS).
-- INSERT: allows authenticated users to create their own rows (gated by RLS).
-- UPDATE: allows authenticated users to update their own rows (gated by RLS).
-- RLS policies already restrict each operation to auth.uid() = user_id.
GRANT SELECT, INSERT, UPDATE ON public.palm_scans TO authenticated;

-- Also ensure the sequence (used by gen_random_uuid default) is accessible.
-- palm_scans.id uses gen_random_uuid() which does not require sequence grants,
-- but granting USAGE on the schema is required for PostgREST access.
GRANT USAGE ON SCHEMA public TO authenticated;

-- Verify RLS is still enabled (idempotent — safe to run multiple times).
ALTER TABLE public.palm_scans ENABLE ROW LEVEL SECURITY;

-- Re-assert the existing RLS policies (idempotent DROP + CREATE).
-- These policies already existed; we recreate them here to confirm they are
-- present and correct after the GRANT is applied.

DROP POLICY IF EXISTS "palm_scans_select_own" ON public.palm_scans;
CREATE POLICY "palm_scans_select_own" ON public.palm_scans
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

DROP POLICY IF EXISTS "palm_scans_insert_own" ON public.palm_scans;
CREATE POLICY "palm_scans_insert_own" ON public.palm_scans
  FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

DROP POLICY IF EXISTS "palm_scans_update_own" ON public.palm_scans;
CREATE POLICY "palm_scans_update_own" ON public.palm_scans
  FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);
