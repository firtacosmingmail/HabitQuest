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
- **Profile** (`/profile`, the avatar in the Quest header): your name,
  email, member-since date and sign-in method; change your password, log out
  or delete your account. See [Profile & account](#profile--account).
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
directly). **The app works out of the box**: a plain `flutter run` (no
`--dart-define`) talks to the live backend.

**Where dev/prod live (the one file to edit):**
[`lib/core/config/env.dart`](lib/core/config/env.dart) has an `AppEnv`
enum (`dev`, `prod`) and the `appEnvs` map with each environment's
`supabaseUrl` and `supabaseAnonKey`. Both currently point at
`https://fwikodmrfoorbstmkedx.supabase.co`. To move prod to another project,
change the `AppEnv.prod` entry there.

**Picking an environment:** `prod` in release builds, `dev` otherwise
(debug/profile). Force one with `ENV`:

```sh
flutter run --dart-define=ENV=prod
flutter build web --dart-define=ENV=dev
```

**Overriding (other servers, local Supabase):** a non-empty
`SUPABASE_URL` and/or `SUPABASE_ANON_KEY` define replaces the chosen
environment's value, each one independently:

| Define | Default | Meaning |
|---|---|---|
| `ENV` | `prod` in release, else `dev` | Which `appEnvs` entry to use |
| `SUPABASE_URL` | the env entry's URL | Project URL; the app calls `{SUPABASE_URL}/functions/v1/<name>` |
| `SUPABASE_ANON_KEY` | the env entry's anon key | Public **anon** key, sent as `apikey` on every request |

```sh
flutter run --dart-define=SUPABASE_URL=http://127.0.0.1:54321 \
            --dart-define=SUPABASE_ANON_KEY=eyJhbGciOi...

# Or keep overrides in a file (env/*.json is gitignored)
cp env/example.json env/local.json     # then fill it in
flutter run --dart-define-from-file=env/local.json
```

`env/local.json` looks like:

```json
{
  "SUPABASE_URL": "https://fwikodmrfoorbstmkedx.supabase.co",
  "SUPABASE_ANON_KEY": "eyJhbGciOi..."
}
```

The login screen's "Server not configured" message only appears if the
resulting URL or key is empty, which does not happen with the built-in
entries.

**Keys:** the anon (publishable) key is public by design: it ships inside
every client, and row-level security plus the Edge Functions protect the
data. That is why it is committed in `env.dart`. The `service_role` (secret)
key bypasses all of that and must **never** be put in the app, in
`env.dart`, or in any define.

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

## Advertising (AdMob)

Habit Quest shows small Google AdMob banners on iOS and Android
(`google_mobile_ads`). **Web has no ads**, and neither do tests.

### Where ads appear

- **Habits list**: one inline ad after the 3rd habit card, then after every 6
  more (9th, 15th, ...), counted across *Today* and *Other habits*. With 1-2
  habits, one ad at the end of the list; none when the list is empty.
  Archived habits get no ads. Ads always sit between whole cards, so never
  between a card and its check-in button.
- **Habit details**: one ad under the monthly calendar, above the actions.
- **Nowhere else**: never on login, profile, splash, create or edit screens.

Each ad sits in a rounded frame about 85% as wide as a habit card, centred,
with a small "Ad" label. Banners load lazily (when the slot is first laid
out) and take no space until they load, so a failed ad collapses cleanly. The
list uses an inline adaptive banner (max 100 pt tall); details uses a medium
rectangle (300x250) when it fits, else an inline adaptive banner.

### Where the IDs live

Every ID defaults to **Google's official test IDs**, which always serve test
ads. All of them are listed in one place, `lib/core/config/env.dart`
(`admobEnvs`, per environment):

| What | Default (test) | Also set in |
|---|---|---|
| iOS app ID | `ca-app-pub-3940256099942544~1458002511` | `ios/Runner/Info.plist` `GADApplicationIdentifier` |
| Android app ID | `ca-app-pub-3940256099942544~3347511713` | `android/app/src/main/AndroidManifest.xml` `com.google.android.gms.ads.APPLICATION_ID` |
| Habits list banner (iOS / Android) | `.../2934735716` / `.../6300978111` | — |
| Habit details banner (iOS / Android) | `.../2934735716` / `.../6300978111` | — |

