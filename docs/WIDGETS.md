# Home-screen widgets — bridge contract

The Dart side (`lib/features/widgets_bridge/`) writes one JSON **snapshot**
into storage it shares with the native widgets, asks them to redraw, and
applies check-offs made on a widget. The Android (`android/`) and iOS
(WidgetKit extension) widgets read that snapshot and nothing else.

All names below are defined once in
[`lib/features/widgets_bridge/widget_constants.dart`](../lib/features/widgets_bridge/widget_constants.dart).
Native code must use exactly these values. The package is
[`home_widget` 0.10.0](https://pub.dev/packages/home_widget).

## Storage

| | iOS | Android |
|---|---|---|
| Container | App Group **`group.com.vvs.habitquest`** (`UserDefaults(suiteName:)`) | SharedPreferences file **`HomeWidgetPreferences`** (`HomeWidgetPlugin.getData(context)`) |
| Snapshot key | `hq_widget_snapshot` (String, JSON) | `hq_widget_snapshot` (String, JSON) |
| Toggle queue key | `hq_widget_toggle_queue` (internal, see below) | same |
| Refresh status key | – | `hq_widget_refresh_status` (internal: Dart reports a background refresh's outcome to `WidgetRefreshWorker`) |

Runner already has the App Group entitlement
(`ios/Runner/Runner.entitlements`). The widget extension needs the same group.

Native code only **reads** `hq_widget_snapshot`. It must never write either
key. Check-offs go through the interactive callback (see below).

## Snapshot JSON (`version` 1)

```json
{
  "version": 1,
  "date": "2026-10-17",
  "generatedAt": "2026-10-17T06:00:00.000Z",
  "state": "ok",
  "habits": [
    {
      "id": "6f1c…",
      "name": "Walk",
      "emoji": "🚶",
      "color": 4283222512,
      "colorHex": "#4CC9F0",
      "done": false,
      "toggleUri": "habitquest://widget/toggle?habitId=6f1c…"
    }
  ],
  "doneCount": 0,
  "totalCount": 1,
  "quote": {
    "text": "Keep going.",
    "author": "Ada",
    "attribution": "— Ada",
    "day": "2026-10-17"
  },
  "upcoming": [
    { "date": "2026-10-18", "habits": [ { "id": "6f1c…", "name": "Walk", "…": "…", "done": false } ] }
  ]
}
```

| Field | Meaning |
|---|---|
| `version` | Schema version. It is bumped only for breaking changes, and new fields may appear at any time. |
| `date` | The local calendar day (`yyyy-MM-dd`) that the habits and `done` flags belong to. If it is **before today** (the app has not run since midnight), show every habit as not done. A check-off still works and rolls the snapshot over. |
| `generatedAt` | When the snapshot was written (ISO-8601 UTC). Informational only. |
| `state` | `ok`: signed in with at least one habit due today. `signedOut`: show an **"Open HabitQuest"** prompt (tap opens `habitquest://open`). `noHabits`: signed in but nothing is due today; show an "Open HabitQuest" prompt too, e.g. "No habits today". An unknown or missing value counts as `signedOut`. |
| `habits` | Today's due habits in app order (empty unless `ok`). Archived and deleted habits are never included. |
| `habits[].color` | ARGB as an unsigned 32-bit integer (`0xAARRGGBB`), so read it as a 64-bit integer. `colorHex` is the same colour as `#RRGGBB`. |
| `habits[].toggleUri` | The check-off URI for that habit (see below). |
| `quote` | Today's quote, or `null` when there is none (not loaded yet, offline with no cache, or signed out). `author` is `null` for anonymous quotes; `attribution` is ready to display ("— Unknown" when anonymous). `day` is the local day it is the quote of (`null` in snapshots written before 2026-10-23); when it is before today the quote is yesterday's and the background refresh fetches a new one. Widgets keep showing it meanwhile. |
| `upcoming` | The due habits (same shape as `habits`, `done: false`) of the next 7 days after `date`, precomputed by the app from local data (habits, schedules, the completion log). When `date` is before today, a widget shows the entry for today if there is one (Android: `WidgetSnapshot.kt`), so Today's habits rolls over at midnight even before anything rewrote the snapshot. Empty when signed out. "N times per week" habits are computed with the check-ins known when the snapshot was written. |

When no snapshot exists yet (the app has never run), treat it as `signedOut`.

## Widget names (the app refreshes these)

| Widget | Android provider (fully qualified class) | iOS WidgetKit `kind` |
|---|---|---|
| Today's habits | `com.vvs.habitquest.widgets.TodayHabitsWidgetReceiver` | `TodayHabitsWidget` |
| Daily quote | `com.vvs.habitquest.widgets.DailyQuoteWidgetReceiver` | `DailyQuoteWidget` |

The app calls `HomeWidget.updateWidget` for each pair. A widget that does not
exist yet is skipped silently. If you rename a class or kind, change
`widget_constants.dart` in the same commit.

## When the snapshot is rewritten

The app rewrites the snapshot, and then refreshes both widgets, in these
cases:

- on app start, after the queued check-offs are applied;
- on every `CompletionEvent` and `HabitChangeEvent` (local or remote/sync),
  and whenever the due-today list or the completion log changes;
- when today's quote loads;
- on sign-in and sign-out;
- when the app resumes;
- at local midnight while the app is running (a timer), and on any day change
  noticed on resume.

Unchanged content is not rewritten. The widgets should still roll over at
midnight on their own: an Android update period or alarm, or an iOS timeline
entry at the next midnight. They do this by using today's `upcoming` entry
(or, without one, treating an older `date` as "all not done"). On Android a
background job also rewrites the snapshot with today's quote; see the next
section.

## Daily roll-over without the app (Android)

**Bug (reported 2026-10-23, Galaxy S24 Ultra):** the Daily quote widget kept
yesterday's quote until the app was opened and closed. **Root cause:** the
midnight alarm (`MidnightRefresh`, home_widget's `HomeWidgetScheduler`) and
`updatePeriodMillis` only made the Glance widgets *re-render the stored
snapshot*. Nothing rewrote that snapshot until the app ran: only the running
app fetched the quote (`GET /quotes` needs the user's bearer token, see
`supabase/API.md`), and its in-app midnight `Timer` does not run when the app
is not running, nor while the phone sleeps (Dart timers stop during deep
sleep). The habits widget had the same issue in a milder form: it showed
yesterday's list, unchecked, instead of today's due habits.

**Fix:** a background refresh that rolls the snapshot over and fetches today's
quote, with no new Flutter dependency:

1. **Scheduling, native (`widgets/WidgetRefresh.kt`).** Jetpack WorkManager
   (`androidx.work`, already in the APK: home_widget 0.10 runs its background
   callback on it) runs `WidgetRefreshWorker`:
   - a one-off **a minute after every local midnight** (unique name per night,
     no constraint, so the habits roll over offline too; each run arms the
     next night);
   - a **periodic safety net every 4 h**, network-constrained (with
     exponential backoff from 15 min), which also catches up after a reboot,
     Doze or a missed midnight;
   - after an offline midnight run, a network-constrained **catch-up** that
     runs as soon as there is a connection.

   The work is armed from the widget receivers' `onUpdate` (KEEP policy, so
   repeated calls are cheap) and cancelled when the last widget is removed:
   no widget, no background work.
2. **The worker wakes Dart** through home_widget's background callback with
   `habitquest://widget/refresh?id=<uuid>` (`HomeWidgetBackgroundWorker`, the
   same headless engine as widget check-offs). It waits up to 30 s for Dart to
   write `{"id", "outcome"}` under `hq_widget_refresh_status`, which keeps the
   process alive during the fetch and lets WorkManager retry: `retryLater`
   makes the periodic and catch-up runs retry with backoff.
3. **Dart does the work (`widget_background_refresh.dart`)**, reusing the app's
   code (no HTTP or auth in Kotlin):
   - If the app is alive in the same process (its `IsolateNameServer` port
     answers within 3 s), the app does it itself
     (`WidgetBridge.refreshFromBackground`: day roll-over, today's quote,
     snapshot write), because its isolate owns the session and the Hive boxes.
   - Otherwise the session is read from secure storage (a failing read is
     *not* treated as a sign-out). Habits roll over locally from `upcoming`
     (`WidgetSnapshot.rolledOverTo`) and are written at once. If `quote.day`
     is not today, the quote is fetched through the app's own
     `quotesApiProvider` → `AuthenticatedTransport` → `AuthController` in a
     short-lived `ProviderContainer`. An expired access token is refreshed
     first (and the new session stored), and a 401 is refreshed and retried
     once, exactly as in the app. The snapshot is re-read just before the
     quote is written, so a widget check-off made meanwhile is kept.
   - Hive is never opened in the background.

| Situation | Result |
|---|---|
| Online, signed in | Today's habits (not done) and today's quote; both widgets refreshed. |
| Snapshot already today's, with today's quote | Nothing written, **no network call** (the common periodic run). |
| Offline / server error | Habits roll over; yesterday's quote stays; retried (catch-up / backoff / next periodic run). The snapshot is never wiped. |
| No stored session | The `signedOut` ("Open HabitQuest") snapshot. |
| Refresh token rejected | `AuthController` clears the session as the app would; `signedOut` snapshot. |
| Session storage unreadable | Nothing changes; retried later. |
| No snapshot yet / snapshot says signed out | Left to the app (nothing to roll over). |
| No quotes on the server (404) | The old quote is kept. |

**Token rotation across isolates.** If the background refresh rotates the
refresh token while the app process is starting, the app may still hold the
old token. When its refresh is then rejected, `AuthController` first re-reads
the stored session and adopts a newer one instead of signing out
(`auth_controller_test.dart`).

**Battery.** At most one run per night plus one every 4 h, and only while a
widget exists. Typical runs read SharedPreferences and exit without network.
No exact alarms or wake locks are added (the existing midnight re-render
alarm is unchanged), and WorkManager batches the runs into Doze maintenance
windows.

**Deep links are unaffected.** The refresh URI only ever goes to the
background receiver and never opens `MainActivity`. The "consumed once"
handling of widget links (3987db2) is unchanged.

**Check it on a device (debug build):**

```sh
adb -s <serial> shell run-as com.vvs.habitquest \
  cat shared_prefs/HomeWidgetPreferences.xml        # see hq_widget_snapshot
# Make the snapshot stale: copy the file out, change "date" and quote "day"
# to yesterday (and the quote text), push it back with run-as, then
# force-stop the app so the edited prefs are re-read.
adb -s <serial> shell am force-stop com.vvs.habitquest
adb -s <serial> shell dumpsys jobscheduler | grep -B2 -A10 com.vvs.habitquest  # find the WorkManager job id
adb -s <serial> shell cmd jobscheduler run -f com.vvs.habitquest <job id>
adb -s <serial> logcat -s HabitQuestWidgets WidgetBridge   # "Widget refresh (periodic): updated"
```

Tests: `test/features/widgets_bridge/widget_background_refresh_test.dart` (day
roll-over, offline, server error, signed out, token refresh, rejected refresh,
unreadable session, unchanged snapshot on failure) and
`widget_bridge_test.dart` (app-alive path).

## iOS: same problem, not fixed yet

The WidgetKit timeline (`ios/HabitQuestWidgets/WidgetSnapshot.swift`) has one
entry now and one at the next local midnight, both built from the *same*
stored snapshot. So the iOS Daily quote widget also shows yesterday's quote
until the app runs. iOS gives no reliable way to run Dart on a schedule:
`BGAppRefreshTask` runs when the system decides, and not at all after a
force-quit. What iOS would need (not done here: the iOS project cannot be
built on this Mac):

1. **Habits:** in `WidgetContent.from`, use the snapshot's `upcoming` entry
   for the entry's day when `date` is older (the Dart side already writes
   it), as `WidgetSnapshot.kt` does.
2. **Quote, offline-proof:** have the app also write the next few days'
   quotes. `GET /quotes?date=` accepts future dates, so this is a Dart-only
   change, e.g. an `upcomingQuotes: [{day, text, author}]` field. The timeline
   would then show the right quote in its midnight entry with no network.
   This also helps Android when the phone is offline at midnight. It was not
   done here because a quote edited or rescheduled later by an admin would
   only be picked up on the next fetch.
3. **Or fetch in the extension:** `getTimeline` may make a network request,
   but it needs the session. That means sharing it through a keychain access
   group (Runner and the extension) and re-implementing `auth-refresh` in
   Swift, i.e. duplicated auth logic. Option 2 is preferred.


## Deep links

| URI | Effect when it opens the app |
|---|---|
| `habitquest://open` | Habits tab (header taps, "Open HabitQuest" state) |
| `habitquest://quotes` | Quotes screen (Daily quote widget tap) |
| `habitquest://widget/toggle?habitId=<id>` | Toggles today's check-in of `<id>` through `HabitService.toggleCompletion`, then shows the Habits tab. Use this as the fallback on iOS < 17. Duplicate deliveries within 3 s are ignored. |

**Each link is consumed exactly once.** The app maps it to one navigation
that keeps the Habits tab underneath (`habitquest://quotes` → `/habits/quotes`,
i.e. Quotes stacked on Habits; `…/quotes/saved` → `/habits/quotes/saved`).
Back from Quotes therefore returns to Habits, and a later launcher start shows
Habits. (Bug fixed on 2026-10-18: the link used to replace the whole stack with
`/quotes`, so on Android 12+ Back moved the still-alive activity to the
background on Quotes, and every launcher start resumed it there until a force
stop. iOS had the same Dart-side stack: Quotes with no way back.) On Android,
`MainActivity` also replaces a widget link with a plain launcher intent when
the system replays it: when the activity is re-created with saved state after
process death, or when it is relaunched from Recents
(`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`). The Dart side does not read any
"initial launch" URI on resume (`HomeWidget.initiallyLaunchedFromHomeWidget`
is not used). Regression test: `test/features/widgets_bridge/widget_deep_link_test.dart`.

> **Not yet verified on a device.** This fix was merged on the strength of
> `flutter analyze`, `flutter test` and `flutter build apk --debug` only; the
> phone was not connected. To check it: tap the Daily quote widget (Quotes
> opens), press Back, then start the app from the launcher icon; it must open
> on Habits.

The `habitId` is URI-encoded (`Uri.encodeQueryComponent`); use the
`toggleUri` field as given. Both platforms already register the `habitquest`
scheme (Android intent filters for the hosts `open`, `quotes` and `widget`;
`CFBundleURLSchemes` on iOS).

## Check-off from a widget (interactive, app not opened)

**Mechanism: the home_widget interactive background callback plus a
queue that the app applies.**

1. The widget fires `habitquest://widget/toggle?habitId=<id>` through
   home_widget's interactive callback:
   - **Android:** `HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse(toggleUri))`
     as the checkbox's click PendingIntent. The receiver
     `es.antonborri.home_widget.HomeWidgetBackgroundReceiver` is already
     declared in `AndroidManifest.xml`.
   - **iOS 17+:** an `AppIntent` whose `perform()` calls
     `await HomeWidgetBackgroundWorker.run(url: URL(string: toggleUri), appGroup: "group.com.vvs.habitquest")`.
     The intent file must be a member of **both** the Runner and widget
     targets. Runner's `AppDelegate` must also call
     `HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in GeneratedPluginRegistrant.register(with: registry) }`
     so that the headless engine has the home_widget plugin. The iOS widget
     task adds this.
2. Dart's `widgetInteractivityCallback` runs in a headless background isolate.
   It flips that habit's `done` in the snapshot, appends the wanted state
   (`{id, habitId, date, done, at}`) to `hq_widget_toggle_queue`, and
   refreshes the widgets. **The widget therefore updates at once.** If the
   app is running, it also signals the app through an `IsolateNameServer`
   port.
3. The app applies the queue through `HabitService.setCompletion`, the call
   behind `toggleCompletion`, so XP, streaks, reminders and sync behave
   exactly like an in-app check-off. It does this right away if it is
   running, otherwise on its next start or resume. Entries carry the wanted
   state, not a flip, so applying them is idempotent. Repeated taps collapse
   to the last state. Entries for deleted habits or future days are dropped.
   An entry tapped before midnight applies to that day.

**Why not run `HabitService` in the background isolate?** Hive is not safe
across isolates. When the app is alive, its isolate keeps the boxes open
with in-memory copies, so a second writer would be overwritten or corrupt
the box. The sync/auth stack (network, token refresh) is also too heavy for
the short background window (iOS gives an AppIntent a few seconds). The
queue is small, durable in the shared store, and gives the same final result
through the real service.

**Trade-off:** until the app runs again, the check-off is visible only on the
widget. XP, streaks and the server catch up on the next start or resume.

## Web and desktop

The bridge is a no-op on web (home_widget is never imported, through a
conditional import) and on desktop (`widgetStoreProvider` is `null`).

## Code map

| File | Role |
|---|---|
| `widget_constants.dart` | Every shared name (keys, group, widget names, URIs). |
| `widget_snapshot.dart` | Snapshot model, JSON, and the pure `buildWidgetSnapshot`. |
| `widget_toggle_queue.dart` | `recordWidgetToggle` (background) and `applyPendingToggles` (app). |
| `widget_bridge.dart` | Riverpod wiring: listeners, writes, midnight timer, link handler. |
| `widget_bridge_bootstrap.dart` | Starts the bridge in `main.dart`, handles resume and the background signal. |
| `widget_links.dart` | Parses widget URIs and maps them to routes (used by `app_router.dart`). |
| `widget_background_refresh.dart` | The daily background refresh: local roll-over + today's quote through the app's auth/quotes stack. |
| `android/.../widgets/WidgetRefresh.kt` | WorkManager scheduling (midnight, periodic, catch-up) and the worker that wakes Dart. |
| `platform_widget_bridge*.dart` | The home_widget calls (io) and the web stub. |

Tests are in `test/features/widgets_bridge/`.
