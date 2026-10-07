# Habit Quest 🌱⚔️

A playful, gamified habit tracker for **iOS, Android and web**. Build habits,
keep streaks alive, earn XP, level up and unlock achievements. All data stays
on the device (hive_ce). There is no account and no server.

## Features

- **Habits tab**: a greeting, today's progress bar, the habits due today with
  big bouncy check-in buttons, then your other habits and an archived section.
  Each card shows the habit's emoji, colour, schedule summary and a 🔥 streak
  flame. A small level/XP chip in the header opens the Quest tab.
- **Create / edit a habit** (`/habits/new`, `/habits/:id/edit`): name, emoji,
  colour, schedule, start date and an optional reminder time, with a live
  preview card. Editing also lets you archive or delete the habit.
- **Habit details** (`/habits/:id`): current and best streak, total
  check-ins, completion rate, a monthly heatmap where you can check in or undo
  today and past days, and edit/archive/delete actions.
- **Calendar tab**: a month grid with a progress ring per day and a ⭐ marker
  for Perfect Days. Tap a day to see the habits due that day and check them in
  (today and past days; future days are read-only). Swipe or use the arrows to
  change month, and "Today" to jump back.
- **Quest tab**: mascot, level, title, an animated XP bar, stats (check-ins,
  best streak, Perfect Days), an achievements grid (locked badges show a hint)
  and a "How to earn XP" card.
- **Celebrations** across the app: a floating "+N XP", confetti and a dialog
  on level-up, and toasts when you unlock an achievement.
- **Reminders**: notifications at each habit's reminder time, following its
  schedule, with rotating fun messages.
- **Light and dark mode** follow the system setting. Bright palette, rounded
  shapes, Fredoka headings and Nunito body text.

Checking in works the same way on every screen (Habits, Details, Calendar).
Each one calls `HabitService.toggleCompletion`, so streaks, XP, level,
achievements and calendar markers stay in sync whichever screen you use.

## Recurrence types

| Type | Due on | Streak counted in |
|---|---|---|
| **Daily** | every day | days |
| **Specific weekdays** | the chosen weekdays (e.g. Mon/Wed/Fri) | scheduled days |
| **Every N days** | the start date, then every N days | scheduled days |
| **X times per week** | any day until the weekly target is met (ISO weeks, Mon–Sun) | weeks that hit the target |

Nothing is due before a habit's start date, and archived habits are never due.
Streaks only count scheduled periods. Missing a day the habit isn't scheduled
on never breaks a streak. Today (or the current week) adds to the streak once
it's done, but can't break the streak before it is over.

## Game rules

**XP**
- **Check-in**: 10 XP, plus a **streak bonus** of +1 per streak day (or week),
  up to **+10**. A check-in that brings a streak to 4 earns 14 XP. From a
  10-day streak on, every check-in earns 20 XP. Check-ins on days the habit
  isn't scheduled get no bonus.
- **Perfect Day**: **+25 XP** when every habit due that day is done. This
  also counts for past days you complete later.

**Levels**: going from level *n* to *n + 1* costs **100 × n XP** (level 1→2
costs 100, 2→3 costs 200, and so on). Level *L* starts at 50·L·(L−1) total XP.

| Levels | Title |
|---|---|
| 1–2 | Sprout |
| 3–4 | Seeker |
| 5–7 | Adventurer |
| 8–10 | Hero |
| 11–14 | Champion |
| 15–19 | Legend |
| 20+ | Mythic |

**Achievements (12)**

| Achievement | How to unlock it |
|---|---|
| A New Quest | create your first habit |
| First Step | your first check-in |
| Warming Up / On Fire / Unstoppable / Centurion | a 3 / 7 / 30 / 100 streak |
| Getting Started / Habit Builder / Triple Digits / Habit Master | 10 / 50 / 100 / 500 total check-ins |
| Perfect Day | your first Perfect Day |
| Juggler | 5 active habits at once |

**Anti-toggle-exploit**: every XP grant goes into a ledger, keyed by what
earned it (`habit + date` for a check-in, `date` for a Perfect Day).
Un-checking a habit takes back exactly the XP that check-in earned, and the
Perfect Day bonus if that day is no longer perfect. Turning a check-in on and
off any number of times therefore nets 0 XP. Deleting a habit removes the XP
of all its check-ins. Level-up and achievement celebrations are shown only
once, ever. Creating, editing or archiving a habit never grants XP.

## Running the app

Requirements: Flutter 3.38+ (Dart 3.10+). For iOS you also need Xcode
(macOS only); for Android, the Android SDK (Android Studio or command-line
tools).

```sh
flutter pub get

# Web (Chrome)
flutter run -d chrome
flutter build web                 # output in build/web

# Android (device or emulator)
flutter run -d android
flutter build apk --debug         # build/app/outputs/flutter-apk/app-debug.apk

# iOS (simulator or device; signing is needed for a device)
open -a Simulator && flutter run -d ios
flutter build ios --no-codesign

# Checks
flutter analyze
flutter test
```