The native SDKs read the **app IDs** before any Dart code runs, so those must
also be changed in `Info.plist` and `AndroidManifest.xml` (keep all three in
sync). Unit IDs can be overridden per build without editing code:

```sh
flutter run \
  --dart-define=ADMOB_IOS_HABITS_LIST_UNIT_ID=ca-app-pub-XXXX/YYYY \
  --dart-define=ADMOB_ANDROID_HABITS_LIST_UNIT_ID=ca-app-pub-XXXX/YYYY \
  --dart-define=ADMOB_IOS_HABIT_DETAILS_UNIT_ID=ca-app-pub-XXXX/YYYY \
  --dart-define=ADMOB_ANDROID_HABIT_DETAILS_UNIT_ID=ca-app-pub-XXXX/YYYY
flutter run --dart-define=ADS_ENABLED=false   # no ads at all
```

### Switching to real ads

1. Create an AdMob account at <https://admob.google.com> and add two apps:
   *Habit Quest* for iOS and for Android. Each has an **app ID**
   (`ca-app-pub-…~…`, under *App settings*).
2. In each app create two **Banner** ad units, e.g. *Habits list* and
   *Habit details*. Each has an **ad unit ID** (`ca-app-pub-…/…`).
3. Put the IDs in `admobEnvs` in `lib/core/config/env.dart` (prod; keep test
   IDs for dev, as Google asks you not to click your own live ads), and the
   app IDs in `Info.plist` and `AndroidManifest.xml`.
4. In AdMob, *Privacy & messaging*: create a **GDPR** consent message (and the
   US state regulations message if you serve the US), and optionally an
   **IDFA explainer** for iOS. Publish them.
5. Add an `app-ads.txt` on your developer website.

### Consent and privacy

- At app start (after the first frame) the app runs **Google UMP**
  (`ConsentInformation` / `ConsentForm`): it refreshes the consent
  requirement and shows the consent form when required (EU/UK). No ad is
  requested and the Mobile Ads SDK is not started before this finishes. If
  UMP says ads may not be requested, no ads are shown.
- On **iOS**, the **App Tracking Transparency** prompt follows UMP
  (`NSUserTrackingUsageDescription` in `Info.plist`). If tracking is not
  authorised, or the consent status is unresolved, ads are requested as
  **non-personalised**. EU users who decline in the UMP form get limited /
  non-personalised ads automatically (the SDK reads the IAB TCF consent string
  UMP stores).
- `Info.plist` lists Google's `SKAdNetworkItems` (from
  <https://developers.google.com/admob/ios/3p-skadnetworks>; refresh it when
  Google updates the list).
- Android needs `minSdk` 24 (set in `android/app/build.gradle.kts`).
- iOS builds with CocoaPods. `ios/Flutter/{Debug,Release}.xcconfig` and the
  `Podfile` set `CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = YES`,
  because the plugin's headers include the Google Mobile Ads SDK's
  non-modular private headers, which current Xcode otherwise rejects.

### Code

`lib/features/ads/`: `AdService` (interface), `NoopAdService` (web, tests,
`ADS_ENABLED=false`, desktop), `GoogleAdService` (consent + banners,
`platform_ad_service_mobile.dart`, only compiled off the web), `AdSlot` /
`AdFrame` (the widget and its look), `AdsBootstrap` (starts consent from
`main.dart`). Widget tests override `adServiceProvider` with
`test/helpers/fake_ad_service.dart`, which renders a placeholder box.

## Email confirmation

The live Supabase project (`fwikodmrfoorbstmkedx`) has email confirmations
**on**: after signing up, the user must click the link in the email before
they can log in.

