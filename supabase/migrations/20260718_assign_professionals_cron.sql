-- Schedule assign-professionals every 2 minutes (T-45 assignment job)
--
-- Run in Supabase Dashboard → SQL Editor
-- Replace YOUR_SERVICE_ROLE_KEY with your project's service role key
-- (Dashboard → Project Settings → API → service_role secret)
--
-- Prerequisite: run 20260717b_enable_cron_extensions.sql first if cron.job does not exist.

-- Remove old job if re-running (safe to run even when job missing)
select cron.unschedule(jobid)
from cron.job
where jobname = 'assign-professionals-t45';

select cron.schedule(
  'assign-professionals-t45',
  '*/2 * * * *',
  $$
  select net.http_post(
    url := 'https://xsuqhcnvmounyyesdoek.supabase.co/functions/v1/assign-professionals',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
    ),
    body := '{}'::jsonb,
    timeout_milliseconds := 30000
  ) as request_id;
  $$
);

-- Verify job exists:
-- select * from cron.job where jobname = 'assign-professionals-t45';
