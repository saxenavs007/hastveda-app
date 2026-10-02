-- ============================================================
-- HastVeda — QA / testing bypass of the free-tier scan quota
--
-- WHY THIS EXISTS
-- ----------------
-- During the current QA cycle the 2-scans-per-month limit forces testers to
-- create disposable accounts to exercise the palm-analysis flow, which
-- clutters the test environment and makes bugs harder to reproduce.
--
-- The palm-analysis Edge Function reads
--   public.app_settings.value->'scans_per_month'   (key = 'free_tier_limits')
-- on every invocation, so raising that value here lifts the server-side
-- 403 FREE_LIMIT_REACHED without a function redeploy.
--
-- Paired with `QaConfig.bypassFreeScanQuota = true` in
--   lib/services/qa_config.dart
-- which silences the matching client-side pre-check in
--   EntitlementService.checkFreeTierLimit('scans_per_month').
--
-- SCOPE
--   * Data-only UPDATE against a single app_settings row.
--   * No schema, RLS, grants, or function changes.
-- ============================================================

UPDATE public.app_settings
   SET value = jsonb_set(
                 COALESCE(value, '{}'::jsonb),
                 '{scans_per_month}',
                 '99999'::jsonb,
                 true
               ),
       updated_at = NOW()
 WHERE key = 'free_tier_limits';

-- ============================================================
-- Verification
--   SELECT key, value->'scans_per_month' AS scans_per_month
--     FROM public.app_settings
--    WHERE key = 'free_tier_limits';
--
-- Expected: scans_per_month = 99999
-- ============================================================

-- ============================================================
-- ROLLBACK — restore the production 2-scans-per-month limit
--
-- Run this SQL when the QA cycle ends (and flip
-- `QaConfig.bypassFreeScanQuota` back to `false`):
--
--   UPDATE public.app_settings
--      SET value = jsonb_set(
--                    COALESCE(value, '{}'::jsonb),
--                    '{scans_per_month}',
--                    '2'::jsonb,
--                    true
--                  ),
--          updated_at = NOW()
--    WHERE key = 'free_tier_limits';
-- ============================================================
