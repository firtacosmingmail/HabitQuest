import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/projects/domain/overlap.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/target.dart';

import 'helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  final p1 = project('p1', name: 'Content business');
  final p2 = project('p2', name: 'Fitness');
  final videos = target('t1', title: '5 videos', deadline: d(2026, 11, 30));
  final run = target(
    't2',
    projectId: 'p2',
    title: 'Half marathon',
    deadline: d(2026, 12, 31),
  );

  ProjectsData data(List<ConsistentAction> actions, {List<Target>? targets}) =>
      ProjectsData.fromRecords(
        projects: [p1, p2],
        targets: targets ?? [videos, run],
        actions: actions,
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

  group('findActionClashes', () {
    final existing = weekly(
      'a1',
      days: monFri,
      created: createdOn(2026, 11, 1),
    );

    test('clashes across projects, with the first clash date', () {
      final candidate = weekly(
        'new',
        targetId: 't2',
        days: {3, 6},
        start: '12:00',
        end: '14:00',
        created: createdOn(2026, 11, 14),
      );
      final clashes = findActionClashes(candidate, run, data([existing]));
      expect(clashes, hasLength(1));
      expect(clashes.single.action.id, 'a1');
      expect(clashes.single.target.title, '5 videos');
      expect(clashes.single.project?.name, 'Content business');
      // 14 Nov 2026 is a Saturday; first shared day is Wed 18 Nov.
      expect(clashes.single.firstDate, d(2026, 11, 18));
      expect(
        clashes.single.describe(),
        '"5 videos" (Content business), Mon–Fri 10:00–13:00, first on 2026-11-18',
      );
    });

    test('touching times never clash', () {
      final candidate = weekly(
        'new',
        targetId: 't2',
        days: monFri,
        start: '13:00',
        end: '15:00',
      );
      expect(findActionClashes(candidate, run, data([existing])), isEmpty);
    });

    test('same times on different days do not clash', () {
      final candidate = weekly('new', targetId: 't2', days: {6, 7});
      expect(findActionClashes(candidate, run, data([existing])), isEmpty);
    });

    test('no clash when the active windows do not meet', () {
      // Starts after the other target's deadline.
      final candidate = weekly(
        'new',
        targetId: 't2',
        days: monFri,
        startDate: d(2026, 12, 1),
      );
      expect(findActionClashes(candidate, run, data([existing])), isEmpty);
    });

    test('weekly vs monthly: clash only on a shared real date', () {
      // Monthly 31st: November has none, so no clash before the deadline.
      final m31 = monthly(
        'new',
        targetId: 't2',
        days: {31},
        created: createdOn(2026, 11, 1),
      );
      expect(findActionClashes(m31, run, data([existing])), isEmpty);
      // Monthly 28th: 28 Nov 2026 is a Saturday → no; 16th is a Monday → yes.
      final m = monthly(
        'new',
        targetId: 't2',
        days: {28, 16},
        created: createdOn(2026, 11, 1),
      );
      final clashes = findActionClashes(m, run, data([existing]));
      expect(clashes.single.firstDate, d(2026, 11, 16));
    });

    test('ignores itself, deleted actions and done targets', () {
      final editedSelf = existing.copyWith(endTime: hm('14:00'));
      expect(findActionClashes(editedSelf, videos, data([existing])), isEmpty);

      final deleted = existing.copyWith(
        deletedAt: () => DateTime.utc(2026, 11, 2),
      );
      final candidate = weekly('new', targetId: 't2', days: monFri);
      expect(findActionClashes(candidate, run, data([deleted])), isEmpty);

      final doneVideos = videos.copyWith(status: TargetStatus.done);
      expect(
        findActionClashes(
          candidate,
          run,
          data([existing], targets: [doneVideos, run]),
        ),
        isEmpty,
      );
      // A done candidate target clashes with nothing.
      expect(
        findActionClashes(
          candidate,
          run.copyWith(status: TargetStatus.done),
          data([existing]),
        ),
        isEmpty,
      );
    });

    test('ignores actions of deleted targets and projects', () {
      final candidate = weekly('new', targetId: 't2', days: monFri);
      final deletedTarget = videos.copyWith(
        deletedAt: () => DateTime.utc(2026, 11, 3),
      );
      expect(
        findActionClashes(
          candidate,
          run,
          data([existing], targets: [deletedTarget, run]),
        ),
        isEmpty,
      );
      final noProject = ProjectsData.fromRecords(
        projects: [p2],
        targets: [videos, run],
        actions: [existing],
      );
      expect(findActionClashes(candidate, run, noProject), isEmpty);
    });

    test('two actions of the same target clash; edited deadline counts', () {
      final sat = weekly('a2', days: {6}, start: '09:00', end: '11:00');
      final candidate = weekly(
        'new',
        days: {6},
        start: '10:00',
        end: '12:00',
        created: createdOn(2026, 11, 1),
      );
      final clashes = findActionClashes(
        candidate,
        videos,
        data([existing, sat]),
      );
      expect(clashes.map((c) => c.action.id), ['a2']);
      expect(clashes.single.firstDate, d(2026, 11, 7));
      // Shrinking the deadline before the first Saturday removes the clash.
      final shorter = videos.copyWith(deadline: d(2026, 11, 6));
      expect(
        findActionClashes(candidate, shorter, data([existing, sat])),
        isEmpty,
      );
    });

    test('returns every clash, sorted by first date', () {
      final a2 = weekly(
        'a2',
        targetId: 't2',
        days: {7},
        start: '09:00',
        end: '12:00',
      );
      final candidate = weekly(
        'new',
        days: {1, 7},
        start: '11:00',
        end: '12:00',
        created: createdOn(2026, 11, 1),
      );
      final c = findActionClashes(candidate, videos, data([existing, a2]));
      expect(c.map((x) => x.action.id), ['a2', 'a1']);
      expect(c.map((x) => x.firstDate), [d(2026, 11, 1), d(2026, 11, 2)]);
      final e = ActionOverlapException(candidate, c);
      expect(e.message, contains('Half marathon'));
      expect(e.message, contains('5 videos'));
      expect(
        e.message,
        startsWith('This time block (Mon, Sun 11:00–12:00) overlaps'),
      );
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
