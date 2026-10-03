# Habit Quest — Architecture

Flutter (iOS, Android, web), all data on the device. State: **Riverpod 3**
(plain providers, no codegen). Navigation: **go_router**. Storage: **hive_ce**
(JSON strings in boxes, no adapters/codegen). Fonts: **google_fonts**
(Fredoka headings, Nunito body).

## Folders

```
lib/
  main.dart                  Hive.initFlutter → HiveHabitRepository.open → ProviderScope(overrides)
  app.dart                   HabitQuestApp (MaterialApp.router, light/dark themes)
  core/
    constants/habit_defaults.dart  HabitDefaults: emoji choices, weekday labels
    router/app_routes.dart   AppRoutes: path constants + helpers
    router/app_router.dart   createRouter(), routerProvider
    router/app_shell.dart    AppShell: bottom NavigationBar (put app-wide overlays here)
    theme/app_colors.dart    AppColors (brand), HabitPalette (habit colour choices)
    theme/app_theme.dart     AppTheme.light / .dark, radii, useGoogleFonts flag
    utils/dates.dart         date-only helpers (dateOnly, addDays, daysBetween, ISO weeks, dateKey)
    widgets/placeholder_screen.dart
  data/
    models/habit.dart            Habit, ReminderTime
    models/habit_schedule.dart   sealed HabitSchedule + 4 subclasses
    models/completion_log.dart   CompletionLog (immutable snapshot of all check-ins)
    repositories/habit_repository.dart          abstract HabitRepository
    repositories/hive_habit_repository.dart     HiveHabitRepository (app)
    repositories/in_memory_habit_repository.dart InMemoryHabitRepository (tests)
  domain/                    pure Dart (no Flutter imports, except providers.dart)
    recurrence.dart          isScheduledOn, isDue, dueHabitsOn, isPerfectDay, dayProgress
    streaks.dart             currentStreak, bestStreak, streakInfo, StreakInfo, StreakUnit
    habit_events.dart        CompletionEvent, HabitChangeEvent, HabitChangeType
    habit_service.dart       HabitService (all mutations + event streams)
    providers.dart           all data/domain Riverpod providers
  features/
    habits/          HabitsScreen (/habits), HabitFormScreen (/habits/new, /habits/:id/edit)
    habit_details/   HabitDetailsScreen (/habits/:id)
    calendar/        CalendarScreen (/calendar)
    quest/           QuestScreen (/quest)
    game/            game engine (logic) + celebration UI — see README there
    notifications/   reminder scheduling — see README there
test/
  flutter_test_config.dart   disables Google Fonts fetching for all tests
  helpers/test_app.dart      pumpHabitQuestApp(tester, …), wrapForTest(widget, …)
  helpers/fixtures.dart      d(y,m,d), habit(…), log(…), range(…)
```

Each feature task owns its folder. Placeholder screens keep their class name
and constructor (`HabitFormScreen({String? habitId})`,
`HabitDetailsScreen({required String habitId})`) because the router uses them.

## Dates

Everything is a **local calendar day**: `dateOnly(dt)` → `DateTime(y, m, d)`.
Never add `Duration(days: n)`; use `addDays(d, n)` and `daysBetween(a, b)`
(DST-safe). Weeks are ISO (Monday–Sunday): `startOfIsoWeek`, `endOfIsoWeek`.
Storage key: `dateKey(d)` = `yyyy-MM-dd`. All domain APIs normalise inputs, so
passing a `DateTime` with a time (or a UTC date from `table_calendar`) is fine.

## Models

```dart
class Habit { String id, name, emoji; int colorValue; HabitSchedule schedule;
  ReminderTime? reminderTime; DateTime createdAt; DateTime startDate /*date-only*/;
  bool archived; copyWith(..., clearReminderTime), toJson(), Habit.fromJson() }
class ReminderTime { int hour, minute; }

sealed class HabitSchedule
  DailySchedule()                 // every day
  WeekdaysSchedule(Set<int> days) // ISO 1=Mon … 7=Sun
  EveryNDaysSchedule(int n)       // startDate, startDate+n, …
  TimesPerWeekSchedule(int times) // 1..7 check-ins per ISO week

class CompletionLog { isCompleted(id, date), datesFor(id), keysFor(id),
  countInRange(id, from, to), totalFor(id), habitIds, withCompletion(...) }
```

Colours: `Habit.colorValue` = `Color.toARGB32()`; use `HabitPalette.colors`,
`HabitPalette.fromValue(v)`, `HabitPalette.onColor(bg)`.

## Recurrence rules (`lib/domain/recurrence.dart`)

