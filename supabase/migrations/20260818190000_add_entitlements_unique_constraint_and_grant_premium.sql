-- ============================================================
-- Migration: Add UNIQUE constraint on entitlements(user_id, entitlement_type)
-- and grant PREMIUM entitlement for the verified ₹199 payment
-- Timestamp: 20260818190000
-- ============================================================

-- STEP 1: Add the missing UNIQUE constraint
-- This is required for the verify-cashfree-payment upsert onConflict clause to work.
-- The constraint name must exactly match: entitlements_user_id_entitlement_type_key
-- Pre-check: all 22 existing rows have entitlement_type = 'FREE' (one per user),
-- so no duplicate (user_id, entitlement_type) pairs exist — constraint will apply cleanly.

ALTER TABLE public.entitlements
  ADD CONSTRAINT entitlements_user_id_entitlement_type_key
  UNIQUE (user_id, entitlement_type);

-- Verify the constraint was created
DO $$
BEGIN
  IF EXISTS (
    SELECT 1
    FROM information_schema.table_constraints
    WHERE constraint_schema = 'public'
      AND table_name = 'entitlements'
      AND constraint_name = 'entitlements_user_id_entitlement_type_key'
      AND constraint_type = 'UNIQUE'
  ) THEN
    RAISE NOTICE 'CONSTRAINT VERIFY OK: entitlements_user_id_entitlement_type_key exists';
  ELSE
    RAISE EXCEPTION 'CONSTRAINT VERIFY FAILED: entitlements_user_id_entitlement_type_key NOT found';
  END IF;
END $$;

-- ============================================================
-- STEP 2: Grant PREMIUM entitlement for user saxenavs007@gmail.com
-- Looked up by email to avoid hardcoding a potentially malformed UUID literal.
-- This re-processes the existing verified ₹199 Cashfree payment directly in the DB.
-- The Cashfree sandbox confirmed PAID status; the upsert previously failed only
-- because the UNIQUE constraint was missing (error 42P10).
-- ============================================================

DO $$
DECLARE
  v_user_id UUID;
  v_order_cashfree_id TEXT;
  v_order_uuid UUID;
BEGIN
  -- Look up user by email from auth.users to get the correct UUID
  SELECT id INTO v_user_id
    FROM auth.users
   WHERE email = 'saxenavs007@gmail.com'
   LIMIT 1;

  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'User saxenavs007@gmail.com not found in auth.users';
  END IF;

  RAISE NOTICE 'Resolved user_id=% for saxenavs007@gmail.com', v_user_id;

  -- Verify user exists in user_profiles
  IF NOT EXISTS (
    SELECT 1 FROM public.user_profiles WHERE id = v_user_id
  ) THEN
    RAISE EXCEPTION 'User % not found in user_profiles', v_user_id;
  END IF;

  -- Find the most recent cashfree order for this user
  SELECT cashfree_order_id, id
    INTO v_order_cashfree_id, v_order_uuid
    FROM public.cashfree_orders
   WHERE user_id = v_user_id
   ORDER BY created_at DESC
   LIMIT 1;

  IF v_order_uuid IS NULL THEN
    RAISE EXCEPTION 'No cashfree_orders found for user %', v_user_id;
  END IF;

  RAISE NOTICE 'Processing order: cashfree_order_id=%, internal_id=%', v_order_cashfree_id, v_order_uuid;

  -- Update cashfree_orders status to payment_successful
  UPDATE public.cashfree_orders
     SET status = 'payment_successful',
         paid_at = COALESCE(paid_at, now()),
         updated_at = now()
   WHERE id = v_order_uuid
     AND user_id = v_user_id;

  RAISE NOTICE 'cashfree_orders updated to payment_successful for order %', v_order_cashfree_id;

  -- Upsert PREMIUM entitlement (now safe because UNIQUE constraint exists)
  INSERT INTO public.entitlements (
    user_id,
    entitlement_type,
    is_active,
    granted_at,
    expires_at,
    metadata
  )
  VALUES (
    v_user_id,
    'PREMIUM',
    true,
    now(),
    NULL,
    jsonb_build_object(
      'source', 'cashfree_payment',
      'cashfree_order_id', v_order_cashfree_id,
      'granted_by', 'migration_20260818190000',
      'reason', 'direct_db_grant_after_42P10_fix'
    )
  )
  ON CONFLICT ON CONSTRAINT entitlements_user_id_entitlement_type_key
  DO UPDATE SET
    is_active = true,
    granted_at = now(),
    expires_at = NULL,
    metadata = jsonb_build_object(
      'source', 'cashfree_payment',
      'cashfree_order_id', v_order_cashfree_id,
      'granted_by', 'migration_20260818190000',
      'reason', 'direct_db_grant_after_42P10_fix'
    ),
    updated_at = now();

  RAISE NOTICE 'PREMIUM entitlement upserted for user %', v_user_id;

  -- Update user_profiles tier to premium
  UPDATE public.user_profiles
     SET tier = 'premium',
         updated_at = now()
   WHERE id = v_user_id;

  RAISE NOTICE 'user_profiles.tier set to premium for user %', v_user_id;

  -- Final verification
  IF EXISTS (
    SELECT 1 FROM public.entitlements
     WHERE user_id = v_user_id
       AND entitlement_type = 'PREMIUM'
       AND is_active = true
  ) THEN
    RAISE NOTICE 'GRANT VERIFY OK: PREMIUM entitlement is_active=true confirmed for user %', v_user_id;
  ELSE
    RAISE EXCEPTION 'GRANT VERIFY FAILED: PREMIUM entitlement NOT found for user %', v_user_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.cashfree_orders
     WHERE id = v_order_uuid
       AND status = 'payment_successful'
  ) THEN
    RAISE NOTICE 'ORDER VERIFY OK: cashfree_orders.status=payment_successful confirmed for order %', v_order_cashfree_id;
  ELSE
    RAISE EXCEPTION 'ORDER VERIFY FAILED: cashfree_orders status NOT payment_successful for order %', v_order_cashfree_id;
  END IF;

  IF EXISTS (
    SELECT 1 FROM public.user_profiles
     WHERE id = v_user_id
       AND tier = 'premium'
  ) THEN
    RAISE NOTICE 'PROFILE VERIFY OK: user_profiles.tier=premium confirmed for user %', v_user_id;
  ELSE
    RAISE NOTICE 'PROFILE VERIFY WARNING: user_profiles.tier not premium for user % (non-fatal)', v_user_id;
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    RAISE EXCEPTION 'Migration failed: % (SQLSTATE: %)', SQLERRM, SQLSTATE;
END $$;
