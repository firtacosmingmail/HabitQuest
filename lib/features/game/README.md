# features/game

Owned by the **game engine** task (pure Dart logic, no UI) and the **game UI**
task (celebration overlays). Subscribe to `HabitService.completionEvents` and
`HabitService.habitChanges` (see `/ARCHITECTURE.md`). Persist game state in
its own hive_ce box (e.g. `game_profile`).
