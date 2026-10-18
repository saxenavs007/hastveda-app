-- Harden HastVeda lifetime question enforcement.
-- Premium grants exactly two lifetime free questions; no calendar/month reset.
-- Serialize per-user free-question inserts to prevent concurrent requests exceeding the quota.
-- Never mark a paid credit consumed when the user's balance is zero.

CREATE OR REPLACE FUNCTION public.enforce_free_question_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_free_count integer;
  v_has_premium boolean;
BEGIN
  IF NEW.is_free IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Transaction-scoped lock serializes quota checks for this user.
  PERFORM pg_advisory_xact_lock(hashtextextended(NEW.user_id::text, 0));

  SELECT EXISTS (
    SELECT 1
    FROM public.entitlements
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

CREATE OR REPLACE FUNCTION public.consume_paid_question_credit(
  p_question_id uuid
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
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

  IF v_applied IS TRUE THEN
    RETURN jsonb_build_object('consumed', false, 'reason', 'already_applied');
  END IF;

  -- Lock the profile row and reject zero-balance consumption.
  SELECT paid_question_balance INTO v_balance
  FROM public.user_profiles
  WHERE id = v_user_id
  FOR UPDATE;

  IF COALESCE(v_balance, 0) < 1 THEN
    RETURN jsonb_build_object('consumed', false, 'reason', 'insufficient_balance');
  END IF;

  UPDATE public.user_profiles
  SET paid_question_balance = paid_question_balance - 1,
      updated_at = now()
  WHERE id = v_user_id
  RETURNING paid_question_balance INTO v_balance;

  UPDATE public.question_usage
  SET paid_credit_applied = true,
      updated_at = now()
  WHERE id = p_question_id;

  RETURN jsonb_build_object(
    'consumed', true,
    'paid_question_balance', COALESCE(v_balance, 0)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.consume_paid_question_credit(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.consume_paid_question_credit(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.consume_paid_question_credit(uuid) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.consume_paid_question_credit(uuid) TO service_role;
