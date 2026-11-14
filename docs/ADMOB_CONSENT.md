# AdMob consent setup (Privacy & messaging)

A click-by-click guide for the AdMob console. You do the clicks (an agent
cannot log in). The app side (Google UMP, then ATT on iOS) is already
built: see README *Advertising (AdMob) > Consent and privacy*.

- Publisher: `pub-5156448354942178`
- Apps: **Habit Quest** iOS and Android, both `com.vvs.habitquest`
- Privacy policy URL: `https://firtacosmingmail.github.io/HabitQuest/privacy.html`
  (**not live yet**: it returned 404 on 2026-11-14. It goes live in the
  release-checklist task, from `confirm-pages/privacy.html`. Publish it
  first, or save the messages as drafts until it is live.)

Sources (checked 2026-11-14): Google AdMob Help *Create a European
regulations message* (support.google.com/admob/answer/10113207), *US state
regulations messages* (answer/10860309, 10862202), *IDFA explainer messages*
(answer/10115027), and the Flutter UMP guide
(developers.google.com/admob/flutter/privacy). The console changes from
time to time. If a label below doesn't match what you see, follow the help
article and choose the closest option.

---

## 0. Before you start

1. Sign in at <https://admob.google.com> with the account that owns
   `pub-5156448354942178`.
2. Left menu: **Privacy & messaging**. It shows cards for **European
   regulations**, **US state regulations** and **IDFA**, and a gear icon
   for settings.
3. Optional but recommended: open the **European regulations** settings
   (gear icon / *Settings*) > **Ad partners** and leave **Commonly used ad
   partners** (Google's default list). *Why:* we only use AdMob, and
   Google's default list is enough.

---

## 1. European regulations (GDPR) message, both apps

Shown to users in the EEA, the UK and Switzerland. Without it, Google
serves only limited ads there.

1. **Privacy & messaging** > **European regulations** card > **Create
   message**. (If one exists already: **Manage** > **Create message**.)
2. **Select apps** > tick **Habit Quest (iOS)** and **Habit Quest
   (Android)** > **Confirm**.
   *Why:* one message for both apps keeps the wording and choices the same.
3. **Languages**
   - **Default language: English.** *Why:* the app is in English, and this
     language is used when the device language can't be detected.
   - **Additional languages: none for now.** *Why:* the app has no
     translations, and the message should match the app's language. (Add
     some later if you like; Google translates the fixed text.)
4. **User consent options**
   - **Consent** (always on): stays.
   - **Manage options** (always on): stays.
   - **Do not consent: ON**, for **all targeted countries**. *Why:* GDPR
     and UK guidance expect refusing to be as easy as accepting, and
     Google requires it for the UK and France, among others. Users who
     decline still see limited, non-personalised ads, so the app keeps
     working.
   - **Close (do not consent): OFF**. *Why:* the extra "X" is optional.
     Turn it on only if you want an even softer form (it counts as
     declining).
5. **Targeting: Countries subject to GDPR (EEA, UK, and Switzerland).**
   *Why:* this asks only users the law covers. "Everywhere" would show the
   form to US and other users for no reason and lose revenue.
6. **Message name:** `Habit Quest – GDPR`. *Why:* only you see it, and it
   tells the messages apart.
7. **Privacy policy URL:** the URL above. *Why:* it's required, and the
   form links to it.
8. **Styling** (optional, the *Edit* / style panel): keep Google's
   defaults, or set the primary colour to the app's purple. You can add the
   app icon as the header image. *Why:* it's cosmetic. Don't change the
   wording of the legal text.
9. **Publish.** (Or **Save draft** if the privacy page isn't live yet, and
   publish it later.)
   *Why:* only published messages reach the app. A change can take a few
   minutes to an hour to show up.

---

## 2. US state regulations message

Needed for California and the other US states with privacy laws, which
Google covers automatically.

1. **Privacy & messaging** > **US state regulations** card > **Create
   message**. (If one exists already: **Manage** > **Create message**.)
2. **Select apps** > both Habit Quest apps > **Confirm**.
3. **Languages:** default **English**, no extras (same reason as above).
4. **Targeting: turn ON "All current and future supported US states".**
   *Why:* new states get covered without you editing the message.
5. **Message name:** `Habit Quest – US states`.
6. **Privacy policy URL:** the same URL.
7. **Styling:** same as the GDPR message, so the two look alike.
8. **Publish.**

How it behaves: US users **don't** see a form at app start. This is an
opt-out message: it appears only when the user opens the app's privacy
options. That's why the app has a **Settings > Ads & privacy > Ad privacy
choices** entry. It shows only when UMP says it is required (EEA/UK users,
and regulated US states once this message is published). Opening it shows
the "Do not sell or share my personal information" form, where users opt
out.

---

## 3. IDFA explainer (iOS only, optional)

A screen Google shows just before Apple's "Allow tracking?" prompt,
explaining why. It usually raises the opt-in rate.

**Recommendation: create it.** It costs nothing, and the app already
supports it. UMP shows the explainer and then Apple's ATT prompt itself.
The app's own ATT call then finds the status already decided and doesn't
ask a second time.

