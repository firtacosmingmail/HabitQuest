# HabitQuest admin console (`admin/`)

A small Flutter **web** app for the HabitQuest admins: manage the daily
quotes and look at aggregated usage stats. It is a separate Flutter app with
its own `pubspec.yaml`; nothing here is imported by the mobile app in `lib/`,
so it never ships inside the iOS/Android builds. See the
[root README](../README.md#admin-web-console) for why it is separate.

## Screens

- **Sign-in**: email + password through the same Supabase auth as the app
  (`auth-login`). Right after, the console calls `GET /admin-stats/me`; anyone
  who is not an admin (service role or an email in `QUOTE_ADMINS`) sees
  **Not authorised** and no data. The server checks the admin again on every
  call. The session lives in memory only (reload = sign out).
- **Quotes**: every quote (past, today, upcoming, unscheduled) with its love
  count; search (text or author), date-range filter, scheduled/unscheduled
  filter; create, edit and reschedule (`POST`/`PUT /quotes`), unschedule
  (`PUT /quotes?id=` `{"day": null}`) and delete (`DELETE /admin-quotes`).
- **Schedule**: the coming 4/8/12 weeks as a calendar; days without a quote
  (gaps, which fall back to cycling) are flagged, and tapping one schedules a
  quote on it.
- **Stats**: totals, sign-ups per day/week, DAU/WAU (from completed
  check-ins), habits created, completions per day, XP and best-streak
  distributions, levels, quote loves per day and the most-loved quotes, with
  range presets and a custom date-range picker (`GET /admin-stats`).
  Widget usage is not recorded by the backend, which the dashboard says.

Endpoints: [supabase/API.md](../supabase/API.md#admin).

## Run

```sh
cd admin
flutter pub get
flutter run -d chrome --dart-define=ADMIN_DEMO=true     # fake data, no backend
flutter run -d chrome                                   # live project
flutter run -d chrome --dart-define-from-file=../env/dev.json   # other project
```

Demo mode signs in `admin@example.com` (password `demo`); any other email
shows "Not authorised". The defines `SUPABASE_URL` / `SUPABASE_ANON_KEY`
override the backend (default: the live project, as in the mobile app). Only
the public anon key is ever in the client, never the service-role key.

## Checks

```sh
cd admin
flutter analyze
flutter test
```

## Build and deploy

```sh
cd admin
flutter build web --release            # → admin/build/web (gitignored)
```

`admin/build/web` is a static site: host it on any static host (Supabase
Storage, Netlify, Cloudflare Pages, GitHub Pages, …). If it is not served at
the domain root, build with `--base-href /some/path/`.

Before it works against a project, the backend must be live there:

1. `supabase db push` (includes `20261017120000_admin_functions.sql`).
2. `supabase functions deploy admin-quotes --no-verify-jwt` and
   `supabase functions deploy admin-stats --no-verify-jwt` (plus `quotes`).
3. `supabase secrets set QUOTE_ADMINS=you@example.com` (comma separated).

CORS is already open (`_shared/cors.ts` allows any origin), so no extra
setting is needed for the console's domain.
