-- morning-engagement reads subscribers and writes the daily inbox row
-- with the service role. These tables had RLS and client grants, but no
-- service_role SELECT/INSERT, so PostgREST rejected the cron job.

GRANT SELECT ON TABLE public.subscriptions TO service_role;
GRANT SELECT ON TABLE public.notification_preferences TO service_role;
GRANT SELECT, INSERT ON TABLE public.notifications TO service_role;
GRANT SELECT, UPDATE ON TABLE public.users TO service_role;
