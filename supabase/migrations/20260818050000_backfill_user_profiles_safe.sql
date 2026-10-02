-- ============================================================
-- Safe backfill of missing user_profiles rows
-- Version 2: handles UNIQUE constraint on email column
-- Root cause of v1 failure: ON CONFLICT (id) DO NOTHING does
-- NOT protect against the UNIQUE constraint on email. If any
-- existing user_profiles row has the same email as an auth.users
-- row with a different UUID, the INSERT raises a unique_violation
-- and the entire migration transaction aborts.
--
-- Fix: guard each INSERT with WHERE NOT EXISTS on BOTH id AND email
-- so rows that would violate either constraint are simply skipped.
-- ============================================================

-- Step 1: Insert missing user_profiles, skipping rows where
-- either the id OR the email already exists in user_profiles.
INSERT INTO public.user_profiles (id, email, full_name, avatar_url, created_at, updated_at)
SELECT
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.email, '@', 1), 'HastVeda User'),
  COALESCE(au.raw_user_meta_data->>'avatar_url', NULL),
  au.created_at,
  NOW()
FROM auth.users au
WHERE
  -- Skip if a profile already exists for this auth UUID
  NOT EXISTS (SELECT 1 FROM public.user_profiles up WHERE up.id = au.id)
  -- Also skip if another profile already owns this email (avoids unique_violation abort)
  AND NOT EXISTS (SELECT 1 FROM public.user_profiles up WHERE up.email = au.email)
ON CONFLICT (id) DO NOTHING;

-- Step 2: Ensure public.users row exists for every user_profiles row.
INSERT INTO public.users (id, created_at, updated_at)
SELECT
  up.id,
  up.created_at,
  NOW()
FROM public.user_profiles up
WHERE NOT EXISTS (
  SELECT 1 FROM public.users u WHERE u.id = up.id
)
ON CONFLICT (id) DO NOTHING;

-- Step 3: Ensure notification_preferences row exists for all profiles.
INSERT INTO public.notification_preferences (user_id, created_at, updated_at)
SELECT
  up.id,
  up.created_at,
  NOW()
FROM public.user_profiles up
WHERE NOT EXISTS (
  SELECT 1 FROM public.notification_preferences np WHERE np.user_id = up.id
)
ON CONFLICT (user_id) DO NOTHING;

-- Step 4: Preserve / restore admin role for saxenavs007@gmail.com.
-- This is a no-op if the role is already set correctly.
UPDATE auth.users
SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
WHERE email = 'saxenavs007@gmail.com';

-- Step 5: Strengthen handle_new_user trigger to be fully idempotent.
-- ON CONFLICT (id) DO NOTHING prevents duplicate-key errors on re-runs.
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
    COALESCE(NEW.raw_user_meta_data->>'avatar_url', NULL)
  )
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.users (id)
  VALUES (NEW.id)
  ON CONFLICT (id) DO NOTHING;

  INSERT INTO public.notification_preferences (user_id)
  VALUES (NEW.id)
  ON CONFLICT (user_id) DO NOTHING;

  RETURN NEW;
END;
$$;

-- Step 6: Diagnostic verification — log counts after backfill.
-- (These DO blocks run at migration time and are visible in migration logs.)
DO $$
DECLARE
  v_auth_count   INT;
  v_profile_count INT;
  v_target_id    UUID;
  v_target_profile_id UUID;
BEGIN
  SELECT COUNT(*) INTO v_auth_count FROM auth.users;
  SELECT COUNT(*) INTO v_profile_count FROM public.user_profiles;

  RAISE NOTICE 'Backfill complete: auth.users=%, public.user_profiles=%', v_auth_count, v_profile_count;

  -- Verify saxenavs007@gmail.com specifically
  SELECT id INTO v_target_id FROM auth.users WHERE email = 'saxenavs007@gmail.com';
  SELECT id INTO v_target_profile_id FROM public.user_profiles WHERE id = v_target_id;

  IF v_target_id IS NULL THEN
    RAISE NOTICE 'VERIFY: saxenavs007@gmail.com NOT found in auth.users';
  ELSIF v_target_profile_id IS NULL THEN
    RAISE WARNING 'VERIFY: saxenavs007@gmail.com auth.users.id=% has NO matching user_profiles row', v_target_id;
  ELSE
    RAISE NOTICE 'VERIFY OK: saxenavs007@gmail.com auth.users.id=% = user_profiles.id=%', v_target_id, v_target_profile_id;
  END IF;
END;
$$;
