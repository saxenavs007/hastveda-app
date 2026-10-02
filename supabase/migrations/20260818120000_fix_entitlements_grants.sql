-- ============================================================
-- Fix: Grant INSERT, UPDATE, DELETE on entitlements to service_role
-- and SELECT to authenticated role.
--
-- Root cause analysis:
--
-- 1. verify-cashfree-payment upserts into public.entitlements using the
--    service_role client. Migration 20260818060000 only granted SELECT on
--    entitlements to service_role — INSERT and UPDATE were missing.
--    The upsert silently failed (error logged, but function still returned
--    success:true), so the PREMIUM entitlement was never written.
--
-- 2. The authenticated role had no table-level SELECT grant on entitlements.
--    RLS policy "users_read_own_entitlements" exists, but PostgreSQL evaluates
--    table-level privileges BEFORE RLS. Without the GRANT, getUserEntitlements()
--    in the Flutter app returns an empty list even when a row exists.
--
-- 3. cashfree-webhook also upserts into entitlements — same missing grants.
--
-- Fix: Grant the minimum required privileges.
-- RLS is NOT weakened — service_role bypasses RLS by design.
-- ============================================================

-- service_role: full access needed for Edge Function upserts
GRANT SELECT, INSERT, UPDATE, DELETE ON public.entitlements TO service_role;

-- authenticated: SELECT only (writes are server-side only)
GRANT SELECT ON public.entitlements TO authenticated;

-- Also ensure UPDATE is granted on cashfree_orders for verify-cashfree-payment
-- (it updates status to payment_successful)
GRANT UPDATE ON public.cashfree_orders TO service_role;

-- Also ensure UPDATE is granted on coupon_redemptions
GRANT UPDATE ON public.coupon_redemptions TO service_role;

-- Diagnostic verification
DO $$
DECLARE
  v_sr_select  BOOLEAN;
  v_sr_insert  BOOLEAN;
  v_sr_update  BOOLEAN;
  v_auth_select BOOLEAN;
BEGIN
  SELECT bool_or(privilege_type = 'SELECT') INTO v_sr_select
  FROM information_schema.role_table_grants
  WHERE grantee = 'service_role' AND table_schema = 'public' AND table_name = 'entitlements';

  SELECT bool_or(privilege_type = 'INSERT') INTO v_sr_insert
  FROM information_schema.role_table_grants
  WHERE grantee = 'service_role' AND table_schema = 'public' AND table_name = 'entitlements';

  SELECT bool_or(privilege_type = 'UPDATE') INTO v_sr_update
  FROM information_schema.role_table_grants
  WHERE grantee = 'service_role' AND table_schema = 'public' AND table_name = 'entitlements';

  SELECT bool_or(privilege_type = 'SELECT') INTO v_auth_select
  FROM information_schema.role_table_grants
  WHERE grantee = 'authenticated' AND table_schema = 'public' AND table_name = 'entitlements';

  RAISE NOTICE 'service_role on public.entitlements: SELECT=%, INSERT=%, UPDATE=%',
    COALESCE(v_sr_select, false),
    COALESCE(v_sr_insert, false),
    COALESCE(v_sr_update, false);

  RAISE NOTICE 'authenticated on public.entitlements: SELECT=%',
    COALESCE(v_auth_select, false);

  IF NOT COALESCE(v_sr_insert, false) OR NOT COALESCE(v_sr_update, false) THEN
    RAISE WARNING 'CRITICAL: service_role still missing INSERT or UPDATE on entitlements — upsert will fail!';
  ELSE
    RAISE NOTICE 'GRANT VERIFY OK: service_role has SELECT/INSERT/UPDATE on public.entitlements';
  END IF;

  IF NOT COALESCE(v_auth_select, false) THEN
    RAISE WARNING 'authenticated role missing SELECT on entitlements — Flutter getUserEntitlements() will return empty!';
  ELSE
    RAISE NOTICE 'GRANT VERIFY OK: authenticated has SELECT on public.entitlements';
  END IF;
END;
$$;
