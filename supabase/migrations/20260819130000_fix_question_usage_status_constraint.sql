-- Migration: Fix question_usage status CHECK constraint
-- Timestamp: 20260819130000
--
-- Problem: The original migration (20260819060000) created question_usage with:
--   status CHECK (status IN ('pending', 'answered', 'failed'))
--
-- But the application uses these additional status values:
--   'awaiting_payment'                  — question row created, payment not yet started
--   'processing'                        — AI is generating the answer
--   'payment_cancelled'                 — user cancelled/abandoned payment
--   'payment_received_pending_question' — webhook received payment but app closed before question text saved
--   'rejected_free_quota_exceeded'      — server rejected: user already has 2 free questions
--   'rejected_no_premium'               — server rejected: user does not have Premium
--   'failed_empty_question'             — question text was empty
--
-- Fix: Drop the old CHECK constraint and add a new one with all valid values.
-- This migration is idempotent.

DO $$
DECLARE
  v_constraint_name text;
BEGIN
  -- Find the existing status check constraint on question_usage
  SELECT conname INTO v_constraint_name
  FROM pg_constraint
  WHERE conrelid = 'public.question_usage'::regclass
    AND contype = 'c'
    AND pg_get_constraintdef(oid) LIKE '%status%';

  IF v_constraint_name IS NOT NULL THEN
    EXECUTE format('ALTER TABLE public.question_usage DROP CONSTRAINT %I', v_constraint_name);
    RAISE NOTICE 'Dropped old status constraint: %', v_constraint_name;
  ELSE
    RAISE NOTICE 'No existing status constraint found — nothing to drop';
  END IF;
END $$;

-- Add the expanded CHECK constraint with all valid status values
ALTER TABLE public.question_usage
  ADD CONSTRAINT question_usage_status_check
  CHECK (status IN (
    'pending',
    'answered',
    'failed',
    'processing',
    'awaiting_payment',
    'payment_cancelled',
    'payment_received_pending_question',
    'rejected_free_quota_exceeded',
    'rejected_no_premium',
    'failed_empty_question'
  ));

-- Verify
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conrelid = 'public.question_usage'::regclass
      AND conname = 'question_usage_status_check'
  ) THEN
    RAISE NOTICE 'VERIFY OK: question_usage_status_check constraint created successfully';
  ELSE
    RAISE EXCEPTION 'VERIFY FAILED: question_usage_status_check constraint not found';
  END IF;
END $$;
