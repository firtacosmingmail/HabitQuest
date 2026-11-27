import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/domain/overlap.dart';
import 'package:habit_quest/features/projects/domain/project_events.dart';
import 'package:habit_quest/features/projects/domain/project_service.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';

import 'helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

void main() {
  late InMemoryProjectRepository repo;
  late ProjectService service;
  late DateTime now;
  late List<ProjectChangeEvent> events;
  late List<ProjectChangeEvent> remote;
  late List<SessionAttendanceEvent> attendance;
  var ids = 0;

  setUp(() {
    ids = 0;
    now = DateTime(2026, 11, 14, 9); // Saturday
    repo = InMemoryProjectRepository();
    service = ProjectService(
      repo,
      now: () => now,
      idGenerator: () => 'id${++ids}',
    );
    events = [];
    remote = [];
    attendance = [];
    service.changes.listen(events.add);
    service.remoteChanges.listen(remote.add);
    service.attendanceEvents.listen(attendance.add);
  });

  tearDown(() => service.dispose());

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  /// The spec example: "Content business" / "5 videos" by 30 Nov, a 3-step
  /// plan, one consistent action and a Mon–Fri 10–13 "Editing" block on the
  /// project.
  Future<(String, Goal, TimeBlock)> example() async {
    final p = await service.createProject(name: '  Content business ');
    final g = await service.createGoal(
      projectId: p.id,
      title: '5 videos',
      deadline: d(2026, 11, 30),
    );
    for (final s in ['scripts', 'recordings', 'edits']) {
      await service.addPlanTask(goalId: g.id, title: '5 $s');
    }
    await service.addConsistentAction(
      goalId: g.id,
      text: 'Post one short a day',
    );
    final b = await service.createTimeBlock(
      projectId: p.id,
      label: '  Editing ',
      startTime: hm('10:00'),
      endTime: hm('13:00'),
      recurrence: WeeklyRecurrence(monFri),
    );
    await flush();
    return (p.id, g, b);
  }

  group('projects', () {
    test('create trims, stamps and emits', () async {
      final p = await service.createProject(name: '  Content business ');
      await flush();
      expect(p.name, 'Content business');
      expect(p.id, 'id1');
      expect(p.updatedAt, now.toUtc());
      expect(events.single.type, ProjectChangeType.created);
      expect(events.single.kind, ProjectEntityKind.project);
      expect(events.single.project, p);
      expect(service.data.projects.single, p);
    });

    test('empty names are rejected', () {
      expect(() => service.createProject(name: '  '), throwsArgumentError);
    });

    test('rename / archive / unarchive; unchanged emits nothing', () async {
      final p = await service.createProject(name: 'A');
      now = now.add(const Duration(minutes: 1));
      final r = await service.renameProject(p.id, 'B');
      expect(r.updatedAt.isAfter(p.updatedAt), isTrue);
      await service.archiveProject(p.id);
      await service.archiveProject(p.id, archived: false);
      await service.renameProject(p.id, 'B');
      await flush();
      expect(events.map((e) => e.type), [
        ProjectChangeType.created,
        ProjectChangeType.updated,
        ProjectChangeType.archived,
        ProjectChangeType.unarchived,
      ]);
    });

    test('delete cascades tombstones to goals, tasks, consistent actions and '
        'time blocks (children first)', () async {
      final (pid, g, b) = await example();
      events.clear();
      now = now.add(const Duration(hours: 1));
      await service.deleteProject(pid);
      await flush();
      expect(service.data.projects, isEmpty);
      expect(service.data.goals, isEmpty);
      expect(service.data.timeBlocks, isEmpty);
      expect(service.data.consistentActions, isEmpty);
      expect(repo.getAllPlanTaskRecords().every((x) => x.isDeleted), isTrue);
      expect(
        repo.getAllConsistentActionRecords().every((x) => x.isDeleted),
        isTrue,
      );
      expect(repo.getTimeBlockRecord(b.id)!.deletedAt, now.toUtc());
      expect(repo.getGoalRecord(g.id)!.deletedAt, now.toUtc());
      expect(events.map((e) => e.kind), [
        ProjectEntityKind.timeBlock,
        ProjectEntityKind.consistentAction,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.goal,
        ProjectEntityKind.project,
      ]);
      expect(events.every((e) => e.type == ProjectChangeType.deleted), isTrue);
      expect(events.first.timeBlock!.isDeleted, isTrue);
      expect(events.first.previous, b);
      expect(events[1].consistentAction!.isDeleted, isTrue);
      expect(events[5].goal!.id, g.id);
      expect(() => service.renameProject(pid, 'x'), throwsStateError);
      expect(g.isDeleted, isFalse);
    });

    test('a deleted project frees its time slots', () async {
      final (pid, _, _) = await example();
      final p2 = await service.createProject(name: 'Fitness');
      await service.deleteProject(pid);
      await service.createTimeBlock(
        projectId: p2.id,
        startTime: hm('10:00'),
        endTime: hm('13:00'),
        recurrence: WeeklyRecurrence(monFri),
      );
      expect(service.data.timeBlocksOf(p2.id), hasLength(1));
    });
  });

  group('goals', () {
    test('needs a live project; status is manual and kept', () async {
      expect(
        () => service.createGoal(
          projectId: 'nope',
          title: 'x',
          deadline: d(2026, 12, 1),
        ),
        throwsStateError,
      );
      final (_, g, _) = await example();
      expect(g.status, GoalStatus.notStarted);
      expect(service.data.goalsOf(g.projectId), [g]);
      // Checking off every task does not change the status.
      for (final k in service.data.planTasksOf(g.id)) {
        await service.setPlanTaskDone(k.id, true);
      }
      expect(service.data.goal(g.id)!.status, GoalStatus.notStarted);
      final s = await service.setGoalStatus(g.id, GoalStatus.inProgress);
      expect(s.status, GoalStatus.inProgress);
      await flush();
      expect(events.last.goal, s);
      expect(events.last.type, ProjectChangeType.updated);
    });

    test('empty titles are rejected; title is trimmed', () async {
      final p = await service.createProject(name: 'P');
      expect(
        () => service.createGoal(
          projectId: p.id,
          title: ' ',
          deadline: d(2026, 12, 1),
        ),
        throwsArgumentError,
      );
      final g = await service.createGoal(
        projectId: p.id,
        title: ' Ship ',
        deadline: d(2026, 12, 1),
      );
      expect(g.title, 'Ship');
      expect(
        () => service.updateGoal(g.copyWith(title: '')),
        throwsArgumentError,
      );
    });

    test('delete cascades to its tasks and consistent actions only', () async {
      final (pid, g, b) = await example();
      final other = await service.createGoal(
        projectId: pid,
        title: 'Other',
        deadline: d(2026, 12, 31),
      );
      final keep = await service.addConsistentAction(
        goalId: other.id,
        text: 'Keep me',
      );
      await flush();
      events.clear();
      await service.deleteGoal(g.id);
      await flush();
      expect(service.data.goals, [other]);
      expect(service.data.planTasks, isEmpty);
      expect(service.data.consistentActions, [keep]);
      expect(service.data.timeBlocks, [b], reason: 'blocks are on the project');
      expect(events.map((e) => e.kind), [
        ProjectEntityKind.consistentAction,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.goal,
      ]);
      expect(
        () => service.addConsistentAction(goalId: g.id, text: 'x'),
        throwsStateError,
      );
    });

    test(
      'deadline and status never touch time blocks or check overlaps',
      () async {
        final (pid, g, b) = await example();
        // Moving the deadline earlier / later and marking the goal done is
        // always allowed.
        await service.updateGoal(g.copyWith(deadline: d(2026, 11, 20)));
        await service.updateGoal(g.copyWith(deadline: d(2027, 6, 30)));
        await service.setGoalStatus(g.id, GoalStatus.done);
        expect(service.data.goal(g.id)!.deadline, d(2027, 6, 30));
        expect(service.data.timeBlock(b.id), b);
        // A done goal does not free the project's time slots.
        final p2 = await service.createProject(name: 'Fitness');
        expect(
          () => service.createTimeBlock(
            projectId: p2.id,
            startTime: hm('12:00'),
            endTime: hm('14:00'),
            recurrence: WeeklyRecurrence(monFri),
          ),
          throwsA(isA<TimeBlockOverlapException>()),
        );
        expect(pid, isNotEmpty);
      },
    );
  });

  group('plan tasks', () {
    test('appended in order, editable, reorderable, deletable', () async {
      final (_, g, _) = await example();
      final tasks = service.data.planTasksOf(g.id);
      expect(tasks.map((x) => x.title), [
        '5 scripts',
        '5 recordings',
        '5 edits',
      ]);
      expect(tasks.map((x) => x.position), [0, 1, 2]);
      expect(tasks.every((x) => x.goalId == g.id), isTrue);
      await service.updatePlanTask(
        tasks[0].copyWith(deliveryDate: () => d(2026, 11, 10)),
      );
      expect(service.data.planTask(tasks[0].id)!.deliveryDate, d(2026, 11, 10));
      await service.reorderPlanTasks(g.id, [
        tasks[2].id,
        tasks[0].id,
        tasks[1].id,
      ]);
      expect(service.data.planTasksOf(g.id).map((x) => x.title), [
        '5 edits',
        '5 scripts',
        '5 recordings',
      ]);
      expect(
        () => service.reorderPlanTasks(g.id, [tasks[0].id]),
        throwsArgumentError,
      );
      await service.deletePlanTask(tasks[1].id);
      expect(service.data.planTasksOf(g.id), hasLength(2));
      expect(
        () => service.setPlanTaskDone(tasks[1].id, true),
        throwsStateError,
      );
      expect(
        () => service.addPlanTask(goalId: 'nope', title: 'x'),
        throwsStateError,
      );
    });
  });

  group('consistent actions', () {
    test('add appends with the next sortOrder, trims and emits', () async {
      final (_, g, _) = await example();
      await flush();
      events.clear();
      final first = service.data.consistentActionsOf(g.id).single;
      expect(first.sortOrder, 0);
      expect(first.text, 'Post one short a day');
      final a = await service.addConsistentAction(
        goalId: g.id,
        text: '  Reply to comments ',
      );
      final b = await service.addConsistentAction(goalId: g.id, text: 'Third');
      await flush();
      expect(a.text, 'Reply to comments');
      expect(a.goalId, g.id);
      expect(a.sortOrder, 1);
      expect(b.sortOrder, 2);
      expect(a.updatedAt, now.toUtc());
      expect(service.data.consistentActionsOf(g.id), [first, a, b]);
      expect(repo.getConsistentActionRecord(a.id), a);
      expect(events.map((e) => (e.type, e.kind)), [
        (ProjectChangeType.created, ProjectEntityKind.consistentAction),
        (ProjectChangeType.created, ProjectEntityKind.consistentAction),
      ]);
      expect(events.first.consistentAction, a);
      expect(events.first.id, a.id);
    });

    test('add rejects blank text and unknown goals', () async {
      final (_, g, _) = await example();
      expect(
        () => service.addConsistentAction(goalId: g.id, text: '   '),
        throwsArgumentError,
      );
      expect(
        () => service.addConsistentAction(goalId: 'nope', text: 'x'),
        throwsStateError,
      );
      expect(service.data.consistentActionsOf(g.id), hasLength(1));
    });

    test('edit trims, stamps and emits; blank text is rejected', () async {
      final (_, g, _) = await example();
      final a = service.data.consistentActionsOf(g.id).single;
      events.clear();
      now = now.add(const Duration(minutes: 5));
      final e = await service.editConsistentAction(a.id, '  Two shorts a day ');
      await flush();
      expect(e.text, 'Two shorts a day');
      expect(e.sortOrder, a.sortOrder);
      expect(e.updatedAt, now.toUtc());
      expect(service.data.consistentAction(a.id), e);
      expect(events.single.type, ProjectChangeType.updated);
      expect(events.single.kind, ProjectEntityKind.consistentAction);
      expect(events.single.previous, a);
      expect(
        () => service.editConsistentAction(a.id, ' '),
        throwsArgumentError,
      );
      expect(service.data.consistentAction(a.id)!.text, 'Two shorts a day');
      // Unchanged (after trimming): no write, no event.
      events.clear();
      final same = await service.editConsistentAction(
        a.id,
        'Two shorts a day ',
      );
      await flush();
      expect(same, e);
      expect(events, isEmpty);
      expect(() => service.editConsistentAction('nope', 'x'), throwsStateError);
    });

    test('update cannot move an action to another goal', () async {
      final (pid, g, _) = await example();
      final other = await service.createGoal(
        projectId: pid,
        title: 'Other',
        deadline: d(2026, 12, 31),
      );
      final a = service.data.consistentActionsOf(g.id).single;
      expect(
        () => service.updateConsistentAction(
          ConsistentAction(
            id: a.id,
            goalId: other.id,
            text: a.text,
            createdAt: a.createdAt,
          ),
        ),
        throwsArgumentError,
      );
    });

    test('reorder validates the ids and stamps only moved items', () async {
      final (pid, g, _) = await example();
      final a = service.data.consistentActionsOf(g.id).single;
      final b = await service.addConsistentAction(goalId: g.id, text: 'B');
      final c = await service.addConsistentAction(goalId: g.id, text: 'C');
      final other = await service.createGoal(
        projectId: pid,
        title: 'Other',
        deadline: d(2026, 12, 31),
      );
      final foreign = await service.addConsistentAction(
        goalId: other.id,
        text: 'Foreign',
      );
      for (final wrong in [
        [a.id, b.id],
        [a.id, b.id, c.id, c.id],
        [a.id, b.id, b.id],
        [a.id, b.id, foreign.id],
        [a.id, b.id, c.id, foreign.id],
      ]) {
        expect(
          () => service.reorderConsistentActions(g.id, wrong),
          throwsArgumentError,
          reason: '$wrong',
        );
      }
      expect(
        () => service.reorderConsistentActions('nope', const []),
        throwsStateError,
      );
      await flush();
      events.clear();
      now = now.add(const Duration(minutes: 1));
      await service.reorderConsistentActions(g.id, [a.id, c.id, b.id]);
      await flush();
      expect(service.data.consistentActionsOf(g.id).map((x) => x.text), [
        'Post one short a day',
        'C',
        'B',
      ]);
      expect(service.data.consistentAction(a.id)!.updatedAt, a.updatedAt);
      expect(service.data.consistentAction(c.id)!.sortOrder, 1);
      expect(service.data.consistentAction(c.id)!.updatedAt, now.toUtc());
      expect(service.data.consistentAction(b.id)!.sortOrder, 2);
      expect(events.map((e) => e.id), [c.id, b.id]);
      expect(
        events.every(
          (e) =>
              e.type == ProjectChangeType.updated &&
              e.kind == ProjectEntityKind.consistentAction,
        ),
        isTrue,
      );
      // Same order again: nothing changes.
      events.clear();
      await service.reorderConsistentActions(g.id, [a.id, c.id, b.id]);
      await flush();
      expect(events, isEmpty);
      expect(service.data.consistentAction(foreign.id)!.sortOrder, 0);
    });

    test(
      'delete tombstones one action; later adds go after the rest',
      () async {
        final (_, g, _) = await example();
        final a = service.data.consistentActionsOf(g.id).single;
        final b = await service.addConsistentAction(goalId: g.id, text: 'B');
        await flush();
        events.clear();
        now = now.add(const Duration(minutes: 1));
        await service.deleteConsistentAction(b.id);
        await flush();
        expect(service.data.consistentActionsOf(g.id), [a]);
        expect(repo.getConsistentActionRecord(b.id)!.deletedAt, now.toUtc());
        expect(events.single.type, ProjectChangeType.deleted);
        expect(events.single.kind, ProjectEntityKind.consistentAction);
        expect(events.single.previous, b);
        expect(() => service.deleteConsistentAction(b.id), throwsStateError);
        expect(() => service.editConsistentAction(b.id, 'x'), throwsStateError);
        final c = await service.addConsistentAction(goalId: g.id, text: 'C');
        expect(c.sortOrder, 1);
      },
    );
  });

  group('time blocks', () {
    test('a label-only edit of an already clashing block is saved', () async {
      final (pid, _, b) = await example();
      // Merged / migrated data may already clash: seed a clashing block
      // through applyRemote (no overlap check there).
      final other = weekly('remote', projectId: pid, days: {1});
      await service.applyRemote(ProjectRecords(timeBlocks: [other]));
      final renamed = await service.updateTimeBlock(
        b.copyWith(label: () => 'Deep work'),
      );
      expect(renamed.label, 'Deep work');
      // Changing the schedule still checks (and is refused).
      expect(
        () => service.updateTimeBlock(renamed.copyWith(endTime: hm('12:00'))),
        throwsA(isA<TimeBlockOverlapException>()),
      );
    });

    test('create on a project: trimmed label, open-ended, emits', () async {
      final (pid, _, b) = await example();
      expect(b.projectId, pid);
      expect(b.label, 'Editing');
      expect(b.isOpenEnded, isTrue);
      expect(b.endDate, isNull);
      expect(b.effectiveStartDate, d(2026, 11, 14));
      expect(service.data.timeBlocksOf(pid), [b]);
      expect(events.last.type, ProjectChangeType.created);
      expect(events.last.kind, ProjectEntityKind.timeBlock);
      expect(events.last.timeBlock, b);
    });

    test('a project can have several non-overlapping blocks', () async {
      final (pid, _, _) = await example();
      final sat = await service.createTimeBlock(
        projectId: pid,
        label: '   ',
        startTime: hm('09:00'),
        endTime: hm('11:00'),
        recurrence: WeeklyRecurrence({6}),
        startDate: d(2026, 11, 21),
        endDate: d(2027, 1, 31),
      );
      expect(service.data.timeBlocksOf(pid), hasLength(2));
      expect(sat.label, isNull);
      expect(sat.effectiveStartDate, d(2026, 11, 21));
      expect(sat.endDate, d(2027, 1, 31));
      expect(
        () => service.createTimeBlock(
          projectId: 'nope',
          startTime: hm('20:00'),
          endTime: hm('21:00'),
          recurrence: WeeklyRecurrence({1}),
        ),
        throwsStateError,
      );
    });

    test(
      'invalid times or an end date before the start date are rejected',
      () async {
        final (pid, _, _) = await example();
        await flush();
        events.clear();
        expect(
          () => service.createTimeBlock(
            projectId: pid,
            startTime: hm('15:00'),
            endTime: hm('15:00'),
            recurrence: WeeklyRecurrence({1}),
          ),
          throwsArgumentError,
        );
        expect(
          () => service.createTimeBlock(
            projectId: pid,
            startTime: hm('15:00'),
            endTime: hm('16:00'),
            recurrence: WeeklyRecurrence({1}),
            startDate: d(2026, 12, 10),
            endDate: d(2026, 12, 9),
          ),
          throwsArgumentError,
        );
        await flush();
        expect(events, isEmpty);
        expect(service.data.timeBlocksOf(pid), hasLength(1));
      },
    );

    test('a clash with another project is blocked with a message naming the '
        'project and the label', () async {
      final (_, _, b) = await example();
      final p2 = await service.createProject(name: 'Fitness');
      await flush();
      events.clear();
      try {
        await service.createTimeBlock(
          projectId: p2.id,
          label: 'Run',
          startTime: hm('12:30'),
          endTime: hm('13:30'),
          recurrence: WeeklyRecurrence({2, 4}),
        );
        fail('expected an overlap');
      } on TimeBlockOverlapException catch (e) {
        expect(e.clashes.single.block.id, b.id);
        expect(e.clashes.single.project!.name, 'Content business');
        expect(e.clashes.single.firstDate, d(2026, 11, 17));
        expect(
          e.message,
          'This time block (Tue, Thu 12:30–13:30) overlaps '
          '"Content business" (Editing), Mon–Fri 10:00–13:00, '
          'first on 2026-11-17',
        );
      }
      await flush();
      expect(events, isEmpty);
      expect(service.data.timeBlocksOf(p2.id), isEmpty);
      // Touching the end is fine.
      await service.createTimeBlock(
        projectId: p2.id,
        startTime: hm('13:00'),
        endTime: hm('14:00'),
        recurrence: WeeklyRecurrence({2, 4}),
      );
      expect(service.data.timeBlocksOf(p2.id), hasLength(1));
    });

    test('an unlabelled clashing block is named by its project only', () async {
      final p1 = await service.createProject(name: 'Writing');
      await service.createTimeBlock(
        projectId: p1.id,
        startTime: hm('08:00'),
        endTime: hm('09:00'),
        recurrence: MonthlyRecurrence({1, 15}),
      );
      final p2 = await service.createProject(name: 'Fitness');
      expect(
        () => service.createTimeBlock(
          projectId: p2.id,
          startTime: hm('08:30'),
          endTime: hm('09:30'),
          recurrence: WeeklyRecurrence({2}),
        ),
        throwsA(
          isA<TimeBlockOverlapException>().having(
            (e) => e.message,
            'message',
            'This time block (Tue 08:30–09:30) overlaps "Writing", '
                '1st, 15th of the month 08:00–09:00, first on 2026-12-01',
          ),
        ),
      );
    });

    test('an archived project still holds its time slots', () async {
      final (pid, _, _) = await example();
      await service.archiveProject(pid);
      final p2 = await service.createProject(name: 'Fitness');
      expect(
        () => service.createTimeBlock(
          projectId: p2.id,
          startTime: hm('11:00'),
          endTime: hm('12:00'),
          recurrence: WeeklyRecurrence({1}),
        ),
        throwsA(isA<TimeBlockOverlapException>()),
      );
    });

    test(
      'end dates bound the clash check; open-ended blocks do not stop',
      () async {
        final (_, _, b) = await example();
        final bounded = await service.updateTimeBlock(
          b.copyWith(endDate: () => d(2026, 11, 30)),
        );
        expect(bounded.endDate, d(2026, 11, 30));
        final p2 = await service.createProject(name: 'Course');
        // Starts the day after the first block ends: no clash.
        final later = await service.createTimeBlock(
          projectId: p2.id,
          startTime: hm('11:00'),
          endTime: hm('12:00'),
          recurrence: WeeklyRecurrence({2}),
          startDate: d(2026, 12, 1),
        );
        // Re-opening the first block now clashes on Tue 1 Dec.
        expect(
          () => service.updateTimeBlock(bounded.copyWith(endDate: () => null)),
          throwsA(
            isA<TimeBlockOverlapException>()
                .having((e) => e.clashes.single.block.id, 'block', later.id)
                .having(
                  (e) => e.clashes.single.firstDate,
                  'first',
                  d(2026, 12, 1),
                ),
          ),
        );
        expect(service.data.timeBlock(b.id)!.endDate, d(2026, 11, 30));
        // An open-ended block clashes with one starting far in the future.
        final p3 = await service.createProject(name: 'Later');
        expect(
          service
              .clashesFor(
                weekly(
                  'probe',
                  projectId: p3.id,
                  days: {2},
                  start: '11:30',
                  end: '12:30',
                  startDate: d(2030, 1, 1),
                ),
              )
              .single
              .block
              .id,
          later.id,
        );
      },
    );

    test('update re-checks overlaps but ignores itself', () async {
      final (pid, _, a) = await example();
      final b = await service.createTimeBlock(
        projectId: pid,
        startTime: hm('14:00'),
        endTime: hm('15:00'),
        recurrence: WeeklyRecurrence(monFri),
      );
      await service.updateTimeBlock(a.copyWith(endTime: hm('14:00')));
      expect(
        () => service.updateTimeBlock(b.copyWith(startTime: hm('13:30'))),
        throwsA(isA<TimeBlockOverlapException>()),
      );
      expect(
        service.clashesFor(b.copyWith(startTime: hm('13:30'))),
        hasLength(1),
      );
      expect(service.clashesFor(b), isEmpty);
    });

    test(
      'update stamps, emits, edits the label; no-op emits nothing',
      () async {
        final (_, _, b) = await example();
        events.clear();
        now = now.add(const Duration(minutes: 1));
        final u = await service.updateTimeBlock(
          b.copyWith(label: () => ' Recording '),
        );
        await flush();
        expect(u.label, 'Recording');
        expect(u.updatedAt, now.toUtc());
        expect(events.single.type, ProjectChangeType.updated);
        expect(events.single.timeBlock, u);
        expect(events.single.previous, b);
        events.clear();
        expect(await service.updateTimeBlock(u), u);
        await flush();
        expect(events, isEmpty);
        // The owning project cannot change.
        expect(
          () => service.updateTimeBlock(
            weekly(b.id, projectId: 'other', days: monFri),
          ),
          throwsArgumentError,
        );
        expect(
          () => service.updateTimeBlock(weekly('nope', days: {7})),
          throwsStateError,
        );
      },
    );

    test('a deleted block no longer blocks', () async {
      final (pid, _, b) = await example();
      await flush();
      events.clear();
      await service.deleteTimeBlock(b.id);
      await flush();
      expect(events.single.type, ProjectChangeType.deleted);
      expect(events.single.kind, ProjectEntityKind.timeBlock);
      await service.createTimeBlock(
        projectId: pid,
        startTime: hm('10:00'),
        endTime: hm('13:00'),
        recurrence: WeeklyRecurrence(monFri),
      );
      expect(service.data.timeBlocksOf(pid), hasLength(1));
      expect(() => service.deleteTimeBlock(b.id), throwsStateError);
    });
  });

  group('sessions', () {
    test('mark attended today or in the past, not in the future', () async {
      now = DateTime(2026, 11, 16, 12); // Monday
      final (pid, _, b) = await example();
      await service.setSessionAttended(b.id, d(2026, 11, 16), true);
      await flush();
      expect(service.isAttended(b.id, d(2026, 11, 16)), isTrue);
      expect(
        attendance.single,
        SessionAttendanceEvent(
          timeBlockId: b.id,
          projectId: pid,
          date: d(2026, 11, 16),
          attended: true,
        ),
      );
      // Idempotent.
      await service.setSessionAttended(b.id, d(2026, 11, 16), true);
      await flush();
      expect(attendance, hasLength(1));
      expect(
        await service.toggleSessionAttended(b.id, d(2026, 11, 16)),
        isFalse,
      );
      expect(
        repo.getSessionMarkRecord(b.id, d(2026, 11, 16))!.attended,
        isFalse,
      );
      expect(
        () => service.setSessionAttended(b.id, d(2026, 11, 17), true),
        throwsArgumentError,
        reason: 'future',
      );
      expect(
        () => service.setSessionAttended(b.id, d(2026, 11, 15), true),
        throwsArgumentError,
        reason: 'Sunday: no session',
      );
      expect(
        () => service.setSessionAttended('nope', d(2026, 11, 16), true),
        throwsStateError,
      );
    });

    test('no session after the block end date', () async {
      now = DateTime(2026, 11, 20, 18); // Friday
      final p = await service.createProject(name: 'P');
      final b = await service.createTimeBlock(
        projectId: p.id,
        startTime: hm('10:00'),
        endTime: hm('11:00'),
        recurrence: WeeklyRecurrence(monFri),
        startDate: d(2026, 11, 16),
        endDate: d(2026, 11, 18),
      );
      await service.setSessionAttended(b.id, d(2026, 11, 18), true);
      expect(
        () => service.setSessionAttended(b.id, d(2026, 11, 19), true),
        throwsArgumentError,
      );
    });
  });

  group('sync hooks', () {
    test(
      'applyRemote announces on remoteChanges only, no attendance',
      () async {
        final (pid, _, b) = await example();
        events.clear();
        final renamed = service.data
            .project(pid)!
            .copyWith(name: 'Renamed', updatedAt: DateTime.utc(2026, 12, 1));
        final gone = b.copyWith(
          updatedAt: DateTime.utc(2026, 12, 1),
          deletedAt: () => DateTime.utc(2026, 12, 1),
        );
        final fresh = goal('g9', projectId: pid, deadline: d(2027, 1, 1));
        final note = action('c9', goalId: 'g9', text: 'Remote item');
        await service.applyRemote(
          ProjectRecords(
            projects: [renamed],
            goals: [fresh],
            timeBlocks: [gone],
            consistentActions: [note],
          ),
        );
        await flush();
        expect(events, isEmpty);
        expect(attendance, isEmpty);
        expect(remote.map((e) => (e.kind, e.type)), [
          (ProjectEntityKind.project, ProjectChangeType.updated),
          (ProjectEntityKind.goal, ProjectChangeType.created),
          (ProjectEntityKind.timeBlock, ProjectChangeType.deleted),
          (ProjectEntityKind.consistentAction, ProjectChangeType.created),
        ]);
        expect(service.data.project(pid)!.name, 'Renamed');
        expect(service.data.timeBlocksOf(pid), isEmpty);
        expect(service.data.consistentActionsOf('g9'), [note]);
      },
    );

    test('clearLocalData wipes and announces deletions', () async {
      await example();
      await service.clearLocalData();
      await flush();
      expect(service.data.projects, isEmpty);
      expect(repo.getAllProjectRecords(), isEmpty);
      expect(repo.getAllConsistentActionRecords(), isEmpty);
      expect(remote.every((e) => e.type == ProjectChangeType.deleted), isTrue);
      expect(remote.map((e) => e.kind), [
        ProjectEntityKind.timeBlock,
        ProjectEntityKind.consistentAction,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.planTask,
        ProjectEntityKind.goal,
        ProjectEntityKind.project,
      ]);
    });
  });
}
