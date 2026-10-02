-- ============================================================
-- HastVeda Complete Backend Schema
-- All 20 tables + RLS + Storage + Entitlement Architecture
-- Google Play Billing-ready
-- ============================================================

-- ============================================================
-- STEP 1: ENUM TYPES
-- ============================================================

DROP TYPE IF EXISTS public.user_tier CASCADE;
CREATE TYPE public.user_tier AS ENUM ('free', 'premium');

DROP TYPE IF EXISTS public.entitlement_type CASCADE;
CREATE TYPE public.entitlement_type AS ENUM (
  'FREE',
  'PREMIUM',
  'COMPLETE_READING',
  'COUPLE_READING',
  'DETAILED_REPORT'
);

DROP TYPE IF EXISTS public.subscription_status CASCADE;
CREATE TYPE public.subscription_status AS ENUM (
  'active',
  'expired',
  'cancelled',
  'pending',
  'grace_period',
  'on_hold',
  'paused'
);

DROP TYPE IF EXISTS public.purchase_status CASCADE;
CREATE TYPE public.purchase_status AS ENUM (
  'pending',
  'completed',
  'failed',
  'refunded',
  'cancelled',
  'acknowledged'
);

DROP TYPE IF EXISTS public.purchase_type CASCADE;
CREATE TYPE public.purchase_type AS ENUM (
  'subscription',
  'one_time'
);

DROP TYPE IF EXISTS public.scan_status CASCADE;
CREATE TYPE public.scan_status AS ENUM (
  'pending',
  'processing',
  'completed',
  'failed'
);

DROP TYPE IF EXISTS public.analysis_status CASCADE;
CREATE TYPE public.analysis_status AS ENUM (
  'pending',
  'processing',
  'completed',
  'failed'
);

DROP TYPE IF EXISTS public.hand_type CASCADE;
CREATE TYPE public.hand_type AS ENUM ('left', 'right', 'both');

DROP TYPE IF EXISTS public.notification_type CASCADE;
CREATE TYPE public.notification_type AS ENUM (
  'reading_ready',
  'subscription_expiring',
  'subscription_renewed',
  'new_prediction',
  'system',
  'promotional'
);

DROP TYPE IF EXISTS public.report_type CASCADE;
CREATE TYPE public.report_type AS ENUM (
  'full_reading',
  'detailed_analysis',
  'couple_compatibility',
  'yearly_forecast'
);

DROP TYPE IF EXISTS public.audit_action CASCADE;
CREATE TYPE public.audit_action AS ENUM (
  'create',
  'update',
  'delete',
  'login',
  'logout',
  'purchase',
  'entitlement_grant',
  'entitlement_revoke'
);

-- ============================================================
-- STEP 2: CORE TABLES (no foreign keys to public schema)
-- ============================================================

