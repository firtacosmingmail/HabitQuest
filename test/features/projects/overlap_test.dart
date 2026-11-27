import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/utils/dates.dart';
import 'package:habit_quest/features/projects/domain/overlap.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';

import 'helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// Reference: day-by-day scan over [days] days (slow but obviously right).
DateTime? bruteForce(
  BlockRecurrence a,
  BlockRecurrence b, {
  required DateTime from,
  DateTime? to,
  int days = 366 * 30,
}) {
  for (var i = 0; i < days; i++) {
    final day = addDays(from, i);
    if (to != null && day.isAfter(to)) return null;
    if (a.occursOn(day) && b.occursOn(day)) return day;
  }
  return null;
}

void main() {
  final p1 = project('p1', name: 'Content business');
  final p2 = project('p2', name: 'Fitness');

  ProjectsData data(List<TimeBlock> blocks, {bool deletedP2 = false}) =>
      ProjectsData.fromRecords(
        projects: [
          p1,
          deletedP2 ? p2.copyWith(deletedAt: () => DateTime.utc(2026)) : p2,
        ],
        timeBlocks: blocks,
      );

  group('timesOverlap', () {
    test('touching ends do not overlap', () {
      expect(
        timesOverlap(hm('10:00'), hm('13:00'), hm('13:00'), hm('15:00')),
        isFalse,
      );
      expect(
        timesOverlap(hm('13:00'), hm('15:00'), hm('10:00'), hm('13:00')),
        isFalse,
      );
    });

    test('partial, contained and identical intervals overlap', () {
      expect(
        timesOverlap(hm('10:00'), hm('13:00'), hm('12:59'), hm('15:00')),
        isTrue,
      );
      expect(
        timesOverlap(hm('10:00'), hm('13:00'), hm('11:00'), hm('12:00')),
        isTrue,
      );
      expect(
        timesOverlap(hm('10:00'), hm('13:00'), hm('10:00'), hm('13:00')),
        isTrue,
      );
      expect(
        timesOverlap(hm('09:00'), hm('10:00'), hm('10:30'), hm('11:00')),
        isFalse,
      );
    });
  });

  group('firstOverlapDate (open-ended blocks)', () {
    test('weekly × weekly: decided within one week, forever', () {
      final a = weekly('a', days: monFri, startDate: d(2026, 11, 14));
      final b = weekly('b', days: {2, 4}, start: '12:00', end: '14:00');
      // 14 Nov 2026 is a Saturday: first shared day is Tue 17 Nov.
      expect(firstOverlapDate(a, b), d(2026, 11, 17));
      // Disjoint weekdays never meet, however long they run.
      final c = weekly('c', days: {6, 7});
      expect(firstOverlapDate(a, c), isNull);
    });

    test('a clash far in the future is found (no short horizon)', () {
      final a = weekly('a', days: monFri);
      final b = weekly('b', days: {1}, startDate: d(2031, 6, 1));
      // 2 Jun 2031 is the first Monday from 1 Jun 2031 (a Sunday).
      expect(firstOverlapDate(a, b), d(2031, 6, 2));
    });

    test('end dates bound the search', () {
      final a = weekly('a', days: {1}, endDate: d(2026, 11, 30));
      final b = weekly('b', days: {1}, startDate: d(2026, 12, 1));
      expect(firstOverlapDate(a, b), isNull);
      final c = weekly('c', days: {1}, startDate: d(2026, 11, 30));
      expect(firstOverlapDate(a, c), d(2026, 11, 30), reason: 'inclusive');
    });

    test('monthly × monthly: disjoint days never meet', () {
      final a = monthly('a', days: {30});
      final b = monthly('b', days: {31});
      expect(firstOverlapDate(a, b), isNull);
    });

    test('monthly × monthly: skips months without the day', () {
      final a = monthly('a', days: {29, 31}, startDate: d(2027, 2, 1));
      final b = monthly('b', days: {29}, startDate: d(2027, 2, 1));
      // 2027 is not a leap year: no 29 Feb.
      expect(firstOverlapDate(a, b), d(2027, 3, 29));
      final c = monthly('c', days: {31}, startDate: d(2026, 4, 1));
      final e = monthly('e', days: {31}, startDate: d(2026, 4, 1));
      expect(firstOverlapDate(c, e), d(2026, 5, 31));
    });

    test('weekly × monthly: the 31st that is a Monday', () {
      final a = monthly('a', days: {31}, startDate: d(2026, 11, 1));
      final b = weekly('b', days: {1});
      final first = firstOverlapDate(a, b)!;
      expect(first.day, 31);
      expect(first.weekday, DateTime.monday);
      expect(first, bruteForce(a.recurrence, b.recurrence, from: d(2026, 11, 1)));
      // Order of the arguments does not matter.
      expect(firstOverlapDate(b, a), first);
    });

    test('weekly × monthly: 29 Feb on a given weekday (leap years only)', () {
      // Months other than February also have a 29th, so restrict the
      // range to make February the only candidate: from 1 Feb to 28 Feb
      // of a non-leap year there is none.
      final a = monthly(
        'a',
        days: {29},
        startDate: d(2027, 2, 1),
        endDate: d(2027, 2, 28),
      );
      final b = weekly('b', days: {1, 2, 3, 4, 5, 6, 7});
      expect(firstOverlapDate(a, b), isNull);
      // 29 Feb 2028 is a Tuesday.
      final c = monthly('c', days: {29}, startDate: d(2028, 2, 1));
      final e = weekly('e', days: {2});
      expect(firstOverlapDate(c, e), d(2028, 2, 29));
    });

    test('matches a day-by-day reference on random open-ended patterns', () {
      final rnd = Random(42);
      Set<int> pick(int max, int n) => {
        for (var i = 0; i < n; i++) 1 + rnd.nextInt(max),
      };
      BlockRecurrence pattern() => rnd.nextBool()
          ? WeeklyRecurrence(pick(7, 1 + rnd.nextInt(3)))
          : MonthlyRecurrence(pick(31, 1 + rnd.nextInt(3)));
      for (var i = 0; i < 300; i++) {
        final ra = pattern(), rb = pattern();
        final from = addDays(d(2026, 1, 1), rnd.nextInt(2000));
        final to = rnd.nextInt(4) == 0
            ? addDays(from, rnd.nextInt(400))
            : null;
        final expected = bruteForce(ra, rb, from: from, to: to);
        final actual = firstCommonDay(ra, rb, from: from, to: to);
        expect(actual, expected, reason: '$ra × $rb from $from to $to');
      }
    });
  });

  group('findTimeBlockClashes', () {
    test('clashes across projects; the message names project, label, times', () {
      final editing = weekly(
        'a1',
        label: 'Editing',
        days: monFri,
        startDate: d(2026, 11, 16),
      );
      final candidate = weekly(
        'new',
        projectId: 'p2',
        days: {2, 4},
        start: '12:30',
        end: '13:30',
        startDate: d(2026, 11, 16),
      );
      final clashes = findTimeBlockClashes(candidate, data([editing]));
      expect(clashes, hasLength(1));
      expect(clashes.single.block.id, 'a1');
      expect(clashes.single.project?.name, 'Content business');
      expect(clashes.single.firstDate, d(2026, 11, 17));
      final message = TimeBlockOverlapException(candidate, clashes).message;
      expect(
        message,
        'This time block (Tue, Thu 12:30–13:30) overlaps "Content business" '
        '(Editing), Mon–Fri 10:00–13:00, first on 2026-11-17',
      );
    });

    test('a block without a label is named by its project only', () {
      final a = weekly('a1', projectId: 'p2', days: {1});
      final c = weekly('c', days: {1}, start: '12:00', end: '14:00');
      final clash = findTimeBlockClashes(c, data([a])).single;
      expect(clash.describe(), startsWith('"Fitness", Mon 10:00–13:00'));
    });

    test('touching times and other days never clash', () {
      final a = weekly('a1', days: monFri);
      expect(
        findTimeBlockClashes(
          weekly('c', days: monFri, start: '13:00', end: '15:00'),
          data([a]),
        ),
        isEmpty,
      );
      expect(
        findTimeBlockClashes(weekly('c', days: {6, 7}), data([a])),
        isEmpty,
      );
    });

    test('blocks of the same project clash too', () {
      final a = weekly('a1', days: {1});
      final c = weekly('c', days: {1}, start: '11:00', end: '12:00');
      expect(findTimeBlockClashes(c, data([a])), hasLength(1));
    });

    test('ignores itself, deleted blocks and deleted projects', () {
      final a = weekly('a1', days: monFri);
      final gone = weekly(
        'gone',
        days: monFri,
      ).copyWith(deletedAt: () => DateTime.utc(2026));
      final other = weekly('o', projectId: 'p2', days: monFri);
      final edited = a.copyWith(startTime: hm('09:00'));
      expect(
        findTimeBlockClashes(edited, data([a, gone, other], deletedP2: true)),
        isEmpty,
      );
    });

    test('archived projects still count', () {
      final archived = ProjectsData.fromRecords(
        projects: [p1, p2.copyWith(archived: true)],
        timeBlocks: [weekly('o', projectId: 'p2', days: {1})],
      );
      expect(
        findTimeBlockClashes(weekly('c', days: {1}), archived),
        hasLength(1),
      );
    });

    test('returns every clash, sorted by first date then project', () {
      final a = weekly('a', days: {3}, startDate: d(2026, 11, 16));
      final b = weekly('b', projectId: 'p2', days: {1}, startDate: d(2026, 11, 16));
      final c = weekly(
        'c',
        days: {1, 3},
        start: '11:00',
        end: '12:00',
        startDate: d(2026, 11, 16),
      );
      final clashes = findTimeBlockClashes(c, data([a, b]));
      expect(clashes.map((x) => x.block.id), ['b', 'a']);
      expect(clashes.first.firstDate, d(2026, 11, 16));
      expect(clashes.last.firstDate, d(2026, 11, 18));
    });
  });

  group('describeRecurrence', () {
    test('labels', () {
      expect(describeRecurrence(WeeklyRecurrence(monFri)), 'Mon–Fri');
      expect(describeRecurrence(WeeklyRecurrence({1, 3, 5})), 'Mon, Wed, Fri');
      expect(describeRecurrence(WeeklyRecurrence({6})), 'Sat');
      expect(
        describeRecurrence(WeeklyRecurrence({1, 2, 3, 4, 5, 6, 7})),
        'Every day',
      );
      expect(
        describeRecurrence(MonthlyRecurrence({15, 1, 22, 13})),
        '1st, 13th, 15th, 22nd of the month',
      );
      expect(ordinal(3), '3rd');
      expect(ordinal(11), '11th');
      expect(ordinal(21), '21st');
      expect(ordinal(31), '31st');
    });
  });
}
