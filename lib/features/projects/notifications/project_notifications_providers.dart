import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../data/sync/string_store.dart';
import '../../../domain/providers.dart';
import '../../notifications/notifications_providers.dart';
import '../../notifications/scheduler/notification_scheduler.dart';
import '../projects_providers.dart';
import 'project_notification_settings.dart';
import 'project_notifications_controller.dart';

/// Storage of the toggles. `main.dart` overrides it with a hive-backed
/// store; tests get an in-memory one (all on).
final projectNotificationSettingsStoreProvider =
    Provider<ProjectNotificationSettingsStore>((ref) {
  final store = ProjectNotificationSettingsStore(MemoryStringStore());
  ref.onDispose(store.dispose);
  return store;
});

/// The toggles, for the Settings screen.
final projectNotificationSettingsProvider = NotifierProvider<
    ProjectNotificationSettingsNotifier, ProjectNotificationSettings>(
  ProjectNotificationSettingsNotifier.new,
);

class ProjectNotificationSettingsNotifier
    extends Notifier<ProjectNotificationSettings> {
  @override
  ProjectNotificationSettings build() =>
      ref.watch(projectNotificationSettingsStoreProvider).value;

  /// Saves [next]; the controller re-plans (and cancels what was turned
  /// off) as soon as the store announces it.
  Future<void> set(ProjectNotificationSettings next) async {
    state = next;
    await ref.read(projectNotificationSettingsStoreProvider).update(next);
  }
}

/// Web: a no-op (like the habit reminders, web cannot schedule for a
/// closed tab; Projects notifications are not shown in-tab either).
/// Mobile: the shared habit-reminder scheduler (same plugin, channel and
/// time zone setup).
final projectNotificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => kIsWeb
      ? const NoopNotificationScheduler()
      : ref.watch(notificationSchedulerProvider),
);

/// The Projects notifications controller. Started by
/// `NotificationsBootstrap`.
final projectNotificationsControllerProvider =
    Provider<ProjectNotificationsController>((ref) {
  final repository = ref.watch(projectRepositoryProvider);
  final settings = ref.watch(projectNotificationSettingsStoreProvider);
  final controller = ProjectNotificationsController(
    scheduler: ref.watch(projectNotificationSchedulerProvider),
    // A plain snapshot read, not a derived provider.
    data: repository.getData,
    settings: () => settings.value,
    triggers: _merge<Object?>([
      ref.watch(projectChangesProvider),
      ref.watch(remoteProjectChangesProvider),
      ref.watch(sessionAttendanceEventsProvider),
      settings.changes,
    ]),
    now: ref.watch(clockProvider),
  );
  ref.onDispose(controller.dispose);
  return controller;
});

Stream<T> _merge<T>(List<Stream<T>> streams) {
  late StreamController<T> controller;
  final subs = <StreamSubscription<T>>[];
  controller = StreamController<T>(
    onListen: () {
      for (final s in streams) {
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
