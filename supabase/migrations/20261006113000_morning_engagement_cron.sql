-- 08:00 Asia/Kolkata morning-engagement run, with one retry at 08:15.
-- pg_cron is UTC, so 02:30 and 02:45.
--
-- The job reads these vault secrets when it fires (not at migration time):
--   cron_secret — same value as the CRON_SECRET edge function secret
--   anon_key    — project anon or publishable key, sent as apikey
--
-- A missing secret is logged by the function as an unauthorized cron call
-- instead of a silent no-op. Inbox rows and push retries are idempotent,
-- so the 08:15 run only delivers pushes the 08:00 run did not finish.

GRANT SELECT ON TABLE public.user_profiles TO service_role;
GRANT SELECT ON TABLE public.subscriptions TO service_role;
GRANT SELECT ON TABLE public.entitlements TO service_role;
GRANT SELECT ON TABLE public.notification_preferences TO service_role;
GRANT SELECT ON TABLE public.palm_analysis TO service_role;
GRANT SELECT, INSERT, UPDATE ON TABLE public.notifications TO service_role;
GRANT SELECT, UPDATE ON TABLE public.users TO service_role;

-- One morning curiosity row per subscriber per IST day. The 08:15 retry
-- can finish a push without inserting a second inbox notification.
DELETE FROM public.notifications
WHERE id IN (
  SELECT id FROM (
    SELECT
      id,
      row_number() OVER (
        PARTITION BY user_id, data->>'ist_date'
        ORDER BY created_at DESC, id DESC
      ) AS rn
    FROM public.notifications
    WHERE data->>'kind' = 'morning_curiosity'
  ) ranked
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS notifications_one_morning_curiosity_per_day
  ON public.notifications (user_id, ((data->>'ist_date')))
  WHERE (data->>'kind') = 'morning_curiosity';

DO $schedule$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'morning-engagement cron was not scheduled: enable pg_cron (%).', SQLERRM;
      RETURN;
    END;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'morning-engagement cron was not scheduled: enable pg_net (%).', SQLERRM;
      RETURN;
    END;
  END IF;

  IF EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'morning-engagement') THEN
    PERFORM cron.unschedule('morning-engagement');
  END IF;

  PERFORM cron.schedule(
    'morning-engagement',
    '30,45 2 * * *',
    $cmd$
    SELECT net.http_post(
      url := 'https://rizmfltarfwthysktjjz.supabase.co/functions/v1/morning-engagement',
      headers := (
        SELECT jsonb_strip_nulls(jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', apikey,
          'Authorization', CASE
            WHEN apikey LIKE '%.%.%' THEN 'Bearer ' || apikey
            ELSE NULL
          END,
          'x-cron-secret', cron_secret
        ))
        FROM (
          SELECT
            (
              SELECT decrypted_secret
              FROM vault.decrypted_secrets
              WHERE name IN ('anon_key', 'supabase_anon_key')
              ORDER BY CASE name WHEN 'anon_key' THEN 0 ELSE 1 END
              LIMIT 1
            ) AS apikey,
            (
              SELECT decrypted_secret
              FROM vault.decrypted_secrets
              WHERE name = 'cron_secret'
              LIMIT 1
            ) AS cron_secret
        ) keys
      ),
      body := '{}'::jsonb,
      timeout_milliseconds := 150000
    );
    $cmd$
  );

  BEGIN
    IF NOT EXISTS (
      SELECT 1 FROM vault.decrypted_secrets WHERE name = 'cron_secret'
    ) THEN
      RAISE WARNING 'morning-engagement is scheduled, but vault secret cron_secret is missing. The 08:00 call will be rejected until it matches CRON_SECRET.';
    END IF;
    IF NOT EXISTS (
      SELECT 1
      FROM vault.decrypted_secrets
      WHERE name IN ('anon_key', 'supabase_anon_key')
    ) THEN
      RAISE WARNING 'morning-engagement is scheduled, but vault secret anon_key is missing. The API gateway will reject the call until it is stored.';
    END IF;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'morning-engagement is scheduled, but vault secrets could not be checked (%).', SQLERRM;
  END;
END
$schedule$;
