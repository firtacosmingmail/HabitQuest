import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/domain/streaks.dart';

import '../helpers/fixtures.dart';

void main() {
  test('providers expose habits, due list, streaks and perfect days', () async {
    final repo = InMemoryHabitRepository(
      habits: [
        habit(id: 'a', startDate: d(2026, 1, 1)),
        habit(id: 'b', schedule: WeekdaysSchedule({1}), startDate: d(2026, 1, 1)),
        habit(id: 'z', archived: true),
      ],
      completions: {'a': range(d(2026, 1, 1), d(2026, 1, 4))},
    );
    final c = ProviderContainer(overrides: [
      habitRepositoryProvider.overrideWithValue(repo),
      clockProvider.overrideWithValue(() => DateTime(2026, 1, 5, 9)),
    ]);
    addTearDown(c.dispose);

    // Keep stream providers alive and wait for first values.
    c.listen(habitsProvider, (_, _) {});
    c.listen(completionsProvider, (_, _) {});
    await c.read(habitsProvider.future);
    await c.read(completionsProvider.future);

    expect(c.read(todayProvider), d(2026, 1, 5));
    expect(c.read(activeHabitsProvider).value!.map((h) => h.id), ['a', 'b']);
    expect(c.read(archivedHabitsProvider).value!.map((h) => h.id), ['z']);
    expect(c.read(dueTodayProvider).value!.map((h) => h.id), ['a', 'b']);
    expect(c.read(habitByIdProvider('b')).value!.id, 'b');
    expect(c.read(habitByIdProvider('missing')).value, isNull);
    expect(
      c.read(streakProvider('a')),
      const StreakInfo(current: 4, best: 4, unit: StreakUnit.days),
    );
    expect(c.read(isPerfectDayProvider(d(2026, 1, 4))), isTrue);
    expect(c.read(isPerfectDayProvider(d(2026, 1, 5))), isFalse);

    // Mutations through the service flow back into the providers.
    final service = c.read(habitServiceProvider);
    final events = [];
    service.completionEvents.listen(events.add);
    await service.toggleCompletion('a', d(2026, 1, 5));
    await service.toggleCompletion('b', d(2026, 1, 5));
    await pumpEventQueue();
    expect(events, hasLength(2));
    expect(c.read(streakProvider('a'))!.current, 5);
    expect(c.read(isPerfectDayProvider(d(2026, 1, 5))), isTrue);
  });
}
