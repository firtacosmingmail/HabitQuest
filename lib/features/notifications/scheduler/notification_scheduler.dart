import '../reminder_request.dart';

/// Platform boundary for reminder notifications.
///
/// Implementations: `MobileNotificationScheduler` (Android / iOS,
/// flutter_local_notifications), `WebNotificationScheduler` (in-app + browser
/// Notification API while the tab is open), `NoopNotificationScheduler`
/// (other platforms) and `FakeNotificationScheduler` (tests).
///
/// Implementations must never throw from these methods for platform
/// problems (missing plugin, denied permission…); they log and carry on.
abstract interface class NotificationScheduler {
  /// One-time setup (plugin, time zone, timers). Idempotent.
  Future<void> initialize();

  /// Asks the user for permission to show notifications where the platform
  /// needs it. Returns whether notifications may be shown.
  Future<bool> requestPermission();

  /// Schedules (or replaces, by id) the given requests.
  Future<void> schedule(List<ReminderRequest> requests);

  /// Cancels the notifications with these ids (unknown ids are ignored).
  Future<void> cancel(Iterable<int> ids);

  /// Ids of the notifications currently pending.
  Future<Set<int>> pendingIds();

  /// Releases resources (timers).
  void dispose();
}

/// Does nothing; used on platforms without notification support.
class NoopNotificationScheduler implements NotificationScheduler {
  const NoopNotificationScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> schedule(List<ReminderRequest> requests) async {}

  @override
  Future<void> cancel(Iterable<int> ids) async {}

  @override
  Future<Set<int>> pendingIds() async => const {};

  @override
  void dispose() {}
}
