import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/models/habit.dart';
import '../../domain/habit_events.dart';
import 'reminder_ids.dart';
import 'reminder_planner.dart';
import 'scheduler/notification_scheduler.dart';

/// Keeps scheduled reminders in sync with the habits.
///
/// * [start]: initialises the scheduler, asks for permission if a habit with
///   a reminder exists, resyncs every habit and listens to [changes].
/// * created / updated / unarchived → reschedule (or cancel if the reminder
///   was removed); archived / deleted → cancel.
/// * [resync] (also called on app resume) re-plans everything, which tops up
///   the one-shot reminders of every-N-days habits.
///
/// All work is serialised so events are applied in order; await [idle] in
/// tests.
class NotificationsController {
  final NotificationScheduler scheduler;
  final List<Habit> Function() _habits;
  final Stream<HabitChangeEvent> _changes;
  final DateTime Function() _now;

  StreamSubscription<HabitChangeEvent>? _subscription;
  Future<void> _queue = Future.value();
  bool _started = false;
  bool _permissionRequested = false;
  bool _disposed = false;

  NotificationsController({
    required this.scheduler,
    required List<Habit> Function() habits,
    required Stream<HabitChangeEvent> changes,
    required DateTime Function() now,
  })  : _habits = habits,
        _changes = changes,
        _now = now;

  /// Completes when all queued work has finished.
  Future<void> get idle => _queue;

  /// Whether the permission prompt was already shown in this session.
  bool get permissionRequested => _permissionRequested;

  /// Starts the controller (idempotent).
  Future<void> start() {
    if (_started) return idle;
    _started = true;
    _subscription = _changes.listen(_onChange);
    return _enqueue(() async {
      await scheduler.initialize();
      await _resyncAll();
    });
  }

  /// Re-plans every habit and cancels stray notifications.
  Future<void> resync() => _enqueue(_resyncAll);

  Future<void> _resyncAll() async {
    final habits = _habits();
    final withReminder = habits.where(_wantsReminder).toList();
    if (withReminder.isNotEmpty) await _ensurePermission();

    final now = _now();
    final planned = <int>{};
    for (final habit in withReminder) {
      final requests = planReminders(habit, now: now);
      planned.addAll(requests.map((r) => r.id));
      await scheduler.cancel(allReminderIds(habit.id));
      await scheduler.schedule(requests);
    }
    // Anything else pending belongs to deleted/archived habits or old slots.
    final stray = (await scheduler.pendingIds()).difference(planned);
    if (stray.isNotEmpty) await scheduler.cancel(stray);
  }

  void _onChange(HabitChangeEvent event) {
    _enqueue(() async {
      final habit = event.habit;
      switch (event.type) {
        case HabitChangeType.created:
        case HabitChangeType.updated:
        case HabitChangeType.unarchived:
          await _reschedule(habit);
        case HabitChangeType.archived:
        case HabitChangeType.deleted:
          await scheduler.cancel(allReminderIds(habit.id));
      }
    });
  }

  Future<void> _reschedule(Habit habit) async {
    await scheduler.cancel(allReminderIds(habit.id));
    if (!_wantsReminder(habit)) return;
    await _ensurePermission();
    await scheduler.schedule(planReminders(habit, now: _now()));
  }

  Future<void> _ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    await scheduler.requestPermission();
  }

  static bool _wantsReminder(Habit h) => !h.archived && h.reminderTime != null;

  Future<void> _enqueue(Future<void> Function() task) {
    if (_disposed) return idle;
    return _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } catch (e, st) {
        debugPrint('Notifications: $e\n$st');
      }
    });
  }

  void dispose() {
    _disposed = true;
    _subscription?.cancel();
    scheduler.dispose();
  }
}
