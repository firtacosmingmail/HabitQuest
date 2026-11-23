# App Store: listing draft

App Store Connect → the app → *App Store* tab (version page) and *App
Information*. Not needed for internal TestFlight, but drafted now. Limits:
name 30, subtitle 30, promotional text 170, description 4000, keywords 100.

## Name (11/30)

```
Perseveo
```

## Subtitle (22/30)

```
Gamified habit tracker
```

## Promotional text (≤170)

```
Turn your routine into a quest: check in, keep your streak flame burning, earn XP and level up. Now with home-screen widgets and a daily quote. 🌱
```

## Description

Same text as the Play full description
([`play-listing.md`](play-listing.md#full-description-20004000)), with
"Google or Apple" kept, and this line instead of the EU/UK ads sentence:

```
Perseveo is free and shows a few small, clearly labelled banner ads in the habit list and habit details. You decide whether the app may track you for ads; saying no still gives you the full app.
```

## Keywords (94/100)

```
habit,tracker,streak,routine,goals,daily,reminder,productivity,xp,level,game,widget,motivation
```

## Other fields

- Primary category: **Productivity**; secondary: **Health & Fitness** (optional)
- Age rating: answer *None* everywhere → **4+** (see
  [`content-rating.md`](content-rating.md)). Ads don't change it.
- Support URL: the developer site or the GitHub Pages site (required)
- Privacy policy URL: `https://firtacosmingmail.github.io/HabitQuest/privacy.html`
- Copyright: `2026 {{DEVELOPER_NAME}}`
- Sign-in information for App Review: the same reviewer email account as for
  Play (*App Review Information → Sign-in required*).
- Review notes: `Sign in with email/password (account provided) or Sign in with
  Apple. Ads are Google AdMob banners; the ATT prompt appears after the Google
  consent form. Account deletion: Profile (avatar on the Quest tab) → Delete
  account.`

## TestFlight "What to Test" (internal)

```
First test build. Please try: creating habits with different schedules, checking in from Habits, Calendar and the widgets, reminders, Sign in with Apple/Google, and deleting a test account from Profile.
```
