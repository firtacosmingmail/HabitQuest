import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/projects/models/clock_time.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/project.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/target.dart';

T roundTrip<T>(T value, Map<String, dynamic> Function(T) toJson,
        T Function(Map<String, dynamic>) fromJson) =>
    fromJson(jsonDecode(jsonEncode(toJson(value))) as Map<String, dynamic>);

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
      expect(const ClockTime(10, 0).compareTo(const ClockTime(9, 59)) > 0,
          isTrue);
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
      final p = Project.fromJson(
          {'id': 'p', 'name': 'n', 'createdAt': '2026-11-01T08:00:00.000Z'});
      expect(p.updatedAt, created);
      expect(p.archived, isFalse);
      expect(p.deletedAt, isNull);
    });

    test('Target', () {
      final t = Target(
        id: 't1',
        projectId: 'p1',
        title: '5 videos',
        deadline: DateTime(2026, 11, 30, 17, 45),
        status: TargetStatus.inProgress,
        createdAt: created,
        updatedAt: later,
      );
      expect(t.deadline, DateTime(2026, 11, 30));
      final json = t.toJson();
      expect(json['deadline'], '2026-11-30');
      expect(json['status'], 'inProgress');
      expect(roundTrip(t, (v) => v.toJson(), Target.fromJson), t);
    });

    test('unknown TargetStatus falls back to notStarted', () {
      expect(TargetStatus.fromJson('bogus'), TargetStatus.notStarted);
      expect(TargetStatus.fromJson('done'), TargetStatus.done);
    });

    test('PlanTask with and without delivery date', () {
      final a = PlanTask(
        id: 'k1',
        targetId: 't1',
        title: 'Script 1',
        deliveryDate: DateTime(2026, 11, 10),
        done: true,
        position: 2,
        createdAt: created,
      );
      expect(a.toJson()['deliveryDate'], '2026-11-10');
      expect(roundTrip(a, (v) => v.toJson(), PlanTask.fromJson), a);
      final b = a.copyWith(deliveryDate: () => null);
      expect(b.deliveryDate, isNull);
      expect(roundTrip(b, (v) => v.toJson(), PlanTask.fromJson), b);
    });

    test('ConsistentAction weekly and monthly', () {
      final w = ConsistentAction(
        id: 'a1',
        targetId: 't1',
        startTime: const ClockTime(10, 0),
        endTime: const ClockTime(13, 0),
        recurrence: WeeklyRecurrence({5, 1, 2, 3, 4}),
        createdAt: created,
      );
      final json = w.toJson();
      expect(json['startTime'], '10:00');
      expect(json['endTime'], '13:00');
      expect(json['recurrence'], {
        'type': 'weekly',
        'weekdays': [1, 2, 3, 4, 5],
      });
      expect(json['startDate'], isNull);
      expect(roundTrip(w, (v) => v.toJson(), ConsistentAction.fromJson), w);

      final m = ConsistentAction(
        id: 'a2',
        targetId: 't1',
        startTime: const ClockTime(9, 0),
        endTime: const ClockTime(9, 30),
        recurrence: MonthlyRecurrence({15, 1}),
        startDate: DateTime(2026, 11, 5),
        createdAt: created,
      );
      expect(m.toJson()['recurrence'], {
        'type': 'monthly',
        'monthDays': [1, 15],
      });
      expect(m.toJson()['startDate'], '2026-11-05');
      expect(roundTrip(m, (v) => v.toJson(), ConsistentAction.fromJson), m);
    });

    test('SessionMark', () {
      final s = SessionMark(
        actionId: 'a1',
        date: DateTime(2026, 11, 3, 10),
        attended: true,
        updatedAt: later,
      );
      expect(s.key, 'a1|2026-11-03');
      expect(roundTrip(s, (v) => v.toJson(), SessionMark.fromJson), s);
    });
  });

  group('ConsistentAction validation', () {
    ConsistentAction make(ClockTime s, ClockTime e) => ConsistentAction(
          id: 'a',
          targetId: 't',
          startTime: s,
          endTime: e,
          recurrence: WeeklyRecurrence({1}),
          createdAt: created,
        );

    test('end must be after start', () {
      expect(() => make(const ClockTime(10, 0), const ClockTime(10, 0)),
          throwsArgumentError);
      expect(() => make(const ClockTime(23, 0), const ClockTime(1, 0)),
          throwsArgumentError);
      expect(make(const ClockTime(10, 0), const ClockTime(10, 1))
          .durationMinutes, 1);
    });

    test('recurrences reject empty / out-of-range days', () {
      expect(() => WeeklyRecurrence({}), throwsArgumentError);
      expect(() => WeeklyRecurrence({0}), throwsArgumentError);
      expect(() => WeeklyRecurrence({8}), throwsArgumentError);
      expect(() => MonthlyRecurrence({}), throwsArgumentError);
      expect(() => MonthlyRecurrence({32}), throwsArgumentError);
      expect(() => ActionRecurrence.fromJson({'type': 'x'}),
          throwsFormatException);
    });

    test('effective start date defaults to the local creation day', () {
      final a = make(const ClockTime(10, 0), const ClockTime(11, 0));
      final local = created.toLocal();
      expect(a.effectiveStartDate,
          DateTime(local.year, local.month, local.day));
      final b = a.copyWith(startDate: () => DateTime(2026, 12, 1, 15));
      expect(b.effectiveStartDate, DateTime(2026, 12, 1));
    });
  });

  group('ProjectsData', () {
    test('hides deleted records and their descendants', () {
      final p1 = Project(id: 'p1', name: 'A', createdAt: created);
      final p2 = Project(
          id: 'p2', name: 'B', createdAt: created, deletedAt: later);
      final t1 = Target(
          id: 't1',
          projectId: 'p1',
          title: 'x',
          deadline: DateTime(2026, 12, 1),
          createdAt: created);
      final t2 = Target(
          id: 't2',
          projectId: 'p2',
          title: 'y',
          deadline: DateTime(2026, 12, 1),
          createdAt: created);
      final a1 = ConsistentAction(
          id: 'a1',
          targetId: 't1',
          startTime: const ClockTime(9, 0),
          endTime: const ClockTime(10, 0),
          recurrence: WeeklyRecurrence({1}),
          createdAt: created);
      final a2 = ConsistentAction(
          id: 'a2',
          targetId: 't2',
          startTime: const ClockTime(9, 0),
          endTime: const ClockTime(10, 0),
          recurrence: WeeklyRecurrence({1}),
          createdAt: created);
      final k1 = PlanTask(
          id: 'k1', targetId: 't1', title: 'b', position: 1,
          createdAt: created);
      final k0 = PlanTask(
          id: 'k0', targetId: 't1', title: 'a', position: 0,
          createdAt: later);
      final k2 = PlanTask(
          id: 'k2', targetId: 't2', title: 'c', createdAt: created);
      final m1 = SessionMark(
          actionId: 'a1',
          date: DateTime(2026, 11, 2),
          attended: true,
          updatedAt: later);
      final m2 = SessionMark(
          actionId: 'a2',
          date: DateTime(2026, 11, 2),
          attended: true,
          updatedAt: later);
      final data = ProjectsData.fromRecords(
        projects: [p2, p1],
        targets: [t1, t2],
        planTasks: [k1, k0, k2],
        actions: [a1, a2],
        sessionMarks: [m1, m2],
      );
      expect(data.projects, [p1]);
      expect(data.targets, [t1]);
      expect(data.planTasksOf('t1'), [k0, k1]);
      expect(data.actions, [a1]);
      expect(data.isAttended('a1', DateTime(2026, 11, 2)), isTrue);
      expect(data.isAttended('a2', DateTime(2026, 11, 2)), isFalse);
      expect(data.target('t2'), isNull);
      expect(data.project('p1'), p1);
    });
  });
}
