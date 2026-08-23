# Supabase Edge Functions — T-45 assignment + FCM push

## Hub coverage (7 km) — server authority

Run [`migrations/20260722_hub_coverage_radius.sql`](../migrations/20260722_hub_coverage_radius.sql)
in the SQL Editor, then redeploy:

```bash
supabase functions deploy assign-professionals
```

This adds:
- `addresses.latitude` / `longitude`
- `resolve_hub_coverage(lat, lng)` RPC
- triggers that set `zone_verified` from distance (app cannot spoof)
- booking insert blocked outside coverage
- `assign-professionals` skips bookings outside 7 km

## Deploy

```bash
cd "d:/App projects/Hestia"
supabase functions deploy assign-professionals
supabase functions deploy send-push-notification
```

## Schedule `assign-professionals`

Supabase does **not** put cron on the Edge Function detail page. Use one of:

### Prerequisite — enable pg_cron

If you see `relation "cron.job" does not exist`, run
[`migrations/20260717b_enable_cron_extensions.sql`](../migrations/20260717b_enable_cron_extensions.sql)
in the SQL Editor first, then refresh the Cron page.

### Option A — Dashboard UI
1. **Integrations** → **Cron** (left sidebar)
2. **Create job**
3. Name: `assign-professionals-t45`
4. Schedule: `*/2 * * * *` (every 2 minutes)
5. Type: **Supabase Edge Function** → select `assign-professionals`
6. Save

### Option B — SQL (`pg_cron` + `pg_net`)

Run [`migrations/20260718_assign_professionals_cron.sql`](../migrations/20260718_assign_professionals_cron.sql)
in the SQL Editor (replace `YOUR_SERVICE_ROLE_KEY`).

Or paste this directly:

```sql
select cron.schedule(
  'assign-professionals-t45',
  '*/2 * * * *',
  $$
  select net.http_post(
    url := 'https://YOUR_PROJECT_REF.supabase.co/functions/v1/assign-professionals',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer YOUR_SERVICE_ROLE_KEY'
    ),
    body := '{}'::jsonb
  );
  $$
);
```

## Apply DB migration

Run [`migrations/20260717_t45_assignment.sql`](../migrations/20260717_t45_assignment.sql)
in the SQL editor.
