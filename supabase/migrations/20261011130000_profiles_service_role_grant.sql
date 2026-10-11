-- morning-engagement queries as service_role. That role bypasses RLS, but
-- PostgreSQL still requires a table GRANT. A missing GRANT is reported as
-- "permission denied for table profiles".

GRANT SELECT ON TABLE public.user_profiles TO service_role;
GRANT SELECT, UPDATE ON TABLE public.users TO service_role;

DO $grant_profiles$
BEGIN
  IF to_regclass('public.profiles') IS NOT NULL THEN
    EXECUTE 'GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE public.profiles TO service_role';
  END IF;
END
$grant_profiles$;