`flutter devices` lists the available targets.

### Environment config

The app talks to the Supabase Edge Functions only (never to tables
directly). Where they live is compiled in with `--dart-define`s:

| Define | Default | Meaning |
|---|---|---|
| `SUPABASE_URL` | `https://fwikodmrfoorbstmkedx.supabase.co` | Project URL; the app calls `{SUPABASE_URL}/functions/v1/<name>` |
| `SUPABASE_ANON_KEY` | *(none)* | The project's public **anon** key (Supabase dashboard → Project Settings → API). Sent as `apikey` on every request |

Without `SUPABASE_ANON_KEY` the app still starts, but the login screen shows
a "Server not configured" message and sign-in is disabled.

```sh
# One-off
flutter run -d chrome --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...

# Or keep the values in a file (env/*.json is gitignored)
cp env/example.json env/dev.json     # then paste your anon key into it
flutter run -d chrome --dart-define-from-file=env/dev.json
flutter build web --dart-define-from-file=env/dev.json
```

`env/dev.json` looks like:

```json
{
  "SUPABASE_URL": "https://fwikodmrfoorbstmkedx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGciOi..."
}
```

The anon key is public by design (row-level security protects the data), but
keep it out of git anyway so each environment can use its own project. Never
put the `service_role` key in the app.

**Session storage**: the session (access + refresh token) is kept with
`flutter_secure_storage`: Keychain on iOS, Keystore-backed encrypted
preferences on Android, and on web an encrypted value in `localStorage`
(WebCrypto, which needs `https://` or `localhost`). The access token is
refreshed about 60 s before it expires, and once on any `401` response.
Logging out (Quest tab) clears the stored session; the habits stored on the
device are kept for now.

### Notifications per platform

- **Android**: asks for notification permission on Android 13+. Uses exact
  alarms if that permission is granted; otherwise inexact alarms, which can
  fire a few minutes late. Reminders are restored after a reboot.
- **iOS**: asks for alert/badge/sound permission the first time a habit has a
  reminder. Reminders also show while the app is in the foreground.
- **Web (limitation)**: browsers can't schedule notifications for a closed
  page without a push server, so **web reminders only work while the app is
  open in a tab**. When a reminder is due, the app shows an in-app banner,
  plus a browser notification if you allowed them. If the tab is closed,
  nothing fires. A reminder missed while the tab was asleep for more than 15
  minutes is skipped rather than replayed.

## Architecture overview

```
lib/
  main.dart, app.dart     bootstrap (Hive, ProviderScope overrides), MaterialApp.router
  core/                   router (go_router + bottom-nav shell), theme, date utils,
                          shared widgets (MessageView for empty/error states)
  data/                   models (Habit, HabitSchedule, CompletionLog) and repositories
                          (HiveHabitRepository for the app, InMemoryHabitRepository for tests)
    remote/               Edge Function client: DTOs, AuthApi / HabitQuestApi (HTTP + fakes)
  domain/                 pure Dart: recurrence, streaks, HabitService, Riverpod providers
  features/
    habits/               Habits tab + create/edit form
    habit_details/        details screen
    calendar/             Calendar tab
    quest/                Quest tab (with logout)
    auth/                 login/register screen, splash, AuthController (session,
                          refresh), SessionStore (flutter_secure_storage)
    game/                 game engine (XP ledger, levels, achievements) + celebration UI
    notifications/        reminder planning + mobile / web / no-op schedulers
```

How data flows:

```
 Screens ──toggleCompletion / create / update──► HabitService ──► HabitRepository (hive_ce)
    ▲                                              │  completionEvents / habitChanges
    │ watch habitsProvider / completionsProvider   ├──────────► GameEngine ──► GameRepository (hive_ce)
    │ (streams from the repository)                │               │ stateChanges / events
    └──────────────────────────────────────────────┘               ▼
                                         gameProfileProvider (Quest tab, level chip),
                                         gameEventsProvider (celebrations)
                                   habitChanges ─► NotificationsController ─► scheduler
```

- **State**: Riverpod 3. The repository exposes streams of habits and
  check-ins. Derived providers (due today, streaks, Perfect Days) recompute
  from them, so every screen refreshes after a mutation.
- **Mutations** all go through `HabitService`. It persists the change, then
  emits a `CompletionEvent` or `HabitChangeEvent`.
- **Game engine**: pure Dart. It subscribes to those events, keeps its own
  persisted state (XP ledger, achievements, stats) and publishes profile
  updates and celebration events.
- **Navigation**: go_router with a `StatefulShellRoute` for the three tabs.
  `/habits/new`, `/habits/:id` and `/habits/:id/edit` are full-screen routes
  pushed above the bottom bar, so the back button returns to the screen you
  came from.
