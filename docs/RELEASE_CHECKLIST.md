# First release checklist: Play closed testing (alpha) + TestFlight

The one-time setup for the first Habit Quest release, in order. It is built
from README → [Release CI](../README.md#release-ci) (*Secrets* and *One-time
setup before the first release*), personalised for this repo:

| | |
|---|---|
| GitHub repo | `firtacosmingmail/HabitQuest` |
| Android package | `com.vvs.habitquest` |
| iOS bundle IDs | `com.vvs.habitquest` (app), `com.vvs.habitquest.widgets` (widget extension) |
| App Group | `group.com.vvs.habitquest` |
| Apple team | `9QMS59N2BZ` |
| Supabase project | `fwikodmrfoorbstmkedx` |
| Workflow | [`.github/workflows/release.yml`](../.github/workflows/release.yml), runs when a `release/VX.Y.Z` branch is created |

Legend: 💰 = costs money. **Paying is your decision**; nothing here pays for
you. 🔐 = secret material: keep it in your password manager, never commit it,
never paste it in chat.

All `gh` commands run from the repo root, logged in with `gh auth login` as
an admin of the repo. `gh secret set NAME` prompts for the value (nothing ends
up in your shell history); `gh secret set NAME < file` reads a file.

Store texts, Data safety / privacy-label answers, content rating notes and the
export-compliance reasoning are drafted in [`docs/store/`](store/). The privacy
policy draft is [`confirm-pages/privacy.html`](../confirm-pages/privacy.html)
(not published yet).

---

## 1. Accounts

- [ ] **Google Play developer account.** 💰 **$25, one-off** registration fee
  at <https://play.google.com/console/signup>. Skip if you already have one.
  New *personal* accounts must pass identity verification and, before
  production, run a closed test with at least 12 testers for 14 days; closed
  testing (alpha) itself is available right away.
- [ ] **Apple Developer Program membership for team `9QMS59N2BZ`.** 💰
  **$99 / year**, only if the membership is not active. Check at
  <https://developer.apple.com/account> → *Membership details* (status and
  expiry). TestFlight and App Store Connect need an active paid membership.
- [ ] **Google Cloud project** used for Google sign-in (the one that holds
  the iOS/web OAuth clients already in `ios/Runner/Info.plist`, project number
  `1004491055558`). Free. You need access to it for steps 2.7 and 2.10.
- [ ] **Decide the developer name and contact email** shown on the store
  listings and in the privacy policy (they replace `{{DEVELOPER_NAME}}` and
  `{{CONTACT_EMAIL}}` in `confirm-pages/privacy.html` and `docs/store/`).

## 2. Android (Google Play)

- [ ] **2.1 Generate the upload keystore** (you run this, on your Mac, outside
  the repo; e.g. in `~/keys/habitquest/`). 🔐

  ```sh
  keytool -genkeypair -v -keystore upload-keystore.jks -alias upload \
    -keyalg RSA -keysize 2048 -validity 10000
  ```

  Choose a strong store password (and use the same for the key unless you have
  a reason not to). **Save the `.jks` file and both passwords in your password
  manager right away.** Losing it means asking Google for an upload key reset
  (days of waiting).

- [ ] **2.2 Write `android/key.properties`** for local release builds (it is
  gitignored):

  ```properties
  storeFile=/Users/<you>/keys/habitquest/upload-keystore.jks
  storePassword=...
  keyAlias=upload
  keyPassword=...
  ```

- [ ] **2.3 Note the upload key SHA-1** (needed in 2.6):

  ```sh
  keytool -list -v -keystore upload-keystore.jks -alias upload | grep SHA1
  ```

- [ ] **2.4 Create the app in Play Console**: *Create app* → name **Habit
  Quest**, default language, **App** (not game), **Free**, accept the
  declarations. Package name `com.vvs.habitquest` is fixed by the first upload
  (2.8).
