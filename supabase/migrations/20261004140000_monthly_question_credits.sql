-- Premium free questions reset every IST calendar month.
-- Paid ₹50 + GST purchases add to paid_question_balance with no monthly cap.
-- Answering a paid question consumes one stored credit, once.

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS free_questions_used integer NOT NULL DEFAULT 0;

ALTER TABLE public.user_profiles
  ADD COLUMN IF NOT EXISTS free_question_period date;

ALTER TABLE public.question_usage
  ADD COLUMN IF NOT EXISTS paid_credit_applied boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.enforce_free_question_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_free_count INTEGER;
  v_has_premium BOOLEAN;
  v_month_start timestamptz;
  v_period date;
BEGIN
  IF NEW.is_free IS NOT TRUE THEN
    RETURN NEW;
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

  v_month_start := date_trunc('month', now() AT TIME ZONE 'Asia/Kolkata')
    AT TIME ZONE 'Asia/Kolkata';
  v_period := (date_trunc('month', now() AT TIME ZONE 'Asia/Kolkata'))::date;

  SELECT COUNT(*) INTO v_free_count
  FROM public.question_usage
  WHERE user_id = NEW.user_id
    AND is_free IS TRUE
    AND created_at >= v_month_start;

  IF v_free_count >= 2 THEN
    RAISE EXCEPTION 'Free question quota exceeded. Premium includes 2 free questions each month. Additional questions cost ₹50 + GST each.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.user_profiles
  SET free_questions_used = v_free_count + 1,
      free_question_period = v_period,
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

  UPDATE public.user_profiles
  SET paid_question_balance = GREATEST(paid_question_balance - 1, 0),
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
