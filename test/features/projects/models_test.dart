import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/projects/models/clock_time.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/project.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';

T roundTrip<T>(
  T value,
  Map<String, dynamic> Function(T) toJson,
  T Function(Map<String, dynamic>) fromJson,
) => fromJson(jsonDecode(jsonEncode(toJson(value))) as Map<String, dynamic>);

void main() {
  final created = DateTime.utc(2026, 11, 1, 8);
  final later = DateTime.utc(2026, 11, 2, 9);

  group('ClockTime', () {
    test('parses and formats HH:mm', () {
      expect(ClockTime.parse('9:05'), const ClockTime(9, 5));
      expect(const ClockTime(9, 5).toString(), '09:05');
      expect(const ClockTime(13, 0).minutesOfDay, 780);
    });

    test('rejects malformed input', () {
      for (final s in ['24:00', '10', '10:60', 'ab:cd', '-1:00']) {
        expect(() => ClockTime.parse(s), throwsFormatException, reason: s);
      }
    });

    test('compares', () {
      expect(const ClockTime(10, 0).isBefore(const ClockTime(10, 1)), isTrue);
      expect(
        const ClockTime(10, 0).compareTo(const ClockTime(9, 59)) > 0,
        isTrue,
      );
    });
  });

  group('JSON round trips', () {
    test('Project', () {
      final p = Project(
        id: 'p1',
        name: 'Content business',
        createdAt: created,
        updatedAt: later,
        deletedAt: later,
        archived: true,
      );
      final back = roundTrip(p, (v) => v.toJson(), Project.fromJson);
      expect(back, p);
      expect(back.updatedAt, later);
      expect(p.toJson()['createdAt'], '2026-11-01T08:00:00.000Z');
    });

    test('Project.updatedAt defaults to createdAt', () {
      final p = Project.fromJson({
        'id': 'p',
        'name': 'n',
        'createdAt': '2026-11-01T08:00:00.000Z',
      });
      expect(p.updatedAt, created);
      expect(p.archived, isFalse);
      expect(p.deletedAt, isNull);
    });

    test('Goal', () {
      final g = Goal(
        id: 'g1',
        projectId: 'p1',
        title: '5 videos',
        deadline: DateTime(2026, 11, 30, 17, 45),
        status: GoalStatus.inProgress,
        createdAt: created,
        updatedAt: later,
      );
      expect(g.deadline, DateTime(2026, 11, 30));
      final json = g.toJson();
      expect(json['deadline'], '2026-11-30');
      expect(json['status'], 'inProgress');
      expect(roundTrip(g, (v) => v.toJson(), Goal.fromJson), g);
    });

    test('unknown GoalStatus falls back to notStarted', () {
      expect(GoalStatus.fromJson('bogus'), GoalStatus.notStarted);
      expect(GoalStatus.fromJson('done'), GoalStatus.done);
    });

    test('PlanTask with and without delivery date', () {
      final a = PlanTask(
        id: 'k1',
        goalId: 'g1',
        title: 'Script 1',
        deliveryDate: DateTime(2026, 11, 10),
        done: true,
        position: 2,
        createdAt: created,
      );
      expect(a.toJson()['goalId'], 'g1');
      expect(a.toJson()['deliveryDate'], '2026-11-10');
      expect(roundTrip(a, (v) => v.toJson(), PlanTask.fromJson), a);
      final b = a.copyWith(deliveryDate: () => null);
      expect(b.deliveryDate, isNull);
      expect(roundTrip(b, (v) => v.toJson(), PlanTask.fromJson), b);
    });

    test('TimeBlock weekly and monthly', () {
      final w = TimeBlock(
        id: 'b1',
        projectId: 'p1',
        startTime: const ClockTime(10, 0),
        endTime: const ClockTime(13, 0),
        recurrence: WeeklyRecurrence({5, 1, 2, 3, 4}),
        createdAt: created,
      );
      final json = w.toJson();
      expect(json['projectId'], 'p1');
      expect(json['startTime'], '10:00');
      expect(json['endTime'], '13:00');
      expect(json['recurrence'], {
        'type': 'weekly',
        'weekdays': [1, 2, 3, 4, 5],
      });
      expect(json['label'], isNull);
      expect(json['startDate'], isNull);
      expect(json['endDate'], isNull);
      final wBack = roundTrip(w, (v) => v.toJson(), TimeBlock.fromJson);
      expect(wBack, w);
      expect(wBack.isOpenEnded, isTrue);

      final m = TimeBlock(
        id: 'b2',
        projectId: 'p1',
        label: 'Editing',
        startTime: const ClockTime(9, 0),
        endTime: const ClockTime(9, 30),
        recurrence: MonthlyRecurrence({15, 1}),
        startDate: DateTime(2026, 11, 5),
        endDate: DateTime(2027, 2, 28, 18),
        createdAt: created,
      );
      expect(m.toJson()['recurrence'], {
        'type': 'monthly',
        'monthDays': [1, 15],
      });
      expect(m.toJson()['label'], 'Editing');
      expect(m.toJson()['startDate'], '2026-11-05');
      expect(m.toJson()['endDate'], '2027-02-28');
      final mBack = roundTrip(m, (v) => v.toJson(), TimeBlock.fromJson);
      expect(mBack, m);
      expect(mBack.label, 'Editing');
      expect(mBack.endDate, DateTime(2027, 2, 28));
      expect(mBack.isOpenEnded, isFalse);
    });

    test('ConsistentAction', () {
      final a = ConsistentAction(
        id: 'c1',
        goalId: 'g1',
        text: 'Post one short a day',
        sortOrder: 3,
        createdAt: created,
        updatedAt: later,
      );
      final json = a.toJson();
      expect(json, {
        'id': 'c1',
        'goalId': 'g1',
        'text': 'Post one short a day',
        'sortOrder': 3,
        'createdAt': '2026-11-01T08:00:00.000Z',
        'updatedAt': '2026-11-02T09:00:00.000Z',
        'deletedAt': null,
      });
      final back = roundTrip(a, (v) => v.toJson(), ConsistentAction.fromJson);
      expect(back, a);
      expect(back.updatedAt, later);
      final gone = a.copyWith(deletedAt: () => later);
      expect(gone.isDeleted, isTrue);
      expect(
        roundTrip(gone, (v) => v.toJson(), ConsistentAction.fromJson),
        gone,
      );
    });

    test('ConsistentAction defaults (sortOrder 0, updatedAt = createdAt)', () {
      final a = ConsistentAction.fromJson({
        'id': 'c',
        'goalId': 'g',
        'text': 'x',
        'createdAt': '2026-11-01T08:00:00.000Z',
      });
      expect(a.sortOrder, 0);
      expect(a.updatedAt, created);
      expect(a.deletedAt, isNull);
      expect(a.copyWith(text: 'y', sortOrder: 2).text, 'y');
      expect(a.copyWith(sortOrder: 2).sortOrder, 2);
    });

    test('SessionMark', () {
      final s = SessionMark(
        timeBlockId: 'b1',
        date: DateTime(2026, 11, 3, 10),
        attended: true,
        updatedAt: later,
      );
      expect(s.key, 'b1|2026-11-03');
      expect(s.toJson()['timeBlockId'], 'b1');
      expect(roundTrip(s, (v) => v.toJson(), SessionMark.fromJson), s);
    });
  });

  group('TimeBlock validation', () {
    TimeBlock make(
      ClockTime s,
      ClockTime e, {
      String? label,
      DateTime? startDate,
      DateTime? endDate,
    }) => TimeBlock(
      id: 'b',
      projectId: 'p',
      label: label,
      startTime: s,
      endTime: e,
      recurrence: WeeklyRecurrence({1}),
      startDate: startDate,
      endDate: endDate,
      createdAt: created,
    );

    test('end must be after start', () {
      expect(
        () => make(const ClockTime(10, 0), const ClockTime(10, 0)),
        throwsArgumentError,
      );
      expect(
        () => make(const ClockTime(23, 0), const ClockTime(1, 0)),
        throwsArgumentError,
      );
      expect(
        make(const ClockTime(10, 0), const ClockTime(10, 1)).durationMinutes,
        1,
      );
    });

    test('end date before start date is rejected; same day is fine', () {
      expect(
        () => make(
          const ClockTime(10, 0),
          const ClockTime(11, 0),
          startDate: DateTime(2026, 12, 2),
          endDate: DateTime(2026, 12, 1),
        ),
        throwsArgumentError,
      );
      final one = make(
        const ClockTime(10, 0),
        const ClockTime(11, 0),
        startDate: DateTime(2026, 12, 1, 8),
        endDate: DateTime(2026, 12, 1, 20),
      );
      expect(one.endDate, DateTime(2026, 12, 1));
      expect(one.isOpenEnded, isFalse);
      // copyWith goes through the same validation.
      expect(
        () => one.copyWith(endDate: () => DateTime(2026, 11, 30)),
        throwsArgumentError,
      );
      expect(one.copyWith(endDate: () => null).isOpenEnded, isTrue);
    });

    test('labels are trimmed; blank labels become null', () {
      const s = ClockTime(10, 0), e = ClockTime(11, 0);
      expect(make(s, e, label: '  Editing ').label, 'Editing');
      expect(make(s, e, label: '   ').label, isNull);
      expect(make(s, e, label: '').label, isNull);
      expect(make(s, e).label, isNull);
      expect(TimeBlock.normalizeLabel(' x '), 'x');
      final b = make(s, e, label: 'A');
      expect(b.copyWith(label: () => ' B ').label, 'B');
      expect(b.copyWith(label: () => null).label, isNull);
      expect(b.copyWith(startTime: const ClockTime(9, 0)).label, 'A');
    });

    test('recurrences reject empty / out-of-range days', () {
      expect(() => WeeklyRecurrence({}), throwsArgumentError);
      expect(() => WeeklyRecurrence({0}), throwsArgumentError);
      expect(() => WeeklyRecurrence({8}), throwsArgumentError);
      expect(() => MonthlyRecurrence({}), throwsArgumentError);
      expect(() => MonthlyRecurrence({32}), throwsArgumentError);
      expect(
        () => BlockRecurrence.fromJson({'type': 'x'}),
        throwsFormatException,
      );
    });

    test('effective start date defaults to the local creation day', () {
      final a = make(const ClockTime(10, 0), const ClockTime(11, 0));
      final local = created.toLocal();
      expect(
        a.effectiveStartDate,
        DateTime(local.year, local.month, local.day),
      );
      final b = a.copyWith(startDate: () => DateTime(2026, 12, 1, 15));
      expect(b.effectiveStartDate, DateTime(2026, 12, 1));
    });
  });

  group('ProjectsData', () {
    test('hides deleted records and their descendants', () {
      final p1 = Project(id: 'p1', name: 'A', createdAt: created);
      final p2 = Project(
        id: 'p2',
        name: 'B',
        createdAt: created,
        deletedAt: later,
      );
      final g1 = Goal(
        id: 'g1',
        projectId: 'p1',
        title: 'x',
        deadline: DateTime(2026, 12, 1),
        createdAt: created,
      );
      final g2 = Goal(
        id: 'g2',
        projectId: 'p2',
        title: 'y',
        deadline: DateTime(2026, 12, 1),
        createdAt: created,
      );
      final g3 = Goal(
        id: 'g3',
        projectId: 'p1',
        title: 'deleted',
        deadline: DateTime(2026, 12, 1),
        createdAt: created,
        deletedAt: later,
      );
      final b1 = TimeBlock(
        id: 'b1',
        projectId: 'p1',
        startTime: const ClockTime(9, 0),
        endTime: const ClockTime(10, 0),
        recurrence: WeeklyRecurrence({1}),
        createdAt: created,
      );
      final b2 = TimeBlock(
        id: 'b2',
        projectId: 'p2',
        startTime: const ClockTime(9, 0),
        endTime: const ClockTime(10, 0),
        recurrence: WeeklyRecurrence({1}),
        createdAt: created,
      );
      final k1 = PlanTask(
        id: 'k1',
        goalId: 'g1',
        title: 'b',
        position: 1,
        createdAt: created,
      );
      final k0 = PlanTask(
        id: 'k0',
        goalId: 'g1',
        title: 'a',
        position: 0,
        createdAt: later,
      );
      final k2 = PlanTask(
        id: 'k2',
        goalId: 'g2',
        title: 'c',
        createdAt: created,
      );
      final c1 = ConsistentAction(
        id: 'c1',
        goalId: 'g1',
        text: 'second',
        sortOrder: 1,
        createdAt: created,
      );
      final c0 = ConsistentAction(
        id: 'c0',
        goalId: 'g1',
        text: 'first',
        sortOrder: 0,
        createdAt: later,
      );
      final cTie = ConsistentAction(
        id: 'c9',
        goalId: 'g1',
        text: 'tie, later',
        sortOrder: 1,
        createdAt: later,
      );
      final cGone = ConsistentAction(
        id: 'cx',
        goalId: 'g1',
        text: 'deleted',
        createdAt: created,
        deletedAt: later,
      );
      final c2 = ConsistentAction(
        id: 'c2',
        goalId: 'g2',
        text: 'of a deleted project',
        createdAt: created,
      );
      final c3 = ConsistentAction(
        id: 'c3',
        goalId: 'g3',
        text: 'of a deleted goal',
        createdAt: created,
      );
      final m1 = SessionMark(
        timeBlockId: 'b1',
        date: DateTime(2026, 11, 2),
        attended: true,
        updatedAt: later,
      );
      final m2 = SessionMark(
        timeBlockId: 'b2',
        date: DateTime(2026, 11, 2),
        attended: true,
        updatedAt: later,
      );
      final data = ProjectsData.fromRecords(
        projects: [p2, p1],
        goals: [g1, g2, g3],
        planTasks: [k1, k0, k2],
        timeBlocks: [b1, b2],
        consistentActions: [cTie, c1, cGone, c0, c2, c3],
        sessionMarks: [m1, m2],
      );
      expect(data.projects, [p1]);
      expect(data.goals, [g1]);
      expect(data.goalsOf('p1'), [g1]);
      expect(data.planTasksOf('g1'), [k0, k1]);
      expect(data.timeBlocks, [b1]);
      expect(data.timeBlocksOf('p1'), [b1]);
      expect(data.timeBlock('b2'), isNull);
      expect(data.consistentActions, [c0, c1, cTie]);
      expect(data.consistentActionsOf('g1'), [c0, c1, cTie]);
      expect(data.consistentAction('c2'), isNull);
      expect(data.consistentAction('c3'), isNull);
      expect(data.consistentAction('cx'), isNull);
      expect(data.isAttended('b1', DateTime(2026, 11, 2)), isTrue);
      expect(data.isAttended('b2', DateTime(2026, 11, 2)), isFalse);
      expect(data.goal('g2'), isNull);
      expect(data.project('p1'), p1);
    });
  });
}
