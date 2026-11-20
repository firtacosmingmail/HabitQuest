# New name ideas for HabitQuest

Status: research only, nothing renamed. The code, the package id
(`com.vvs.habitquest`), the stores and the backend are unchanged.

**Why rename:** the app is no longer only a habit tracker. It now helps you
reach goals and get things done: habits with streaks, **projects** with
targets, deadlines and plans of tasks, recurring **work sessions** in the
"work split" week calendar, notifications, and a game layer (XP, levels,
achievements, and a mascot that grows from *Sprout* through *Seeker*,
*Adventurer*, *Hero*, *Champion* and *Legend* to *Mythic*). The tone is
bright, playful and encouraging. "Habit" in the name now undersells the app.

**Why now:** the store identity is the package id / bundle id. Changing it
later creates a *new* app on Google Play and the App Store (reviews,
installs and testers do not carry over). Nothing is published yet, so this is
the cheapest moment to change both the display name and the id.

---

## 1. Research summary

### Competitor and neighbour names

| App | Category | Naming pattern |
|---|---|---|
| Todoist | tasks | descriptive compound ("to-do" + "-ist", a person who practises it) |
| TickTick | tasks, habits, focus | onomatopoeia/repetition (a clock ticking, ticking items off) |
| Things | tasks | plain everyday word |
| Sunsama | daily planner | evocative, invented ("sun" + Japanese honorific "-sama": respect, care) |
| Motion | AI scheduling | single abstract word, "forward movement" |
| Structured | day planner | adjective describing the benefit |
| Akiflow, Amie, Notion | planners / workspace | short, soft, brandable |
| Habitica | gamified habits | category word + Latinate suffix |
| Strides | habits/goals | metaphor of walking forward |
| Fabulous | routines | emotional adjective |
| Finch | self-care pet | the mascot *is* the name |
| Forest | focus | the reward metaphor *is* the name (grow trees) |
| Beeminder, SuperBetter, Level Up Life, Habit Hunter, Do It Now | gamified | compounds or phrases |
| Streaks, Habitify, Productive, Griply, Grit, Progressio, Goalify | habits/goals | category words with suffixes |

Store sweep of the **gamified "quest/level" niche** (where HabitQuest sits) shows it
is crowded with lookalikes: Questly, Questlii, QuestUP, QuestFlow,
QuestJournal, Questmate, Questor, Levelite, Levelio, Life Leveling, Loggd,
Kubbo, Motidayt, Dayforge, Forgeday, Daybound, several "Kaizen" apps,
Telos (two apps, one is a gamified focus/habit tracker), Ascendo (habit
tracker), GoalCraft, Momentum - Goal Planner, Climb (habit tracker), Cairn
(habit tracker). Generic "Quest + word" names will be hard to own.

### Patterns that work in the category

1. **Short, invented or blended words** (Sunsama, Todoist, Habitica): easy
   to trademark, easy to find, but need a story.
2. **One metaphor word** (Motion, Forest, Strides, Things): memorable, but
   almost always already taken as a store name and `.com`.
3. **Mascot or reward as the name** (Finch, Forest): fits apps with a strong
   game layer like ours.
4. **Word + friendly suffix** (-ly, -ify, -ist, -wise, -io): the cheapest way
   to make a dictionary word ownable; overused but still workable.
5. **Foreign roots** (Sunsama, Kaizen, Telos, Ikigai): add warmth and a story;
   popular roots (Kaizen, Telos) are now saturated.

### Inspiration sources used

- Momentum/progress: step, stride, forth, onward, kick, level, tally.
- Journeys and quests: way, trail, quest, venture, myth (the mascot's top title
  is *Mythic*).
