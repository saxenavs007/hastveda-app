-- ============================================================
-- HastVeda Phase 2 — Security Hardening Migration
-- INCREMENTAL — Safe to apply on top of existing schema
-- Does NOT drop tables, does NOT delete data
-- ============================================================
-- 
-- SECURITY WEAKNESSES FOUND IN PHASE 1:
-- 1. subscriptions: FOR ALL policy → users could INSERT/UPDATE/DELETE their own subscription
-- 2. purchases: FOR ALL policy → users could INSERT/UPDATE purchase tokens, order IDs, verification data
-- 3. palm_features: FOR ALL policy → users could write AI-extracted feature data
-- 4. palm_analysis: FOR ALL policy → users could write AI analysis, confidence scores, model info
-- 5. palm_profiles: FOR ALL policy → users could write aggregated AI profile data
-- 6. reports: FOR ALL policy → users could create/modify backend-generated reports
-- 7. couple_readings: FOR ALL policy → users could create couple readings without backend verification
-- 8. notifications: FOR ALL policy → users could INSERT notifications to themselves
-- 9. grant_entitlement(), revoke_entitlement(), expire_entitlements(): callable by any authenticated user
-- 10. user_profiles: tier field writable by client → user could set tier='premium' directly
-- ============================================================

-- ============================================================
-- SECTION 1: LOCK DOWN ENTITLEMENT MUTATION FUNCTIONS
-- Restrict grant_entitlement, revoke_entitlement, expire_entitlements
-- to service_role ONLY — authenticated users cannot call them
-- ============================================================

-- Revoke EXECUTE from authenticated/public on entitlement mutation functions
REVOKE EXECUTE ON FUNCTION public.grant_entitlement(UUID, public.entitlement_type, TIMESTAMPTZ, UUID, UUID) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.grant_entitlement(UUID, public.entitlement_type, TIMESTAMPTZ, UUID, UUID) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.grant_entitlement(UUID, public.entitlement_type, TIMESTAMPTZ, UUID, UUID) FROM anon;

REVOKE EXECUTE ON FUNCTION public.revoke_entitlement(UUID, public.entitlement_type) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.revoke_entitlement(UUID, public.entitlement_type) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.revoke_entitlement(UUID, public.entitlement_type) FROM anon;

REVOKE EXECUTE ON FUNCTION public.expire_entitlements() FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.expire_entitlements() FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.expire_entitlements() FROM anon;

-- Grant EXECUTE only to service_role (backend/Edge Functions)
GRANT EXECUTE ON FUNCTION public.grant_entitlement(UUID, public.entitlement_type, TIMESTAMPTZ, UUID, UUID) TO service_role;
GRANT EXECUTE ON FUNCTION public.revoke_entitlement(UUID, public.entitlement_type) TO service_role;
GRANT EXECUTE ON FUNCTION public.expire_entitlements() TO service_role;

-- Keep read-only entitlement functions accessible to authenticated users
GRANT EXECUTE ON FUNCTION public.has_entitlement(UUID, public.entitlement_type) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_user_entitlements(UUID) TO authenticated;

-- ============================================================
-- SECTION 2: HARDEN user_profiles
-- Users can read/update their own profile BUT cannot change tier
-- Tier changes are backend-only (done by grant_entitlement/revoke_entitlement)
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_user_profiles" ON public.user_profiles;

-- SELECT: users can read their own profile
CREATE POLICY "users_read_own_user_profiles"
ON public.user_profiles FOR SELECT TO authenticated
USING (id = auth.uid());

-- UPDATE: users can update their own profile but NOT the tier field
-- We use a trigger to enforce this
CREATE POLICY "users_update_own_user_profiles"
ON public.user_profiles FOR UPDATE TO authenticated
USING (id = auth.uid())
WITH CHECK (id = auth.uid());

-- Trigger to prevent client from changing tier directly
CREATE OR REPLACE FUNCTION public.prevent_tier_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- If tier is being changed and caller is not service_role, block it
  IF NEW.tier IS DISTINCT FROM OLD.tier THEN
    IF current_setting('role') != 'service_role' THEN
      RAISE EXCEPTION 'Tier changes are not permitted from the client. Use the backend entitlement system.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_tier_change_trigger ON public.user_profiles;
CREATE TRIGGER prevent_tier_change_trigger
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.prevent_tier_change();

-- ============================================================
-- SECTION 3: HARDEN subscriptions
-- Users can READ their own subscription only
-- All mutations (INSERT, UPDATE, DELETE) are backend-only
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_subscriptions" ON public.subscriptions;

