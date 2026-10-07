import '../models/check_in.dart';
import '../models/habit.dart';
import 'cached_habit_repository.dart';

/// Non-persistent [HabitRepository] for tests, previews and widget tests.
class InMemoryHabitRepository extends CachedHabitRepository {
  /// Seeds [habits] and [completions] (done check-ins stamped with each
  /// habit's `updatedAt`, or now when the habit is unknown).
  InMemoryHabitRepository({
    Iterable<Habit> habits = const [],
    Map<String, Iterable<DateTime>> completions = const {},
    super.recorder,
    super.now,
  }) {
    for (final h in habits) {
      habitRecords[h.id] = h;
    }
    for (final e in completions.entries) {
      final stamp = habitRecords[e.key]?.updatedAt ?? DateTime.now().toUtc();
      for (final date in e.value) {
        final c = CheckIn(
          habitId: e.key,
          date: date,
          completed: true,
          updatedAt: stamp,
        );
        checkInRecords[c.key] = c;
      }
    }
  }

  @override
  Future<void> writeHabits(Map<String, Habit?> changes) async {}

  @override
  Future<void> writeCheckIns(Map<String, CheckIn?> changes) async {}

  @override
  Future<void> clearStorage() async {}

  @override
  Future<void> closeStorage() async {}
}
