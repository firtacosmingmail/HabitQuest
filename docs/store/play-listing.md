# Google Play: store listing draft

Play Console → *Grow users → Store presence → Main store listing*. Replace
`{{DEVELOPER_NAME}}` / `{{CONTACT_EMAIL}}` before pasting. Limits: name 30,
short description 80, full description 4000 characters.

## App name (11/30)

```
Habit Quest
```

## Short description (80/80)

```
Build habits, keep streaks alive, earn XP and level up. Your daily quest awaits!
```

## Full description (~2,000/4,000)

```
Turn your habits into a quest! Habit Quest is a playful habit tracker that rewards every check-in with XP, levels, streaks and achievements, so building a routine feels like a game you want to keep playing.

⚔️ BUILD YOUR HABITS
• Create habits with a name, emoji and colour
• Flexible schedules: every day, chosen weekdays, every few days, or a number of times per week
• Optional reminder time for each habit
• Archive habits you want to pause without losing their history

🔥 KEEP YOUR STREAKS ALIVE
• Big, bouncy check-in buttons for the habits due today
• A streak flame on every habit, plus your best streak
• Monthly heatmap and completion rate for each habit
• Calendar with a progress ring for every day and a ⭐ for Perfect Days

🏆 LEVEL UP
• Earn XP for every check-in, streak milestone and Perfect Day
• Level up with confetti and a celebration
• Unlock achievements and climb through the titles
• No way to farm XP: un-checking a habit takes its XP back

💬 A QUOTE A DAY
• A fresh motivational quote every day
• Tap ♥ to save the ones you love and find them again later

📱 HOME-SCREEN WIDGETS
• See today's habits and check them off right from your home screen
• A daily quote widget

☁️ OFFLINE-FIRST, SYNCED
• Everything works without a connection
• Sign in with email, Google or Apple, and your habits, check-ins and progress sync to your account in the background
• Change phones or reinstall without losing your streaks

🌗 Light and dark mode, following your system.

🔒 PRIVACY
Your habits are yours: we don't sell your data and never share your habits with advertisers. You can delete your account and all its data from the app at any time (Profile → Delete account).

Habit Quest is free and shows a few small, clearly labelled banner ads in the habit list and habit details. In the EU/UK you choose how ads use your data before any ad is shown.

Start your quest today: one habit, one check-in, one level at a time. 🌱
```

> Check the recurrence list against README *Recurrence types* before
> publishing if schedules change.

## Category and tags

- App category: **Productivity** (alternative: *Health & Fitness*; Productivity
  avoids the extra health-app declarations).
- Tags: Habit tracker, Productivity, To-do list / Planner (pick what Play offers).

## Contact details

- Email: `{{CONTACT_EMAIL}}` (required, shown publicly)
- Website: the developer site (must match where `app-ads.txt` will live; see
  the app-ads.txt task)
- Privacy policy: `https://firtacosmingmail.github.io/HabitQuest/privacy.html`
  (expected URL once published)

## Graphics (to prepare)

- App icon 512×512 PNG (from `assets/` / the launcher icon)
- Feature graphic 1024×500
- At least 2 phone screenshots (Habits, Calendar, Quest, widgets);
  `docs/screenshots/` has device captures to start from. Avoid personal data.

## App access

Sign-in is required, so reviewers need credentials. In *App content → App
access* choose *All or some functionality is restricted* and add:

- Name: `Reviewer account`
- Username: a dedicated test email account you create in the app (confirm the
  email first)
- Password: its password (stored only in Play Console and your password manager)
- Notes: `Sign in with email and password on the login screen. Google and
  Apple sign-in are optional alternatives.`

## Alpha release notes (en-US, ≤500)

```
First test build of Habit Quest 🌱⚔️ Please try: creating habits with different schedules, checking in from the Habits tab, the calendar and the widgets, reminders, and sign-in with email/Google. Tell us what breaks or feels confusing!
```
