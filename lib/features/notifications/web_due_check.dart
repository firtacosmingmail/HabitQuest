/// Pure due-check logic for the web fallback (no timers, no browser APIs).
library;

import '../../core/utils/dates.dart';
import 'reminder_request.dart';

/// The occurrences of [request] in the window `(from, to]` (local times),
/// never earlier than its `firstFire`.
List<DateTime> occurrencesBetween(
  ReminderRequest request,
  DateTime from,
  DateTime to,
) {
  if (!to.isAfter(from)) return const [];
  final result = <DateTime>[];
  final lastDay = dateOnly(to);
  for (var day = dateOnly(from);
      !day.isAfter(lastDay);
      day = addDays(day, 1)) {
    final matches = switch (request.repeat) {
      ReminderRepeat.daily => true,
      ReminderRepeat.weekly => day.weekday == request.weekday,
      ReminderRepeat.once => isSameDay(day, request.firstFire),
    };
    if (!matches) continue;
    final at =
        DateTime(day.year, day.month, day.day, request.hour, request.minute);
    if (at.isAfter(from) && !at.isAfter(to) && !at.isBefore(request.firstFire)) {
      result.add(at);
    }
  }
  return result;
}

/// Requests that came due in `(lastCheck, now]`.
///
/// The window is clamped to [maxCatchUp] so that a tab that slept for hours
/// (laptop lid closed, background throttling) does not replay a burst of
/// stale reminders when it wakes up. Each request is reported at most once
/// per check, even if several of its occurrences fall in the window.
List<ReminderRequest> dueReminders(
  Iterable<ReminderRequest> requests, {
  required DateTime lastCheck,
  required DateTime now,
  Duration maxCatchUp = const Duration(minutes: 15),
}) {
  final earliest = now.subtract(maxCatchUp);
  final from = lastCheck.isBefore(earliest) ? earliest : lastCheck;
  return [
    for (final r in requests)
      if (occurrencesBetween(r, from, now).isNotEmpty) r,
  ];
}

/// Stateful wrapper around [dueReminders] that remembers the last check.
///
/// Starts at the time it is created, so reminders that were due before the
/// app was opened are not shown.
class WebDueChecker {
  final DateTime Function() _clock;
  final Duration maxCatchUp;
  DateTime _lastCheck;

  WebDueChecker({
    required DateTime Function() clock,
    this.maxCatchUp = const Duration(minutes: 15),
  })  : _clock = clock,
        _lastCheck = clock();

  DateTime get lastCheck => _lastCheck;

  /// Returns the requests due since the previous call and advances the
  /// window to now.
  List<ReminderRequest> check(Iterable<ReminderRequest> requests) {
    final now = _clock();
    if (!now.isAfter(_lastCheck)) {
      // Clock went backwards (e.g. time-zone / manual change): just resync.
      _lastCheck = now;
      return const [];
    }
    final due = dueReminders(
      requests,
      lastCheck: _lastCheck,
      now: now,
      maxCatchUp: maxCatchUp,
    );
    _lastCheck = now;
    return due;
  }
}