CREATE POLICY "users_read_own_subscriptions"
ON public.subscriptions FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 4: HARDEN purchases
-- Users can READ their own purchases only
-- Users can INSERT a pending purchase record (to initiate flow)
-- Users CANNOT update authoritative fields (token, order_id, verification_data, status, etc.)
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_purchases" ON public.purchases;

-- SELECT: read own purchases
CREATE POLICY "users_read_own_purchases"
ON public.purchases FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- INSERT: users can create a pending purchase record to initiate Google Play flow
-- They can only set product_id and purchase_type — status defaults to 'pending'
CREATE POLICY "users_insert_pending_purchases"
ON public.purchases FOR INSERT TO authenticated
WITH CHECK (
  user_id = auth.uid()
  AND status = 'pending'
  AND purchase_token IS NULL
  AND order_id IS NULL
  AND acknowledged_at IS NULL
  AND consumed_at IS NULL
  AND refunded_at IS NULL
);

-- No UPDATE or DELETE policy for users — backend only

-- ============================================================
-- SECTION 5: HARDEN palm_features
-- Users can READ their own palm features only
-- AI/backend controls all writes
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_palm_features" ON public.palm_features;

CREATE POLICY "users_read_own_palm_features"
ON public.palm_features FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 6: HARDEN palm_analysis
-- Users can READ their own analysis only
-- AI/backend controls all writes (model, confidence, interpretation)
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_palm_analysis" ON public.palm_analysis;

CREATE POLICY "users_read_own_palm_analysis"
ON public.palm_analysis FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 7: HARDEN palm_profiles
-- Users can READ their own palm profile only
-- Backend/AI controls aggregated profile creation
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_palm_profiles" ON public.palm_profiles;

CREATE POLICY "users_read_own_palm_profiles"
ON public.palm_profiles FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 8: HARDEN predictions
-- Users can READ their own predictions only
-- AI/backend generates and modifies predictions
-- Remove the INSERT policy that allowed client to create predictions
-- ============================================================

DROP POLICY IF EXISTS "users_read_own_predictions" ON public.predictions;
DROP POLICY IF EXISTS "users_insert_own_predictions" ON public.predictions;

CREATE POLICY "users_read_own_predictions"
ON public.predictions FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 9: HARDEN reports
-- Users can READ their own reports only
-- Backend controls report generation
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_reports" ON public.reports;

CREATE POLICY "users_read_own_reports"
ON public.reports FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 10: HARDEN couple_readings
-- Users can READ their own couple readings only
-- Backend controls creation and modification
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_couple_readings" ON public.couple_readings;

CREATE POLICY "users_read_own_couple_readings"
ON public.couple_readings FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- SECTION 11: HARDEN notifications
-- Users can READ their own notifications
-- Users can UPDATE is_read (mark as read) — but NOT insert/delete
-- Backend controls notification creation
-- ============================================================

DROP POLICY IF EXISTS "users_manage_own_notifications" ON public.notifications;

CREATE POLICY "users_read_own_notifications"
ON public.notifications FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- Users can mark notifications as read (UPDATE is_read only)
CREATE POLICY "users_mark_notifications_read"
ON public.notifications FOR UPDATE TO authenticated
USING (user_id = auth.uid())
WITH CHECK (user_id = auth.uid());

-- Trigger to prevent users from changing anything except is_read
CREATE OR REPLACE FUNCTION public.prevent_notification_tampering()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  -- Only allow is_read to change; block all other field changes from client
  IF current_setting('role') != 'service_role' THEN
    IF NEW.title IS DISTINCT FROM OLD.title
      OR NEW.body IS DISTINCT FROM OLD.body
      OR NEW.notification_type IS DISTINCT FROM OLD.notification_type
      OR NEW.user_id IS DISTINCT FROM OLD.user_id
    THEN
      RAISE EXCEPTION 'Notification content cannot be modified by the client.';
    END IF;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS prevent_notification_tampering_trigger ON public.notifications;
CREATE TRIGGER prevent_notification_tampering_trigger
  BEFORE UPDATE ON public.notifications
  FOR EACH ROW EXECUTE FUNCTION public.prevent_notification_tampering();

-- ============================================================
-- SECTION 12: HARDEN ai_usage
-- Users can READ their own AI usage
-- Users can INSERT (to track usage) but NOT update/delete
-- ============================================================

-- Existing policies are already correct (read + insert only) — no change needed

-- ============================================================
-- SECTION 13: STORAGE HARDENING
-- Verify palm-images bucket is private (already set in Phase 1)
-- Add UPDATE policy restriction — users cannot rename/move others' files
-- ============================================================

