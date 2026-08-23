# Firebase / FCM setup (killed-app push)

The T-45 assign job writes `user_notifications` and calls `send-push-notification`.
For the push to reach a device when the app is **closed**, configure Firebase:

## 1. FlutterFire

```powershell
cd "D:\App projects\Hestia\hestia_consumer"
dart pub global run flutterfire_cli:flutterfire configure
```

This creates `lib/firebase_options.dart` and `android/app/google-services.json`.

## 2. Service account (FCM HTTP v1 — no Legacy Server key)

New Firebase projects have **Legacy API disabled**. Use a service account instead:

1. Firebase Console → **hestia-consumer**
2. ⚙️ **Project settings** → **Service accounts**
3. Click **Generate new private key** → downloads a `.json` file
4. Set it as a Supabase secret (from `D:\App projects\Hestia`):

```powershell
cd "D:\App projects\Hestia"
$json = Get-Content -Raw -Path "C:\path\to\hestia-consumer-firebase-adminsdk-xxxxx.json"
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$json"
```

5. Redeploy the push function:

```powershell
supabase functions deploy send-push-notification
```

**Do not commit the JSON file to git.**

## 3. Deploy + schedule

```powershell
supabase functions deploy assign-professionals
supabase functions deploy send-push-notification
```

Schedule `assign-professionals`:
1. If Cron UI errors with `cron.job does not exist`, run `supabase/migrations/20260717b_enable_cron_extensions.sql` in SQL Editor
2. Dashboard → **Integrations** → **Cron** → Create job → every 2 min → Edge Function `assign-professionals`
3. Or run `supabase/migrations/20260718_assign_professionals_cron.sql` in SQL Editor

## 4. Verify

1. Run app, sign in → row in `device_tokens`
2. Book ~50 min ahead → `professional_id` null, `assignment_status = pending`
3. Wait for cron → pro assigned + push on device (even if app closed)
