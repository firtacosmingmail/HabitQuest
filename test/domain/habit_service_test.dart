import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/habit_events.dart';
import 'package:habit_quest/domain/habit_service.dart';

import '../helpers/fixtures.dart';

void main() {
  late InMemoryHabitRepository repo;
  late HabitService service;
  late List<CompletionEvent> completions;
  late List<HabitChangeEvent> changes;
  var ids = 0;

  setUp(() {
    repo = InMemoryHabitRepository();
    service = HabitService(
      repo,
      now: () => DateTime(2026, 1, 10, 15, 30),
      idGenerator: () => 'id${ids++}',
    );
    completions = [];
    changes = [];
    service.completionEvents.listen(completions.add);
    service.habitChanges.listen(changes.add);
  });

  tearDown(() => service.dispose());

  Future<Habit> create([String name = 'Run']) => service.createHabit(
        name: name,
        emoji: '🏃',
        colorValue: 0xFFFF6B6B,
        schedule: WeekdaysSchedule({1, 3}),
        reminderTime: const ReminderTime(hour: 8, minute: 0),
      );

  test('createHabit persists with defaults and emits created', () async {
    final h = await create('  Run  ');
    expect(h.name, 'Run');
    expect(h.startDate, d(2026, 1, 10));
    expect(h.createdAt, DateTime(2026, 1, 10, 15, 30));
    expect(repo.getHabit(h.id), h);
    await pumpEventQueue();
    expect(changes.single.type, HabitChangeType.created);
    expect(changes.single.habit, h);
  });

  test('createHabit rejects empty names', () {
    expect(
      () => service.createHabit(name: '  ', emoji: '⭐', colorValue: 0),
      throwsArgumentError,
    );
  });

  test('updateHabit / archiveHabit emit the right event types', () async {
    final h = await create();
    await service.updateHabit(h.copyWith(name: 'Jog'));
    await service.archiveHabit(h.id);
    await service.archiveHabit(h.id); // no-op
    await service.archiveHabit(h.id, archived: false);
    await pumpEventQueue();
    expect(changes.map((e) => e.type), [
      HabitChangeType.created,
      HabitChangeType.updated,
      HabitChangeType.archived,
      HabitChangeType.unarchived,
    ]);
    expect(changes[1].previous?.name, 'Run');
    expect(repo.getHabit(h.id)!.name, 'Jog');
    expect(repo.getHabit(h.id)!.archived, isFalse);
  });

  test('updateHabit of unknown habit throws', () {
    expect(() => service.updateHabit(habit(id: 'nope')), throwsStateError);
  });

  test('toggleCompletion flips state, normalises date, emits events', () async {
    final h = await create();
    expect(await service.toggleCompletion(h.id, DateTime(2026, 1, 9, 21)), isTrue);
    expect(service.isCompleted(h.id, d(2026, 1, 9)), isTrue);
    expect(await service.toggleCompletion(h.id, d(2026, 1, 9)), isFalse);
    expect(service.isCompleted(h.id, d(2026, 1, 9)), isFalse);
    await pumpEventQueue();
    expect(completions, [
      CompletionEvent(habitId: h.id, date: d(2026, 1, 9), completed: true),
      CompletionEvent(habitId: h.id, date: d(2026, 1, 9), completed: false),
    ]);
  });

  test('setCompletion is idempotent (no duplicate events)', () async {
    final h = await create();
    await service.setCompletion(h.id, d(2026, 1, 10), true);
    await service.setCompletion(h.id, d(2026, 1, 10), true);
    await pumpEventQueue();
    expect(completions, hasLength(1));
  });

  test('future check-ins and unknown habits are rejected', () async {
    final h = await create();
    expect(() => service.toggleCompletion(h.id, d(2026, 1, 11)), throwsArgumentError);
    expect(() => service.toggleCompletion('nope', d(2026, 1, 10)), throwsStateError);
  });

  test('deleteHabit removes the habit and its completions', () async {
    final h = await create();
    final other = await create('Other');
    await service.toggleCompletion(h.id, d(2026, 1, 8));
    await service.toggleCompletion(h.id, d(2026, 1, 9));
    await service.toggleCompletion(other.id, d(2026, 1, 9));
    await service.deleteHabit(h.id);
    await pumpEventQueue();

    expect(repo.getHabit(h.id), isNull);
    expect(repo.getCompletions().totalFor(h.id), 0);
    expect(repo.getCompletions().totalFor(other.id), 1);
    final deleted = changes.last;
    expect(deleted.type, HabitChangeType.deleted);
    expect(deleted.habit.id, h.id);
    expect(deleted.removedCompletions, [d(2026, 1, 8), d(2026, 1, 9)]);
  });

  test('streams are broadcast', () {
    expect(service.completionEvents.isBroadcast, isTrue);
    expect(service.habitChanges.isBroadcast, isTrue);
  });
}