- **Notifications** live behind a `NotificationScheduler` interface, with
  mobile, web, no-op and fake (test) implementations.

More detail: [ARCHITECTURE.md](ARCHITECTURE.md),
[lib/features/game/README.md](lib/features/game/README.md) and
[lib/features/notifications/README.md](lib/features/notifications/README.md).

## Tests

`flutter test` runs unit tests (recurrence, streaks, the service, game rules
and engine, reminder planning), widget tests for every screen, and end-to-end
flow tests in `test/flows/`. The flow tests cover: create a habit → check in →
XP and streak update; checking in from the calendar or details shows up on the
Habits screen and in the Quest profile; un-checking takes the XP back.

## Backend (Supabase)

The backend lives in [`supabase/`](supabase/) and targets the Supabase project
`fwikodmrfoorbstmkedx`. The app talks only to Edge Functions; the HTTP contract
(endpoints, JSON shapes, error codes, last-write-wins and delta-pull cursors) is
in **[supabase/API.md](supabase/API.md)**.

```
supabase/
  config.toml                 # local stack + per-function settings (verify_jwt)
  migrations/                 # schema, RLS policies, LWW SQL functions
  functions/
    _shared/                  # cors, errors, auth, validation, mapping, LWW, stores
    auth-register|auth-login|auth-refresh|auth-logout/
    habits/ check-ins/ game-state/
    tests/                    # Deno unit tests + e2e_smoke.ts
  .env.example                # placeholders only, never commit real keys
```

Tables `profiles` (created by a trigger on sign-up), `habits`, `check_ins`
and `game_state` each belong to `auth.uid()` and have row-level security with
select/insert/update/delete policies. The functions create their Supabase
client with the anon key plus the caller's JWT, so RLS applies to every query;
the service-role key is never used.

### 1. Install the Supabase CLI

```sh
brew install supabase/tap/supabase      # macOS (or: npm i -D supabase, scoop, …)
supabase --version
brew install deno                       # only for running the Deno tests/checks
```

Docker is needed only for the local stack.

### 2. Link the project and push the migrations

```sh
supabase login
supabase link --project-ref fwikodmrfoorbstmkedx   # asks for the database password
supabase db push                                    # applies supabase/migrations/*
```

### 3. Deploy the Edge Functions

`verify_jwt` is **off for every function** (set in `supabase/config.toml`):

| Function | verify_jwt | Why |
|---|---|---|
| `auth-register`, `auth-login`, `auth-refresh` | off | called without a user token |
| `auth-logout`, `habits`, `check-ins`, `game-state` | off | the function validates the bearer token itself (`supabase.auth.getUser`) so a bad token gets the contract's `401 {"error":{"code":"unauthorized"}}` body instead of the gateway's own format; data is still only reachable with the user's JWT through RLS |

```sh
supabase functions deploy auth-register --no-verify-jwt
supabase functions deploy auth-login    --no-verify-jwt
supabase functions deploy auth-refresh  --no-verify-jwt
supabase functions deploy auth-logout   --no-verify-jwt
supabase functions deploy habits        --no-verify-jwt
supabase functions deploy check-ins     --no-verify-jwt
supabase functions deploy game-state    --no-verify-jwt
# or all at once (uses config.toml): supabase functions deploy
```

### 4. Secrets and auth settings

The functions need **no custom secrets**: `SUPABASE_URL` and
`SUPABASE_ANON_KEY` are injected by the Edge Runtime. If you add one later, use
`supabase secrets set NAME=value` (or `supabase secrets set --env-file
supabase/.env`) and list it in `supabase/.env.example` with a placeholder.
Never commit keys.

In the dashboard (Authentication → Sign In / Providers → Email), decide
whether "Confirm email" is on. When it is, `auth-register` answers
`{"session":null,"needsConfirmation":true}` and the user must confirm before
logging in.

The app gets the URL and the anon (public) key via `--dart-define`
(see the app configuration section).

### 5. Run locally

```sh
supabase start                 # Postgres, Auth, API gateway in Docker; applies migrations
supabase db reset              # re-apply migrations from scratch
supabase functions serve       # serves all functions at http://127.0.0.1:54321/functions/v1/
supabase status                # shows the local anon key
```

Local email confirmation is off (`[auth.email] enable_confirmations = false`).

### 6. Checks and tests

```sh
cd supabase/functions
deno task check                # type-check all functions and tests
deno task lint
deno task test                 # unit tests: validation, mapping, LWW, routing, auth errors
# end-to-end against the local stack (or a deployed project):
SUPABASE_URL=http://127.0.0.1:54321 SUPABASE_ANON_KEY=<anon key> \
  deno run --allow-net --allow-env tests/e2e_smoke.ts
```
