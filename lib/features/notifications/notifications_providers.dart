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
    changes: service.habitChanges,
    now: ref.watch(clockProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});