- Climbing and summits: summit, peak, ascent, cairn, waymark.
- Growth and gardens: sprout (the mascot's first title), grove, bloom.
- Craft: forge, plot (plan), aim.
- Other languages: Latin *gradus* (step, as in *Gradus ad Parnassum*, "steps
  to the summit"), Latin *proficio* ("I make progress"), Latin/Italian
  *venturo* ("what is to come"), Japanese *ganba(ru)* ("hang in there, give it
  your all"), Greek *telos* (goal; taken).
- Game vocabulary: quest, level, hero, XP, tally, myth.

---

## 2. Twenty candidates

**How the checks were done (indicative only):** one or two web searches per
name for an App Store / Google Play app with the same or a near-identical name,
then `dig NS` on `<name>.com` and `<name>.app`, and a look at the page title of
any site that answers. "Registered" means the domain has name servers, so it
belongs to someone. It may still be parked or for sale. "No NS" means no DNS
was found, so the domain *may* be free. This is not a trademark search and not
a registrar availability check. Nothing was bought or registered. Before
choosing, run a proper trademark search (EUIPO/USPTO/WIPO, class 9 and 42)
and check the registrar.

Most short `.com`/`.app` domains are taken, so the table also lists a
fallback pattern (`get<name>.app` or `<name>app.com`) where DNS showed no NS.

| # | Name | Meaning / story | Why it fits the new scope | Store conflicts (indicative) | Domains (indicative) | Package id |
|---|---|---|---|---|---|---|
| 1 | **Summitly** | Summit + friendly "-ly": every target is a peak you climb, step by step. | Projects → targets → plan tasks reads naturally as "routes to a summit"; habits are the daily climb. Bright and upbeat. | No app found (the only near match is *Summly*, a news app Yahoo bought and shut down; *Summits* is a hiking log). | `.com` registered (contact-centre consultancy); `.app` registered/parked. `getsummitly.app`, `summitlyapp.com`: no NS. | `com.vvs.summitly` |
| 2 | **Questwise** | Quest + "-wise" (in the manner of, and wise): a smart way to do your quests. | Keeps the "Quest" equity and the game layer, and adds the planning/productivity angle ("wise"). | No app found (only QuestJournal and QuestFlow, which are different names). | `.com` parked at Afternic (for sale, cost unknown); `.app` registered (Cloudflare, no site). `getquestwise.app`, `questwiseapp.com`: no NS. | `com.vvs.questwise` |
| 3 | **Ganba** | From Japanese *ganbaru* / *ganbare!*: "keep going, give it your all", said to cheer someone on. | The app's encouraging voice in one cheerful word. Short, distinctive, mascot-friendly ("Ganba!" on a level-up). | No app found. | `.com` and `.app` registered (no live site seen); `getganba.app`: no NS; `ganbaapp.com` registered. | `com.vvs.ganba` |
| 4 | **Gradus** | Latin "step"; *Gradus ad Parnassum*, "steps to Parnassus", the classic method of mastery one step at a time. | Plans are steps, sessions are steps, levels are steps. Good story, premium feel. | No productivity app found. | `.com` used (interiors company); `.app` live site; `getgradus.app` registered. **Weak on domains.** | `com.vvs.gradus` |
| 5 | **Wayquest** | Your way + your quest: a path to the goal you choose yourself. | Journey metaphor for projects and plans, and keeps the quest DNA. | No store app found, but **`wayquest.app` is a live German travel/explorer product.** | `.com` registered (Cloudflare); `.app` live (travel). `getwayquest.app`: no NS. | `com.vvs.wayquest` |
| 6 | **Steplight** | A light on the next step: always shows what to do now. | Fits the "today" focus: due habits, today's sessions, tasks due. Calm, friendly. | No store app found, but **`steplight.app` is a live checklist/work-instructions product** (adjacent space). | `.com` and `.app` registered. `getsteplight.app`: no NS. | `com.vvs.steplight` |
| 7 | **Peakwise** | Peak + wise: smart about reaching your peaks. | Goals/targets as peaks; "wise" hints at planning and scheduling. | No app found (Peaks, PeakVisor and PeakWatch are outdoor/health apps). | `.com` and `.app` registered. `getpeakwise.app`: no NS. | `com.vvs.peakwise` |
| 8 | **Brightstep** | A bright step forward every day. | Matches the bright, playful tone; generic enough to cover habits, tasks and projects. | No app with this exact name found. | `.com` registered (hosting); `.app` live (no description); `brightstepapp.com` registered; `getbrightstep.app`: no NS. Common word, so it is **hard to own**. | `com.vvs.brightstep` |
| 9 | **Forthly** | From "forth" (onward, forward): always moving forward. | Momentum word that covers both habits and project progress. Short and soft. | No app found. | `.com` and `.app` registered. `getforthly.app`, `forthlyapp.com`: no NS. | `com.vvs.forthly` |
| 10 | **Stridewell** | Stride well: a steady, healthy pace. | Consistent actions and streaks are about pace, not sprints. | No app found (*Stridely* is a step/wellness app: a near-name). | `.com` is a spine clinic; `.app` registered. `getstridewell.app`, `stridewellapp.com`: no NS. | `com.vvs.stridewell` |
| 11 | **Sproutquest** | The mascot's first title is *Sprout*: a quest where you grow. | Ties the name to the mascot and to growth; playful. Leans habit/kids. | No store app found, but **`sproutquest.app` is a live kids'-food product.** | `.com` registered; `.app` live (kids food). `getsproutquest.app`: no NS. | `com.vvs.sproutquest` |
| 12 | **Aimbit** | Aim + bit: aim at a goal and get there bit by bit. | Goals plus small tasks and sessions; techy and short. | No app found (Aimly, a goal app, is a near-name). | `.com` registered (Cloudflare); **`.app` showed no NS** (may be free). | `com.vvs.aimbit` |
| 13 | **Plotwise** | Plot your plan, wisely; "plot" also means a story. | The plan and work-split features are literally plotting time. | No app found. | `.com` and `.app` registered; `plotwiseapp.com` registered (Squarespace). `getplotwise.app`: no NS. | `com.vvs.plotwise` |
| 14 | **Mythly** | Become *Mythic*, the mascot's final title: turn your days into your own legend. | Game layer front and centre; aspirational and fun. | No store app found; **`mythly.com` is a live "inspiring adventure/discover" site.** | `.com` live; `.app` registered. `getmythly.app`, `mythlyapp.com`: no NS. | `com.vvs.mythly` |
| 15 | **Venturo** | Latin/Italian "what is to come": your future, built today. | Future-facing, like deadlines and targets; adventurous. | No app found. | `.com` registered; `.app` parked at Afternic (for sale). `getventuro.app`: no NS; `venturoapp.com` registered. | `com.vvs.venturo` |
| 16 | **Levelday** | Level up your day, every day. | XP and levels plus daily habits and sessions. | No exact app found, but the "Level-" space is crowded (Levelite, Levelio, Life Leveling). | `.com` registered (China); `.app` registered. `getlevelday.app`, `leveldayapp.com`: no NS. | `com.vvs.levelday` |
| 17 | **Kickstep** | A kick-off step: the first push that starts momentum. | Beating procrastination, starting sessions and tasks. | No app found (Kickstart is a dev tool). | `.com` registered; `.app` live (no description). `getkickstep.app`, `kickstepapp.com`: no NS. | `com.vvs.kickstep` |
| 18 | **Proficio** | Latin "I make progress, I accomplish". | Literally "achieve/progress": exactly the new scope. A bit formal. | No app found; *Progressio* (a habit tracker) is near in meaning and sound. Proficio is also a cybersecurity company. | `.com` and `.app` registered. `getproficio.app`, `proficioapp.com`: no NS. | `com.vvs.proficio` |
| 19 | **Questrail** | Quest + trail: the trail of steps to your quest's end. | The plan is the trail and the sessions are the miles; keeps "Quest". | No app found. | `.com` is "QuEST Rail LLC"; **`.app` showed no NS** (may be free). | `com.vvs.questrail` |
| 20 | **Tallyhero** | Tally (count your wins) + hero (the mascot's *Hero* title); a nod to "tally-ho!", the cry to set off. | Streaks, XP and attended sessions are tallies; playful. | No app found. | `.com` registered; **`.app` showed no NS** (may be free). | `com.vvs.tallyhero` |

### Names considered and dropped (clear conflicts)

Questly, Questlii, QuestUP/Upquest, Questmate, QuestGrove (`questgrove.app`
is a live daily-quest product), Forgeday (`forgeday.app` is a live
self-improvement product; Dayforge is a habit tracker), Cairn (Cairn
Milestones habit tracker), Telos (two goal/habit apps), Ascendo (habit
tracker), Kaizo / Kaizen (several productivity apps), GoalCraft (goal app),
Momentra (two apps), Daybound (two apps, one is a task/habit app), Momentum
(several), Climbit (climbing weather), Strivio (trainer marketplace; Strivo
also exists), Waymark (Bible app).

---

## 3. Top 3 picks

1. **Summitly.** The clearest fit for the *new* scope: goals and targets are
   summits, plans are routes, habits and sessions are the daily climb. It is
   warm and playful, easy to say and spell in any language, and gives the
   mascot and the levels an obvious visual world (trails, flags; the app
   already shows 🚩 deadline flags). No store app found. Risk: the `.com`
   belongs to an unrelated consultancy, so use `getsummitly.app` /
   `summitlyapp.com` (no NS found) or try to buy the parked `summitly.app`.
2. **Questwise.** The safest evolution: it keeps the "Quest" brand and game
   identity users of HabitQuest would recognise, drops the narrow "Habit",
   and adds "wise" for planning and productivity. No store app found. Risk:
   the `.com` is for sale at Afternic (cost unknown; buying it is the user's
   decision) and the `.app` is registered, so use `getquestwise.app`.
3. **Ganba.** The most distinctive and ownable: one cheerful word that *is*
   the app's encouraging voice ("Ganba!" when you check in or level up), and
   a natural mascot catchphrase. Short for an icon label. No store app found.
   Risk: the `.com` and `.app` are registered. Ask a Japanese speaker for a
   quick tone check (it is a friendly, everyday cheer, but worth confirming).

**Next steps (not done here):** shortlist 2 or 3 names, run a trademark search
and a registrar availability check, test the names with a few users, then (a
separate task) rename the display name, bundle ids
(`com.vvs.<name>`), Supabase redirect URLs/deep links, the OAuth clients,
AdMob app entries and the store drafts together.

## Sources

- Gamified productivity apps: [Yu-kai Chou, best gamified productivity apps](https://yukaichou.com/lifestyle-gamification/best-gamified-productivity-apps/), [ClickUp, Habitica alternatives](https://clickup.com/blog/habitica-alternatives/), [Habitica on the App Store](https://apps.apple.com/us/app/habitica-gamified-taskmanager/id994882113)
- Name origins: [Sunsama about](https://sunsama.com/about), [Todoist about](https://www.todoist.com/about-us), [TickTick welcome post](https://blog.ticktick.com/2013/05/31/lets-give-ticktick-a-warm-welcome/), [Motion](https://www.usemotion.com/help/getting-started/what-is-motion)
- App naming guides: [Fabrik, how to name an app](https://fabrikbrands.com/how-to-name-an-app/), [BrandBucket app naming](https://www.brandbucket.com/app-naming)
- Conflicts found: [Questly](https://chrome-stats.com/d/com.questly.todo), [Questlii](https://betalist.com/startups/questlii), [questUP](https://apps.apple.com/app/id6759447175), [Cairn Milestones](https://alternativeto.net/software/cairn-milestones/about/), [Telos – Focus & Habit Tracker](https://apps.apple.com/app/id6744418601), [Ascendo](https://chrome-stats.com/d/id6801818646), [GoalCraft](https://apps.apple.com/us/app/goalcraft-%E7%9B%AE%E6%A0%87%E7%AE%A1%E5%AE%B6/id6477860453?l=en-US), [Momentra](https://www.producthunt.com/products/momentra-aesthetic-camera/launches/momentra), [Daybound](https://apps.apple.com/app/id6751446752), [Dayforge](https://apps.apple.com/us/app/-/id6760379171), [Kaizen apps](https://www.producthunt.com/p/kaizen-6), [Levelite](https://apps.apple.com/gw/app/levelite/id6743447435), [Levelio](https://apps.apple.com/us/app/levelio/id6762884895), [Questmate](https://marketplace.atlassian.com/vendors/1225065/questmate), [Strivio](https://strivio.carrd.co/), [Climbit Score](https://apps.apple.com/ca/app/climbit-score/id6517296523), [Stridely](https://apps.apple.com/us/app/stridely/id6748138510), [Progressio](https://apps.apple.com/app/id6740454461)
- Domain checks: `dig NS` and HTTP page titles, run on 2026-11-20 from this Mac.
