# On-device check: main dc9ad8c on Galaxy S24 Ultra (RFCX41EFFXZ)

Date: 2026-11-04, about 07:15–07:40 local time (Europe/Bucharest). Debug build (`flutter build apk --debug`,
shared debug keystore), live backend `fwikodmrfoorbstmkedx`. Android 16 / One UI, system
dark mode **on** (the original setting; restored after check f).

All screenshots use a throwaway account (`habitquest-devicetest+…@example.com`, created
with the admin API, deleted at the end; no rows remain in `habits`, `check_ins`,
`game_state`, `profiles` or `quote_loves`). No screenshot shows the owner's habits.

| Check | Result | Evidence |
|---|---|---|
| a. App starts, sign-in | **PASS** (email/password and Google) | `a1-cold-start.png`, `a3-…`, `a4-profile-email-signin.png` ("Sign-in method: Email & password"). The owner signed in with **Google** on this debug build at 05:19:28Z (the Supabase google identity was updated at that time); no screenshot, since it was their account. |
| b. Signed-out flow | **PASS** | `b0-widgets-signed-out.png` (Daily quote shows today's quote signed out; Today's habits shows "Sign in to see today's habits"), `b1-public-quote.png` (today's quote, Wed Nov 4), `b2-back-to-login.png` (Back goes to login), `b3-heart-to-login.png` (heart goes to login with "Sign in to save this quote."), `a3-signed-in-heart-loved.png` (after the email sign-in: Quotes with today's quote loved; a `quote_loves` row was confirmed on the server) |
| c. Quote-widget relaunch fix | **PASS** (warm and cold) | Warm: widget, then Quotes, Back (`c1-back-from-quotes.png`: Habits), Back, Home, launcher icon (`c2-launcher-after-widget.png`: Habits). Cold (after force-stop): widget, then Quotes (`c3-cold-widget-quotes.png`), Back (`c3b-cold-back.png`: Habits), Back, Home, launcher (`c4-cold-launcher-after.png`: Habits, not Quotes). |
| d. Check-off from Today's habits widget | **PASS** (app process alive in background) | Before: `d1-app-before.png` (0/1, streak 0), `d2-quest-xp-before.png` (0 XP, 0 check-ins), `d3-widget-before.png`. Tap the checkbox: `d4-widget-after-tap.png` (1/1, struck through, app not opened). Open the app: `d5-app-after.png` (1/1 done, 🔥 1 day, "First Step" unlocked), `d6-quest-xp-after.png` (36 XP, 1 check-in, best streak 1, Synced). Server: 1 `check_ins` row, completed=true. |
| e. Daily roll-over (forced WorkManager job) | **NOT CHECKED** (blocked) | See below. |
| f. Dark mode, both widgets | **PASS** | `f1-widgets-dark.png` (night mode yes), `f2-widgets-light.png` (`cmd uimode night no`); restored to `yes` and verified. |

## e. Why the roll-over could not be forced

Following docs/WIDGETS.md: the snapshot was made stale with `run-as` (`date` and quote
`day` set to 2026-11-03, placeholder quote text), the process was killed with
`run-as … kill <pid>` (a force-stop cancels the app's jobs), and the
WidgetRefreshWorker jobs were forced:

```
$ adb shell cmd jobscheduler run -f com.vvs.habitquest 3
Could not find job 3 in package com.vvs.habitquest / user 0     # jobs are namespaced
$ adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler com.vvs.habitquest 3
WM-WorkerWrapper: Status for 3fd44370-… is ENQUEUED; not doing any work and rescheduling for later execution
$ adb shell cmd jobscheduler run -f -n androidx.work.systemjobscheduler com.vvs.habitquest 5
WM-WorkerWrapper: Delaying execution for com.vvs.habitquest.widgets.WidgetRefreshWorker because it is being executed before schedule.
```

WorkManager refuses a JobScheduler run before the work's own schedule, so a forced
`cmd jobscheduler run` does nothing; the snapshot stayed stale (the periodic job was next
due in about 3h45m). The `APPWIDGET_UPDATE` broadcast from the shell is also denied, so
the stale state could not be rendered on the widget first. Changing the device date was
out of scope. Opening the app afterwards rewrote the snapshot to today, as expected.

## Other observations

- After a **force-stop**, One UI greys out both widgets (placeholder icon) until the app
  is launched again. This is platform behaviour for stopped packages, not an app bug.
- The old debug build on the phone (installed 2026-10-18, different signature) had a
  widget snapshot dated 2026-10-31 on 2026-11-04. That build predates the WorkManager
  roll-over fix.
