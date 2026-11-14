# Google Play: Data safety answers

Play Console → *Policy → App content → Data safety*. Based on the code at
commit a26c259 (see the privacy policy draft
[`confirm-pages/privacy.html`](../../confirm-pages/privacy.html)).

The Google Mobile Ads SDK part follows Google's own guidance,
<https://developers.google.com/admob/android/privacy/play-data-disclosure>.
**Re-check that page when you fill the form**: Google updates it when the
SDK changes.

## Overview questions

| Question | Answer | Why |
|---|---|---|
| Does your app collect or share any of the required user data types? | **Yes** | Account data synced to Supabase; AdMob SDK |
| Is all of the user data collected by your app encrypted in transit? | **Yes** | Supabase Edge Functions over HTTPS only; the AdMob SDK uses HTTPS |
| Which account creation methods does your app support? | **Username and password**, **OAuth** (Sign in with Google, Sign in with Apple) | Login screen |
| Do you provide a way for users to request that their data is deleted? | **Yes** | Profile → Delete account (in-app), plus email request |
| Delete account URL (required with account creation) | The published privacy policy, section 8: `https://firtacosmingmail.github.io/HabitQuest/privacy.html#delete-account` | Play requires a **web** link where users can request deletion without reinstalling the app. Section 8 of the policy describes the email path |
| Has your app been independently validated against a global security standard? | **No** | |

## Data types

"Collected" = sent off the device. "Shared" = transferred to a third party
(Supabase is our processor/service provider, so sending data to it is **not**
sharing). "Ephemeral" = No unless stated.

| Category → type | Collected | Shared | Optional? | Purposes | Source |
|---|---|---|---|---|---|
| Personal info → **Email address** | Yes | No | Required | App functionality, Account management | Sign-up / Google / Apple sign-in |
| Personal info → **Name** | Yes | No | Optional (email sign-up); provided by Google/Apple | App functionality, Account management | Display name on Profile |
| Personal info → **User IDs** | Yes | No | Required | App functionality, Account management | Supabase user id |
| App activity → **Other user-generated content** | Yes | No | Required | App functionality | Habits (name, emoji, colour, schedule, reminder time) synced to your account |
| App activity → **Other actions** | Yes | No | Required | App functionality | Check-ins, game state (XP, level, achievements), quote loves |
| App activity → **App interactions** | Yes | **Yes** (Google, ads) | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob SDK: ad impressions/taps, app launches |
| Location → **Approximate location** | Yes | **Yes** (Google, ads) | Required | Advertising or marketing, Analytics, Fraud prevention/security | AdMob SDK derives it from the IP address |
| App info and performance → **Diagnostics** | Yes | **Yes** (Google, ads) | Required | Analytics, Fraud prevention/security | AdMob SDK |
| App info and performance → **Crash logs** | Yes | **Yes** (Google, ads) | Required | Analytics | AdMob SDK (per Google's disclosure page) |
| Device or other IDs | Yes | **Yes** (Google, ads) | Required | Advertising or marketing, Analytics, Fraud prevention/security | Advertising ID / App set ID, AdMob SDK |

Notes:

- **Not collected**: precise location, contacts, photos/videos, audio, files,
  calendar, messages, health & fitness data (a generic habit tracker; the app
  doesn't read health sensors or Health Connect), financial info, web browsing,
  installed apps.
- **Reminders and widgets** stay on the device: no data type for them.
- **The daily quote** (`GET /quotes`) is the same for everyone; signed-out
  requests carry no user data.
- **Passwords** are sent to Supabase Auth only to sign in; Play does not list
  passwords as a data type (they fall under account management).
- *Shared* for the AdMob rows: Google's guidance says ads data is shared with
  Google. If the current guidance page says otherwise, follow it.

## Advertising ID declaration

*App content → Advertising ID*: **Yes**, the app uses an advertising ID;
purpose **Advertising or marketing** (and Analytics if you ticked it above).
The merged manifest gets `com.google.android.gms.permission.AD_ID` from the
Google Mobile Ads SDK.

## Ads declaration

*App content → Ads*: **Yes, my app contains ads.**
