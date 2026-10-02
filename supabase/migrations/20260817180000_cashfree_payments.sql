-- ============================================================
-- CASHFREE PAYMENT INTEGRATION MIGRATION
-- HastVeda Premium — Cashfree Sandbox
-- ============================================================

-- ── 1. TYPES ─────────────────────────────────────────────────

DROP TYPE IF EXISTS public.payment_status_type CASCADE;
CREATE TYPE public.payment_status_type AS ENUM (
  'order_created',
  'payment_initiated',
  'payment_successful',
  'payment_failed',
  'payment_cancelled',
  'payment_pending',
  'refunded'
);

DROP TYPE IF EXISTS public.discount_type CASCADE;
CREATE TYPE public.discount_type AS ENUM ('percentage', 'fixed_amount');

-- ── 2. CASHFREE ORDERS TABLE ──────────────────────────────────

CREATE TABLE IF NOT EXISTS public.cashfree_orders (
  id                  UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id             UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  cashfree_order_id   TEXT NOT NULL UNIQUE,
  payment_session_id  TEXT,
  payment_id          TEXT,
  original_amount     NUMERIC(10,2) NOT NULL,
  discount_amount     NUMERIC(10,2) NOT NULL DEFAULT 0,
  final_amount        NUMERIC(10,2) NOT NULL,
  currency            TEXT NOT NULL DEFAULT 'INR',
  status              public.payment_status_type NOT NULL DEFAULT 'order_created',
  coupon_id           UUID,
  coupon_code         TEXT,
  product_id          TEXT NOT NULL DEFAULT 'hastveda_premium',
  failure_reason      TEXT,
  webhook_received_at TIMESTAMPTZ,
  paid_at             TIMESTAMPTZ,
  created_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at          TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_cashfree_orders_user_id ON public.cashfree_orders(user_id);
CREATE INDEX IF NOT EXISTS idx_cashfree_orders_cashfree_order_id ON public.cashfree_orders(cashfree_order_id);
CREATE INDEX IF NOT EXISTS idx_cashfree_orders_status ON public.cashfree_orders(status);

-- ── 3. DISCOUNT CODES TABLE ───────────────────────────────────

CREATE TABLE IF NOT EXISTS public.discount_codes (
  id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code                  TEXT NOT NULL UNIQUE,
  discount_type         public.discount_type NOT NULL DEFAULT 'fixed_amount',
  discount_value        NUMERIC(10,2) NOT NULL,
  applicable_product    TEXT NOT NULL DEFAULT 'hastveda_premium',
  max_redemptions       INTEGER NOT NULL DEFAULT 1,
  max_per_customer      INTEGER NOT NULL DEFAULT 1,
  used_count            INTEGER NOT NULL DEFAULT 0,
  assigned_user_id      UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  assigned_phone        TEXT,
  assigned_email        TEXT,
  campaign              TEXT,
  admin_note            TEXT,
  is_active             BOOLEAN NOT NULL DEFAULT TRUE,
  expires_at            TIMESTAMPTZ,
  created_by            UUID REFERENCES public.user_profiles(id) ON DELETE SET NULL,
  created_at            TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at            TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_discount_codes_code ON public.discount_codes(code);
CREATE INDEX IF NOT EXISTS idx_discount_codes_is_active ON public.discount_codes(is_active);
CREATE INDEX IF NOT EXISTS idx_discount_codes_assigned_user ON public.discount_codes(assigned_user_id);

-- ── 4. COUPON REDEMPTIONS TABLE ───────────────────────────────

CREATE TABLE IF NOT EXISTS public.coupon_redemptions (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  coupon_id       UUID NOT NULL REFERENCES public.discount_codes(id) ON DELETE CASCADE,
  coupon_code     TEXT NOT NULL,
  user_id         UUID NOT NULL REFERENCES public.user_profiles(id) ON DELETE CASCADE,
  order_id        UUID REFERENCES public.cashfree_orders(id) ON DELETE SET NULL,
  original_amount NUMERIC(10,2) NOT NULL,
  discount_amount NUMERIC(10,2) NOT NULL,
  final_amount    NUMERIC(10,2) NOT NULL,
  payment_status  TEXT NOT NULL DEFAULT 'pending',
  campaign        TEXT,
  redeemed_at     TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_coupon_id ON public.coupon_redemptions(coupon_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_user_id ON public.coupon_redemptions(user_id);
CREATE INDEX IF NOT EXISTS idx_coupon_redemptions_order_id ON public.coupon_redemptions(order_id);

-- Prevent double-redemption of a single-use coupon per user
CREATE UNIQUE INDEX IF NOT EXISTS idx_coupon_redemptions_user_coupon_success
  ON public.coupon_redemptions(user_id, coupon_id)
  WHERE payment_status = 'success';

-- ── 5. UPDATED_AT TRIGGER ─────────────────────────────────────

CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_cashfree_orders_updated_at ON public.cashfree_orders;
CREATE TRIGGER set_cashfree_orders_updated_at
  BEFORE UPDATE ON public.cashfree_orders
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

DROP TRIGGER IF EXISTS set_discount_codes_updated_at ON public.discount_codes;
CREATE TRIGGER set_discount_codes_updated_at
  BEFORE UPDATE ON public.discount_codes
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ── 6. ADMIN ROLE CHECK FUNCTION ─────────────────────────────

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

-- ── 7. ENABLE RLS ─────────────────────────────────────────────

ALTER TABLE public.cashfree_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.discount_codes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.coupon_redemptions ENABLE ROW LEVEL SECURITY;

-- ── 8. RLS POLICIES — cashfree_orders ────────────────────────

DROP POLICY IF EXISTS "users_view_own_cashfree_orders" ON public.cashfree_orders;
CREATE POLICY "users_view_own_cashfree_orders"
  ON public.cashfree_orders FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_cashfree_orders" ON public.cashfree_orders;
CREATE POLICY "users_insert_own_cashfree_orders"
  ON public.cashfree_orders FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "service_role_all_cashfree_orders" ON public.cashfree_orders;
CREATE POLICY "service_role_all_cashfree_orders"
  ON public.cashfree_orders FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "admin_all_cashfree_orders" ON public.cashfree_orders;
CREATE POLICY "admin_all_cashfree_orders"
  ON public.cashfree_orders FOR ALL
  TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

-- ── 9. RLS POLICIES — discount_codes ─────────────────────────

DROP POLICY IF EXISTS "users_read_active_discount_codes" ON public.discount_codes;
CREATE POLICY "users_read_active_discount_codes"
  ON public.discount_codes FOR SELECT
  TO authenticated
  USING (is_active = true);

DROP POLICY IF EXISTS "admin_all_discount_codes" ON public.discount_codes;
CREATE POLICY "admin_all_discount_codes"
  ON public.discount_codes FOR ALL
  TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

DROP POLICY IF EXISTS "service_role_all_discount_codes" ON public.discount_codes;
CREATE POLICY "service_role_all_discount_codes"
  ON public.discount_codes FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ── 10. RLS POLICIES — coupon_redemptions ────────────────────

DROP POLICY IF EXISTS "users_view_own_coupon_redemptions" ON public.coupon_redemptions;
CREATE POLICY "users_view_own_coupon_redemptions"
  ON public.coupon_redemptions FOR SELECT
  TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "users_insert_own_coupon_redemptions" ON public.coupon_redemptions;
CREATE POLICY "users_insert_own_coupon_redemptions"
  ON public.coupon_redemptions FOR INSERT
  TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "service_role_all_coupon_redemptions" ON public.coupon_redemptions;
CREATE POLICY "service_role_all_coupon_redemptions"
  ON public.coupon_redemptions FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

DROP POLICY IF EXISTS "admin_all_coupon_redemptions" ON public.coupon_redemptions;
CREATE POLICY "admin_all_coupon_redemptions"
  ON public.coupon_redemptions FOR ALL
  TO authenticated
  USING (public.is_admin_user())
  WITH CHECK (public.is_admin_user());

-- ── 11. GRANT PERMISSIONS ─────────────────────────────────────

GRANT SELECT, INSERT, UPDATE ON public.cashfree_orders TO authenticated;
GRANT SELECT ON public.discount_codes TO authenticated;
GRANT SELECT, INSERT ON public.coupon_redemptions TO authenticated;
GRANT ALL ON public.cashfree_orders TO service_role;
GRANT ALL ON public.discount_codes TO service_role;
GRANT ALL ON public.coupon_redemptions TO service_role;