-- 1. user_profiles (core identity table)
CREATE TABLE IF NOT EXISTS public.user_profiles (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT NOT NULL UNIQUE,
  full_name TEXT NOT NULL DEFAULT '',
  avatar_url TEXT,
  phone TEXT,
  date_of_birth DATE,
  gender TEXT,
  language_preference TEXT NOT NULL DEFAULT 'en',
  tier public.user_tier NOT NULL DEFAULT 'free',
  is_active BOOLEAN NOT NULL DEFAULT true,
  onboarding_completed BOOLEAN NOT NULL DEFAULT false,
  last_seen_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 2. app_settings (global configuration, admin-managed)
CREATE TABLE IF NOT EXISTS public.app_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  key TEXT NOT NULL UNIQUE,
  value JSONB NOT NULL DEFAULT '{}',
  description TEXT,
  is_public BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 3: PRODUCT / BILLING TABLES
-- ============================================================

-- 3. subscriptions
CREATE TABLE IF NOT EXISTS public.subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  status public.subscription_status NOT NULL DEFAULT 'pending',
  purchase_token TEXT,
  order_id TEXT,
  started_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  cancelled_at TIMESTAMPTZ,
  auto_renewing BOOLEAN NOT NULL DEFAULT true,
  trial_end_at TIMESTAMPTZ,
  grace_period_end_at TIMESTAMPTZ,
  linked_purchase_id UUID,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 4. purchases (one-time and subscription purchase records)
CREATE TABLE IF NOT EXISTS public.purchases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  product_id TEXT NOT NULL,
  purchase_type public.purchase_type NOT NULL DEFAULT 'one_time',
  status public.purchase_status NOT NULL DEFAULT 'pending',
  purchase_token TEXT,
  order_id TEXT,
  amount_micros BIGINT,
  currency_code TEXT DEFAULT 'INR',
  purchase_time TIMESTAMPTZ,
  acknowledged_at TIMESTAMPTZ,
  consumed_at TIMESTAMPTZ,
  refunded_at TIMESTAMPTZ,
  verification_data JSONB NOT NULL DEFAULT '{}',
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 5. entitlements (centralized access control)
CREATE TABLE IF NOT EXISTS public.entitlements (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  entitlement_type public.entitlement_type NOT NULL,
  is_active BOOLEAN NOT NULL DEFAULT true,
  granted_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  source_purchase_id UUID REFERENCES public.purchases(id) ON DELETE SET NULL,
  source_subscription_id UUID REFERENCES public.subscriptions(id) ON DELETE SET NULL,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 4: PALM SCAN / ANALYSIS TABLES
-- ============================================================

-- 6. palm_scans
CREATE TABLE IF NOT EXISTS public.palm_scans (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  hand_type public.hand_type NOT NULL DEFAULT 'right',
  image_path TEXT,
  image_bucket TEXT DEFAULT 'palm-images',
  status public.scan_status NOT NULL DEFAULT 'pending',
  quality_score NUMERIC(5,2),
  scan_metadata JSONB NOT NULL DEFAULT '{}',
  device_info JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 7. palm_features (extracted line/feature data)
CREATE TABLE IF NOT EXISTS public.palm_features (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id UUID NOT NULL REFERENCES public.palm_scans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  life_line JSONB NOT NULL DEFAULT '{}',
  heart_line JSONB NOT NULL DEFAULT '{}',
  head_line JSONB NOT NULL DEFAULT '{}',
  fate_line JSONB NOT NULL DEFAULT '{}',
  sun_line JSONB NOT NULL DEFAULT '{}',
  mercury_line JSONB NOT NULL DEFAULT '{}',
  marriage_lines JSONB NOT NULL DEFAULT '[]',
  mounts JSONB NOT NULL DEFAULT '{}',
  finger_ratios JSONB NOT NULL DEFAULT '{}',
  special_marks JSONB NOT NULL DEFAULT '[]',
  raw_features JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 8. palm_analysis
CREATE TABLE IF NOT EXISTS public.palm_analysis (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  scan_id UUID NOT NULL REFERENCES public.palm_scans(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  features_id UUID REFERENCES public.palm_features(id) ON DELETE SET NULL,
  status public.analysis_status NOT NULL DEFAULT 'pending',
  ai_model TEXT,
  ai_provider TEXT,
  analysis_version TEXT,
  life_analysis JSONB NOT NULL DEFAULT '{}',
  love_analysis JSONB NOT NULL DEFAULT '{}',
  career_analysis JSONB NOT NULL DEFAULT '{}',
  health_analysis JSONB NOT NULL DEFAULT '{}',
  wealth_analysis JSONB NOT NULL DEFAULT '{}',
  personality_analysis JSONB NOT NULL DEFAULT '{}',
  spiritual_analysis JSONB NOT NULL DEFAULT '{}',
  summary TEXT,
  confidence_score NUMERIC(5,2),
  processing_time_ms INTEGER,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 9. palm_profiles (aggregated user palm profile)
CREATE TABLE IF NOT EXISTS public.palm_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  dominant_hand public.hand_type NOT NULL DEFAULT 'right',
  primary_scan_id UUID REFERENCES public.palm_scans(id) ON DELETE SET NULL,
  primary_analysis_id UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,
  life_path_number INTEGER,
  destiny_number INTEGER,
  soul_urge_number INTEGER,
  personality_type TEXT,
  elemental_type TEXT,
  dominant_mount TEXT,
  key_traits JSONB NOT NULL DEFAULT '[]',
  strengths JSONB NOT NULL DEFAULT '[]',
  challenges JSONB NOT NULL DEFAULT '[]',
  lucky_numbers JSONB NOT NULL DEFAULT '[]',
  lucky_colors JSONB NOT NULL DEFAULT '[]',
  compatible_signs JSONB NOT NULL DEFAULT '[]',
  profile_summary TEXT,
  last_updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 5: PREDICTIONS / READINGS TABLES
-- ============================================================

-- 10. predictions
CREATE TABLE IF NOT EXISTS public.predictions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  analysis_id UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,
  prediction_type TEXT NOT NULL,
  time_period TEXT NOT NULL,
  period_start DATE,
  period_end DATE,
  title TEXT NOT NULL,
  content TEXT NOT NULL,
  short_summary TEXT,
  category TEXT,
  confidence_score NUMERIC(5,2),
  is_premium BOOLEAN NOT NULL DEFAULT false,
  is_featured BOOLEAN NOT NULL DEFAULT false,
  tags JSONB NOT NULL DEFAULT '[]',
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 11. reading_history
CREATE TABLE IF NOT EXISTS public.reading_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  scan_id UUID REFERENCES public.palm_scans(id) ON DELETE SET NULL,
  analysis_id UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,
  reading_type TEXT NOT NULL,
  title TEXT NOT NULL,
  summary TEXT,
  is_complete BOOLEAN NOT NULL DEFAULT false,
  is_premium BOOLEAN NOT NULL DEFAULT false,
  viewed_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  completed_at TIMESTAMPTZ,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 12. prediction_feedback
CREATE TABLE IF NOT EXISTS public.prediction_feedback (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  prediction_id UUID NOT NULL REFERENCES public.predictions(id) ON DELETE CASCADE,
  rating INTEGER CHECK (rating >= 1 AND rating <= 5),
  accuracy_rating INTEGER CHECK (accuracy_rating >= 1 AND accuracy_rating <= 5),
  comment TEXT,
  is_helpful BOOLEAN,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 6: REPORTS / COUPLE READINGS
-- ============================================================

-- 13. reports
CREATE TABLE IF NOT EXISTS public.reports (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  analysis_id UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,
  report_type public.report_type NOT NULL DEFAULT 'full_reading',
  title TEXT NOT NULL,
  content JSONB NOT NULL DEFAULT '{}',
  pdf_path TEXT,
  pdf_bucket TEXT DEFAULT 'palm-images',
  is_premium BOOLEAN NOT NULL DEFAULT true,
  purchase_id UUID REFERENCES public.purchases(id) ON DELETE SET NULL,
  generated_at TIMESTAMPTZ,
  expires_at TIMESTAMPTZ,
  download_count INTEGER NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 14. couple_readings
CREATE TABLE IF NOT EXISTS public.couple_readings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  partner_name TEXT NOT NULL,
  partner_date_of_birth DATE,
  partner_scan_id UUID REFERENCES public.palm_scans(id) ON DELETE SET NULL,
  compatibility_score NUMERIC(5,2),
  compatibility_analysis JSONB NOT NULL DEFAULT '{}',
  relationship_strengths JSONB NOT NULL DEFAULT '[]',
  relationship_challenges JSONB NOT NULL DEFAULT '[]',
  love_compatibility TEXT,
  career_compatibility TEXT,
  life_goals_compatibility TEXT,
  summary TEXT,
  purchase_id UUID REFERENCES public.purchases(id) ON DELETE SET NULL,
  is_complete BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 7: NOTIFICATIONS
-- ============================================================

-- 15. notification_preferences
CREATE TABLE IF NOT EXISTS public.notification_preferences (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL UNIQUE REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  push_enabled BOOLEAN NOT NULL DEFAULT true,
  email_enabled BOOLEAN NOT NULL DEFAULT true,
  reading_ready BOOLEAN NOT NULL DEFAULT true,
  subscription_alerts BOOLEAN NOT NULL DEFAULT true,
  new_predictions BOOLEAN NOT NULL DEFAULT true,
  promotional BOOLEAN NOT NULL DEFAULT false,
  quiet_hours_start TIME,
  quiet_hours_end TIME,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 16. notifications
CREATE TABLE IF NOT EXISTS public.notifications (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  notification_type public.notification_type NOT NULL DEFAULT 'system',
  title TEXT NOT NULL,
  body TEXT NOT NULL,
  data JSONB NOT NULL DEFAULT '{}',
  is_read BOOLEAN NOT NULL DEFAULT false,
  read_at TIMESTAMPTZ,
  sent_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 8: ANALYTICS / TRACKING
-- ============================================================

-- 17. ai_usage
CREATE TABLE IF NOT EXISTS public.ai_usage (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  scan_id UUID REFERENCES public.palm_scans(id) ON DELETE SET NULL,
  analysis_id UUID REFERENCES public.palm_analysis(id) ON DELETE SET NULL,
  ai_provider TEXT NOT NULL,
  ai_model TEXT NOT NULL,
  operation_type TEXT NOT NULL,
  input_tokens INTEGER NOT NULL DEFAULT 0,
  output_tokens INTEGER NOT NULL DEFAULT 0,
  total_tokens INTEGER NOT NULL DEFAULT 0,
  cost_micros BIGINT NOT NULL DEFAULT 0,
  latency_ms INTEGER,
  success BOOLEAN NOT NULL DEFAULT true,
  error_message TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 18. analytics_events
CREATE TABLE IF NOT EXISTS public.analytics_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  event_name TEXT NOT NULL,
  event_category TEXT,
  properties JSONB NOT NULL DEFAULT '{}',
  session_id TEXT,
  device_info JSONB NOT NULL DEFAULT '{}',
  app_version TEXT,
  platform TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 19. audit_logs
CREATE TABLE IF NOT EXISTS public.audit_logs (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  action public.audit_action NOT NULL,
  resource_type TEXT NOT NULL,
  resource_id UUID,
  old_values JSONB,
  new_values JSONB,
  ip_address INET,
  user_agent TEXT,
  metadata JSONB NOT NULL DEFAULT '{}',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 20. users (alias/extended view table for app compatibility)
CREATE TABLE IF NOT EXISTS public.users (
  id UUID PRIMARY KEY REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  fcm_token TEXT,
  device_id TEXT,
  app_version TEXT,
  platform TEXT,
  timezone TEXT DEFAULT 'Asia/Kolkata',
  last_active_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ============================================================
-- STEP 9: INDEXES
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_user_profiles_email ON public.user_profiles(email);
CREATE INDEX IF NOT EXISTS idx_user_profiles_tier ON public.user_profiles(tier);

CREATE INDEX IF NOT EXISTS idx_subscriptions_user_id ON public.subscriptions(user_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_status ON public.subscriptions(status);
CREATE INDEX IF NOT EXISTS idx_subscriptions_product_id ON public.subscriptions(product_id);
CREATE INDEX IF NOT EXISTS idx_subscriptions_expires_at ON public.subscriptions(expires_at);

CREATE INDEX IF NOT EXISTS idx_purchases_user_id ON public.purchases(user_id);
CREATE INDEX IF NOT EXISTS idx_purchases_product_id ON public.purchases(product_id);
CREATE INDEX IF NOT EXISTS idx_purchases_status ON public.purchases(status);
CREATE INDEX IF NOT EXISTS idx_purchases_order_id ON public.purchases(order_id);

CREATE INDEX IF NOT EXISTS idx_entitlements_user_id ON public.entitlements(user_id);
CREATE INDEX IF NOT EXISTS idx_entitlements_type ON public.entitlements(entitlement_type);
CREATE INDEX IF NOT EXISTS idx_entitlements_active ON public.entitlements(user_id, is_active);
CREATE INDEX IF NOT EXISTS idx_entitlements_expires_at ON public.entitlements(expires_at);

CREATE INDEX IF NOT EXISTS idx_palm_scans_user_id ON public.palm_scans(user_id);
CREATE INDEX IF NOT EXISTS idx_palm_scans_status ON public.palm_scans(status);

CREATE INDEX IF NOT EXISTS idx_palm_features_scan_id ON public.palm_features(scan_id);
CREATE INDEX IF NOT EXISTS idx_palm_features_user_id ON public.palm_features(user_id);

CREATE INDEX IF NOT EXISTS idx_palm_analysis_scan_id ON public.palm_analysis(scan_id);
CREATE INDEX IF NOT EXISTS idx_palm_analysis_user_id ON public.palm_analysis(user_id);
CREATE INDEX IF NOT EXISTS idx_palm_analysis_status ON public.palm_analysis(status);

CREATE INDEX IF NOT EXISTS idx_palm_profiles_user_id ON public.palm_profiles(user_id);

CREATE INDEX IF NOT EXISTS idx_predictions_user_id ON public.predictions(user_id);
CREATE INDEX IF NOT EXISTS idx_predictions_type ON public.predictions(prediction_type);
CREATE INDEX IF NOT EXISTS idx_predictions_period ON public.predictions(time_period);

CREATE INDEX IF NOT EXISTS idx_reading_history_user_id ON public.reading_history(user_id);
CREATE INDEX IF NOT EXISTS idx_reading_history_viewed_at ON public.reading_history(viewed_at DESC);

CREATE INDEX IF NOT EXISTS idx_prediction_feedback_user_id ON public.prediction_feedback(user_id);
CREATE INDEX IF NOT EXISTS idx_prediction_feedback_prediction_id ON public.prediction_feedback(prediction_id);

CREATE INDEX IF NOT EXISTS idx_reports_user_id ON public.reports(user_id);
CREATE INDEX IF NOT EXISTS idx_couple_readings_user_id ON public.couple_readings(user_id);

CREATE INDEX IF NOT EXISTS idx_notifications_user_id ON public.notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_unread ON public.notifications(user_id, is_read);

CREATE INDEX IF NOT EXISTS idx_ai_usage_user_id ON public.ai_usage(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_usage_created_at ON public.ai_usage(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_analytics_events_user_id ON public.analytics_events(user_id);
CREATE INDEX IF NOT EXISTS idx_analytics_events_name ON public.analytics_events(event_name);
CREATE INDEX IF NOT EXISTS idx_analytics_events_created_at ON public.analytics_events(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_audit_logs_user_id ON public.audit_logs(user_id);
CREATE INDEX IF NOT EXISTS idx_audit_logs_action ON public.audit_logs(action);
CREATE INDEX IF NOT EXISTS idx_audit_logs_created_at ON public.audit_logs(created_at DESC);

-- ============================================================
-- STEP 10: FUNCTIONS (must be before RLS policies)
-- ============================================================

-- Auto-create user_profiles on auth signup
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  INSERT INTO public.user_profiles (id, email, full_name, avatar_url)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', split_part(NEW.email, '@', 1)),
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', '')
  )
  ON CONFLICT (id) DO NOTHING;

  -- Also create users row
  INSERT INTO public.users (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  -- Create default notification preferences
  INSERT INTO public.notification_preferences (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  -- Grant FREE entitlement
  INSERT INTO public.entitlements (user_id, entitlement_type, is_active)
  VALUES (NEW.id, 'FREE'::public.entitlement_type, true)
  ON CONFLICT DO NOTHING;

  RETURN NEW;
END;
$$;

-- Updated_at auto-update function
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Check if user has active entitlement
CREATE OR REPLACE FUNCTION public.has_entitlement(p_user_id UUID, p_entitlement_type public.entitlement_type)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.entitlements
    WHERE user_id = p_user_id
      AND entitlement_type = p_entitlement_type
      AND is_active = true
      AND (expires_at IS NULL OR expires_at > NOW())
  );
$$;

-- Get user's active entitlements
CREATE OR REPLACE FUNCTION public.get_user_entitlements(p_user_id UUID)
RETURNS TABLE(entitlement_type public.entitlement_type, expires_at TIMESTAMPTZ)
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
  SELECT entitlement_type, expires_at
  FROM public.entitlements
  WHERE user_id = p_user_id
    AND is_active = true
    AND (expires_at IS NULL OR expires_at > NOW());
$$;

-- Grant entitlement (called after purchase verification)
CREATE OR REPLACE FUNCTION public.grant_entitlement(
  p_user_id UUID,
  p_entitlement_type public.entitlement_type,
  p_expires_at TIMESTAMPTZ DEFAULT NULL,
  p_source_purchase_id UUID DEFAULT NULL,
  p_source_subscription_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_entitlement_id UUID;
BEGIN
  INSERT INTO public.entitlements (
    user_id, entitlement_type, is_active, expires_at,
    source_purchase_id, source_subscription_id
  )
  VALUES (
    p_user_id, p_entitlement_type, true, p_expires_at,
    p_source_purchase_id, p_source_subscription_id
  )
  RETURNING id INTO v_entitlement_id;

  -- Update user tier if granting PREMIUM
  IF p_entitlement_type = 'PREMIUM'::public.entitlement_type THEN
    UPDATE public.user_profiles
    SET tier = 'premium'::public.user_tier, updated_at = NOW()
    WHERE id = p_user_id;
  END IF;

  RETURN v_entitlement_id;
END;
$$;

-- Revoke entitlement
CREATE OR REPLACE FUNCTION public.revoke_entitlement(
  p_user_id UUID,
  p_entitlement_type public.entitlement_type
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
BEGIN
  UPDATE public.entitlements
  SET is_active = false, updated_at = NOW()
  WHERE user_id = p_user_id
    AND entitlement_type = p_entitlement_type
    AND is_active = true;

  -- Downgrade tier if revoking PREMIUM
  IF p_entitlement_type = 'PREMIUM'::public.entitlement_type THEN
    UPDATE public.user_profiles
    SET tier = 'free'::public.user_tier, updated_at = NOW()
    WHERE id = p_user_id;
  END IF;
END;
$$;

-- Expire stale entitlements (run periodically)
CREATE OR REPLACE FUNCTION public.expire_entitlements()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  UPDATE public.entitlements
  SET is_active = false, updated_at = NOW()
  WHERE is_active = true
    AND expires_at IS NOT NULL
    AND expires_at <= NOW();

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

-- ============================================================
-- STEP 11: ENABLE ROW LEVEL SECURITY
-- ============================================================

ALTER TABLE public.user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.entitlements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.palm_scans ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.palm_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.palm_analysis ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.palm_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.predictions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reading_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.prediction_feedback ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.couple_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_usage ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.analytics_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;

-- ============================================================
-- STEP 12: RLS POLICIES
-- ============================================================

-- user_profiles
DROP POLICY IF EXISTS "users_manage_own_user_profiles" ON public.user_profiles;
CREATE POLICY "users_manage_own_user_profiles"
ON public.user_profiles FOR ALL TO authenticated
USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- users
DROP POLICY IF EXISTS "users_manage_own_users" ON public.users;
CREATE POLICY "users_manage_own_users"
ON public.users FOR ALL TO authenticated
USING (id = auth.uid()) WITH CHECK (id = auth.uid());

-- app_settings (public read for public settings)
DROP POLICY IF EXISTS "public_read_app_settings" ON public.app_settings;
CREATE POLICY "public_read_app_settings"
ON public.app_settings FOR SELECT TO authenticated
USING (is_public = true);

-- subscriptions
DROP POLICY IF EXISTS "users_manage_own_subscriptions" ON public.subscriptions;
CREATE POLICY "users_manage_own_subscriptions"
ON public.subscriptions FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- purchases
DROP POLICY IF EXISTS "users_manage_own_purchases" ON public.purchases;
CREATE POLICY "users_manage_own_purchases"
ON public.purchases FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- entitlements (read-only for users; writes via server-side functions)
DROP POLICY IF EXISTS "users_read_own_entitlements" ON public.entitlements;
CREATE POLICY "users_read_own_entitlements"
ON public.entitlements FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- palm_scans
DROP POLICY IF EXISTS "users_manage_own_palm_scans" ON public.palm_scans;
CREATE POLICY "users_manage_own_palm_scans"
ON public.palm_scans FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- palm_features
DROP POLICY IF EXISTS "users_manage_own_palm_features" ON public.palm_features;
CREATE POLICY "users_manage_own_palm_features"
ON public.palm_features FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- palm_analysis
DROP POLICY IF EXISTS "users_manage_own_palm_analysis" ON public.palm_analysis;
CREATE POLICY "users_manage_own_palm_analysis"
ON public.palm_analysis FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- palm_profiles
DROP POLICY IF EXISTS "users_manage_own_palm_profiles" ON public.palm_profiles;
CREATE POLICY "users_manage_own_palm_profiles"
ON public.palm_profiles FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- predictions
DROP POLICY IF EXISTS "users_read_own_predictions" ON public.predictions;
CREATE POLICY "users_read_own_predictions"
ON public.predictions FOR SELECT TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_predictions" ON public.predictions;
CREATE POLICY "users_insert_own_predictions"
ON public.predictions FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- reading_history
DROP POLICY IF EXISTS "users_manage_own_reading_history" ON public.reading_history;
CREATE POLICY "users_manage_own_reading_history"
ON public.reading_history FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- prediction_feedback
DROP POLICY IF EXISTS "users_manage_own_prediction_feedback" ON public.prediction_feedback;
CREATE POLICY "users_manage_own_prediction_feedback"
ON public.prediction_feedback FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- reports
DROP POLICY IF EXISTS "users_manage_own_reports" ON public.reports;
CREATE POLICY "users_manage_own_reports"
ON public.reports FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- couple_readings
DROP POLICY IF EXISTS "users_manage_own_couple_readings" ON public.couple_readings;
CREATE POLICY "users_manage_own_couple_readings"
ON public.couple_readings FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- notifications
DROP POLICY IF EXISTS "users_manage_own_notifications" ON public.notifications;
CREATE POLICY "users_manage_own_notifications"
ON public.notifications FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- notification_preferences
DROP POLICY IF EXISTS "users_manage_own_notification_preferences" ON public.notification_preferences;
CREATE POLICY "users_manage_own_notification_preferences"
ON public.notification_preferences FOR ALL TO authenticated
USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- ai_usage (insert only for users, read own)
DROP POLICY IF EXISTS "users_read_own_ai_usage" ON public.ai_usage;
CREATE POLICY "users_read_own_ai_usage"
ON public.ai_usage FOR SELECT TO authenticated
USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_ai_usage" ON public.ai_usage;
CREATE POLICY "users_insert_own_ai_usage"
ON public.ai_usage FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid());

-- analytics_events (insert only)
DROP POLICY IF EXISTS "users_insert_analytics_events" ON public.analytics_events;
CREATE POLICY "users_insert_analytics_events"
ON public.analytics_events FOR INSERT TO authenticated
WITH CHECK (user_id = auth.uid() OR user_id IS NULL);

-- audit_logs (read own only)
DROP POLICY IF EXISTS "users_read_own_audit_logs" ON public.audit_logs;
CREATE POLICY "users_read_own_audit_logs"
ON public.audit_logs FOR SELECT TO authenticated
USING (user_id = auth.uid());

-- ============================================================
-- STEP 13: TRIGGERS
-- ============================================================

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();

-- updated_at triggers
DROP TRIGGER IF EXISTS set_updated_at_user_profiles ON public.user_profiles;
CREATE TRIGGER set_updated_at_user_profiles
  BEFORE UPDATE ON public.user_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_subscriptions ON public.subscriptions;
CREATE TRIGGER set_updated_at_subscriptions
  BEFORE UPDATE ON public.subscriptions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_purchases ON public.purchases;
CREATE TRIGGER set_updated_at_purchases
  BEFORE UPDATE ON public.purchases
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_entitlements ON public.entitlements;
CREATE TRIGGER set_updated_at_entitlements
  BEFORE UPDATE ON public.entitlements
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_palm_scans ON public.palm_scans;
CREATE TRIGGER set_updated_at_palm_scans
  BEFORE UPDATE ON public.palm_scans
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_palm_analysis ON public.palm_analysis;
CREATE TRIGGER set_updated_at_palm_analysis
  BEFORE UPDATE ON public.palm_analysis
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_palm_profiles ON public.palm_profiles;
CREATE TRIGGER set_updated_at_palm_profiles
  BEFORE UPDATE ON public.palm_profiles
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_predictions ON public.predictions;
CREATE TRIGGER set_updated_at_predictions
  BEFORE UPDATE ON public.predictions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_reading_history ON public.reading_history;
CREATE TRIGGER set_updated_at_reading_history
  BEFORE UPDATE ON public.reading_history
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_reports ON public.reports;
CREATE TRIGGER set_updated_at_reports
  BEFORE UPDATE ON public.reports
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_couple_readings ON public.couple_readings;
CREATE TRIGGER set_updated_at_couple_readings
  BEFORE UPDATE ON public.couple_readings
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_updated_at_notification_preferences ON public.notification_preferences;
CREATE TRIGGER set_updated_at_notification_preferences
  BEFORE UPDATE ON public.notification_preferences
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ============================================================
-- STEP 14: STORAGE BUCKET (private palm images)
-- ============================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'palm-images',
  'palm-images',
  false,
  10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic', 'application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = false,
  file_size_limit = 10485760;

-- Storage RLS policies
DROP POLICY IF EXISTS "users_upload_own_palm_images" ON storage.objects;
CREATE POLICY "users_upload_own_palm_images"
ON storage.objects FOR INSERT TO authenticated
WITH CHECK (
  bucket_id = 'palm-images'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

DROP POLICY IF EXISTS "users_read_own_palm_images" ON storage.objects;
CREATE POLICY "users_read_own_palm_images"
ON storage.objects FOR SELECT TO authenticated
USING (
  bucket_id = 'palm-images'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

DROP POLICY IF EXISTS "users_delete_own_palm_images" ON storage.objects;
CREATE POLICY "users_delete_own_palm_images"
ON storage.objects FOR DELETE TO authenticated
USING (
  bucket_id = 'palm-images'
  AND (storage.foldername(name))[1] = auth.uid()::TEXT
);

-- ============================================================
-- STEP 15: DEFAULT APP SETTINGS (Google Play product IDs)
-- ============================================================

INSERT INTO public.app_settings (key, value, description, is_public) VALUES
  ('google_play_products', jsonb_build_object(
    'hastveda_premium_monthly', jsonb_build_object(
      'product_id', 'hastveda_premium_monthly',
      'type', 'subscription',
      'display_price', '₹99/month',
      'entitlement', 'PREMIUM',
      'duration_days', 30
    ),
    'hastveda_premium_yearly', jsonb_build_object(
      'product_id', 'hastveda_premium_yearly',
      'type', 'subscription',
      'display_price', '₹799/year',
      'entitlement', 'PREMIUM',
      'duration_days', 365
    ),
    'hastveda_complete_reading', jsonb_build_object(
      'product_id', 'hastveda_complete_reading',
      'type', 'one_time',
      'display_price', '₹99',
      'entitlement', 'COMPLETE_READING',
      'duration_days', null
    ),
    'hastveda_couple_reading', jsonb_build_object(
      'product_id', 'hastveda_couple_reading',
      'type', 'one_time',
      'display_price', '₹199',
      'entitlement', 'COUPLE_READING',
      'duration_days', null
    ),
    'hastveda_detailed_report', jsonb_build_object(
      'product_id', 'hastveda_detailed_report',
      'type', 'one_time',
      'display_price', '₹99',
      'entitlement', 'DETAILED_REPORT',
      'duration_days', null
    )
  ), 'Google Play Billing product catalog', true),
  ('feature_flags', jsonb_build_object(
    'google_play_billing_enabled', false,
    'ai_analysis_enabled', true,
    'couple_reading_enabled', true,
    'detailed_report_enabled', true
  ), 'Feature flags for the application', true),
  ('free_tier_limits', jsonb_build_object(
    'scans_per_month', 2,
    'predictions_visible', 3,
    'history_days', 7
  ), 'Limits for free tier users', true)
ON CONFLICT (key) DO NOTHING;