**Pages.** Two static pages (plain HTML/CSS, no build, no secrets) live in
[`confirm-pages/`](confirm-pages/) and are published on GitHub Pages from the
`gh-pages` branch of
[firtacosmingmail/HabitQuest](https://github.com/firtacosmingmail/HabitQuest):

- success: <https://firtacosmingmail.github.io/HabitQuest/>
- error: <https://firtacosmingmail.github.io/HabitQuest/error.html?reason=expired|invalid|missing>

The old `cf-latch/habit-quest-pages` repo is no longer used and can be deleted.

**Flow today (Supabase's default email template).** The free tier with the
built-in email provider does not allow custom templates, so the email still
uses Supabase's default `{{ .ConfirmationURL }}`: Supabase Auth
(`/auth/v1/verify`) confirms the email and redirects to `redirect_to`, which
`auth-register` sets to the success page (`emailRedirectTo` = the
`CONFIRM_SUCCESS_URL` secret). On failure Supabase appends
`#error_code=otp_expired`, and the success page forwards to `error.html`.

**Flow with the custom template (once custom SMTP is configured).**
`supabase/templates/confirmation.html` links to the `auth-confirm` Edge Function
(`verify_jwt = false`):
`https://fwikodmrfoorbstmkedx.supabase.co/functions/v1/auth-confirm?token_hash={{ .TokenHash }}&type=signup`.
It calls `verifyOtp` and 303-redirects to the success page, or to
`error.html?reason=...`. Edge Functions can't serve HTML (GET `text/html` is
rewritten to `text/plain`), which is why the pages are hosted separately. To
switch to this flow: set up SMTP (for example Resend or Brevo free tiers) in the
dashboard, uncomment `[auth.email.template.confirmation]` in
`supabase/config.toml`, and push only the auth config (see the caveat below).

**Secrets** (function secrets, not in the repo):

```bash
supabase secrets set --project-ref fwikodmrfoorbstmkedx \
  CONFIRM_SUCCESS_URL=https://firtacosmingmail.github.io/HabitQuest/ \
  CONFIRM_ERROR_URL=https://firtacosmingmail.github.io/HabitQuest/error.html
supabase functions deploy auth-confirm --no-verify-jwt
supabase functions deploy auth-register --no-verify-jwt
```

If the secrets are unset, `auth-confirm` answers in plain text and
`auth-register` falls back to the success page URL.

**Redeploying the pages.** Edit `confirm-pages/`, copy the changed files to the
root of the `gh-pages` branch of firtacosmingmail/HabitQuest, commit and push
that branch. GitHub Pages rebuilds in a minute or so.

**Auth settings on the live project:** `site_url` is the success page, and the
redirect allow-list holds both page URLs, the `auth-confirm` URL and
`habitquest://auth-callback`.

**Config push caveat.** `supabase config push` pushes the **whole**
`config.toml` (API, DB, storage, all auth settings) and does **not** stop when
you answer "n" to its prompt. `config.toml` has been aligned with the remote
(`enable_confirmations = true`, `otp_length = 8`, `max_frequency = "1m0s"`,
MFA TOTP on), but the CLI defaults can still drift. Prefer the Management API
for single auth fields:

```bash
curl -X PATCH https://api.supabase.com/v1/projects/fwikodmrfoorbstmkedx/config/auth \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" -H "Content-Type: application/json" \
  -d '{"site_url":"https://firtacosmingmail.github.io/HabitQuest/"}'
```

`SUPABASE_ACCESS_TOKEN` is the token `supabase login` saved. On macOS it is in
the Keychain (service "Supabase CLI", stored as `go-keyring-base64:<base64>`):
`export SUPABASE_ACCESS_TOKEN=$(security find-generic-password -s "Supabase CLI" -w | sed 's/^go-keyring-base64://' | base64 -d)`.
Never print or commit it.

**Testing by hand.** Sign up in the app with a real address, open the email,
tap the link, check that the "Email confirmed! 🎉" page appears, then log in
in the app. The built-in email provider sends only a few emails per hour.

## Profile & account

Tap the avatar (your initials) at the top right of the Quest tab to open
`/profile` (`lib/features/profile/`). The Logout button lives there too,
behind a confirmation.

- **Header**: avatar initials (from the display name, else the email), the
  display name with an inline ✏️ edit (trimmed, 1–50 characters), and the
  email.
- **Member since** and **Sign-in method** ("Email & password", "Google",
  "Apple"), from `GET /profile`.
- **Change password** (hidden for accounts without a password, such as
  Google/Apple sign-ins): current, new and confirm fields, checked in the
  app (6–72 characters, different from the current one, matching) and on the
  server (wrong current password → shown on that field). Supabase revokes the
  existing sessions when the password changes, so the app signs in again with
  the new password straight away.
- **Danger zone → Delete account**: a dialog explains what goes, and you must
  type `DELETE`. The server deletes your check-ins, habits, game state and
  profile, then the auth user. The app then wipes everything it keeps on the
  device (habits, check-ins, game state, sync queue, sync cursors and the
  owner marker), cancels scheduled reminders, clears the session and shows
  "Your account was deleted" on the login screen. Offline, the dialog says
  "You need to be online to delete your account" and nothing is deleted.

Backend: the `profile`, `auth-change-password` and `account-delete` Edge
Functions (contract in [supabase/API.md](supabase/API.md#account)). They
check the caller's token in code and read or write the user's rows with the
caller's JWT, so RLS applies; the user is always the token's user, never an
id from the request. Only `account-delete` uses the service role key, for
`auth.admin.deleteUser`: Supabase provides `SUPABASE_SERVICE_ROLE_KEY` to
deployed functions, so it stays on the server and is never in the app.

Deploy them with:

```sh
supabase functions deploy profile auth-change-password account-delete \
  --no-verify-jwt --project-ref fwikodmrfoorbstmkedx
```

In code, the app talks to them through `AccountApi` (`HttpAccountApi`;
`FakeAccountApi` in tests), and `LocalDataWiper` does the local cleanup.

## Sign in with Google & Apple

The login/register screen shows **Continue with Google** and **Sign in with
Apple** above the email form (with an "or" divider). The native SDK
(`google_sign_in`, `sign_in_with_apple`) returns an **ID token**; the app
sends it to the `auth-oauth` Edge Function, which calls
`supabase.auth.signInWithIdToken` and returns the usual session (contract in
[supabase/API.md](supabase/API.md#auth-oauth)). The app never talks to
Supabase Auth directly. After that it behaves exactly like an email login
(stored session, refresh, sync ownership, redirect to `/habits`). A first
sign-in creates the account; the signup trigger fills the profile's display
name from the provider's name when it has one. On the Profile screen these
accounts show "Google" / "Apple" as the sign-in method and have no Change
password.

**Until you configure it, the buttons are hidden** (debug builds show a small
"not configured" hint under the form). Exception: on iOS/macOS the Apple
button always shows (native flow), but it answers "Apple sign-in isn't set up
yet" until Apple is enabled in Supabase.

| Platform | Google | Apple |
|---|---|---|
| iOS / macOS | native, iOS client ID | native (bundle ID) |
| Android | native (Credential Manager), web client ID as `serverClientId` | Apple's web flow, only if `appleServiceId` + `appleRedirectUri` are set |
| Web | Google's own rendered button, web client ID | Apple's JS popup, only if `appleServiceId` + `appleRedirectUri` are set |

Code: `lib/features/auth/oauth/` (`OAuthSignIn` interface,
`PlatformOAuthSignIn`, `FakeOAuthSignIn` for tests, `OAuthConfig`, brand
buttons), `AuthController.signInWithGoogle/signInWithApple`. Apple gets a
fresh random nonce per sign-in: its SHA-256 goes to Apple (and into the
token), the raw value goes to the server, which Supabase hashes to compare.

### 1. Google Cloud: OAuth clients

In the [Google Cloud console](https://console.cloud.google.com/) (one
project for the app):

1. **APIs & Services → OAuth consent screen** (Google Auth Platform →
   Branding / Audience): app name "Habit Quest", support email, logo,
   authorized domain `supabase.co` (plus your web domain), the scopes
   `openid`, `email`, `profile`. Publish it (or add test users while in
   Testing).
2. **Credentials → Create credentials → OAuth client ID**, three times:
   - **iOS**: bundle ID `com.habitquest.habitQuest`. Gives the *iOS client
     ID* (`1234-abcd.apps.googleusercontent.com`) and its reversed form
     `com.googleusercontent.apps.1234-abcd` (shown as "iOS URL scheme").
   - **Android**: package name `com.habitquest.habit_quest` and the
     **SHA-1** of the signing certificate. Get it with
     `cd android && ./gradlew signingReport` (the `debug` variant for
     development) or
     `keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android`.
     Add one Android client per certificate (debug, your upload/release key,
     and the Play App Signing key from the Play Console). The app never
     uses this client's ID directly: Google matches package + SHA-1.
   - **Web application**: gives the *web client ID* and a **client
     secret**. Authorized JavaScript origins: your web app's origin(s), e.g.
     `http://localhost:5000` for `flutter run -d chrome --web-port 5000`.
     Authorized redirect URI:
     `https://fwikodmrfoorbstmkedx.supabase.co/auth/v1/callback`.

### 2. Apple Developer: App ID, Services ID, key

Needs a **paid Apple Developer Program** membership (team `9QMS59N2BZ` is
set in the Xcode project).

1. **Certificates, Identifiers & Profiles → Identifiers → App IDs**:
   `com.habitquest.habitQuest`, enable the **Sign in with Apple**
   capability. The app already ships `ios/Runner/Runner.entitlements`
   (`com.apple.developer.applesignin = Default`, wired via
   `CODE_SIGN_ENTITLEMENTS`); Xcode's automatic signing then picks a profile
   with the capability.
2. Only for Android / web (Apple's web flow): **Identifiers → Services
   IDs**, e.g. `com.habitquest.signin`; enable Sign in with Apple, primary
   App ID `com.habitquest.habitQuest`, domain = your web domain, and a
   **Return URL**. On web the return URL is your site (the JS popup posts back
   to it). On Android it must be an HTTPS endpoint that redirects to
   `intent://callback?<the posted params>#Intent;package=com.habitquest.habit_quest;scheme=signinwithapple;end`
   (see the `sign_in_with_apple` package docs; the Android callback activity
   is already in `AndroidManifest.xml`). Without it, leave the Apple button
   hidden on Android.
3. **Keys → +**: enable Sign in with Apple (primary App ID as above),
   download the `.p8` once, and note the **Key ID** and your **Team ID**
   (top right of the portal). Supabase uses them to generate the client
   secret (a JWT, valid at most 6 months: regenerate it before it expires).

### 3. Supabase dashboard → Authentication → Sign In / Providers

- **Google**: enable; *Client ID* = the **web client ID**, *Client Secret* =
  the web client's secret. **Authorized Client IDs**: add the **iOS client
  ID** and the **web client ID** (comma separated; plus any Android client
  IDs if you ever make tokens for them). Leave "Skip nonce check" off.
- **Apple**: enable; *Client IDs* = the bundle ID
  `com.habitquest.habitQuest` (native iOS tokens) and, if used, the Services
  ID `com.habitquest.signin` (web flow tokens), comma separated; *Secret
  Key* = the client secret generated from the Team ID, Key ID and `.p8`
  (the dashboard has a generator).

Until a provider is enabled, `auth-oauth` answers `400 provider_disabled`
and the app says "Google sign-in isn't set up yet (it's turned off on the
quest server)".

### 4. Values to put in the app

| Value | Where |
|---|---|
| iOS client ID | `googleIosClientId` in `lib/core/config/env.dart` (or `--dart-define=GOOGLE_IOS_CLIENT_ID=...`) |
| Reversed iOS client ID | `ios/Runner/Info.plist` → `CFBundleURLSchemes`: replace `com.googleusercontent.apps.REPLACE-WITH-IOS-CLIENT-ID`. Required: Google Sign-In on iOS returns through this URL scheme and refuses to start without it |
| Web client ID | `googleWebClientId` in `env.dart` (or `GOOGLE_WEB_CLIENT_ID`). Used on web and as the Android `serverClientId`, so Android ID tokens have the web client as their audience |
| Android SHA-1(s) | Google Cloud only (Android OAuth client), nothing in the app |
| Apple Services ID + return URL | `appleServiceId` / `appleRedirectUri` in `env.dart` (or `APPLE_SERVICE_ID` / `APPLE_REDIRECT_URI`): Android/web only |
| Web client secret, Apple Team ID / Key ID / `.p8` | Supabase dashboard only. **Never** in the app |

Example run without editing files:

```sh
flutter run \
  --dart-define=GOOGLE_IOS_CLIENT_ID=1234-ios.apps.googleusercontent.com \
  --dart-define=GOOGLE_WEB_CLIENT_ID=1234-web.apps.googleusercontent.com
```

(The Info.plist URL scheme still has to be edited for iOS.)

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
exponential backoff (5 s doubling up to 5 min); a `429 rate_limited` also
holds the automatic triggers (local changes, connectivity, resume) until
the backoff retry, only **Sync now** overrides it; a `401` is first handled by
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
   are retried one by one (the server writes nothing from a batch with an
   invalid item): the offending entity stays queued with its error (shown
   as "N changes couldn't sync") and **never blocks the rest**. In that
   per-item path, tombstones go out as `DELETE …?updatedAt=<local
   updatedAt>` (always sent, so LWW uses the client's time), and a `404
   not_found` counts as acknowledged (the server never had the row).
2. **Pull** deltas `since` the stored cursors (the `serverTime` of the
   previous pull; stored per user, separately for habits and check-ins;
   the server sets it 5 s in the past, so rows can come back again and an
   equal `updatedAt` is a no-op) and
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

### Mapping notes

The contract's Habit has no `startDate` (the start of "every N days"
schedules). It travels inside the opaque `schedule` object as
`schedule.startDate = "yyyy-MM-dd"`; on pull, a missing or malformed value
falls back to the date of `createdAt`.

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
    profile/ auth-change-password/ account-delete/
    tests/                    # Deno unit tests + e2e_smoke.ts
  .env.example                # placeholders only, never commit real keys
```

Tables `profiles` (created by a trigger on sign-up), `habits`, `check_ins`
and `game_state` each belong to `auth.uid()` and have row-level security with
select/insert/update/delete policies. The functions create their Supabase
client with the anon key plus the caller's JWT, so RLS applies to every query;
the service-role key is used only by `account-delete` (for
`auth.admin.deleteUser`, see [Profile & account](#profile--account)).

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
| `auth-register`, `auth-login`, `auth-refresh`, `auth-oauth` | off | called without a user token |
| `auth-logout`, `habits`, `check-ins`, `game-state`, `profile`, `auth-change-password`, `account-delete` | off | the function validates the bearer token itself (`supabase.auth.getUser`) so a bad token gets the contract's `401 {"error":{"code":"unauthorized"}}` body instead of the gateway's own format; data is still only reachable with the user's JWT through RLS |

```sh
supabase functions deploy auth-register --no-verify-jwt
supabase functions deploy auth-login    --no-verify-jwt
supabase functions deploy auth-refresh  --no-verify-jwt
supabase functions deploy auth-logout   --no-verify-jwt
supabase functions deploy auth-oauth    --no-verify-jwt
supabase functions deploy habits        --no-verify-jwt
supabase functions deploy check-ins     --no-verify-jwt
supabase functions deploy game-state    --no-verify-jwt
supabase functions deploy profile auth-change-password account-delete --no-verify-jwt
# or all at once (uses config.toml): supabase functions deploy
```

### 4. Secrets and auth settings

The functions need **no custom secrets**: `SUPABASE_URL` and
`SUPABASE_ANON_KEY` (and `SUPABASE_SERVICE_ROLE_KEY`, used server-side by
`account-delete` only) are injected by the Edge Runtime. If you add one later, use
`supabase secrets set NAME=value` (or `supabase secrets set --env-file
supabase/.env`) and list it in `supabase/.env.example` with a placeholder.
Never commit keys.

In the dashboard (Authentication → Sign In / Providers → Email), decide
whether "Confirm email" is on. When it is, `auth-register` answers
`{"session":null,"needsConfirmation":true}` and the user must confirm before
logging in.

The app has the URL and the anon (public) key built in
(`lib/core/config/env.dart`), overridable with `--dart-define`
(see [Environment config](#environment-config)).

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
