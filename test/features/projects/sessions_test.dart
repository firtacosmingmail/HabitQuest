import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/utils/dates.dart';
import 'package:habit_quest/features/projects/domain/sessions.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';

import 'helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

const everyDay = {1, 2, 3, 4, 5, 6, 7};

void main() {
  group('weekly', () {
    test('Mon–Fri 10–13 over November, open-ended', () {
      final b = weekly(
        'b1',
        label: 'Editing',
        days: monFri,
        created: createdOn(2026, 11, 1),
      );
      final s = expandSessions(b, from: d(2026, 11, 1), to: d(2026, 11, 30));
      // Nov 2026: Mon 2 … Mon 30 → 21 weekdays.
      expect(s, hasLength(21));
      expect(s.first.date, d(2026, 11, 2));
      expect(s.last.date, d(2026, 11, 30));
      expect(s.every((x) => x.date.weekday <= 5), isTrue);
      expect(s.first.start, DateTime(2026, 11, 2, 10));
      expect(s.first.end, DateTime(2026, 11, 2, 13));
      expect(s.first.projectId, 'p1');
      expect(s.first.timeBlockId, 'b1');
      expect(s.first.label, 'Editing');
    });

    test('open-ended blocks keep going (years ahead)', () {
      final b = weekly('b1', days: {1}, created: createdOn(2026, 11, 1));
      final s = sessionDates(b, from: d(2030, 1, 1), to: d(2030, 1, 31));
      expect(s, [
        d(2030, 1, 7),
        d(2030, 1, 14),
        d(2030, 1, 21),
        d(2030, 1, 28),
      ]);
      expect(b.isOpenEnded, isTrue);
    });

    test('the end date is included, nothing after it', () {
      final b = weekly('b1', days: everyDay, endDate: d(2026, 11, 4));
      final s = sessionDates(b, from: d(2026, 11, 1), to: d(2026, 11, 30));
      expect(s.last, d(2026, 11, 4));
      expect(s, hasLength(4));
    });

    test('starts at the creation day when there is no start date', () {
      final b = weekly(
        'b1',
        days: everyDay,
        created: createdOn(2026, 11, 10),
        endDate: d(2026, 11, 12),
      );
      final s = sessionDates(b, from: d(2026, 11, 1), to: d(2026, 11, 30));
      expect(s, [d(2026, 11, 10), d(2026, 11, 11), d(2026, 11, 12)]);
    });

    test('an explicit start date wins over the creation day', () {
      final b = weekly(
        'b1',
        days: everyDay,
        created: createdOn(2026, 11, 1),
        startDate: d(2026, 11, 20),
        endDate: d(2026, 11, 21),
      );
      final s = sessionDates(b, from: d(2026, 11, 1), to: d(2026, 11, 30));
      expect(s, [d(2026, 11, 20), d(2026, 11, 21)]);
      // A start date before creation is honoured too (back-filled plans).
      final c = b.copyWith(startDate: () => d(2026, 10, 30));
      expect(
        sessionDates(c, from: d(2026, 10, 1), to: d(2026, 11, 30)).first,
        d(2026, 10, 30),
      );
    });

    test('range bounds are inclusive and normalised to dates', () {
      final b = weekly('b1', days: everyDay);
      final s = sessionDates(
        b,
        from: DateTime(2026, 11, 3, 23, 59),
        to: DateTime(2026, 11, 5, 0, 1),
      );
      expect(s, [d(2026, 11, 3), d(2026, 11, 4), d(2026, 11, 5)]);
    });

    test('empty when the range is outside the active window', () {
      final b = weekly(
        'b1',
        days: monFri,
        created: createdOn(2026, 11, 10),
        endDate: d(2026, 11, 30),
      );
      expect(sessionDates(b, from: d(2026, 12, 1), to: d(2026, 12, 31)), isEmpty);
      expect(sessionDates(b, from: d(2026, 11, 1), to: d(2026, 11, 9)), isEmpty);
    });

    test('an end date before the start date is refused', () {
      expect(
        () => weekly(
          'b1',
          days: monFri,
          startDate: d(2026, 11, 10),
          endDate: d(2026, 11, 9),
        ),
        throwsArgumentError,
      );
    });
  });

  group('monthly', () {
    test('1st and 15th', () {
      final b = monthly('b1', days: {1, 15});
      final s = sessionDates(b, from: d(2026, 10, 2), to: d(2026, 12, 1));
      expect(s, [
        d(2026, 10, 15),
        d(2026, 11, 1),
        d(2026, 11, 15),
        d(2026, 12, 1),
      ]);
    });

    test('the 31st has no session in 30-day months nor in February', () {
      final b = monthly('b1', days: {31});
      final s = sessionDates(b, from: d(2026, 1, 1), to: d(2026, 12, 31));
      expect(s.map((x) => x.month), [1, 3, 5, 7, 8, 10, 12]);
      expect(s.every((x) => x.day == 31), isTrue);
    });

    test('29th and 30th skip February (and the 29th only in leap years)', () {
      final b = monthly('b1', days: {29, 30});
      expect(sessionDates(b, from: d(2026, 2, 1), to: d(2026, 3, 31)), [
        d(2026, 3, 29),
        d(2026, 3, 30),
      ]);
      expect(sessionDates(b, from: d(2028, 2, 1), to: d(2028, 2, 29)), [
        d(2028, 2, 29),
      ]);
    });

    test('end date cut-off mid-month', () {
      final b = monthly('b1', days: {1, 15, 28}, endDate: d(2026, 11, 15));
      final s = sessionDates(b, from: d(2026, 11, 1), to: d(2026, 11, 30));
      expect(s, [d(2026, 11, 1), d(2026, 11, 15)]);
    });
  });

  group('DST', () {
    // EU switches on 2026-03-29 and 2026-10-25, US on 2026-03-08 and
    // 2026-11-01. Whatever the test machine's zone, every calendar day is
    // produced exactly once with the same wall-clock time.
    test('every day exactly once across DST changes, same wall clock', () {
      final b = weekly('b1', days: everyDay, start: '10:00', end: '11:30');
      for (final (from, to) in [
        (d(2026, 3, 1), d(2026, 4, 5)),
        (d(2026, 10, 20), d(2026, 11, 5)),
      ]) {
        final s = expandSessions(b, from: from, to: to);
        expect(s, hasLength(daysBetween(from, to) + 1));
        expect(s.map((x) => x.date).toSet(), hasLength(s.length));
        for (final x in s) {
          expect(x.start.hour, 10);
          expect(x.end.hour, 11);
          expect(x.end.minute, 30);
          expect(x.date.hour, 0);
        }
      }
    });
  });

  group('sessionsInRange', () {
    test('merges blocks of all projects, sorts, fills attended, filters', () {
      final p1 = project('p1');
      final p2 = project('p2', archived: true);
      final b1 = weekly('b1', days: {1}, start: '10:00', end: '13:00');
      final b2 = weekly('b2', days: {1}, start: '08:00', end: '09:00');
      final b3 = weekly(
        'b3',
        projectId: 'p2',
        days: {1},
        start: '14:00',
        end: '15:00',
      );
      final gone = weekly(
        'gone',
        projectId: 'p3',
        days: {1},
        start: '16:00',
        end: '17:00',
      );
      final data = ProjectsData.fromRecords(
        projects: [p1, p2],
        timeBlocks: [b1, b2, b3, gone],
        sessionMarks: [
          SessionMark(
            timeBlockId: 'b1',
            date: d(2026, 11, 2),
            attended: true,
            updatedAt: DateTime.utc(2026, 11, 2),
          ),
        ],
      );
      final all = sessionsInRange(data, from: d(2026, 11, 2), to: d(2026, 11, 2));
      // `gone` belongs to an unknown project: hidden.
      expect(all.map((s) => s.timeBlockId), ['b2', 'b1', 'b3']);
      expect(all[1].attended, isTrue);
      expect(all[0].attended, isFalse);
      final active = sessionsInRange(
        data,
        from: d(2026, 11, 2),
        to: d(2026, 11, 2),
        includeArchivedProjects: false,
      );
      expect(active.map((s) => s.timeBlockId), ['b2', 'b1']);
    });

    test('hasSessionOn respects the window and recurrence', () {
      final b = weekly(
        'b1',
        days: monFri,
        created: createdOn(2026, 11, 2),
        endDate: d(2026, 11, 30),
      );
      expect(hasSessionOn(b, date: d(2026, 11, 2)), isTrue);
      expect(hasSessionOn(b, date: d(2026, 11, 1)), isFalse);
      expect(hasSessionOn(b, date: d(2026, 11, 7)), isFalse);
      expect(hasSessionOn(b, date: d(2026, 12, 1)), isFalse);
      final open = b.copyWith(endDate: () => null);
      expect(hasSessionOn(open, date: d(2036, 12, 1)), isTrue);
    });

    test('labels are trimmed; blank labels are none', () {
      expect(weekly('b', days: {1}, label: '  Edit  ').label, 'Edit');
      expect(weekly('b', days: {1}, label: '   ').label, isNull);
      final json = weekly('b', days: {1}, label: 'X', endDate: d(2027, 1, 1))
          .toJson();
      expect(json['label'], 'X');
      expect(json['endDate'], '2027-01-01');
      expect(TimeBlock.fromJson(json), weekly('b', days: {1}, label: 'X', endDate: d(2027, 1, 1)));
    });
  });
}
