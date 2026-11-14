import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/utils/dates.dart';
import 'package:habit_quest/features/projects/domain/sessions.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/target.dart';

import 'helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  group('weekly', () {
    test('Mon–Fri 10–13 over November up to a 30 Nov deadline', () {
      final t = target('t1', deadline: d(2026, 11, 30));
      final a = weekly('a1', days: monFri, created: createdOn(2026, 11, 1));
      final s = expandSessions(a, t, from: d(2026, 11, 1), to: d(2026, 12, 31));
      // Nov 2026: Mon 2 … Mon 30 → 21 weekdays.
      expect(s, hasLength(21));
      expect(s.first.date, d(2026, 11, 2));
      expect(s.last.date, d(2026, 11, 30));
      expect(s.every((x) => x.date.weekday <= 5), isTrue);
      expect(s.first.start, DateTime(2026, 11, 2, 10));
      expect(s.first.end, DateTime(2026, 11, 2, 13));
      expect(s.first.projectId, 'p1');
      expect(s.first.targetId, 't1');
    });

    test('deadline day is included, nothing after it', () {
      final t = target('t1', deadline: d(2026, 11, 4));
      final a = weekly('a1', days: {1, 2, 3, 4, 5, 6, 7});
      final s = sessionDates(
        a,
        deadline: t.deadline,
        from: d(2026, 11, 1),
        to: d(2026, 11, 30),
      );
      expect(s.last, d(2026, 11, 4));
      expect(s, hasLength(4));
    });

    test('starts at the creation day when there is no start date', () {
      final a = weekly(
        'a1',
        days: {1, 2, 3, 4, 5, 6, 7},
        created: createdOn(2026, 11, 10),
      );
      final s = sessionDates(
        a,
        deadline: d(2026, 11, 12),
        from: d(2026, 11, 1),
        to: d(2026, 11, 30),
      );
      expect(s, [d(2026, 11, 10), d(2026, 11, 11), d(2026, 11, 12)]);
    });

    test('an explicit start date wins over the creation day', () {
      final a = weekly(
        'a1',
        days: {1, 2, 3, 4, 5, 6, 7},
        created: createdOn(2026, 11, 1),
        startDate: d(2026, 11, 20),
      );
      final s = sessionDates(
        a,
        deadline: d(2026, 11, 21),
        from: d(2026, 11, 1),
        to: d(2026, 11, 30),
      );
      expect(s, [d(2026, 11, 20), d(2026, 11, 21)]);
      // A start date before creation is honoured too (back-filled plans).
      final b = a.copyWith(startDate: () => d(2026, 10, 30));
      expect(
        sessionDates(
          b,
          deadline: d(2026, 11, 1),
          from: d(2026, 10, 1),
          to: d(2026, 11, 30),
        ).first,
        d(2026, 10, 30),
      );
    });

    test('range bounds are inclusive and normalised to dates', () {
      final a = weekly('a1', days: {1, 2, 3, 4, 5, 6, 7});
      final s = sessionDates(
        a,
        deadline: d(2026, 12, 31),
        from: DateTime(2026, 11, 3, 23, 59),
        to: DateTime(2026, 11, 5, 0, 1),
      );
      expect(s, [d(2026, 11, 3), d(2026, 11, 4), d(2026, 11, 5)]);
    });

    test('empty when the range is outside the active window', () {
      final a = weekly('a1', days: monFri, created: createdOn(2026, 11, 10));
      expect(
        sessionDates(
          a,
          deadline: d(2026, 11, 30),
          from: d(2026, 12, 1),
          to: d(2026, 12, 31),
        ),
        isEmpty,
      );
      expect(
        sessionDates(
          a,
          deadline: d(2026, 11, 30),
          from: d(2026, 11, 1),
          to: d(2026, 11, 9),
        ),
        isEmpty,
      );
      // Deadline before the start: never any session.
      expect(
        sessionDates(
          a,
          deadline: d(2026, 11, 5),
          from: d(2026, 1, 1),
          to: d(2027, 1, 1),
        ),
        isEmpty,
      );
    });
  });

  group('monthly', () {
    test('1st and 15th', () {
      final a = monthly('a1', days: {1, 15});
      final s = sessionDates(
        a,
        deadline: d(2026, 12, 31),
        from: d(2026, 10, 2),
        to: d(2026, 12, 1),
      );
      expect(s, [
        d(2026, 10, 15),
        d(2026, 11, 1),
        d(2026, 11, 15),
        d(2026, 12, 1),
      ]);
    });

    test('the 31st has no session in 30-day months nor in February', () {
      final a = monthly('a1', days: {31});
      final s = sessionDates(
        a,
        deadline: d(2026, 12, 31),
        from: d(2026, 1, 1),
        to: d(2026, 12, 31),
      );
      expect(s.map((x) => x.month), [1, 3, 5, 7, 8, 10, 12]);
      expect(s.every((x) => x.day == 31), isTrue);
    });

    test('29th and 30th skip February (and the 29th only in leap years)', () {
      final a = monthly('a1', days: {29, 30});
      final s2026 = sessionDates(
        a,
        deadline: d(2026, 3, 31),
        from: d(2026, 2, 1),
        to: d(2026, 3, 31),
      );
      expect(s2026, [d(2026, 3, 29), d(2026, 3, 30)]);
      final s2028 = sessionDates(
        a,
        deadline: d(2028, 3, 1),
        from: d(2028, 2, 1),
        to: d(2028, 2, 29),
      );
      expect(s2028, [d(2028, 2, 29)]);
    });

    test('deadline cut-off mid-month', () {
      final a = monthly('a1', days: {1, 15, 28});
      final s = sessionDates(
        a,
        deadline: d(2026, 11, 15),
        from: d(2026, 11, 1),
        to: d(2026, 11, 30),
      );
      expect(s, [d(2026, 11, 1), d(2026, 11, 15)]);
    });
  });

  group('DST', () {
    // EU switches on 2026-03-29 and 2026-10-25, US on 2026-03-08 and
    // 2026-11-01. Whatever the test machine's zone, every calendar day is
    // produced exactly once with the same wall-clock time.
    test('every day exactly once across DST changes, same wall clock', () {
      final a = weekly(
        'a1',
        days: {1, 2, 3, 4, 5, 6, 7},
        start: '10:00',
        end: '11:30',
      );
      final t = target('t1', deadline: d(2026, 12, 31));
      for (final (from, to) in [
        (d(2026, 3, 1), d(2026, 4, 5)),
        (d(2026, 10, 20), d(2026, 11, 5)),
      ]) {
        final s = expandSessions(a, t, from: from, to: to);
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
    test('merges actions, sorts, fills attended, applies the filters', () {
      final p1 = project('p1');
      final p2 = project('p2', archived: true);
      final t1 = target('t1', deadline: d(2026, 11, 30));
      final t2 = target('t2', projectId: 'p2', deadline: d(2026, 11, 30));
      final t3 = target(
        't3',
        deadline: d(2026, 11, 30),
        status: TargetStatus.done,
      );
      final a1 = weekly('a1', days: {1}, start: '10:00', end: '13:00');
      final a2 = weekly(
        'a2',
        targetId: 't1',
        days: {1},
        start: '08:00',
        end: '09:00',
      );
      final a3 = weekly(
        'a3',
        targetId: 't2',
        days: {1},
        start: '14:00',
        end: '15:00',
      );
      final a4 = weekly(
        'a4',
        targetId: 't3',
        days: {1},
        start: '16:00',
        end: '17:00',
      );
      final data = ProjectsData.fromRecords(
        projects: [p1, p2],
        targets: [t1, t2, t3],
        actions: [a1, a2, a3, a4],
        sessionMarks: [
          SessionMark(
            actionId: 'a1',
            date: d(2026, 11, 2),
            attended: true,
            updatedAt: DateTime.utc(2026, 11, 2),
          ),
        ],
      );
      final all = sessionsInRange(
        data,
        from: d(2026, 11, 2),
        to: d(2026, 11, 2),
      );
      expect(all.map((s) => s.actionId), ['a2', 'a1', 'a3', 'a4']);
      expect(all[1].attended, isTrue);
      expect(all[0].attended, isFalse);
      final filtered = sessionsInRange(
        data,
        from: d(2026, 11, 2),
        to: d(2026, 11, 2),
        includeDoneTargets: false,
        includeArchivedProjects: false,
      );
      expect(filtered.map((s) => s.actionId), ['a2', 'a1']);
    });

    test('hasSessionOn respects the window and recurrence', () {
      final a = weekly('a1', days: monFri, created: createdOn(2026, 11, 2));
      expect(
        hasSessionOn(a, deadline: d(2026, 11, 30), date: d(2026, 11, 2)),
        isTrue,
      );
      expect(
        hasSessionOn(a, deadline: d(2026, 11, 30), date: d(2026, 11, 1)),
        isFalse,
      );
      expect(
        hasSessionOn(a, deadline: d(2026, 11, 30), date: d(2026, 11, 7)),
        isFalse,
      );
      expect(
        hasSessionOn(a, deadline: d(2026, 11, 30), date: d(2026, 12, 1)),
        isFalse,
      );
    });
  });
}
