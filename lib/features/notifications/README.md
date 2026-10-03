# features/notifications

Owned by the **reminder notifications** task. Listen to
`HabitService.habitChanges` (or `habitsProvider`) to (re)schedule reminders
from `Habit.reminderTime` + `Habit.schedule`; use `isScheduledOn` from
`lib/domain/recurrence.dart` for the schedule logic (see `/ARCHITECTURE.md`).
