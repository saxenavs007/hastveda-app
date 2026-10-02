-- ============================================================
-- CASHFREE HELPER FUNCTIONS
-- ============================================================

-- Atomic increment of coupon used_count
CREATE OR REPLACE FUNCTION public.increment_coupon_used_count(p_coupon_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.discount_codes
  SET used_count = used_count + 1,
      updated_at = NOW()
  WHERE id = p_coupon_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.increment_coupon_used_count(UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.increment_coupon_used_count(UUID) TO authenticated;

-- Ensure entitlements table has unique constraint on user_id + entitlement_type
-- (needed for upsert idempotency in edge functions)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'entitlements_user_id_entitlement_type_key'
      AND conrelid = 'public.entitlements'::regclass
  ) THEN
    ALTER TABLE public.entitlements
      ADD CONSTRAINT entitlements_user_id_entitlement_type_key
      UNIQUE (user_id, entitlement_type);
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Constraint may already exist: %', SQLERRM;
END $$;
