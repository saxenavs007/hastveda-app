-- Enforce HastVeda's lifetime Ask Question policy and restore the idempotent credit RPCs.
-- Premium: two lifetime free questions, no calendar reset.
-- Each additional/non-Premium question requires its own successful ₹59 Cashfree order.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS free_questions_used integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS free_question_period date,
  ADD COLUMN IF NOT EXISTS free_question_quota integer NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS paid_question_balance integer NOT NULL DEFAULT 0;

ALTER TABLE public.question_usage
  ADD COLUMN IF NOT EXISTS paid_credit_applied boolean NOT NULL DEFAULT false;

CREATE TABLE IF NOT EXISTS public.question_credit_grants (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  cashfree_order_id text NOT NULL,
  grant_type text NOT NULL CHECK (grant_type IN ('premium_quota', 'topup')),
  credits integer NOT NULL CHECK (credits > 0),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (cashfree_order_id, grant_type)
);
ALTER TABLE public.question_credit_grants ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "users_read_own_question_credits" ON public.question_credit_grants;
CREATE POLICY "users_read_own_question_credits" ON public.question_credit_grants
  FOR SELECT TO authenticated USING (auth.uid() = user_id);
GRANT SELECT ON public.question_credit_grants TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.question_credit_grants TO service_role;

-- A Cashfree order can back exactly one question. Prevent reuse, including concurrent requests.
CREATE UNIQUE INDEX IF NOT EXISTS question_usage_payment_order_id_unique
  ON public.question_usage(payment_order_id)
  WHERE payment_order_id IS NOT NULL;

CREATE OR REPLACE FUNCTION public.grant_question_credits(
  p_user_id uuid, p_cashfree_order_id text, p_grant_type text, p_credits integer
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_inserted integer;
BEGIN
  IF p_user_id IS NULL OR NULLIF(p_cashfree_order_id, '') IS NULL
     OR p_grant_type NOT IN ('premium_quota', 'topup') OR p_credits <= 0 THEN
    RAISE EXCEPTION 'Invalid question credit grant';
  END IF;

  INSERT INTO public.question_credit_grants(user_id, cashfree_order_id, grant_type, credits)
  VALUES (p_user_id, p_cashfree_order_id, p_grant_type, p_credits)
  ON CONFLICT (cashfree_order_id, grant_type) DO NOTHING;
  GET DIAGNOSTICS v_inserted = ROW_COUNT;

  IF v_inserted = 0 THEN
    RETURN jsonb_build_object('granted', false, 'reason', 'already_granted');
  END IF;

  IF p_grant_type = 'premium_quota' THEN
    UPDATE public.user_profiles
    SET free_question_quota = 2, updated_at = now()
    WHERE id = p_user_id;
  ELSE
    UPDATE public.user_profiles
    SET paid_question_balance = paid_question_balance + p_credits, updated_at = now()
    WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object('granted', true, 'grant_type', p_grant_type, 'credits', p_credits);
END;
$$;
REVOKE ALL ON FUNCTION public.grant_question_credits(uuid, text, text, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.grant_question_credits(uuid, text, text, integer) TO service_role;

-- Lifetime quota. Advisory lock serializes concurrent inserts for the same user.
CREATE OR REPLACE FUNCTION public.enforce_free_question_limit()
RETURNS trigger
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_free_count integer;
  v_has_premium boolean;
BEGIN
  IF NEW.is_free IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id::text, 0));

  SELECT EXISTS (
    SELECT 1 FROM public.entitlements
    WHERE user_id = NEW.user_id
      AND entitlement_type = 'PREMIUM'
      AND is_active = TRUE
  ) INTO v_has_premium;

  IF NOT v_has_premium THEN
    RAISE EXCEPTION 'Premium purchase required for free questions.'
      USING ERRCODE = 'P0002';
  END IF;

  SELECT COUNT(*) INTO v_free_count
  FROM public.question_usage
  WHERE user_id = NEW.user_id
    AND is_free IS TRUE
    AND id IS DISTINCT FROM NEW.id;

  IF v_free_count >= 2 THEN
    RAISE EXCEPTION 'Lifetime free question limit reached. Additional questions cost ₹59 including GST.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.user_profiles
  SET free_questions_used = v_free_count + 1,
      free_question_period = NULL,
      free_question_quota = 2,
      updated_at = now()
  WHERE id = NEW.user_id;

  RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.consume_paid_question_credit(p_question_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $$
DECLARE
  v_user_id uuid;
  v_applied boolean;
  v_is_paid boolean;
  v_balance integer;
BEGIN
  SELECT user_id, paid_credit_applied, is_paid
  INTO v_user_id, v_applied, v_is_paid
  FROM public.question_usage
  WHERE id = p_question_id
  FOR UPDATE;

  IF v_user_id IS NULL OR v_is_paid IS NOT TRUE THEN
    RETURN jsonb_build_object('consumed', false, 'reason', 'not_paid');
  END IF;

  -- Retrying the same question after an AI failure must not charge a second credit.
  IF v_applied IS TRUE THEN
    RETURN jsonb_build_object('consumed', true, 'reason', 'already_applied');
  END IF;

  SELECT paid_question_balance INTO v_balance
  FROM public.user_profiles
  WHERE id = v_user_id
  FOR UPDATE;

  IF COALESCE(v_balance, 0) < 1 THEN
    RETURN jsonb_build_object('consumed', false, 'reason', 'insufficient_balance');
  END IF;

  UPDATE public.user_profiles
  SET paid_question_balance = paid_question_balance - 1, updated_at = now()
  WHERE id = v_user_id;

  UPDATE public.question_usage
  SET paid_credit_applied = true, updated_at = now()
  WHERE id = p_question_id;

  RETURN jsonb_build_object('consumed', true, 'paid_question_balance', v_balance - 1);
END;
$$;
REVOKE ALL ON FUNCTION public.consume_paid_question_credit(uuid) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.consume_paid_question_credit(uuid) TO service_role;
