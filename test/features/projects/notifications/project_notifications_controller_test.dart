import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/notifications/notifications_controller.dart';
import 'package:habit_quest/features/notifications/reminder_ids.dart';
import 'package:habit_quest/features/notifications/scheduler/fake_notification_scheduler.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/domain/project_service.dart';
import 'package:habit_quest/features/projects/models/target.dart';
import 'package:habit_quest/features/projects/notifications/project_notification_planner.dart';
import 'package:habit_quest/features/projects/notifications/project_notification_settings.dart';
import 'package:habit_quest/features/projects/notifications/project_notifications_controller.dart';

import '../../notifications/notification_test_helpers.dart';
import '../helpers.dart';

void main() {
  // Saturday 14 Nov 2026, 08:00.
  var now = DateTime(2026, 11, 14, 8);
  late InMemoryProjectRepository repo;
  late ProjectService service;
  late ProjectNotificationSettingsStore settings;
  late FakeNotificationScheduler scheduler;
  late ProjectNotificationsController controller;
  var ids = 0;

  setUp(() {
    now = DateTime(2026, 11, 14, 8);
    ids = 0;
    repo = InMemoryProjectRepository(
      seed: ProjectRecords(
        projects: [project('p1', name: 'Content')],
        targets: [target('t1', deadline: DateTime(2026, 11, 20))],
        actions: [
          weekly('a1', days: {1}),
        ],
      ),
    );
    service = ProjectService(
      repo,
      now: () => now,
      idGenerator: () => 'id${++ids}',
    );
    settings = ProjectNotificationSettingsStore(MemoryStringStore());
    scheduler = FakeNotificationScheduler();
    controller = ProjectNotificationsController(
      scheduler: scheduler,
      data: repo.getData,
      settings: () => settings.value,
      triggers: _merge([
        service.changes,
        service.remoteChanges,
        settings.changes,
      ]),
      now: () => now,
    );
  });

  tearDown(() async {
    controller.dispose();
    await service.dispose();
    await settings.dispose();
  });

  Future<void> settle() async {
    await Future<void>.delayed(Duration.zero);
    await controller.idle;
  }

  Set<String> payloadKinds() => {
    for (final r in scheduler.pending.values)
      if (r.title.isNotEmpty) r.habitId,
  };

  test('start initialises, asks permission once and schedules', () async {
    await controller.start();
    expect(scheduler.initialized, isTrue);
    expect(scheduler.permissionRequests, 1);
    // Monday 16 Nov 10:00 + deadline 17, 19, 20 Nov 09:00.
    expect(scheduler.pending, hasLength(4));
    expect(payloadKinds(), {'${kProjectPayloadPrefix}p1'});
    await controller.resync();
    expect(scheduler.permissionRequests, 1);
  });

  test('no permission prompt when there is nothing to notify', () async {
    await settings.update(ProjectNotificationSettings.allOff);
    await controller.start();
    expect(scheduler.permissionRequests, 0);
    expect(scheduler.pending, isEmpty);
  });

  test('turning a toggle off cancels its notifications at once', () async {
    await controller.start();
    await settings.update(
      ProjectNotificationSettings.allOn.copyWith(deadlines: false),
    );
    await settle();
    expect(scheduler.pending.values.map((r) => r.firstFire), [
      DateTime(2026, 11, 16, 10),
    ]);
    await settings.update(ProjectNotificationSettings.allOn);
    await settle();
    expect(scheduler.pending, hasLength(4));
  });

  test('marking a target done cancels its notifications', () async {
    await controller.start();
    await service.setTargetStatus('t1', TargetStatus.done);
    await settle();
    expect(scheduler.pending, isEmpty);
  });

  test('deleting items cancels their notifications', () async {
    await controller.start();
    final task = await service.addPlanTask(
      targetId: 't1',
      title: 'Script',
      deliveryDate: DateTime(2026, 11, 18),
    );
    await settle();
    final taskId = projectNotificationId('task|${task.id}');
    expect(scheduler.pending.keys, contains(taskId));

    await service.deletePlanTask(task.id);
    await settle();
    expect(scheduler.pending.keys, isNot(contains(taskId)));

    await service.deleteProject('p1');
    await settle();
    expect(scheduler.pending, isEmpty);
  });

  test('remote changes reschedule too', () async {
    await controller.start();
    await service.applyRemote(
      ProjectRecords(
        targets: [
          repo
              .getData()
              .target('t1')!
              .copyWith(
                status: TargetStatus.done,
                updatedAt: DateTime.utc(2030),
              ),
        ],
      ),
    );
    await settle();
    expect(scheduler.pending, isEmpty);
  });

  test('resync moves the rolling window forward', () async {
    await controller.start();
    now = DateTime(2026, 11, 19, 10);
    await controller.resync();
    expect(scheduler.pending.values.map((r) => r.firstFire), [
      DateTime(2026, 11, 20, 9),
    ]);
  });

  test(
    'habit reminders and project notifications never cancel each other',
    () async {
      final habits = InMemoryHabitRepository(
        habits: [
          reminderHabit(
            id: 'h1',
            reminderTime: const ReminderTime(hour: 8, minute: 0),
          ),
        ],
      );
      final habitService = HabitService(habits, now: () => now);
      final habitController = NotificationsController(
        scheduler: scheduler,
        habits: habits.getHabits,
        changes: habitService.habitChanges,
        now: () => now,
      );
      await habitController.start();
      await controller.start();
      final habitIds = scheduler.pending.keys.where(isHabitReminderId).toSet();
      final projectIds = scheduler.pending.keys
          .where(isProjectNotificationId)
          .toSet();
      expect(habitIds, isNotEmpty);
      expect(projectIds, hasLength(4));

      // Habit resync leaves the project notifications alone…
      await habitController.resync();
      expect(
        scheduler.pending.keys.where(isProjectNotificationId).toSet(),
        projectIds,
      );
      // …and turning every project toggle off leaves the habit ones.
      await settings.update(ProjectNotificationSettings.allOff);
      await settle();
      expect(scheduler.pending.keys.toSet(), habitIds);

      habitController.dispose();
      await habitService.dispose();
    },
  );

  group('settings store', () {
    test('defaults to all on and persists changes', () async {
      final mem = MemoryStringStore();
      final store = ProjectNotificationSettingsStore(mem);
      expect(store.value, ProjectNotificationSettings.allOn);
      await store.update(
        ProjectNotificationSettings.allOn.copyWith(taskDeliveries: false),
      );
      final reopened = ProjectNotificationSettingsStore(mem);
      expect(reopened.value.taskDeliveries, isFalse);
      expect(reopened.value.workSplits, isTrue);
      await store.dispose();
      await reopened.dispose();
    });

    test('malformed data falls back to all on', () {
      final store = ProjectNotificationSettingsStore(
        MemoryStringStore({'settings': 'not json'}),
      );
      expect(store.value, ProjectNotificationSettings.allOn);
    });
  });
}

Stream<Object?> _merge(List<Stream<Object?>> streams) async* {
  // Simple fan-in for tests.
  final controller = StreamController<Object?>();
  for (final s in streams) {
    s.listen(controller.add);
  }
  yield* controller.stream;
}
