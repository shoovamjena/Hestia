-- Enable Supabase Cron + HTTP calls to Edge Functions.
-- Run this FIRST in SQL Editor if you see: relation "cron.job" does not exist

create extension if not exists pg_cron with schema pg_catalog;

grant usage on schema cron to postgres;
grant all privileges on all tables in schema cron to postgres;

-- Required for net.http_post() when invoking Edge Functions from cron
create extension if not exists pg_net with schema extensions;
