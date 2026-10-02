-- ============================================================
-- Grant required privileges to service_role on all tables
-- touched by create-cashfree-order Edge Function.
--
-- Root cause: PostgreSQL error 42501 (permission denied for table
-- user_profiles) was thrown because the service_role database role
-- lacked SELECT/INSERT/UPDATE on public.user_profiles.
--
-- The Edge Function correctly uses SUPABASE_SERVICE_ROLE_KEY for
-- all administrative DB operations. The missing GRANT is the sole
-- cause of the failure.
--
-- Tables touched by create-cashfree-order:
--   1. public.user_profiles       - profile lookup + self-healing INSERT
--   2. public.entitlements        - check existing Premium entitlement
--   3. public.discount_codes      - coupon validation
--   4. public.coupon_redemptions  - create pending redemption record
--   5. public.cashfree_orders     - store order record
--
-- NOTE: We do NOT weaken RLS. service_role bypasses RLS by design
-- in Supabase. These GRANTs only affect the PostgreSQL-level
-- privilege check that runs BEFORE RLS evaluation.
-- ============================================================

-- 1. user_profiles: SELECT (lookup) + INSERT (self-healing create) + UPDATE (upsert/update)
GRANT SELECT, INSERT, UPDATE ON public.user_profiles TO service_role;

-- 2. entitlements: SELECT (check existing Premium)
GRANT SELECT ON public.entitlements TO service_role;

-- 3. discount_codes: SELECT (coupon validation)
GRANT SELECT ON public.discount_codes TO service_role;

-- 4. coupon_redemptions: SELECT (per-customer limit check) + INSERT (create pending record)
GRANT SELECT, INSERT ON public.coupon_redemptions TO service_role;

-- 5. cashfree_orders: INSERT (store order record) + SELECT (for .select() after insert)
GRANT SELECT, INSERT ON public.cashfree_orders TO service_role;

-- Also grant to authenticated role for any client-side reads that go through RLS
-- (these are already likely granted but ensure completeness)
GRANT SELECT ON public.user_profiles TO authenticated;
GRANT SELECT ON public.entitlements TO authenticated;

-- Diagnostic: verify the grants were applied
DO $$
DECLARE
  v_has_select BOOLEAN;
  v_has_insert BOOLEAN;
  v_has_update BOOLEAN;
BEGIN
  -- Check service_role privileges on user_profiles
  SELECT
    bool_or(privilege_type = 'SELECT') INTO v_has_select
  FROM information_schema.role_table_grants
  WHERE grantee = 'service_role'
    AND table_schema = 'public'
    AND table_name = 'user_profiles';

  SELECT
    bool_or(privilege_type = 'INSERT') INTO v_has_insert
  FROM information_schema.role_table_grants
  WHERE grantee = 'service_role'
    AND table_schema = 'public'
    AND table_name = 'user_profiles';

  SELECT
    bool_or(privilege_type = 'UPDATE') INTO v_has_update
  FROM information_schema.role_table_grants
  WHERE grantee = 'service_role'
    AND table_schema = 'public'
    AND table_name = 'user_profiles';

  RAISE NOTICE 'service_role on public.user_profiles: SELECT=%, INSERT=%, UPDATE=%',
    COALESCE(v_has_select, false),
    COALESCE(v_has_insert, false),
    COALESCE(v_has_update, false);

  IF NOT COALESCE(v_has_select, false) OR NOT COALESCE(v_has_insert, false) OR NOT COALESCE(v_has_update, false) THEN
    RAISE WARNING 'One or more required privileges on user_profiles are still missing for service_role!';
  ELSE
    RAISE NOTICE 'GRANT VERIFY OK: service_role has all required privileges on public.user_profiles';
  END IF;
END;
$$;
