import 'dart:async';

import '../browser/browser_notifications.dart';
import '../in_app_reminder.dart';
import '../reminder_request.dart';
import '../web_due_check.dart';
import 'notification_scheduler.dart';

/// Web fallback: browsers cannot schedule notifications for a closed tab, so
/// reminders are kept in memory and a periodic timer fires the ones that
/// came due while the app is open — as an in-app banner, plus a browser
/// notification when the user granted permission.
class WebNotificationScheduler implements NotificationScheduler {
  final DateTime Function() _clock;
  final Duration interval;
  final void Function(ReminderRequest) _showInApp;
  final BrowserNotifications _browser;

  final Map<int, ReminderRequest> _requests = {};
  WebDueChecker? _checker;
  Timer? _timer;

  WebNotificationScheduler({
    DateTime Function()? clock,
    this.interval = const Duration(seconds: 30),
    void Function(ReminderRequest)? showInApp,
    BrowserNotifications browser = const BrowserNotifications(),
  })  : _clock = clock ?? DateTime.now,
        _showInApp = showInApp ?? showInAppReminder,
        _browser = browser;

  /// Currently tracked reminders (for tests / debugging).
  Iterable<ReminderRequest> get requests => _requests.values;

  @override
  Future<void> initialize() async {
    if (_timer != null) return;
    _checker = WebDueChecker(clock: _clock);
    _timer = Timer.periodic(interval, (_) => checkNow());
  }

  /// Fires reminders that came due since the previous check.
  void checkNow() {
    final checker = _checker ??= WebDueChecker(clock: _clock);
    for (final r in checker.check(_requests.values)) {
      try {
        _showInApp(r);
      } catch (_) {
        // Never let a UI hiccup stop the ticker.
      }
      _browser.show(r.title, r.body);
      if (r.repeat == ReminderRepeat.once) _requests.remove(r.id);
    }
  }

  @override
  Future<bool> requestPermission() => _browser.requestPermission();

  @override
  Future<void> schedule(List<ReminderRequest> requests) async {
    for (final r in requests) {
      _requests[r.id] = r;
    }
  }

  @override
  Future<void> cancel(Iterable<int> ids) async => ids.forEach(_requests.remove);

  @override
  Future<Set<int>> pendingIds() async => _requests.keys.toSet();

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
