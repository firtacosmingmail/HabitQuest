import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/features/notifications/reminder_planner.dart';
import 'package:habit_quest/features/notifications/reminder_request.dart';
import 'package:habit_quest/features/notifications/scheduler/web_notification_scheduler.dart';
import 'package:habit_quest/features/notifications/web_due_check.dart';

import 'notification_test_helpers.dart';

/// A controllable clock.
class FakeClock {
  DateTime now;
  FakeClock(this.now);
  DateTime call() => now;
  void advance(Duration d) => now = now.add(d);
}

void main() {
  // Monday 2026-01-05 08:00; reminders at 08:30.
  final start = DateTime(2026, 1, 5, 8);
  ReminderRequest daily() =>
      planReminders(reminderHabit(id: 'd'), now: start).single;

  group('occurrencesBetween', () {
    test('daily: window is (from, to]', () {
      final r = daily();
      expect(occurrencesBetween(r, start, DateTime(2026, 1, 5, 8, 29)), isEmpty);
      expect(occurrencesBetween(r, start, DateTime(2026, 1, 5, 8, 30)),
          [DateTime(2026, 1, 5, 8, 30)]);
      expect(
          occurrencesBetween(
              r, DateTime(2026, 1, 5, 8, 30), DateTime(2026, 1, 5, 9)),
          isEmpty);
    });

    test('daily: spans midnight', () {
      final r = daily();
      expect(
        occurrencesBetween(r, DateTime(2026, 1, 5, 9), DateTime(2026, 1, 7, 9)),
        [DateTime(2026, 1, 6, 8, 30), DateTime(2026, 1, 7, 8, 30)],
      );
    });

    test('weekly: only on its weekday', () {
      final plan = planReminders(
          reminderHabit(schedule: WeekdaysSchedule({3})), now: start);
      final r = plan.single; // Wednesday
      expect(
        occurrencesBetween(r, start, DateTime(2026, 1, 14, 23)),
        [DateTime(2026, 1, 7, 8, 30), DateTime(2026, 1, 14, 8, 30)],
      );
    });

    test('once: only its date', () {
      final r = planReminders(
              reminderHabit(schedule: EveryNDaysSchedule(3)), now: start)
          .first; // Jan 7
      expect(occurrencesBetween(r, start, DateTime(2026, 1, 20)),
          [DateTime(2026, 1, 7, 8, 30)]);
    });

    test('never before firstFire', () {
      final r = planReminders(
              reminderHabit(startDate: DateTime(2026, 1, 10)), now: start)
          .single;
      expect(occurrencesBetween(r, start, DateTime(2026, 1, 9, 23)), isEmpty);
    });
  });

  group('WebDueChecker with a fake clock', () {
    test('fires once when the time passes, not again', () {
      final clock = FakeClock(start);
      final checker = WebDueChecker(clock: clock.call);
      final requests = [daily()];

      clock.advance(const Duration(minutes: 29, seconds: 30)); // 08:29:30
      expect(checker.check(requests), isEmpty);
      clock.advance(const Duration(seconds: 30)); // 08:30:00
      expect(checker.check(requests), requests);
      clock.advance(const Duration(seconds: 30));
      expect(checker.check(requests), isEmpty);
    });

    test('does not fire reminders that were due before the app opened', () {
      final clock = FakeClock(DateTime(2026, 1, 5, 12));
      final checker = WebDueChecker(clock: clock.call);
      clock.advance(const Duration(seconds: 30));
      expect(checker.check([daily()]), isEmpty);
    });

    test('a long sleep only catches up the recent window', () {
      final clock = FakeClock(DateTime(2026, 1, 5, 6));
      final checker =
          WebDueChecker(clock: clock.call, maxCatchUp: const Duration(minutes: 15));
      // Tab suspended from 06:00 to 10:00: the 08:30 reminder is stale.
      clock.now = DateTime(2026, 1, 5, 10);
      expect(checker.check([daily()]), isEmpty);
      // Woken at 08:40: within 15 minutes → still shown.
      final clock2 = FakeClock(DateTime(2026, 1, 5, 6));
      final checker2 = WebDueChecker(clock: clock2.call);
      clock2.now = DateTime(2026, 1, 5, 8, 40);
      expect(checker2.check([daily()]), hasLength(1));
    });

    test('clock going backwards does not fire', () {
      final clock = FakeClock(DateTime(2026, 1, 5, 9));
      final checker = WebDueChecker(clock: clock.call);
      clock.now = DateTime(2026, 1, 5, 8);
      expect(checker.check([daily()]), isEmpty);
      expect(checker.lastCheck, DateTime(2026, 1, 5, 8));
    });
  });

  group('WebNotificationScheduler', () {
    test('shows due reminders in-app and drops fired one-shots', () async {
      final clock = FakeClock(start);
      final shown = <ReminderRequest>[];
      final scheduler =
          WebNotificationScheduler(clock: clock.call, showInApp: shown.add);
      addTearDown(scheduler.dispose);
      await scheduler.initialize();

      final dailyReq = daily();
      final once = planReminders(
              reminderHabit(id: 'n', schedule: EveryNDaysSchedule(4)),
              now: start)
          .first; // Jan 5 is scheduled (1, 5, 9…) → 08:30 today
      expect(once.firstFire, DateTime(2026, 1, 5, 8, 30));
      await scheduler.schedule([dailyReq, once]);

      clock.now = DateTime(2026, 1, 5, 8, 30, 10);
      scheduler.checkNow();
      expect(shown, [dailyReq, once]);
      expect(await scheduler.pendingIds(), {dailyReq.id});

      await scheduler.cancel([dailyReq.id]);
      clock.now = DateTime(2026, 1, 6, 8, 30, 10);
      scheduler.checkNow();
      expect(shown, hasLength(2));
    });

    test('permission request without the browser API is a harmless false',
        () async {
      final scheduler = WebNotificationScheduler();
      addTearDown(scheduler.dispose);
      expect(await scheduler.requestPermission(), isFalse);
    });

    testWidgets('the periodic timer drives the checks', (tester) async {
      final clock = FakeClock(DateTime(2026, 1, 5, 8, 29));
      final shown = <ReminderRequest>[];
      final scheduler =
          WebNotificationScheduler(clock: clock.call, showInApp: shown.add);
      await scheduler.initialize();
      await scheduler.schedule([daily()]);

      clock.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(shown, isEmpty);
      clock.advance(const Duration(seconds: 30));
      await tester.pump(const Duration(seconds: 30));
      expect(shown, hasLength(1));

      scheduler.dispose();
    });
  });
}
