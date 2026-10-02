-- ============================================================
-- Fix: Grant SELECT, INSERT on public.palm_analysis to service_role
-- Root cause: palm-analysis Edge Function uses serviceClient
-- (service_role key) but service_role lacked table privileges.
-- RLS remains enabled and unchanged.
-- anon/public roles are NOT granted any privileges.
-- ============================================================

-- Grant minimum required privileges to service_role only
GRANT SELECT, INSERT ON public.palm_analysis TO service_role;

-- ============================================================
-- Verification comments (informational only):
-- A. service_role SELECT on public.palm_analysis: GRANTED
-- B. service_role INSERT on public.palm_analysis: GRANTED
-- C. RLS status: UNCHANGED (enabled, policies intact)
-- D. anon/public privileges: UNCHANGED (no grant made)
-- ============================================================
