import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/notifications/notifications_controller.dart';
import 'package:habit_quest/features/notifications/reminder_ids.dart';
import 'package:habit_quest/features/notifications/reminder_request.dart';
import 'package:habit_quest/features/notifications/scheduler/fake_notification_scheduler.dart';

import 'notification_test_helpers.dart';

void main() {
  final now = DateTime(2026, 1, 5, 7);
  const eight = ReminderTime(hour: 8, minute: 0);

  late InMemoryHabitRepository repo;
  late HabitService service;
  late FakeNotificationScheduler scheduler;
  late NotificationsController controller;
  var nextId = 0;

  void setUpWith(List<Habit> habits, {bool grant = true}) {
    repo = InMemoryHabitRepository(habits: habits);
    service = HabitService(repo, now: () => now, idGenerator: () => 'new${nextId++}');
    scheduler = FakeNotificationScheduler(grantPermission: grant);
    controller = NotificationsController(
      scheduler: scheduler,
      habits: repo.getHabits,
      changes: service.habitChanges,
      now: () => now,
    );
  }

  tearDown(() async {
    controller.dispose();
    await service.dispose();
  });

  Future<void> settle() async {
    // Let broadcast events be delivered, then wait for queued work.
    await Future<void>.delayed(Duration.zero);
    await controller.idle;
  }

  group('start', () {
    test('initialises, asks permission once and schedules active habits',
        () async {
      setUpWith([
        reminderHabit(id: 'a'),
        reminderHabit(id: 'b', schedule: WeekdaysSchedule({1, 3})),
        reminderHabit(id: 'c', reminderTime: null),
        reminderHabit(id: 'd', archived: true),
      ]);
      await controller.start();

      expect(scheduler.initialized, isTrue);
      expect(scheduler.calls.first, 'initialize');
      expect(scheduler.permissionRequests, 1);
      expect(scheduler.forHabit('a'), hasLength(1));
      expect(scheduler.forHabit('b').map((r) => r.slot), [1, 3]);
      expect(scheduler.forHabit('c'), isEmpty);
      expect(scheduler.forHabit('d'), isEmpty);
    });

    test('does not ask for permission when no habit has a reminder',
        () async {
      setUpWith([reminderHabit(reminderTime: null)]);
      await controller.start();
      expect(scheduler.permissionRequests, 0);
      expect(scheduler.pending, isEmpty);
    });

    test('cancels stray notifications of unknown habits', () async {
      setUpWith([reminderHabit(id: 'a')]);
      final ghost = ReminderRequest(
        id: reminderId('ghost', 0),
        habitId: 'ghost',
        slot: 0,
        title: 't',
        body: 'b',
        repeat: ReminderRepeat.daily,
        firstFire: now,
      );
      scheduler.pending[ghost.id] = ghost;
      await controller.start();
      expect(scheduler.forHabit('ghost'), isEmpty);
      expect(scheduler.forHabit('a'), hasLength(1));
    });

    test('resync tops up every-N-days one-shots', () async {
      setUpWith([reminderHabit(id: 'n', schedule: EveryNDaysSchedule(2))]);
      await controller.start();
      expect(scheduler.forHabit('n'), hasLength(12));
      // Simulate some one-shots having fired.
      for (final r in scheduler.forHabit('n').take(5)) {
        scheduler.pending.remove(r.id);
      }
      await controller.resync();
      expect(scheduler.forHabit('n'), hasLength(12));
    });

    test('start is idempotent', () async {
      setUpWith([reminderHabit()]);
      await controller.start();
      await controller.start();
      expect(scheduler.calls.where((c) => c == 'initialize'), hasLength(1));
    });

    test('a denied permission does not stop scheduling', () async {
      setUpWith([reminderHabit()], grant: false);
      await controller.start();
      expect(scheduler.pending, hasLength(1));
    });
  });

  group('habit changes', () {
    setUp(() async {
      setUpWith([]);
      await controller.start();
    });

    test('create with a reminder schedules and asks permission the first time',
        () async {
      await service.createHabit(
          name: 'Run', emoji: '🏃', colorValue: 0, reminderTime: eight);
      await settle();
      expect(scheduler.permissionRequests, 1);
      final r = scheduler.forHabit('new${nextId - 1}').single;
      expect(r.firstFire, DateTime(2026, 1, 5, 8));
      expect(r.title, contains('🏃 Run'));

      await service.createHabit(
          name: 'Read', emoji: '📚', colorValue: 0, reminderTime: eight);
      await settle();
      expect(scheduler.permissionRequests, 1);
    });

    test('create without a reminder schedules nothing', () async {
      await service.createHabit(name: 'Run', emoji: '🏃', colorValue: 0);
      await settle();
      expect(scheduler.pending, isEmpty);
      expect(scheduler.permissionRequests, 0);
    });

    test('update reschedules exactly that habit', () async {
      final a = await service.createHabit(
        name: 'A',
        emoji: '🅰️',
        colorValue: 0,
        reminderTime: eight,
        schedule: WeekdaysSchedule({1, 2, 3, 4, 5}),
      );
      final b = await service.createHabit(
          name: 'B', emoji: '🅱️', colorValue: 0, reminderTime: eight);
      await settle();
      expect(scheduler.forHabit(a.id), hasLength(5));

      await service.updateHabit(a.copyWith(
        schedule: WeekdaysSchedule({6}),
        reminderTime: const ReminderTime(hour: 21, minute: 15),
      ));
      await settle();
      final aReminders = scheduler.forHabit(a.id);
      expect(aReminders, hasLength(1));
      expect(aReminders.single.slot, 6);
      expect(aReminders.single.firstFire, DateTime(2026, 1, 10, 21, 15));
      expect(scheduler.forHabit(b.id), hasLength(1));
    });

    test('switching to every-N-days replaces the daily reminder', () async {
      final a = await service.createHabit(
          name: 'A', emoji: '⭐', colorValue: 0, reminderTime: eight);
      await settle();
      await service.updateHabit(a.copyWith(schedule: EveryNDaysSchedule(3)));
      await settle();
      final reminders = scheduler.forHabit(a.id);
      expect(reminders, hasLength(12));
      expect(reminders.every((r) => r.repeat == ReminderRepeat.once), isTrue);
    });

    test('removing the reminder cancels', () async {
      final a = await service.createHabit(
          name: 'A', emoji: '⭐', colorValue: 0, reminderTime: eight);
      await settle();
      await service.updateHabit(a.copyWith(clearReminderTime: true));
      await settle();
      expect(scheduler.forHabit(a.id), isEmpty);
    });

    test('archive cancels, unarchive schedules again', () async {
      final a = await service.createHabit(
          name: 'A', emoji: '⭐', colorValue: 0, reminderTime: eight);
      await settle();
      await service.archiveHabit(a.id);
      await settle();
      expect(scheduler.forHabit(a.id), isEmpty);
      expect(scheduler.calls.last, 'cancel:$kReminderSlotsPerHabit');

      await service.archiveHabit(a.id, archived: false);
      await settle();
      expect(scheduler.forHabit(a.id), hasLength(1));
    });

    test('delete cancels only that habit', () async {
      final a = await service.createHabit(
          name: 'A', emoji: '⭐', colorValue: 0, reminderTime: eight);
      final b = await service.createHabit(
          name: 'B', emoji: '🌙', colorValue: 0, reminderTime: eight);
      await settle();
      await service.deleteHabit(a.id);
      await settle();
      expect(scheduler.forHabit(a.id), isEmpty);
      expect(scheduler.forHabit(b.id), hasLength(1));
    });

    test('nothing happens after dispose', () async {
      controller.dispose();
      expect(scheduler.disposed, isTrue);
      await service.createHabit(
          name: 'A', emoji: '⭐', colorValue: 0, reminderTime: eight);
      await settle();
      expect(scheduler.pending, isEmpty);
    });
  });
}
