-- HastVeda Review & Feedback System
-- Migration: 20260819200000_hastveda_reviews.sql
-- Creates the user_reviews table with full RLS, admin access, and analytics support.

-- ── Review status type ────────────────────────────────────────────────────────
DROP TYPE IF EXISTS public.review_status CASCADE;
CREATE TYPE public.review_status AS ENUM ('new', 'reviewed', 'featured', 'archived');

-- ── Feature context type ──────────────────────────────────────────────────────
DROP TYPE IF EXISTS public.review_feature_context CASCADE;
CREATE TYPE public.review_feature_context AS ENUM (
  'palm_analysis',
  'detailed_report',
  'predictions',
  'ask_hastveda',
  'overall_app'
);

-- ── Recommendation type ───────────────────────────────────────────────────────
DROP TYPE IF EXISTS public.review_recommendation CASCADE;
CREATE TYPE public.review_recommendation AS ENUM ('yes', 'maybe', 'no');

-- ── user_reviews table ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.user_reviews (
  id                     UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id                UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  rating                 SMALLINT NOT NULL CHECK (rating >= 1 AND rating <= 5),
  review_text            TEXT,
  feature_context        public.review_feature_context NOT NULL DEFAULT 'overall_app',
  recommend_hastveda     public.review_recommendation,
  improvement_category   TEXT,
  review_status          public.review_status NOT NULL DEFAULT 'new',
  marketing_consent      BOOLEAN NOT NULL DEFAULT false,
  public_display_consent BOOLEAN NOT NULL DEFAULT false,
  created_at             TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- ── Indexes ───────────────────────────────────────────────────────────────────
CREATE INDEX IF NOT EXISTS idx_user_reviews_user_id ON public.user_reviews(user_id);
CREATE INDEX IF NOT EXISTS idx_user_reviews_rating ON public.user_reviews(rating);
CREATE INDEX IF NOT EXISTS idx_user_reviews_feature_context ON public.user_reviews(feature_context);
CREATE INDEX IF NOT EXISTS idx_user_reviews_review_status ON public.user_reviews(review_status);
CREATE INDEX IF NOT EXISTS idx_user_reviews_created_at ON public.user_reviews(created_at DESC);

-- One review per user per feature context (users can update, not create duplicates)
CREATE UNIQUE INDEX IF NOT EXISTS idx_user_reviews_user_feature_unique
  ON public.user_reviews(user_id, feature_context);

-- ── updated_at trigger ────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.update_user_reviews_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_user_reviews_updated_at ON public.user_reviews;
CREATE TRIGGER trg_user_reviews_updated_at
  BEFORE UPDATE ON public.user_reviews
  FOR EACH ROW
  EXECUTE FUNCTION public.update_user_reviews_updated_at();

-- ── Admin check function ──────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.is_admin_user()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
AS $$
SELECT EXISTS (
  SELECT 1 FROM auth.users au
  WHERE au.id = auth.uid()
  AND (
    au.raw_user_meta_data->>'role' = 'admin'
    OR au.raw_app_meta_data->>'role' = 'admin'
  )
)
$$;

-- ── Enable RLS ────────────────────────────────────────────────────────────────
ALTER TABLE public.user_reviews ENABLE ROW LEVEL SECURITY;

-- ── RLS Policies ─────────────────────────────────────────────────────────────

-- Users can read their own reviews
DROP POLICY IF EXISTS "users_read_own_reviews" ON public.user_reviews;
CREATE POLICY "users_read_own_reviews"
  ON public.user_reviews
  FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

-- Users can create their own reviews
DROP POLICY IF EXISTS "users_create_own_reviews" ON public.user_reviews;
CREATE POLICY "users_create_own_reviews"
  ON public.user_reviews
  FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

-- Users can update their own reviews
DROP POLICY IF EXISTS "users_update_own_reviews" ON public.user_reviews;
CREATE POLICY "users_update_own_reviews"
  ON public.user_reviews
  FOR UPDATE
  TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

-- Admin can read all reviews
DROP POLICY IF EXISTS "admin_read_all_reviews" ON public.user_reviews;
CREATE POLICY "admin_read_all_reviews"
  ON public.user_reviews
  FOR SELECT
  TO authenticated
  USING (public.is_admin_user());

-- Admin can update all reviews (for status management)
DROP POLICY IF EXISTS "admin_update_all_reviews" ON public.user_reviews;
CREATE POLICY "admin_update_all_reviews"
  ON public.user_reviews
  FOR UPDATE
  TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

-- Service role has full access
DROP POLICY IF EXISTS "service_role_all_reviews" ON public.user_reviews;
CREATE POLICY "service_role_all_reviews"
  ON public.user_reviews
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── Grants ────────────────────────────────────────────────────────────────────
GRANT SELECT, INSERT, UPDATE ON public.user_reviews TO authenticated;
GRANT ALL ON public.user_reviews TO service_role;
