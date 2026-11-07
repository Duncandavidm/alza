-- Job diario 8:15 a.m. Panama (13:15 UTC), despues de verify-dgi-receipts:
-- suma puntos por habitos y avisa por push los premios que ya alcanzan.
select cron.unschedule(jobid) from cron.job where jobname = 'daily-habit-points-and-unlocks';
select cron.schedule('daily-habit-points-and-unlocks', '15 13 * * *', $c$
  select net.http_post(
    url := 'https://jfhevxztsvnlsuwkwtmd.supabase.co/functions/v1/award-habit-points',
    headers := jsonb_build_object('Content-Type','application/json',
      'x-admin-secret', (select decrypted_secret from vault.decrypted_secrets where name = 'admin_job_secret')),
    body := '{}'::jsonb, timeout_milliseconds := 120000);
$c$);
