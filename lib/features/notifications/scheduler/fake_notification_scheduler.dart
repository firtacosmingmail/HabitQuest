import '../reminder_request.dart';
import 'notification_scheduler.dart';

/// In-memory [NotificationScheduler] for tests: records what is pending and
/// every call made.
class FakeNotificationScheduler implements NotificationScheduler {
  /// Pending requests by id.
  final Map<int, ReminderRequest> pending = {};

  /// Call log, e.g. `['initialize', 'permission', 'cancel:16', 'schedule:1']`.
  final List<String> calls = [];

  /// Value returned by [requestPermission].
  bool grantPermission;
  int permissionRequests = 0;
  bool initialized = false;
  bool disposed = false;

  FakeNotificationScheduler({this.grantPermission = true});

  /// Pending requests of one habit, sorted by slot.
  List<ReminderRequest> forHabit(String habitId) =>
      pending.values.where((r) => r.habitId == habitId).toList()
        ..sort((a, b) => a.slot.compareTo(b.slot));

  @override
  Future<void> initialize() async {
    initialized = true;
    calls.add('initialize');
  }

  @override
  Future<bool> requestPermission() async {
    permissionRequests++;
    calls.add('permission');
    return grantPermission;
  }

  @override
  Future<void> schedule(List<ReminderRequest> requests) async {
    calls.add('schedule:${requests.length}');
    for (final r in requests) {
      pending[r.id] = r;
    }
  }

  @override
  Future<void> cancel(Iterable<int> ids) async {
    final list = ids.toList();
    calls.add('cancel:${list.length}');
    list.forEach(pending.remove);
  }

  @override
  Future<Set<int>> pendingIds() async => pending.keys.toSet();

  @override
  void dispose() => disposed = true;
}
