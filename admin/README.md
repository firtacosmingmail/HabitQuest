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
the domain root, build with `--base-href /some/path/`. **Hosting is still in
the backlog**: for now, run the console locally (`flutter run -d chrome`).

### Backend status

**Deployed** to the live project `fwikodmrfoorbstmkedx` on **2026-11-14**:

1. Migration `20261017120000_admin_functions.sql` applied (on its own; the
   Projects migration `20261114120000` was not part of this deploy).
2. `admin-quotes` and `admin-stats` deployed with `--no-verify-jwt`.
3. Admins = the emails in the `QUOTE_ADMINS` function secret. That secret is
   the only admin list. To change it:
   `supabase secrets set QUOTE_ADMINS=a@example.com,b@example.com` (comma
   separated, it replaces the whole list; no redeploy needed). Never use
   `supabase config push` for this.

Smoke test on that day: no token → 401 on both functions; a signed-in
non-admin → 403 on both. To check the admin path (200), sign in to the
console running locally against live with an email from `QUOTE_ADMINS`.

**Admin stats v2: deployed on 2026-11-18.**
`20261114130000_admin_stats_projects.sql` (project XP in the XP
totals/distribution, project XP buckets, Projects usage counts, sessions
attended per day) was applied right after the Projects migration
`20261114120000_projects.sql`, and `admin-stats` was redeployed with
`--no-verify-jwt`. Smoke test: a signed-in non-admin still gets 403, and the
live `admin_stats` SQL returns the Projects fields. The dashboard's Projects
tiles and charts now show live data.

To set the backend up on another project: apply the migrations, deploy the
two functions (plus `quotes`) with `--no-verify-jwt`, and set
`QUOTE_ADMINS`.

CORS is already open (`_shared/cors.ts` allows any origin), so no extra
setting is needed for the console's domain.
