-- Reschedule morning-engagement so pg_cron + pg_net call the live function.
-- 08:00 and 08:15 Asia/Kolkata are 02:30 and 02:45 UTC.
--
-- Vault secrets are read when the job fires:
--   cron_secret — same value as the CRON_SECRET edge function secret
--   anon_key    — project anon or publishable key, sent as apikey
--
-- verify_jwt is off for this function. The gateway still expects apikey.
-- The function accepts x-cron-secret (and a Bearer token only when that
-- token itself is the cron secret).

DO $schedule$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_cron') THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_cron;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'morning-engagement cron was not updated: enable pg_cron (%).', SQLERRM;
      RETURN;
    END;
  END IF;

  IF NOT EXISTS (SELECT 1 FROM pg_extension WHERE extname = 'pg_net') THEN
    BEGIN
      CREATE EXTENSION IF NOT EXISTS pg_net;
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'morning-engagement cron was not updated: enable pg_net (%).', SQLERRM;
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
END
$schedule$;
