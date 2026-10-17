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
    "attribution": "— Ada"
  }
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
| `quote` | Today's quote, or `null` when there is none (not loaded yet, offline with no cache, or signed out). `author` is `null` for anonymous quotes; `attribution` is ready to display ("— Unknown" when anonymous). |

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
entry at the next midnight. They do this by treating an older `date` as "all
not done".

## Deep links

| URI | Effect when it opens the app |
|---|---|
| `habitquest://open` | Habits tab (header taps, "Open HabitQuest" state) |
| `habitquest://quotes` | Quotes screen (Daily quote widget tap) |
| `habitquest://widget/toggle?habitId=<id>` | Toggles today's check-in of `<id>` through `HabitService.toggleCompletion`, then shows the Habits tab. Use this as the fallback on iOS < 17. Duplicate deliveries within 3 s are ignored. |

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
| `platform_widget_bridge*.dart` | The home_widget calls (io) and the web stub. |

Tests are in `test/features/widgets_bridge/`.