1. **Privacy & messaging** > **IDFA** card > **Create message**.
2. **Select apps** > **Habit Quest (iOS)** only > **Confirm**. (There is
   no IDFA on Android.)
3. **Languages:** default **English**.
4. **Message name:** `Habit Quest – IDFA explainer`.
5. **Explainer text:** keep Google's text, or shorten it to match the
   app's ATT text (in `Info.plist`):
   *"Habit Quest is free thanks to a few small ads. Allowing tracking lets
   us show ads that are more relevant to you. Your habits are never
   shared."*
   *Why:* the explainer and the Apple prompt should say the same thing.
6. **ATT alert page:** this is a preview of Apple's dialog. The text comes
   from `NSUserTrackingUsageDescription` in the app, not from AdMob, so
   there's nothing to change here.
7. **Publish.**

Order on iOS: GDPR form (EEA/UK only), then the IDFA explainer, then
Apple's ATT prompt. Each one only appears if needed.

---

## 4. Test the consent form on the Galaxy S24 Ultra (debug build)

Debug builds can make UMP behave as if the phone were in the EEA. This
never works in release builds: the defines are ignored when `kReleaseMode`
is true (`lib/features/ads/ad_consent_debug.dart`). Debug builds use
Google's test ad units, so tapping ads is safe.

Defines (debug and profile builds only):

| Define | Value | Effect |
|---|---|---|
| `ADS_CONSENT_DEBUG_GEOGRAPHY` | `eea`, `us` or `other` | UMP treats the device as being in that region |
| `ADS_CONSENT_TEST_DEVICE_ID` | the hashed id (comma-separate several) | the device(s) the debug geography applies to |
| `ADS_CONSENT_RESET` | `true` | forgets the stored consent at start, so the form shows again |

There's also **Settings > Ads & privacy > Reset ad consent (debug)**. It
appears in debug builds only. Restart the app after using it.

### 4.1 Connect the phone

1. On the S24 Ultra: **Settings > About phone > Software information**,
   then tap **Build number** 7 times to enable Developer options.
2. **Settings > Developer options > USB debugging: ON**.
3. Plug the phone in, accept "Allow USB debugging" on the phone, and run:
   ```sh
   adb devices          # the phone shows as "device"
   flutter devices      # note the device id (e.g. R5CX...)
   ```

### 4.2 Find the hashed device id

1. Run a debug build once, without the defines:
   ```sh
   flutter run -d <device-id>
   ```
2. In a second terminal, watch the UMP log:
   ```sh
   adb logcat -s UserMessagingPlatform
   # or: adb logcat | grep addTestDeviceHashedId
   ```
3. Look for this line (the id is a 32-character hex string):
   ```
   I UserMessagingPlatform: Use new ConsentDebugSettings.Builder().addTestDeviceHashedId("33BE2250B43518CCDA7DE426D04EE231") to set this as a debug device.
   ```
   The quoted value is your hashed id. It identifies only this test phone
   for UMP. It isn't a secret, but keep it out of the repo anyway: pass it
   on the command line.

(On an iPhone, the Xcode console prints `To enable debug mode for this
device, set: UMPDebugSettings.testDeviceIdentifiers = @[ @"<id>" ]`.)

### 4.3 Run with the EEA debug geography

```sh
flutter run -d <device-id> \
  --dart-define=ADS_CONSENT_DEBUG_GEOGRAPHY=eea \
  --dart-define=ADS_CONSENT_TEST_DEVICE_ID=<hashed id> \
  --dart-define=ADS_CONSENT_RESET=true
```

The app logs `Ads: consent debug: geography=eea, test devices=1,
reset=true` at start. Drop `ADS_CONSENT_RESET=true` to check that the
choice is remembered between launches. Use `ADS_CONSENT_DEBUG_GEOGRAPHY=us`
to test the US message through Settings > Ad privacy choices. You can also
wipe everything with `adb shell pm clear com.vvs.habitquest` (this also
signs you out of the app).

---

## 5. Follow-up checklist (after the messages are published)

The on-device check needs the published messages, so do it after sections
1–3.

- [ ] GDPR message published for both apps; US state message published;
      IDFA explainer published (optional).
- [ ] Privacy policy URL returns 200.
- [ ] S24 Ultra, debug build with `eea` + test device id + reset (4.3): the
      **consent form appears** on the first screen.
- [ ] **No ad is requested before the form is answered.** In
      `adb logcat | grep -E "Ads:|Ads\b|UserMessagingPlatform"`, no banner
      load (`Ads: ... failed` or an ad on screen) appears before the form
      closes. The code only starts the Mobile Ads SDK after consent
      (`GoogleAdService._consentThenStart`).
- [ ] "Do not consent": test ads still show (limited ads).
- [ ] Settings > Ads & privacy > **Ad privacy choices** is visible and
      re-opens the form.
- [ ] Restart without `ADS_CONSENT_RESET`: no form; the choice is
      remembered.
- [ ] `us` geography: no form at start; Ad privacy choices shows the US
      opt-out form.
- [ ] iOS (optional): IDFA explainer, then the ATT prompt, each shown once.
- [ ] Screenshots without personal data: use a test account, and hide or
      blur the email on Profile.
