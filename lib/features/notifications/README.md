# features/notifications — reminder notifications

Schedules a reminder for every active habit with a `reminderTime`, matching
its schedule, with fun rotating messages (`reminder_messages.dart`, 8
templates such as "🔥 Keep your streak alive: {emoji} {name}!").

## How it works

```
HabitService.habitChanges ─┐
repository.getHabits()  ───┼─► NotificationsController ─► planReminders() ─► NotificationScheduler
app start / resume  ───────┘        (serialised queue)      (pure Dart)       mobile | web | noop | fake
```

* `reminder_planner.dart` — pure: `planReminders(habit, now:)` → `ReminderRequest`s.
  * Daily, times-per-week, every-1-day → one **daily** repeating reminder.
  * Weekdays → one **weekly** repeating reminder per weekday (slot = ISO weekday).
  * Every N days (N ≥ 2) → the next **12 one-shot** reminders; topped up on
    every app start and resume (`NotificationsController.resync`).
  * Times-per-week does not skip days once the weekly target is met (the
    repeating reminder cannot know); it is a gentle daily nudge.
  * Never before `startDate`; every request fires strictly after `now`.
* `reminder_ids.dart` — stable ids `(fnv1a(habitId) & 0x3FFFFFF) * 16 + slot`.
  Rescheduling cancels all 16 ids of the habit, so no state is stored.
* `notifications_controller.dart` — on start: initialise scheduler, request
  permission (only if a habit with a reminder exists), reschedule every
  habit, cancel stray pending ids. Then: created / updated / unarchived →
  reschedule (or cancel if the reminder was removed); archived / deleted →
  cancel. Permission is asked the first time a habit with a reminder exists.
* `notifications_providers.dart` — `notificationSchedulerProvider` (platform
  pick: `kIsWeb` → web, Android/iOS → mobile, else no-op) and
  `notificationsControllerProvider`. Override the scheduler with
  `FakeNotificationScheduler` in tests.
* `notifications_bootstrap.dart` — wraps the app in `main.dart`, starts the
  controller, resyncs on resume. Widget tests that pump `HabitQuestApp`
  directly don't start notifications.
* `in_app_reminder.dart` — `appScaffoldMessengerKey` (wired into
  `MaterialApp` in `app.dart`; other features may reuse it) and the banner.

## Platform behaviour

| Platform | Behaviour |
|---|---|
| Android | `flutter_local_notifications` + `timezone`/`flutter_timezone`. `POST_NOTIFICATIONS` requested on Android 13+. Uses `inexactAllowWhileIdle` (may be a few minutes late) unless the exact-alarm permission is granted, then `exactAllowWhileIdle`; an exact failure falls back to inexact. Boot / app-update receiver re-registers reminders. Icon: `res/drawable/ic_stat_habit_quest.xml`. Core library desugaring enabled in Gradle. |
| iOS | Same plugin; alert/badge/sound permission requested explicitly (not at plugin init). `AppDelegate` sets the `UNUserNotificationCenter` delegate so reminders also show in the foreground. iOS keeps at most 64 pending notifications per app: each habit uses ≤ 12, so many every-N-days habits can hit the cap (the OS keeps the soonest). |
| Web | **Reminders only fire while the app is open in a tab.** Browsers cannot schedule notifications for a closed page without a push server. A 30 s timer checks for reminders due since the last check (catch-up window 15 min, so a sleeping tab doesn't replay stale reminders) and shows an in-app snackbar plus a browser `Notification` if the user granted permission. Missing/blocked Notification API is handled silently. |
| Others | No-op. |

## Tests

`test/features/notifications/`: planner per schedule type, stable ids,
controller reactions with `FakeNotificationScheduler`, web due-check and the
web scheduler with a fake clock.