-- Ensure bucket remains private
UPDATE storage.buckets
SET public = false
WHERE id = 'palm-images';

-- Add UPDATE restriction for storage objects (prevent rename attacks)
DROP POLICY IF EXISTS "users_update_own_palm_images" ON storage.objects;
CREATE POLICY "users_update_own_palm_images"
ON storage.objects FOR UPDATE TO authenticated
USING (
  bucket_id = 'palm-images'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
)
WITH CHECK (
  bucket_id = 'palm-images'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

-- ============================================================
-- SECTION 14: SECURE PURCHASE VERIFICATION FUNCTION
-- Backend-only function to update purchase with verified data
-- Cannot be called by authenticated client
-- ============================================================

CREATE OR REPLACE FUNCTION public.verify_and_complete_purchase(
  p_purchase_id UUID,
  p_user_id UUID,
  p_purchase_token TEXT,
  p_order_id TEXT,
  p_verification_data JSONB,
  p_amount_micros BIGINT DEFAULT NULL,
  p_currency_code TEXT DEFAULT 'INR'
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.purchases
  SET
    purchase_token = p_purchase_token,
    order_id = p_order_id,
    verification_data = p_verification_data,
    status = 'completed'::public.purchase_status,
    amount_micros = COALESCE(p_amount_micros, amount_micros),
    currency_code = COALESCE(p_currency_code, currency_code),
    purchase_time = NOW(),
    acknowledged_at = NOW(),
    updated_at = NOW()
  WHERE id = p_purchase_id
    AND user_id = p_user_id
    AND status = 'pending';

  RETURN FOUND;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.verify_and_complete_purchase(UUID, UUID, TEXT, TEXT, JSONB, BIGINT, TEXT) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.verify_and_complete_purchase(UUID, UUID, TEXT, TEXT, JSONB, BIGINT, TEXT) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.verify_and_complete_purchase(UUID, UUID, TEXT, TEXT, JSONB, BIGINT, TEXT) FROM anon;
GRANT EXECUTE ON FUNCTION public.verify_and_complete_purchase(UUID, UUID, TEXT, TEXT, JSONB, BIGINT, TEXT) TO service_role;

-- ============================================================
-- SECTION 15: SECURE SUBSCRIPTION MANAGEMENT FUNCTION
-- Backend-only function to create/update subscriptions
-- ============================================================

CREATE OR REPLACE FUNCTION public.upsert_subscription(
  p_user_id UUID,
  p_product_id TEXT,
  p_status public.subscription_status,
  p_purchase_token TEXT,
  p_order_id TEXT,
  p_started_at TIMESTAMPTZ DEFAULT NOW(),
  p_expires_at TIMESTAMPTZ DEFAULT NULL,
  p_auto_renewing BOOLEAN DEFAULT true
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_subscription_id UUID;
BEGIN
  INSERT INTO public.subscriptions (
    user_id, product_id, status, purchase_token, order_id,
    started_at, expires_at, auto_renewing
  )
  VALUES (
    p_user_id, p_product_id, p_status, p_purchase_token, p_order_id,
    p_started_at, p_expires_at, p_auto_renewing
  )
  ON CONFLICT (user_id, product_id) DO UPDATE SET
    status = EXCLUDED.status,
    purchase_token = EXCLUDED.purchase_token,
    order_id = EXCLUDED.order_id,
    started_at = COALESCE(EXCLUDED.started_at, subscriptions.started_at),
    expires_at = EXCLUDED.expires_at,
    auto_renewing = EXCLUDED.auto_renewing,
    updated_at = NOW()
  RETURNING id INTO v_subscription_id;

  RETURN v_subscription_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_subscription(UUID, TEXT, public.subscription_status, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION public.upsert_subscription(UUID, TEXT, public.subscription_status, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) FROM authenticated;
REVOKE EXECUTE ON FUNCTION public.upsert_subscription(UUID, TEXT, public.subscription_status, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) FROM anon;
GRANT EXECUTE ON FUNCTION public.upsert_subscription(UUID, TEXT, public.subscription_status, TEXT, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, BOOLEAN) TO service_role;

-- Add unique constraint for upsert to work (if not already present)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'subscriptions_user_product_unique'
  ) THEN
    ALTER TABLE public.subscriptions
    ADD CONSTRAINT subscriptions_user_product_unique UNIQUE (user_id, product_id);
  END IF;
END;
$$;

-- ============================================================
-- SECTION 16: CANUSE FEATURE FUNCTION (read-only, client-safe)
-- Centralized feature access check callable by authenticated users
-- ============================================================

CREATE OR REPLACE FUNCTION public.can_use_feature(p_feature TEXT)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_has_premium BOOLEAN;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN FALSE;
  END IF;

  -- Check premium first
  SELECT public.has_entitlement(v_user_id, 'PREMIUM'::public.entitlement_type)
  INTO v_has_premium;

  -- Premium users can use all features
  IF v_has_premium THEN
    RETURN TRUE;
  END IF;

  -- Feature-specific checks for one-time purchases
  CASE p_feature
    WHEN 'complete_reading' THEN
      RETURN public.has_entitlement(v_user_id, 'COMPLETE_READING'::public.entitlement_type);
    WHEN 'couple_reading' THEN
      RETURN public.has_entitlement(v_user_id, 'COUPLE_READING'::public.entitlement_type);
    WHEN 'detailed_report' THEN
      RETURN public.has_entitlement(v_user_id, 'DETAILED_REPORT'::public.entitlement_type);
    -- Free features
    WHEN 'basic_scan', 'basic_analysis', 'basic_predictions', 'basic_personality',
         'basic_life_line', 'basic_relationship', 'basic_career', 'basic_wealth' THEN
      RETURN TRUE;
    ELSE
      RETURN FALSE;
  END CASE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_use_feature(TEXT) TO authenticated;

-- ============================================================
-- SECTION 17: FREE TIER LIMIT CHECK FUNCTION
-- Checks if user has exceeded free tier limits
-- ============================================================

CREATE OR REPLACE FUNCTION public.check_free_tier_limit(p_limit_type TEXT)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
AS $$
DECLARE
  v_user_id UUID := auth.uid();
  v_has_premium BOOLEAN;
  v_limit_config JSONB;
  v_current_count INTEGER;
  v_limit INTEGER;
BEGIN
  IF v_user_id IS NULL THEN
    RETURN jsonb_build_object('allowed', false, 'reason', 'not_authenticated');
  END IF;

  SELECT public.has_entitlement(v_user_id, 'PREMIUM'::public.entitlement_type)
  INTO v_has_premium;

  IF v_has_premium THEN
    RETURN jsonb_build_object('allowed', true, 'is_premium', true);
  END IF;

  -- Get free tier limits from app_settings
  SELECT value INTO v_limit_config
  FROM public.app_settings
  WHERE key = 'free_tier_limits';

  CASE p_limit_type
    WHEN 'scans_per_month' THEN
      v_limit := COALESCE((v_limit_config->>'scans_per_month')::INTEGER, 2);
      SELECT COUNT(*) INTO v_current_count
      FROM public.palm_scans
      WHERE user_id = v_user_id
        AND created_at >= date_trunc('month', NOW());
      RETURN jsonb_build_object(
        'allowed', v_current_count < v_limit,
        'current', v_current_count,
        'limit', v_limit,
        'limit_type', p_limit_type
      );
    WHEN 'predictions_visible' THEN
      v_limit := COALESCE((v_limit_config->>'predictions_visible')::INTEGER, 3);
      RETURN jsonb_build_object(
        'allowed', true,
        'limit', v_limit,
        'limit_type', p_limit_type
      );
    WHEN 'history_days' THEN
      v_limit := COALESCE((v_limit_config->>'history_days')::INTEGER, 7);
      RETURN jsonb_build_object(
        'allowed', true,
        'limit', v_limit,
        'limit_type', p_limit_type
      );
    ELSE
      RETURN jsonb_build_object('allowed', false, 'reason', 'unknown_limit_type');
  END CASE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.check_free_tier_limit(TEXT) TO authenticated;

-- ============================================================
-- MIGRATION COMPLETE
-- ============================================================
-- Summary of changes:
-- A. grant_entitlement/revoke_entitlement/expire_entitlements → service_role only
-- B. verify_and_complete_purchase → service_role only (new function)
-- C. upsert_subscription → service_role only (new function)
-- D. subscriptions → SELECT only for authenticated users
-- E. purchases → SELECT + restricted INSERT (pending only, no token/order_id)
-- F. palm_features → SELECT only for authenticated users
-- G. palm_analysis → SELECT only for authenticated users
-- H. palm_profiles → SELECT only for authenticated users
-- I. predictions → SELECT only (removed client INSERT)
-- J. reports → SELECT only for authenticated users
-- K. couple_readings → SELECT only for authenticated users
-- L. notifications → SELECT + UPDATE is_read only (trigger blocks content changes)
-- M. user_profiles → tier field protected by trigger (client cannot change tier)
-- N. storage.objects → UPDATE policy added for palm-images bucket
-- O. can_use_feature() → new client-safe feature check function
-- P. check_free_tier_limit() → new client-safe limit check function
-- ============================================================
