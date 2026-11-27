import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/notifications/reminder_ids.dart';
import 'package:habit_quest/features/notifications/reminder_request.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/projects_data.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/projects/notifications/project_notification_planner.dart';
import 'package:habit_quest/features/projects/notifications/project_notification_settings.dart';

import '../helpers.dart';

/// Saturday 14 Nov 2026, 08:00.
final now = DateTime(2026, 11, 14, 8);

PlanTask task(
  String id,
  DateTime? delivery, {
  String goalId = 't1',
  bool done = false,
}) => PlanTask(
  id: id,
  goalId: goalId,
  title: 'Task $id',
  deliveryDate: delivery,
  done: done,
  createdAt: createdOn(2026, 11, 1),
);

List<ProjectNotification> plan(
  ProjectsData data, {
  ProjectNotificationSettings settings = ProjectNotificationSettings.allOn,
  int cap = kProjectNotificationCap,
  DateTime? at,
}) => planProjectNotifications(
  data,
  now: at ?? now,
  settings: settings,
  cap: cap,
);

List<String> keys(List<ProjectNotification> ns) => [for (final n in ns) n.key];

void main() {
  group('work split', () {
    final data = ProjectsData.fromRecords(
      projects: [project('p1', name: 'Content')],
      goals: [goal('t1', title: '5 videos', deadline: DateTime(2026, 11, 20))],
      // Open-ended project blocks: Mon, Wed 10:00 ("Editing") and Sat
      // 07:00 (already past today).
      timeBlocks: [
        weekly('a1', label: 'Editing', days: {1, 3}),
        weekly('a2', days: {6}, start: '07:00', end: '07:30'),
      ],
    );

    const splitsOnly = ProjectNotificationSettings(
      workSplits: true,
      deadlines: false,
      taskDeliveries: false,
    );

    test('fires at each session start of an open-ended block through the '
        'whole window (a goal deadline does not cut it off); skips past '
        'ones', () {
      final ns = plan(data, settings: splitsOnly);
      expect(ns.map((n) => n.fireAt), [
        DateTime(2026, 11, 16, 10),
        DateTime(2026, 11, 18, 10),
        DateTime(2026, 11, 21, 7),
        DateTime(2026, 11, 23, 10),
        DateTime(2026, 11, 25, 10),
        DateTime(2026, 11, 28, 7), // the window ends 28 Nov 08:00
      ]);
      expect(
        ns.every((n) => n.kind == ProjectNotificationKind.workSplit),
        isTrue,
      );
      expect(ns.first.key, 'split|a1|2026-11-16');
      expect(ns.first.projectId, 'p1');
      expect(ns.first.title, contains('Content'));
      expect(ns.first.body, contains('Editing'));
      expect(ns.first.body, isNot(contains('5 videos')));
    });

    test('an unlabelled block names the project in the body', () {
      final ns = plan(data, settings: splitsOnly);
      final sat = ns.firstWhere((n) => n.key == 'split|a2|2026-11-21');
      expect(sat.body, contains('Content'));
      expect(sat.body, contains('07:00'));
    });

    test('a block with an end date stops after it', () {
      final ended = ProjectsData.fromRecords(
        projects: data.projects,
        timeBlocks: [
          weekly('a1', days: {1, 3}, endDate: DateTime(2026, 11, 18)),
        ],
      );
      expect(plan(ended, settings: splitsOnly).map((n) => n.fireAt), [
        DateTime(2026, 11, 16, 10),
        DateTime(2026, 11, 18, 10),
      ]);
    });

    test('skips attended sessions', () {
      final marked = ProjectsData.fromRecords(
        projects: data.projects,
        goals: data.goals,
        timeBlocks: data.timeBlocks,
        sessionMarks: [
          SessionMark(
            timeBlockId: 'a1',
            date: DateTime(2026, 11, 16),
            attended: true,
            updatedAt: now,
          ),
        ],
      );
      final ns = plan(marked, settings: splitsOnly);
      expect(ns.map((n) => n.fireAt), [
        DateTime(2026, 11, 18, 10),
        DateTime(2026, 11, 21, 7),
        DateTime(2026, 11, 23, 10),
        DateTime(2026, 11, 25, 10),
        DateTime(2026, 11, 28, 7), // the window ends 28 Nov 08:00
      ]);
    });
  });

  group('deadline', () {
    test('3 days before, 1 day before and the deadline morning at 09:00', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [goal('t1', deadline: DateTime(2026, 11, 20))],
      );
      final ns = plan(data);
      expect(ns.map((n) => n.fireAt), [
        DateTime(2026, 11, 17, 9),
        DateTime(2026, 11, 19, 9),
        DateTime(2026, 11, 20, 9),
      ]);
      expect(ns.map((n) => n.kind).toSet(), {ProjectNotificationKind.deadline});
    });

    test('skips times already past (deadline today after 09:00)', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [goal('t1', deadline: DateTime(2026, 11, 15))],
      );
      // 14 Nov 10:00: the 3-day reminder (12 Nov) is past; 1-day (14 Nov
      // 09:00) is past too; only the deadline morning remains.
      final ns = plan(data, at: DateTime(2026, 11, 14, 10));
      expect(ns.map((n) => n.fireAt), [DateTime(2026, 11, 15, 9)]);
    });

    test('skips the deadline and tasks of goals marked done; the '
        "project's sessions still notify", () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [
          goal(
            't1',
            deadline: DateTime(2026, 11, 20),
            status: GoalStatus.done,
          ),
        ],
        timeBlocks: [weekly('a1', days: monFri)],
        planTasks: [task('k1', DateTime(2026, 11, 18))],
      );
      final ns = plan(data);
      expect(ns, isNotEmpty);
      expect(ns.map((n) => n.kind).toSet(), {
        ProjectNotificationKind.workSplit,
      });
    });

    test('in progress goals still notify', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [
          goal(
            't1',
            deadline: DateTime(2026, 11, 20),
            status: GoalStatus.inProgress,
          ),
        ],
      );
      expect(plan(data), hasLength(3));
    });
  });

  group('task delivery', () {
    final data = ProjectsData.fromRecords(
      projects: [project('p1', name: 'Content')],
      goals: [goal('t1', title: 'Launch', deadline: DateTime(2027, 1, 31))],
      planTasks: [
        task('k1', DateTime(2026, 11, 18)),
        task('k2', DateTime(2026, 11, 19), done: true),
        task('k3', null),
        task('k4', DateTime(2026, 11, 14)), // reminder was yesterday
      ],
    );

    test('the day before at 09:00; skips done, undated and past', () {
      final ns = plan(data);
      expect(keys(ns), ['task|k1']);
      expect(ns.single.fireAt, DateTime(2026, 11, 17, 9));
      expect(ns.single.title, contains('Task k1'));
      expect(ns.single.kind, ProjectNotificationKind.taskDelivery);
    });

    test('delivery tomorrow before 09:00 still fires this morning', () {
      final ns = plan(data, at: DateTime(2026, 11, 17, 8, 59));
      expect(ns.single.fireAt, DateTime(2026, 11, 17, 9));
    });
  });

  group('toggles', () {
    final data = ProjectsData.fromRecords(
      projects: [project('p1')],
      goals: [goal('t1', deadline: DateTime(2026, 11, 20))],
      timeBlocks: [
        weekly('a1', days: {1}),
      ],
      planTasks: [task('k1', DateTime(2026, 11, 18))],
    );

    Set<ProjectNotificationKind> kinds(ProjectNotificationSettings s) =>
        plan(data, settings: s).map((n) => n.kind).toSet();

    test('each toggle controls its own kind', () {
      expect(
        kinds(ProjectNotificationSettings.allOn),
        ProjectNotificationKind.values.toSet(),
      );
      expect(kinds(ProjectNotificationSettings.allOff), isEmpty);
      expect(
        kinds(ProjectNotificationSettings.allOn.copyWith(workSplits: false)),
        {
          ProjectNotificationKind.deadline,
          ProjectNotificationKind.taskDelivery,
        },
      );
      expect(
        kinds(ProjectNotificationSettings.allOn.copyWith(deadlines: false)),
        {
          ProjectNotificationKind.workSplit,
          ProjectNotificationKind.taskDelivery,
        },
      );
      expect(
        kinds(
          ProjectNotificationSettings.allOn.copyWith(taskDeliveries: false),
        ),
        {ProjectNotificationKind.workSplit, ProjectNotificationKind.deadline},
      );
    });
  });

  test('archived projects are skipped', () {
    final data = ProjectsData.fromRecords(
      projects: [project('p1', archived: true)],
      goals: [goal('t1', deadline: DateTime(2026, 11, 20))],
      timeBlocks: [weekly('a1', days: monFri)],
      planTasks: [task('k1', DateTime(2026, 11, 18))],
    );
    expect(plan(data), isEmpty);
  });

  group('window and cap', () {
    test('only the next 14 days', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [goal('t1', deadline: DateTime(2027, 6, 30))],
        timeBlocks: [
          weekly('a1', days: {1}),
        ], // Mondays 10:00
      );
      final ns = plan(data);
      expect(ns.map((n) => n.fireAt), [
        DateTime(2026, 11, 16, 10),
        DateTime(2026, 11, 23, 10),
      ]);
    });

    test('capped, nearest first', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [goal('t1', deadline: DateTime(2026, 11, 25))],
        timeBlocks: [
          weekly('a1', days: {1, 2, 3, 4, 5, 6, 7}, start: '10:00'),
          weekly(
            'a2',
            days: {1, 2, 3, 4, 5, 6, 7},
            start: '14:00',
            end: '15:00',
          ),
        ],
        planTasks: [task('k1', DateTime(2026, 11, 16))],
      );
      final all = plan(data, cap: 1000);
      // 2 sessions/day 14..27 Nov = 28 (open-ended: not cut at the 25 Nov
      // deadline; 28 Nov 10:00 is past the window), + 3 deadline + 1 task.
      expect(all, hasLength(32));
      final capped = plan(data, cap: 5);
      expect(keys(capped), keys(all).take(5).toList());
      final fires = all.map((n) => n.fireAt).toList();
      expect(fires, [...fires]..sort());
      expect(plan(data, cap: 20), hasLength(20));
    });

    test('the default cap leaves room for habit reminders on iOS', () {
      expect(kProjectNotificationCap, lessThanOrEqualTo(32));
      expect(kProjectNotificationWindow, const Duration(days: 14));
    });
  });

  group('ids', () {
    test('stable per occurrence and outside the habit range', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [goal('t1', deadline: DateTime(2026, 11, 20))],
        timeBlocks: [weekly('a1', days: monFri)],
        planTasks: [task('k1', DateTime(2026, 11, 18))],
      );
      final a = plan(data);
      final b = plan(data);
      expect(a.map((n) => n.id), b.map((n) => n.id));
      expect(a.map((n) => n.id).toSet(), hasLength(a.length));
      for (final n in a) {
        expect(isProjectNotificationId(n.id), isTrue);
        expect(isHabitReminderId(n.id), isFalse);
        expect(n.id, lessThan(1 << 31));
      }
    });

    test('habit reminder ids are never project ids', () {
      for (final h in ['a', 'habit-1', 'x' * 40, 'ünïcode']) {
        for (final id in allReminderIds(h)) {
          expect(isHabitReminderId(id), isTrue);
          expect(isProjectNotificationId(id), isFalse);
        }
      }
    });

    test('requests are one-shot with a project payload', () {
      final data = ProjectsData.fromRecords(
        projects: [project('p1')],
        goals: [goal('t1', deadline: DateTime(2026, 11, 20))],
      );
      final r = plan(data).first.toRequest();
      expect(r.repeat, ReminderRepeat.once);
      expect(r.habitId, '${kProjectPayloadPrefix}p1');
      expect(r.firstFire, DateTime(2026, 11, 17, 9));
    });
  });
}
