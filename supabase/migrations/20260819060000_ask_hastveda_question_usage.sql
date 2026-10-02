-- ============================================================
-- Migration: Ask HastVeda question usage tracking
-- Creates question_usage table for tracking 2 free Premium
-- questions + ₹50 per additional question purchases.
-- ============================================================

-- 1. Create question_usage table
CREATE TABLE IF NOT EXISTS public.question_usage (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  question_text text NOT NULL,
  answer_text   text,
  status        text NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending', 'answered', 'failed')),
  is_free       boolean NOT NULL DEFAULT false,
  is_paid       boolean NOT NULL DEFAULT false,
  payment_order_id text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  answered_at   timestamptz
);

-- 2. Index for fast per-user lookups
CREATE INDEX IF NOT EXISTS idx_question_usage_user_id
  ON public.question_usage(user_id);

CREATE INDEX IF NOT EXISTS idx_question_usage_user_created
  ON public.question_usage(user_id, created_at DESC);

-- 3. RLS
ALTER TABLE public.question_usage ENABLE ROW LEVEL SECURITY;

-- Users can read their own questions
DROP POLICY IF EXISTS "users_read_own_questions" ON public.question_usage;
CREATE POLICY "users_read_own_questions"
  ON public.question_usage
  FOR SELECT
  USING (auth.uid() = user_id);

-- Users can insert their own questions
DROP POLICY IF EXISTS "users_insert_own_questions" ON public.question_usage;
CREATE POLICY "users_insert_own_questions"
  ON public.question_usage
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Users can update their own questions (for payment_order_id)
DROP POLICY IF EXISTS "users_update_own_questions" ON public.question_usage;
CREATE POLICY "users_update_own_questions"
  ON public.question_usage
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Service role has full access (for edge functions writing answers)
GRANT SELECT, INSERT, UPDATE, DELETE ON public.question_usage TO service_role;
GRANT SELECT, INSERT, UPDATE ON public.question_usage TO authenticated;

-- 4. Verify
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables
    WHERE table_schema = 'public' AND table_name = 'question_usage'
  ) THEN
    RAISE NOTICE 'VERIFY OK: question_usage table created successfully';
  ELSE
    RAISE EXCEPTION 'VERIFY FAILED: question_usage table not found';
  END IF;
END $$;
