import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../notifications/scheduler/notification_scheduler.dart';
import '../models/projects_data.dart';
import 'project_notification_planner.dart';
import 'project_notification_settings.dart';

/// Keeps the scheduled Projects notifications in sync with the data.
///
/// A plain service fed by a data snapshot (no derived providers): every
/// trigger (a projects change, local or remote, an attendance mark, a
/// settings toggle, app start / resume, sign-in / out) re-plans the whole
/// rolling window with [planProjectNotifications], schedules it (replacing
/// by id) and cancels every other pending id in the Projects range, which
/// covers deleted items, done goals / tasks, toggles turned off and
/// occurrences that dropped out of the cap. Habit reminder ids are never
/// touched.
///
/// Work is serialised; bursts of triggers coalesce into one re-plan. Await
/// [idle] in tests.
class ProjectNotificationsController {
  final NotificationScheduler scheduler;
  final ProjectsData Function() _data;
  final ProjectNotificationSettings Function() _settings;
  final Stream<Object?> _triggers;
  final DateTime Function() _now;

  StreamSubscription<Object?>? _subscription;
  Future<void> _queue = Future.value();
  bool _started = false;
  bool _resyncQueued = false;
  bool _permissionRequested = false;
  bool _disposed = false;

  /// Ids this controller scheduled last time (in case the platform cannot
  /// list pending notifications).
  Set<int> _scheduled = {};

  ProjectNotificationsController({
    required this.scheduler,
    required ProjectsData Function() data,
    required ProjectNotificationSettings Function() settings,
    required Stream<Object?> triggers,
    required DateTime Function() now,
  }) : _data = data,
       _settings = settings,
       _triggers = triggers,
       _now = now;

  /// Completes when all queued work has finished.
  Future<void> get idle => _queue;

  /// Starts the controller (idempotent): initialises the scheduler, plans
  /// once and listens to the triggers.
  Future<void> start() {
    if (_started) return idle;
    _started = true;
    _subscription = _triggers.listen((_) => resync());
    _enqueue(scheduler.initialize);
    return resync();
  }

  /// Re-plans the window (coalesced with an already queued re-plan).
  Future<void> resync() {
    if (_resyncQueued || _disposed) return idle;
    _resyncQueued = true;
    return _enqueue(() async {
      _resyncQueued = false;
      await _resyncNow();
    });
  }

  Future<void> _resyncNow() async {
    final planned = planProjectNotifications(
      _data(),
      now: _now(),
      settings: _settings(),
    );
    final plannedIds = {for (final n in planned) n.id};
    final pending = (await scheduler.pendingIds()).where(
      isProjectNotificationId,
    );
    final stale = {...pending, ..._scheduled}.difference(plannedIds);
    if (stale.isNotEmpty) await scheduler.cancel(stale);
    if (planned.isNotEmpty) {
      await _ensurePermission();
      await scheduler.schedule([for (final n in planned) n.toRequest()]);
    }
    _scheduled = plannedIds;
  }

  Future<void> _ensurePermission() async {
    if (_permissionRequested) return;
    _permissionRequested = true;
    await scheduler.requestPermission();
  }

  Future<void> _enqueue(Future<void> Function() task) {
    if (_disposed) return idle;
    return _queue = _queue.then((_) async {
      if (_disposed) return;
      try {
        await task();
      } catch (e, st) {
        debugPrint('Project notifications: $e\n$st');
      }
    });
  }

  /// Stops listening. The scheduler is shared with the habit reminders and
  /// is disposed by them.
  void dispose() {
    _disposed = true;
    _subscription?.cancel();
  }
}
