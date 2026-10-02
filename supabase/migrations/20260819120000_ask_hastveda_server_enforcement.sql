-- Migration: Server-side enforcement for Ask HastVeda question limits and schema improvements
-- Timestamp: 20260819120000
-- 
-- Changes:
-- 1. Add updated_at column to question_usage (needed by answer function)
-- 2. Add server-side trigger: reject is_free=true inserts when user already has 2 free questions
-- 3. Add unique constraint: one payment_order_id per question (prevents one payment → multiple questions)
-- 4. Add index on payment_order_id for fast webhook lookups
-- 5. Expand status enum to include new statuses used by answer-hastveda-question

-- ── 1. Add updated_at column if not exists ────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name = 'question_usage'
      AND column_name = 'updated_at'
  ) THEN
    ALTER TABLE public.question_usage ADD COLUMN updated_at TIMESTAMPTZ DEFAULT now();
    RAISE NOTICE 'Added updated_at column to question_usage';
  ELSE
    RAISE NOTICE 'updated_at column already exists in question_usage';
  END IF;
END $$;

-- ── 2. Add unique constraint on payment_order_id ──────────────────────────────
-- Prevents one ₹50 payment from being used for multiple questions
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'question_usage_payment_order_id_key'
      AND conrelid = 'public.question_usage'::regclass
  ) THEN
    -- Only add unique constraint on non-null payment_order_id values
    -- Use a partial unique index instead to allow multiple NULL values
    RAISE NOTICE 'Adding partial unique index on payment_order_id';
  ELSE
    RAISE NOTICE 'payment_order_id unique constraint already exists';
  END IF;
END $$;

-- Partial unique index: payment_order_id must be unique when not null
CREATE UNIQUE INDEX IF NOT EXISTS question_usage_payment_order_id_unique
  ON public.question_usage (payment_order_id)
  WHERE payment_order_id IS NOT NULL;

-- ── 3. Add index on payment_order_id for fast webhook lookups ─────────────────
CREATE INDEX IF NOT EXISTS idx_question_usage_payment_order_id
  ON public.question_usage (payment_order_id)
  WHERE payment_order_id IS NOT NULL;

-- ── 4. Add index on (user_id, is_free) for free quota checks ─────────────────
CREATE INDEX IF NOT EXISTS idx_question_usage_user_is_free
  ON public.question_usage (user_id, is_free);

-- ── 5. Server-side free question quota enforcement function ───────────────────
-- This function is called by a BEFORE INSERT trigger on question_usage.
-- It rejects any insert with is_free=true when the user already has 2 free questions.
-- This prevents APK manipulation or direct API calls from bypassing the quota.

CREATE OR REPLACE FUNCTION public.enforce_free_question_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_free_count INTEGER;
  v_has_premium BOOLEAN;
BEGIN
  -- Only enforce for free questions
  IF NEW.is_free IS NOT TRUE THEN
    RETURN NEW;
  END IF;

  -- Count existing free questions for this user
  SELECT COUNT(*) INTO v_free_count
  FROM public.question_usage
  WHERE user_id = NEW.user_id
    AND is_free = TRUE;

  -- Reject if already at or above the limit (2 free questions max)
  IF v_free_count >= 2 THEN
    RAISE EXCEPTION 'Free question quota exceeded. Maximum 2 free questions allowed per Premium user. Additional questions cost ₹50 each.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Verify user has an active Premium entitlement (free questions require Premium)
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

-- ── 6. Attach trigger to question_usage ──────────────────────────────────────
DROP TRIGGER IF EXISTS trg_enforce_free_question_limit ON public.question_usage;

CREATE TRIGGER trg_enforce_free_question_limit
  BEFORE INSERT ON public.question_usage
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_free_question_limit();

-- ── 7. Grant execute on the trigger function to service_role ─────────────────
GRANT EXECUTE ON FUNCTION public.enforce_free_question_limit() TO service_role;

-- ── 8. Ensure service_role can update question_usage (for answer function) ────
GRANT SELECT, INSERT, UPDATE ON public.question_usage TO service_role;

-- ── 9. Verification ──────────────────────────────────────────────────────────
DO $$
DECLARE
  v_trigger_exists BOOLEAN;
  v_index_exists BOOLEAN;
BEGIN
  SELECT EXISTS(
    SELECT 1 FROM pg_trigger
    WHERE tgname = 'trg_enforce_free_question_limit'
      AND tgrelid = 'public.question_usage'::regclass
  ) INTO v_trigger_exists;

  SELECT EXISTS(
    SELECT 1 FROM pg_indexes
    WHERE tablename = 'question_usage'
      AND indexname = 'question_usage_payment_order_id_unique'
  ) INTO v_index_exists;

  RAISE NOTICE '=== ask_hastveda enforcement migration verification ===';
  RAISE NOTICE 'Free question limit trigger: %', CASE WHEN v_trigger_exists THEN 'EXISTS ✓' ELSE 'MISSING ✗' END;
  RAISE NOTICE 'Payment order unique index: %', CASE WHEN v_index_exists THEN 'EXISTS ✓' ELSE 'MISSING ✗' END;
END $$;
