# features/game

Owned by the **game engine** task (pure Dart logic, no UI) and the **game UI**
task (celebration overlays). Persisted in its own hive_ce box `game`.

## Public API

| File | What |
|---|---|
| `game_providers.dart` | `gameEngineProvider`, `gameProfileProvider`, `achievementsCatalogProvider`, `gameEventsProvider`, `gameRepositoryProvider` |
| `game_profile.dart` | `GameProfile` {xp, level, xpIntoLevel, xpForNextLevel, progress (0..1), title, unlockedAchievements, stats, isUnlocked(id), unlockedAt(id)}, `GameStats` {totalCheckIns, bestStreakEver, perfectDays}, `UnlockedAchievement` {achievement, unlockedAt} |
| `game_events.dart` | sealed `GameEvent`: `XpGained`/`XpLost` {amount, habitId?, reason: XpReason, date}, `LevelUp` {newLevel, title}, `AchievementUnlocked` {achievement} |
| `achievements.dart` | `Achievement` {id, name, description, emoji, hint, kind, threshold}, `achievementCatalog`, `AchievementIds`, `achievementById` |
| `game_rules.dart` | `GameRules` (XP constants, level curve, titles) |
| `game_engine.dart` | `GameEngine` (started eagerly by `app.dart`) |
| `game_state.dart`, `game_repository.dart` | persisted state; `GameRepository`, `HiveGameRepository`, `InMemoryGameRepository` |

```dart
final profile = ref.watch(gameProfileProvider);          // synchronous GameProfile
final catalog = ref.watch(achievementsCatalogProvider);  // locked + unlocked
// Celebrations (e.g. in AppShell.initState; cancel in dispose):
_sub = ref.read(gameEventsProvider).listen((e) => switch (e) {
  XpGained() => ..., XpLost() => ..., LevelUp() => ..., AchievementUnlocked() => ...,
});
```

Events for one action arrive in order: XP events, then `LevelUp`, then
`AchievementUnlocked`. `LevelUp` fires only for a level never reached before;
each achievement is announced once.

## Rules

* Check-in: 10 XP + streak bonus (+1 per streak period incl. this check-in,
  max +10; weeks for times-per-week habits; 0 on a non-scheduled day). The
  streak is computed as of the check-in's date.
* Perfect Day: +25 XP once per date while every habit due that day is done.
  Re-evaluated when that day's check-ins change (check-in, un-check, deleting
  a habit with its check-ins). Creating / editing / archiving habits never
  changes XP.
* Anti-exploit ledger: XP is the sum of a per-(habitId, date) check-in ledger
  and a per-date Perfect Day ledger. Un-checking reverses exactly the recorded
  amount; a key already in the ledger never earns again. Toggling nets 0.
  Deleting a habit removes the XP of its check-ins.
* Levels: n → n+1 costs 100·n XP (level L starts at 50·L·(L−1)). Titles:
  Sprout 1–2, Seeker 3–4, Adventurer 5–7, Hero 8–10, Champion 11–14,
  Legend 15–19, Mythic 20+. Level is derived from XP and can drop.
* Stats: `totalCheckIns` = check-ins currently holding XP, `perfectDays` =
  dates currently holding the bonus, `bestStreakEver` = high-water mark.
* Achievements never get revoked. Check-ins that existed before the engine
  ran earn nothing (and un-checking them costs nothing).
