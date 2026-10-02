-- ============================================================
-- Backfill missing user_profiles rows
-- Fixes: create-cashfree-order "User profile not found" error
-- Root cause: handle_new_user trigger did not fire for users
-- created via Supabase dashboard or imported directly.
-- ============================================================

-- Step 1: Insert missing user_profiles for any auth.users
-- that do not yet have a corresponding row.
INSERT INTO public.user_profiles (id, email, full_name, avatar_url, created_at, updated_at)
SELECT
  au.id,
  au.email,
  COALESCE(au.raw_user_meta_data->>'full_name', split_part(au.email, '@', 1), 'HastVeda User'),
  COALESCE(au.raw_user_meta_data->>'avatar_url', NULL),
  au.created_at,
  NOW()
FROM auth.users au
WHERE NOT EXISTS (
  SELECT 1 FROM public.user_profiles up WHERE up.id = au.id
)
ON CONFLICT (id) DO NOTHING;

-- Step 2: Also ensure the public.users (device/session table) row exists
-- for any user_profiles that are missing it.
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

-- Step 4: Preserve admin role in raw_app_meta_data for saxenavs007@gmail.com
-- This is a no-op if the role is already set; it only adds it if missing.
UPDATE auth.users
SET raw_app_meta_data = COALESCE(raw_app_meta_data, '{}'::jsonb) || '{"role":"admin"}'::jsonb
WHERE email = 'saxenavs007@gmail.com'
  AND (raw_app_meta_data->>'role' IS NULL OR raw_app_meta_data->>'role' != 'admin');

-- Step 5: Strengthen handle_new_user trigger to be idempotent
-- (uses ON CONFLICT DO NOTHING so re-runs never fail)
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
