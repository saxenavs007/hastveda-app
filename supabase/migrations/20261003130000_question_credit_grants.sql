-- Idempotent Q&A credits granted by Cashfree verify + webhook.
-- Premium sets a 2-question free quota. A ₹50 top-up adds 1 paid credit.
-- The unique order key stops verify and webhook from granting twice.

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
CREATE POLICY "users_read_own_question_credits"
  ON public.question_credit_grants
  FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

GRANT SELECT ON public.question_credit_grants TO authenticated;
GRANT SELECT, INSERT, UPDATE ON public.question_credit_grants TO service_role;

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS free_question_quota integer NOT NULL DEFAULT 0;

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS paid_question_balance integer NOT NULL DEFAULT 0;

CREATE OR REPLACE FUNCTION public.grant_question_credits(
  p_user_id uuid,
  p_cashfree_order_id text,
  p_grant_type text,
  p_credits integer
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_inserted integer;
BEGIN
  IF p_grant_type NOT IN ('premium_quota', 'topup') OR p_credits <= 0 THEN
    RAISE EXCEPTION 'Invalid question credit grant';
  END IF;

  INSERT INTO public.question_credit_grants (
    user_id, cashfree_order_id, grant_type, credits
  )
  VALUES (p_user_id, p_cashfree_order_id, p_grant_type, p_credits)
  ON CONFLICT (cashfree_order_id, grant_type) DO NOTHING;

  GET DIAGNOSTICS v_inserted = ROW_COUNT;
  IF v_inserted = 0 THEN
    RETURN jsonb_build_object('granted', false, 'reason', 'already_granted');
  END IF;

  IF p_grant_type = 'premium_quota' THEN
    UPDATE public.user_profiles
    SET free_question_quota = GREATEST(free_question_quota, p_credits),
        updated_at = now()
    WHERE id = p_user_id;
  ELSE
    UPDATE public.user_profiles
    SET paid_question_balance = paid_question_balance + p_credits,
        updated_at = now()
    WHERE id = p_user_id;
  END IF;

  RETURN jsonb_build_object(
    'granted', true,
    'grant_type', p_grant_type,
    'credits', p_credits
  );
END;
$$;

REVOKE ALL ON FUNCTION public.grant_question_credits(uuid, text, text, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.grant_question_credits(uuid, text, text, integer) FROM anon;
REVOKE ALL ON FUNCTION public.grant_question_credits(uuid, text, text, integer) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.grant_question_credits(uuid, text, text, integer) TO service_role;

-- Free questions follow the quota written at premium purchase.
-- Existing premium users with quota 0 keep the original allowance of 2.
CREATE OR REPLACE FUNCTION public.enforce_free_question_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_free_count INTEGER;
  v_has_premium BOOLEAN;
  v_quota INTEGER;
  v_profile_quota INTEGER;
BEGIN
  IF NEW.is_free IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  SELECT COUNT(*) INTO v_free_count
  FROM public.question_usage
  WHERE user_id = NEW.user_id
    AND is_free = TRUE;

  v_quota := 2;
  SELECT free_question_quota INTO v_profile_quota
  FROM public.user_profiles
  WHERE id = NEW.user_id;

  IF v_profile_quota IS NOT NULL AND v_profile_quota > v_quota THEN
    v_quota := v_profile_quota;
  END IF;

  IF v_free_count >= v_quota THEN
    RAISE EXCEPTION 'Free question quota exceeded. Maximum % free questions allowed per Premium user. Additional questions cost ₹50 each.', v_quota
      USING ERRCODE = 'P0001';
  END IF;

  SELECT EXISTS(
    SELECT 1 FROM public.entitlements
    WHERE user_id = NEW.user_id
      AND entitlement_type = 'PREMIUM'
      AND is_active = TRUE
  ) INTO v_has_premium;

  IF NOT v_has_premium THEN
    RAISE EXCEPTION 'Premium subscription required to ask free questions.'
      USING ERRCODE = 'P0002';
  END IF;

  RETURN NEW;
END;
$$;
