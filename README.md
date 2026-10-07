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
- **Offline-first sync**: everything works offline; when signed in and
  online, habits, check-ins and the game state sync with your account in the
  background (☁️ badge in the Habits header, "Sync now" on the Quest tab).
  See [Sync](#sync).
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
device are kept (see [Sync](#sync) for what happens when another account
signs in).

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

## Sync

Habit Quest is **offline-first**: hive_ce on the device is the source of
truth, the UI only ever reads and writes hive, and it never waits for the
network. When signed in and online, changes are exchanged with the Supabase
Edge Functions in the background.

### Local model

- `Habit`, check-ins (`CheckIn`, one record per habit per day) and the
  `GameState` carry an `updatedAt` (UTC) stamped by every local write
  (create, edit, archive, delete, check-in toggle, XP change). Stamps are
  strictly increasing per entity even if the clock goes backwards.
- **Tombstones**: deleting a habit stores it with `deletedAt` instead of
  removing it. Repositories hide tombstoned habits (and their check-ins)
  from every read, so the UI, recurrence, streaks, the game and reminders
  never see them. Un-checking keeps the check-in record with
  `completed: false` so the un-check syncs too.
- **Upgrading**: data written by the previous version is still readable.
  Habits without `updatedAt` default to their `createdAt`; the old boolean
  check-ins are migrated once, on first launch, to records stamped with the
  migration time.

### Sync queue

Every local write of the repositories is recorded in a persistent hive box
(`sync_queue`) as *"this entity changed"*, coalesced per entity (one entry
per habit, per check-in, and one for the game state). The push always sends
the entity's **current** local record, so the latest local change wins. The
queue survives restarts. Data applied from the server is never queued.

### When it syncs

`SyncController` (started by `SyncBootstrap` in `main.dart`) syncs on: app
start when signed in, login, regaining connectivity (connectivity_plus plus a
cheap reachability probe of `{SUPABASE_URL}/auth/v1/health`; the probe is
skipped on web), app resume, local changes (debounced 3 s), and the manual
**Sync now** button (Quest tab, or tap the ☁️ badge in the Habits header).
It never syncs while signed out. Network/server errors retry with
exponential backoff (5 s doubling up to 5 min); a `401` is first handled by
the authenticated transport (token refresh + retry), and if the session is
really gone the controller stops and the auth gate takes over.

The badge shows ☁️ synced, 🔄 syncing, 📴 offline (with the number of
waiting changes) or ⚠️ error; the tooltip and the Quest card show the last
sync time.

### One sync run (`SyncEngine`)

1. **Push** habits, then check-ins (the server rejects check-ins of habits
   it does not know), through the batch endpoints (≤ 500 per call).
   An entry is dropped once the server acknowledges it, whether it was
   applied or refused because the server has something newer (the pull
   brings that). If a batch is refused for a validation reason, its items
   are retried one by one: the offending entity stays queued with its error
   (shown as "N changes couldn't sync") and **never blocks the rest**.
2. **Pull** deltas `since` the stored cursors (the `serverTime` of the
   previous pull; stored per user, separately for habits and check-ins) and
   merge with **last-write-wins** on `updatedAt`: a remote item replaces
   the local one only if it is strictly newer; on a tie the local copy is
   kept. Remote data is applied through `HabitService.applyRemote`, a
   repository-level path that only refreshes the UI: it emits **no
   completion events** (so no XP), and only habits that actually changed
   are rescheduled for reminders.
3. **Game state**: GET, merge (below), PUT back if the merged state differs
   from the server's copy.

### How XP stays consistent

XP was already never a free-running counter: the game engine keeps a
**ledger** of grants keyed by what earned them (`habitId|date` for a
check-in, `date` for a Perfect Day) and XP is the sum of the ledger. A key
can only be granted once, which is what makes toggling a check-in on/off/on
net zero. Sync builds on that:

- The game state is **merged, not overwritten**: ledgers are unioned by key
  (a key on both sides is counted once), achievements are unioned keeping
  the earliest unlock time, and best streak / max level take the maximum.
- The merged ledger is then **reconciled** against the merged check-ins:
  grants whose check-in is no longer done (un-checked or deleted on another
  device, decided by check-in LWW) are dropped; a pulled check-in that holds
  no grant on either side yet gets its base grant under the same key (so a
  later merge cannot double it); Perfect Days of the touched days are
  re-evaluated.
- All of this happens **silently**: remote awards, level-ups and
  achievements never fire celebration events; the profile is simply
  re-derived from the merged state.

So: a check-in made offline on device A and pulled by device B gives no
extra XP on B; toggling across devices cannot farm XP; and two devices
awarding different days both keep their XP. These scenarios are covered by
`test/features/sync/sync_engine_test.dart`.

### Account switching

Local data is tied to the user id that first synced it (`sync_meta` box):

- **First login** on a device whose data was never synced (e.g. created with
  the previous, offline-only version): the data is adopted by that account
  and uploaded (merged with whatever the account already has).
- **Same user** logging in again: nothing special; local data and the queue
  are kept.
- **A different user** signs in: the previous user's local habits,
  check-ins, game state, queue and cursors are **wiped** before anything is
  synced, then the new user's data is pulled. The previous account's data is
  never uploaded into the new one.

### Known limitations

- Changes the previous user had not synced yet are lost when a *different*
  account signs in on the same device (they cannot be uploaded without that
  user's session). Sync before handing the device over.
- Last-write-wins is per entity, not per field: two devices editing
  different fields of the same habit offline keep only the later edit.
- If one device edits a habit after another deleted it, the newer edit wins
  and the habit comes back, but check-ins removed with the deletion on the
  deleting device are not restored there.
- Conflict resolution trusts device clocks (`updatedAt` is set by the
  client, as in the API contract); a device with a clock far in the future
  wins conflicts.
- Tombstones are kept locally and on the server indefinitely (no purge yet).
- On web, reachability relies on the browser's online state; an unreachable
  backend shows up as "offline" after the first failed request.
- Not yet run against the real backend: the client follows the shared API
  contract and is tested against `FakeHabitQuestApi`.

## Architecture overview

```
lib/
  main.dart, app.dart     bootstrap (Hive, ProviderScope overrides), MaterialApp.router
  core/                   router (go_router + bottom-nav shell), theme, date utils,
                          shared widgets (MessageView for empty/error states)
  data/                   models (Habit, HabitSchedule, CompletionLog) and repositories
                          (HiveHabitRepository for the app, InMemoryHabitRepository for tests)
    remote/               Edge Function client: DTOs, AuthApi / HabitQuestApi (HTTP + fakes)
    sync/                 SyncQueue (pending changes), SyncMeta (owner, cursors), StringStore
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
    sync/                 SyncEngine (push / pull / merge), SyncController (triggers,
                          backoff, status), connectivity, indicator + "Sync now" UI
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

Sync is tested in `test/features/sync/` against `FakeHabitQuestApi` (which
behaves like the server: LWW, tombstones, `since`, offline / injected
failures) and `FakeConnectivityMonitor`: queue coalescing and persistence
across restarts, migration of pre-sync hive data, push then pull, LWW in both
directions, tombstones, offline → online, error isolation, cursors, the
double-XP scenarios, account switching, the controller's triggers / backoff,
and a widget test for the sync indicator.