- [ ] **2.5 Fill in *App content*** (Play Console → *Policy → App content*),
  using the drafts in `docs/store/`:
  - [ ] Privacy policy URL: the published `privacy.html` (published in the
    next task; the expected URL is
    `https://firtacosmingmail.github.io/HabitQuest/privacy.html`).
  - [ ] Ads: **Yes, my app contains ads**.
  - [ ] App access: sign-in is required. Give reviewers a **test account**
    (email + password) you create for them in the app; see
    [`docs/store/play-listing.md`](store/play-listing.md#app-access).
  - [ ] Data safety: [`docs/store/play-data-safety.md`](store/play-data-safety.md).
  - [ ] Content rating questionnaire: [`docs/store/content-rating.md`](store/content-rating.md).
  - [ ] Target audience: 13+ (do not select under-13 age groups; see the
    content rating notes).
  - [ ] Account deletion: the in-app path plus a web URL / email request path
    (Play requires a web resource too; see the Data safety notes).
  - [ ] Government app / financial features / health: **No**.
  - [ ] Advertising ID: **Yes**, used for advertising (AdMob).
- [ ] **2.6 Play App Signing**: keep it **enabled** (default). Your keystore
  from 2.1 is the **upload key**; Google holds the app signing key.
- [ ] **2.7 Google sign-in on store builds: Android OAuth clients.** In Google
  Cloud → *APIs & Services → Credentials → Create credentials → OAuth client
  ID → Android*, package `com.vvs.habitquest`, one client **per SHA-1**:
  - [ ] the **upload key** SHA-1 (from 2.3; covers your locally built,
    side-loaded release builds);
  - [ ] the **Play app signing key** SHA-1: Play Console → *Test and release →
    App integrity → App signing* (shown after the first upload in 2.8). Builds
    installed from Play are signed with this key, so **without this client
    Google sign-in fails in every Play build**.

  (The shared debug key's client already exists; see README *Sign in with
  Google & Apple*.)

- [ ] **2.8 First AAB upload, by hand** (the Play API cannot upload to an app
  that never had a build). Build it locally with the upload key:

  ```sh
  flutter clean && flutter pub get
  ANDROID_REQUIRE_RELEASE_SIGNING=true flutter build appbundle --release
  keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab | grep Owner
  # must NOT say "CN=Android Debug"
  ```

  **On this Mac, first:** install the Android SDK *Command-line Tools*
  (Android Studio → *Settings → Languages & Frameworks → Android SDK → SDK
  Tools* → tick *Android SDK Command-line Tools (latest)*), then run
  `flutter doctor --android-licenses`. Without them `flutter build appbundle`
  writes the bundle but exits with *"Release app bundle failed to strip debug
  symbols from native libraries"* (seen in the dry run on 2026-11-14). Also,
  this Mac has Flutter 3.47 while CI pins **3.38.10**; building with 3.47
  rewrites `pubspec.lock` and `ios/Flutter/AppFrameworkInfo.plist`: don't
  commit those changes (`git checkout -- pubspec.lock ios/`).

  `ANDROID_REQUIRE_RELEASE_SIGNING=true` makes the build fail instead of
  silently falling back to the debug key. The version is the one in
  `pubspec.yaml` (`1.0.0+1` today); the first CI release then uses a higher
  build number automatically.
  (Alternative: let the CI create the bundle: after section 4, push the
  release branch; the Play upload step fails because the app has no build yet,
  but the `android-aab-<version>` artifact is kept. Download it with
  `gh run download <run-id> -n android-aab-<version>`.)

  Upload it: Play Console → *Test and release → Testing → Closed testing →
  **Alpha*** → *Create new release* → upload `app-release.aab` → release
  notes → *Next* → *Save* (and send for review when the App content forms are
  done).

- [ ] **2.9 Alpha testers**: *Closed testing → Alpha → Testers*: create an
  email list (or use a Google Group), add the testers' Google account emails,
  save, and copy the **opt-in link** to send them. Choose the countries
  (*Countries / regions* tab).
- [ ] **2.10 Service account for CI uploads**:
  1. Google Cloud → *IAM & Admin → Service accounts* → create one (e.g.
     `play-release`) → *Keys → Add key → JSON*. 🔐
  2. Enable the **Google Play Android Developer API** in that project.
  3. Play Console → *Users and permissions* → *Invite new users* → the
     service account's email → app permissions for Habit Quest: **Release to
     testing tracks** and **View app information**.
- [ ] **2.11 Android secrets** (repo `firtacosmingmail/HabitQuest`):

  ```sh
  base64 -i upload-keystore.jks | gh secret set ANDROID_KEYSTORE_BASE64
  gh secret set ANDROID_KEYSTORE_PASSWORD        # the store password from 2.1
  printf upload | gh secret set ANDROID_KEY_ALIAS
  gh secret set ANDROID_KEY_PASSWORD             # same as the store password unless you chose another
  gh secret set PLAY_SERVICE_ACCOUNT_JSON < service-account.json   # plain JSON, not base64
  ```

  Then delete the downloaded `service-account.json` from Downloads once it is
  in your password manager.

## 3. Apple (TestFlight)

- [ ] **3.1 Identifiers** (developer.apple.com → *Certificates, IDs &
  Profiles*). Check they exist (Xcode's automatic signing usually made them):
  - [ ] App ID `com.vvs.habitquest` with **Sign in with Apple** and **App
    Groups** (`group.com.vvs.habitquest`) enabled.
  - [ ] App ID `com.vvs.habitquest.widgets` with **App Groups**
    (`group.com.vvs.habitquest`).
  - [ ] App Group `group.com.vvs.habitquest`.
- [ ] **3.2 Apple Distribution certificate** (if the team has none): Xcode →
  *Settings → Accounts* → team `9QMS59N2BZ` → *Manage Certificates* → **+** →
  *Apple Distribution*. Then Keychain Access → *My Certificates* → right-click
  "Apple Distribution: …" → *Export* → `dist.p12` with a password. 🔐
- [ ] **3.3 Two App Store provisioning profiles** (*Profiles → + → App Store
  Connect*), both with the certificate from 3.2, created **after** the
  capabilities in 3.1 are on:
  - [ ] App ID `com.vvs.habitquest` → name e.g. *Habit Quest App Store*.
  - [ ] App ID `com.vvs.habitquest.widgets` → name e.g. *Habit Quest Widgets
    App Store*.
- [ ] **3.4 Create the app in App Store Connect**: *Apps → + → New App* →
  iOS, name **Habit Quest**, primary language, bundle ID `com.vvs.habitquest`,
  SKU e.g. `habitquest-ios`, full access. TestFlight uploads fail until this
  record exists.
- [ ] **3.5 App Store Connect API key**: *Users and Access → Integrations →
  App Store Connect API → Team Keys* → generate, role **App Manager**. Note the
  **Key ID** and the **Issuer ID**, and download `AuthKey_<KEYID>.p8`
  (**downloadable only once**). 🔐
- [ ] **3.6 App Privacy** (App Store Connect → the app → *App Privacy*): fill
  in from [`docs/store/app-store-privacy.md`](store/app-store-privacy.md), with
  the privacy policy URL. Not needed for internal TestFlight, but needed for
  external testers and the store.
- [ ] **3.7 Apple secrets**:

  ```sh
  base64 -i dist.p12 | gh secret set IOS_DIST_CERT_P12_BASE64
  gh secret set IOS_DIST_CERT_PASSWORD           # the .p12 export password
  base64 -i Habit_Quest_App_Store.mobileprovision | gh secret set IOS_PROVISIONING_PROFILE_BASE64
  base64 -i Habit_Quest_Widgets_App_Store.mobileprovision | gh secret set IOS_WIDGETS_PROVISIONING_PROFILE_BASE64
  gh secret set ASC_KEY_ID                       # 10-character Key ID
  gh secret set ASC_ISSUER_ID                    # the UUID on the keys page
  base64 -i AuthKey_<KEYID>.p8 | gh secret set ASC_PRIVATE_KEY_P8_BASE64
  ```

- [ ] **3.8 Export compliance**: decide the answer (proposal:
  `ITSAppUsesNonExemptEncryption = false`, see
  [`docs/store/export-compliance.md`](store/export-compliance.md)). Either
  answer it per build in App Store Connect, or approve adding the key to
  `ios/Runner/Info.plist` so builds go straight to testers.
- [ ] **3.9 TestFlight internal testers**: App Store Connect → the app →
  *TestFlight → Internal Testing → +* → a group (e.g. *Team*) → add users
  (they must be App Store Connect users of the team; up to 100). Enable
  automatic distribution so each new build reaches them.

## 4. GitHub

- [ ] **4.1 Workflow permissions**: *Settings → Actions → General → Workflow
  permissions* → tick **Allow GitHub Actions to create and approve pull
  requests** (the *Open PR into main* job needs it). Check:

  ```sh
  gh api repos/firtacosmingmail/HabitQuest/actions/permissions/workflow
  # "can_approve_pull_request_reviews": true
  ```

- [ ] **4.2 `release/*` must accept pushes from `github-actions[bot]`** (the
  *Set version* job pushes the version commit). If you add branch protection
  or a ruleset that matches `release/*` (or `**`), add *GitHub Actions* to its
  bypass list, or don't require PRs / signed commits on `release/*`. Check
  what applies today:

  ```sh
  gh api repos/firtacosmingmail/HabitQuest/rulesets
  gh api repos/firtacosmingmail/HabitQuest/branches/main/protection   # 404 = no protection
  ```

- [ ] **4.3 Repository variable `PLAY_RELEASE_STATUS=draft`** (Play rejects
  `completed` releases while the app is a draft):

  ```sh
  gh variable set PLAY_RELEASE_STATUS --body draft
  ```

  Remove it (`gh variable delete PLAY_RELEASE_STATUS`) once the app has passed
  review and is published to a track; then CI rolls out to alpha testers at
  once.

- [ ] **4.4 All 12 secrets present** (names only; values are never shown):

  ```sh
  gh secret list
  gh variable list
  ```

  Expected: `ANDROID_KEYSTORE_BASE64`, `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS`, `ANDROID_KEY_PASSWORD`, `PLAY_SERVICE_ACCOUNT_JSON`,
  `IOS_DIST_CERT_P12_BASE64`, `IOS_DIST_CERT_PASSWORD`,
  `IOS_PROVISIONING_PROFILE_BASE64`, `IOS_WIDGETS_PROVISIONING_PROFILE_BASE64`,
  `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_PRIVATE_KEY_P8_BASE64`, and the variable
  `PLAY_RELEASE_STATUS=draft`.

## 5. First release

- [ ] **5.1 Privacy policy published** (fill the placeholders, then publish
  `confirm-pages/privacy.html` to gh-pages) and its URL entered in Play
  Console (2.5) and App Store Connect (3.6).
- [ ] **5.2 First AAB is in Closed testing → Alpha** (2.8), and the
  app-signing SHA-1 OAuth client exists (2.7).
- [ ] **5.3 Cut the release** from an up-to-date `main`:

  ```sh
  git checkout main && git pull
  git checkout -b release/V1.0.0
  git push origin release/V1.0.0
  gh run watch    # pick the "Release" run
  ```

  The branch name must be exactly `release/VX.Y.Z` (or `release/vX.Y.Z`). The
  version must be higher than the manual upload's build number; CI uses
  `max(current build + 1, run number)`, so `1.0.0+2` or more.
- [ ] **5.4 Check the run**: *Set version* pushed `chore(release): set version
  to 1.0.0+N`, a PR "Release 1.0.0+N" is open into `main`, analyze/test
  passed, *Android → Play alpha* and *iOS → TestFlight* are green. On failure,
  see README *When something fails* (fix on the release branch, then
  *Actions → Release → Run workflow* on that branch).
- [ ] **5.5 Play**: with `PLAY_RELEASE_STATUS=draft` the alpha release is a
  **draft**: open it in Play Console → *Closed testing → Alpha*, review, and
  *Send for review* / roll out. Testers join through the opt-in link (2.9).
- [ ] **5.6 TestFlight**: the build appears after Apple's processing (~10–30
  min). Answer **export compliance** if prompted (3.8), then it reaches the
  internal testers (3.9) automatically.
- [ ] **5.7 Smoke test on both stores' builds**: sign in with email, Google
  (Play build: proves the app-signing OAuth client) and Apple; a habit
  check-in syncs; ads show (or collapse) after the consent form; reminders
  fire; widgets update.
- [ ] **5.8 Merge the auto-opened release PR** into `main` (it only carries
  the version bump).
