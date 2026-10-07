import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/providers.dart';
import 'notifications_controller.dart';
import 'scheduler/mobile_notification_scheduler.dart';
import 'scheduler/notification_scheduler.dart';
import 'scheduler/web_notification_scheduler.dart';

/// Picks the scheduler for the current platform.
NotificationScheduler createPlatformScheduler() {
  if (kIsWeb) return WebNotificationScheduler();
  return switch (defaultTargetPlatform) {
    TargetPlatform.android ||
    TargetPlatform.iOS =>
      MobileNotificationScheduler(),
    _ => const NoopNotificationScheduler(),
  };
}

/// Platform scheduler; override with `FakeNotificationScheduler` in tests.
final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => createPlatformScheduler(),
);

/// The reminder controller. Not started until [NotificationsController.start]
/// is called (see `NotificationsBootstrap`).
final notificationsControllerProvider = Provider<NotificationsController>((ref) {
  final service = ref.watch(habitServiceProvider);
  final controller = NotificationsController(
    scheduler: ref.watch(notificationSchedulerProvider),
    habits: service.repository.getHabits,
    // Local edits and habits changed by sync (only those are rescheduled).
    changes: _merge(service.habitChanges, service.remoteHabitChanges),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

Stream<T> _merge<T>(Stream<T> a, Stream<T> b) {
  late StreamController<T> controller;
  final subs = <StreamSubscription<T>>[];
  controller = StreamController<T>(
    onListen: () {
      for (final s in [a, b]) {
        subs.add(s.listen(controller.add, onError: controller.addError));
      }
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
    },
  );
  return controller.stream;
}