* Nothing is due before `startDate`.
* `isScheduledOn(habit, date)` — schedule only (times-per-week: every day).
* `isDue(habit, date, [log])` — for times-per-week: due while check-ins on
  *earlier* days of that ISO week are `< times` (the day that reaches the
  target stays due). Does not look at `archived`.
* `dueHabitsOn(habits, date, log)` — non-archived habits due that day.
* `isPerfectDay(date, habits, log)` — ≥ 1 due habit and all due habits done.
* `dayProgress(date, habits, log)` → `(done:, due:)`.

## Streak rules (`lib/domain/streaks.dart`)

Counted in scheduled periods. Day schedules: consecutive *scheduled* days done;
non-scheduled days never break it and check-ins on them do not extend it.
Times-per-week: consecutive successful ISO weeks (first, partial week only needs
`min(times, days left)`). Today / the current week extends the current streak
once done but never breaks it. `streakUnitOf(habit)` → `days` / `weeks`.

```dart
int currentStreak(Habit, CompletionLog, DateTime today)
int bestStreak(Habit, CompletionLog, DateTime today)
StreakInfo streakInfo(Habit, CompletionLog, DateTime today) // {current, best, unit}
```

## HabitService (`lib/domain/habit_service.dart`)

Use it for **every** mutation so events stay consistent.

```dart
Future<Habit> createHabit({name, emoji, colorValue, schedule = Daily, reminderTime, startDate /*default today*/})
Future<Habit> updateHabit(Habit)                 // emits updated / archived / unarchived
Future<Habit> archiveHabit(String id, {bool archived = true})
Future<void>  deleteHabit(String id)             // also deletes its check-ins
Future<bool>  toggleCompletion(String id, DateTime date) // → new state
Future<void>  setCompletion(String id, DateTime date, bool completed) // idempotent
bool          isCompleted(String id, DateTime date)
DateTime      today
Stream<CompletionEvent>  completionEvents  // broadcast {habitId, date, completed}
Stream<HabitChangeEvent> habitChanges      // broadcast {type, habit, previous?, removedCompletions}
```

* Future dates throw `ArgumentError`; unknown ids throw `StateError`.
* Events fire **after** the repository write; no event if nothing changed.
* Deleting a habit emits only `HabitChangeEvent(deleted, removedCompletions: [...])`
  — no `CompletionEvent`s for the removed check-ins (game: reverse XP there if needed).

## Providers (`lib/domain/providers.dart`)

| Provider | Type |
|---|---|
| `habitRepositoryProvider` | `Provider<HabitRepository>` — **must be overridden** |
| `clockProvider` | `Provider<DateTime Function()>` — override in tests |
| `todayProvider` | `Provider<DateTime>` (date-only; invalidated on app resume) |
| `habitServiceProvider` | `Provider<HabitService>` |
| `habitsProvider` | `StreamProvider<List<Habit>>` (incl. archived) |
| `activeHabitsProvider` / `archivedHabitsProvider` | `Provider<AsyncValue<List<Habit>>>` |
| `habitByIdProvider(id)` | `Provider<AsyncValue<Habit?>>` |
| `completionsProvider` | `StreamProvider<CompletionLog>` |
| `dueHabitsProvider(date)` / `dueTodayProvider` | `Provider<AsyncValue<List<Habit>>>` |
| `streakProvider(id)` | `Provider<StreakInfo?>` |
| `isPerfectDayProvider(date)` | `Provider<bool>` |
| `completionEventsProvider` | `Provider<Stream<CompletionEvent>>` |
| `habitChangesProvider` | `Provider<Stream<HabitChangeEvent>>` |
| `routerProvider` (core/router) | `Provider<GoRouter>` |

Pass `dateOnly(...)` values as family keys.

## Storage

`HiveHabitRepository` boxes: `habits` (`id → jsonEncode(habit)`), `completions`
(`"<habitId>|yyyy-MM-dd" → true`). Other features should open **their own**
boxes (e.g. `game_profile`, `notification_state`) after `Hive.initFlutter()`
in `main.dart`. Watch streams emit the current value on listen, then on change.

## Routes

`StatefulShellRoute.indexedStack` with branches `/habits`, `/calendar`,
`/quest`. `/habits/new`, `/habits/:id`, `/habits/:id/edit` are pushed on the
root navigator (full screen). Use `context.push(AppRoutes.habitDetails(id))`.

## Testing

```dart
await pumpHabitQuestApp(tester, repository: InMemoryHabitRepository(habits: [...]),
    clock: () => DateTime(2026, 1, 5));
await tester.pumpWidget(wrapForTest(MyWidget(), repository: repo));
```
`test/flutter_test_config.dart` sets `AppTheme.useGoogleFonts = false`.
