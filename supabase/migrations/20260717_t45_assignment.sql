-- T-45 professional assignment + FCM device tokens
-- Apply on Supabase SQL editor or via `supabase db push`

-- Bookings: defer assignment metadata
ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS user_id uuid REFERENCES auth.users(id) ON DELETE SET NULL;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS assigned_at timestamp with time zone;

ALTER TABLE public.bookings
  ADD COLUMN IF NOT EXISTS assignment_status text NOT NULL DEFAULT 'pending';

COMMENT ON COLUMN public.bookings.assignment_status IS
  'pending | assigned | unassigned_failed';

CREATE INDEX IF NOT EXISTS bookings_t45_assign_idx
  ON public.bookings (status, assignment_status, scheduled_date, scheduled_time)
  WHERE professional_id IS NULL;

-- Device tokens for FCM push when app is killed / backgrounded
CREATE TABLE IF NOT EXISTS public.device_tokens (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  token text NOT NULL,
  platform text NOT NULL DEFAULT 'android',
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT device_tokens_pkey PRIMARY KEY (id),
  CONSTRAINT device_tokens_user_token_unique UNIQUE (user_id, token)
);

CREATE INDEX IF NOT EXISTS device_tokens_user_id_idx
  ON public.device_tokens (user_id);

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage own device tokens" ON public.device_tokens;
CREATE POLICY "Users manage own device tokens" ON public.device_tokens
  FOR ALL
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Service role / edge functions insert notifications; users read/update own rows
-- (user_notifications policies already exist in user_notifications_migration.sql)

-- Optional: cron invocation helper notes
-- Schedule Edge Function `assign-professionals` every 2–5 minutes via
-- Supabase Dashboard → Edge Functions → Schedules, or pg_cron + net.http_post:
--
--   select cron.schedule(
--     'assign-professionals-t45',
--     '*/2 * * * *',
--     $$
--     select net.http_post(
--       url := 'https://<PROJECT_REF>.supabase.co/functions/v1/assign-professionals',
--       headers := jsonb_build_object(
--         'Content-Type', 'application/json',
--         'Authorization', 'Bearer <SERVICE_ROLE_KEY>'
--       ),
--       body := '{}'::jsonb
--     );
--     $$
--   );
