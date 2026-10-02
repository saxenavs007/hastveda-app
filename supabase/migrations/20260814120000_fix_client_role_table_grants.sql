-- Fix missing table-level GRANTs for the client roles.
--
-- Every table in this schema has RLS enabled and a matching policy, but most
-- never received a table-level GRANT, so PostgREST rejects the request with
-- "permission denied for table X" (403) before RLS is ever consulted. A policy
-- grants nothing on its own — it only narrows what an existing privilege can
-- reach. 20260813000000_fix_palm_scans_grants.sql patched palm_scans for this
-- exact reason; the rest of the tables were left behind, which is why signing
-- in still yields 403s on entitlements and analytics_events.
--
-- The privileges below mirror each table's declared policy (FOR ALL vs
-- FOR SELECT vs FOR INSERT), so this widens nothing beyond the stated intent.
-- RLS continues to scope every statement to the caller's own rows.

GRANT USAGE ON SCHEMA public TO authenticated, anon;

-- FOR ALL policies — full row-scoped access to the user's own records.
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLE
  public.couple_readings,
  public.notification_preferences,
  public.notifications,
  public.palm_analysis,
  public.palm_features,
  public.palm_profiles,
  public.palm_scans,
  public.prediction_feedback,
  public.purchases,
  public.reading_history,
  public.reports,
  public.subscriptions,
  public.user_profiles,
  public.users
TO authenticated;

-- FOR SELECT + FOR INSERT policies.
GRANT SELECT, INSERT ON TABLE
  public.ai_usage,
  public.predictions
TO authenticated;

-- FOR SELECT policies — read-only.
GRANT SELECT ON TABLE
  public.app_settings,
  public.audit_logs,
  public.entitlements
TO authenticated;

-- FOR INSERT policy — write-only telemetry sink.
GRANT INSERT ON TABLE public.analytics_events TO authenticated;

-- Guest mode: allow unattributed analytics events only.
--
-- analytics_events had an INSERT policy for `authenticated` alone, so events
-- fired before sign-in (and throughout guest mode) were rejected. Guests may
-- insert rows not attributed to any user; they still cannot forge another
-- user's id, and the table stays insert-only for both roles.
DROP POLICY IF EXISTS "anon_insert_analytics_events" ON public.analytics_events;
CREATE POLICY "anon_insert_analytics_events"
ON public.analytics_events FOR INSERT TO anon
WITH CHECK (user_id IS NULL);

GRANT INSERT ON TABLE public.analytics_events TO anon;
