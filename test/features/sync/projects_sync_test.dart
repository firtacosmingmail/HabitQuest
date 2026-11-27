import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_habit_quest_api.dart';
import 'package:habit_quest/data/remote/remote_models.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/features/game/game_rules.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/domain/project_events.dart';
import 'package:habit_quest/features/projects/models/clock_time.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/project.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/sync/remote_mapping.dart';
import 'package:habit_quest/features/sync/sync_engine.dart';

import 'sync_harness.dart';

/// Projects sync (projects, goals, time blocks, plan tasks, consistent
/// actions, session marks), mirroring `sync_engine_test.dart` with the same fakes.
void main() {
  late TestClock clock;
  late FakeHabitQuestApi server;

  /// Monday 5 Jan 2026 (the harness clock's day).
  final today = DateTime(2026, 1, 5);

  setUp(() {
    clock = TestClock();
    server = FakeHabitQuestApi();
  });

  Device device(String name) => Device(name, clock: clock, api: server);

  /// A project with a weekday time block and a goal → plan task +
  /// consistent action, with today's session marked attended (when
  /// [attend]).
  Future<
    ({
      Project project,
      Goal goal,
      PlanTask task,
      TimeBlock block,
      ConsistentAction action,
    })
  >
  seed(Device dev, {bool attend = true}) async {
    clock.advance();
    final p = await dev.projects.createProject(name: 'Content');
    final g = await dev.projects.createGoal(
      projectId: p.id,
      title: '5 videos',
      deadline: DateTime(2026, 1, 31),
    );
    final task = await dev.projects.addPlanTask(goalId: g.id, title: 'Scripts');
    final b = await dev.projects.createTimeBlock(
      projectId: p.id,
      label: 'Filming',
      startTime: const ClockTime(6, 0),
      endTime: const ClockTime(7, 0),
      recurrence: WeeklyRecurrence({1, 2, 3, 4, 5}),
    );
    final a = await dev.projects.addConsistentAction(
      goalId: g.id,
      text: 'Post one short a day',
    );
    if (attend) await dev.projects.setSessionAttended(b.id, today, true);
    await pumpEventQueue();
    return (project: p, goal: g, task: task, block: b, action: a);
  }

  List<String> projectPosts() => [
    for (final c in server.calls)
      if (c.startsWith('POST') &&
          !c.contains('habits') &&
          !c.contains('check-ins'))
        c,
  ];

  group('push then pull', () {
    test('parents are pushed before children, through batches', () async {
      final a = device('A');
      final s = await seed(a);

      final report = await a.sync();
      expect(projectPosts(), [
        'POST projects/batch',
        'POST goals/batch',
        'POST time-blocks/batch',
        'POST plan-tasks/batch',
        'POST consistent-actions/batch',
        'POST session-marks/batch',
      ]);
      expect(report.pushed, 6);
      expect(report.issues, isEmpty);
      expect(a.queue.isEmpty, isTrue);
      expect(server.projectRecords(ProjectResource.projects).keys, [
        s.project.id,
      ]);
      expect(server.projectRecords(ProjectResource.sessionMarks).keys, [
        SessionMark.keyFor(s.block.id, today),
      ]);
      expect(
        server
            .projectRecords(ProjectResource.sessionMarks)
            .values
            .single
            .json['timeBlockId'],
        s.block.id,
      );
      expect(
        server
            .projectRecords(ProjectResource.timeBlocks)[s.block.id]!
            .json['projectId'],
        s.project.id,
      );
      expect(
        server
            .projectRecords(ProjectResource.consistentActions)[s.action.id]!
            .json['goalId'],
        s.goal.id,
      );
    });

    test('a second device receives every record, announced on '
        'remoteChanges, without queueing them', () async {
      final a = device('A');
      final s = await seed(a);
      await a.sync();

      final b = device('B');
      final report = await b.sync();
      expect(report.pulledProjectRecords, 6);
      final data = b.projects.data;
      expect(data.project(s.project.id)!.name, 'Content');
      expect(data.goal(s.goal.id)!.deadline, DateTime(2026, 1, 31));
      expect(data.planTask(s.task.id)!.title, 'Scripts');
      expect(data.timeBlock(s.block.id), s.block);
      expect(data.timeBlocksOf(s.project.id).single.label, 'Filming');
      expect(data.consistentAction(s.action.id), s.action);
      expect(
        data.consistentActionsOf(s.goal.id).single.text,
        'Post one short a day',
      );
      expect(data.isAttended(s.block.id, today), isTrue);
      expect(b.queue.isEmpty, isTrue);
      expect(
        {for (final e in b.remoteProjectEvents) (e.kind, e.type)},
        {
          for (final k in ProjectEntityKind.values)
            (k, ProjectChangeType.created),
        },
      );
    });

    test('records round-trip through the contract mapping', () async {
      final a = device('A');
      final s = await seed(a);
      final repo = a.projectRepo;
      for (final r in ProjectResource.values) {
        for (final id in localProjectIds(repo, r)) {
          final remote = localProjectRecord(repo, r, id)!;
          final again = RemoteProjectRecord.fromJson(r, remote.toJson());
          expect(again.id, id);
          expect(again.updatedAt, remote.updatedAt);
        }
      }
      final back = projectRecordsFromRemote([
        localProjectRecord(
          repo,
          ProjectResource.consistentActions,
          s.action.id,
        )!,
      ]);
      expect(back.consistentActions.single, s.action);

      final blocks = projectRecordsFromRemote([
        localProjectRecord(repo, ProjectResource.timeBlocks, s.block.id)!,
      ]);
      expect(blocks.timeBlocks.single, s.block);
    });

    test('consistent actions round-trip: edits, reorders and deletes reach '
        'the other device', () async {
      final a = device('A');
      final s = await seed(a, attend: false);
      clock.advance();
      final second = await a.projects.addConsistentAction(
        goalId: s.goal.id,
        text: 'Reply to comments',
      );
      await a.sync();
      final b = device('B');
      await b.sync();
      expect(
        b.projects.data.consistentActionsOf(s.goal.id).map((x) => x.text),
        ['Post one short a day', 'Reply to comments'],
      );

      clock.advance();
      await b.projects.editConsistentAction(s.action.id, 'Post two shorts');
      await b.projects.reorderConsistentActions(s.goal.id, [
        second.id,
        s.action.id,
      ]);
      await b.sync();
      expect(projectPosts().last, 'POST consistent-actions/batch');
      await a.sync();
      expect(
        a.projects.data.consistentActionsOf(s.goal.id).map((x) => x.text),
        ['Reply to comments', 'Post two shorts'],
      );

      clock.advance();
      await a.projects.deleteConsistentAction(second.id);
      await a.sync();
      expect(
        server
            .projectRecords(ProjectResource.consistentActions)[second.id]!
            .isDeleted,
        isTrue,
      );
      await b.sync();
      expect(b.projects.data.consistentActionsOf(s.goal.id).map((x) => x.id), [
        s.action.id,
      ]);
    });

    test('a child whose parent the server refused stays queued and is '
        'reported; the rest syncs', () async {
      final a = device('A');
      final good = await seed(a, attend: false);
      // A record the server refuses (blank name), saved past the service.
      clock.advance();
      final bad = Project(id: 'bad-project', name: ' ', createdAt: clock());
      await a.projectRepo.save(ProjectRecords(projects: [bad]));
      final orphan = Goal(
        id: 'orphan-goal',
        projectId: bad.id,
        title: 'Orphan',
        deadline: DateTime(2026, 2, 1),
        createdAt: clock(),
      );
      await a.projectRepo.save(ProjectRecords(goals: [orphan]));

      final report = await a.sync();
      expect({for (final i in report.issues) i.id}, {bad.id, orphan.id});
      expect(
        report.issues.firstWhere((i) => i.id == orphan.id).message,
        startsWith(ApiException.parentNotFound),
      );
      expect(server.projectRecords(ProjectResource.projects).keys, [
        good.project.id,
      ]);
      expect(server.projectRecords(ProjectResource.goals).keys, [good.goal.id]);
      expect(a.queue.length, 2);
    });
  });

  group('deletes are soft', () {
    test(
      'deleting a project tombstones it and its children everywhere',
      () async {
        final a = device('A');
        final s = await seed(a);
        await a.sync();
        final b = device('B');
        await b.sync();
        b.remoteProjectEvents.clear();

        clock.advance();
        await a.projects.deleteProject(s.project.id);
        await a.sync();
        for (final r in [
          ProjectResource.projects,
          ProjectResource.goals,
          ProjectResource.timeBlocks,
          ProjectResource.planTasks,
          ProjectResource.consistentActions,
        ]) {
          expect(
            server.projectRecords(r).values.single.isDeleted,
            isTrue,
            reason: '${r.function} is a tombstone on the server',
          );
        }

        await b.sync();
        expect(b.projects.data.projects, isEmpty);
        expect(b.projects.data.timeBlocks, isEmpty);
        expect(b.projects.data.consistentActions, isEmpty);
        expect(b.projects.data.sessionMarks, isEmpty);
        // Kept locally as tombstones (sync), hidden from the UI.
        expect(b.projectRepo.getProjectRecord(s.project.id)!.isDeleted, isTrue);
        expect(
          {
            for (final e in b.remoteProjectEvents)
              if (e.type == ProjectChangeType.deleted) e.kind,
          },
          {
            ProjectEntityKind.project,
            ProjectEntityKind.goal,
            ProjectEntityKind.timeBlock,
            ProjectEntityKind.planTask,
            ProjectEntityKind.consistentAction,
          },
        );
      },
    );

    test('a tombstone the server never had is acknowledged', () async {
      final a = device('A');
      final s = await seed(a, attend: false);
      clock.advance();
      await a.projects.deletePlanTask(s.task.id);
      await a.sync();
      expect(a.queue.isEmpty, isTrue);
      expect(
        server.projectRecords(ProjectResource.planTasks)[s.task.id]!.isDeleted,
        isTrue,
      );
    });
  });

  group('last-write-wins', () {
    test('the newest rename wins on both devices', () async {
      final a = device('A');
      final s = await seed(a);
      await a.sync();
      final b = device('B');
      await b.sync();

      clock.advance();
      await a.projects.renameProject(s.project.id, 'Older');
      clock.advance();
      await b.projects.renameProject(s.project.id, 'Newer');

      await b.sync();
      await a.sync(); // pushes the older edit (not applied), pulls B's
      await b.sync();
      expect(a.projects.data.project(s.project.id)!.name, 'Newer');
      expect(b.projects.data.project(s.project.id)!.name, 'Newer');
      expect(
        server
            .projectRecords(ProjectResource.projects)[s.project.id]!
            .json['name'],
        'Newer',
      );
    });

    test('session marks converge on the newest mark', () async {
      final a = device('A');
      final s = await seed(a);
      await a.sync();
      final b = device('B');
      await b.sync();

      clock.advance();
      await b.projects.setSessionAttended(s.block.id, today, false);
      await b.sync();
      await a.sync();
      expect(a.projects.data.isAttended(s.block.id, today), isFalse);
      expect(
        a.remoteProjectEvents.where(
          (e) => e.kind == ProjectEntityKind.sessionMark,
        ),
        hasLength(1),
      );
    });

    test(
      'overlapping time blocks merged from two devices are tolerated',
      () async {
        final a = device('A');
        final s = await seed(a, attend: false);
        await a.sync();
        final b = device('B');
        await b.sync();
        // Both offline-create a clashing block on the same project.
        clock.advance();
        await a.projects.createTimeBlock(
          projectId: s.project.id,
          startTime: const ClockTime(8, 0),
          endTime: const ClockTime(9, 0),
          recurrence: WeeklyRecurrence({1}),
        );
        await b.projects.createTimeBlock(
          projectId: s.project.id,
          startTime: const ClockTime(8, 30),
          endTime: const ClockTime(9, 30),
          recurrence: WeeklyRecurrence({1}),
        );
        await a.sync();
        final report = await b.sync();
        expect(report.issues, isEmpty);
        expect(b.projects.data.timeBlocks, hasLength(3));
      },
    );
  });

  group('cursor', () {
    test('a re-sync pulls nothing new; cursors are per resource', () async {
      final a = device('A');
      await seed(a);
      await a.sync();
      final b = device('B');
      expect((await b.sync()).pulledProjectRecords, 6);
      for (final r in ProjectResource.values) {
        expect(b.meta.projectsCursor('u1', r.function), isNotNull);
      }
      b.remoteProjectEvents.clear();
      // The server's overlap repeats rows; equal updatedAt changes nothing.
      expect((await b.sync()).pulledProjectRecords, 0);
      expect(b.remoteProjectEvents, isEmpty);
    });
  });

  group('XP (GameEngine.reconcileSynced appliedProjects)', () {
    test('a plan task done on A gives B its XP once, without a '
        'celebration', () async {
      final a = device('A');
      final s = await seed(a, attend: false);
      await a.sync();
      final b = device('B');
      await b.sync();

      clock.advance();
      await a.projects.setPlanTaskDone(s.task.id, true);
      await pumpEventQueue();
      expect(a.xp, GameRules.planTaskXp);
      await a.sync();

      await b.sync();
      expect(b.xp, GameRules.planTaskXp);
      expect(b.gameEvents, isEmpty);

      await b.sync();
      await a.sync();
      expect(a.xp, GameRules.planTaskXp);
      expect(b.xp, GameRules.planTaskXp);
    });

    test(
      'records pulled before their game state grant XP once, silently',
      () async {
        // Another device pushed its records but not (yet) its game state.
        final other = device('Other');
        final s = await seed(other);
        await other.projects.setPlanTaskDone(s.task.id, true);
        await other.projects.setGoalStatus(s.goal.id, GoalStatus.done);
        final repo = other.projectRepo;
        for (final r in ProjectResource.values) {
          for (final id in localProjectIds(repo, r)) {
            server.seedProjectRecord(localProjectRecord(repo, r, id)!);
          }
        }
        expect(server.gameState, isNull);

        final b = device('B');
        await b.sync();
        const expected =
            GameRules.planTaskXp + GameRules.goalDoneXp + GameRules.sessionXp;
        expect(b.xp, expected);
        expect(b.game.state.projectLedger.keys, {
          GameState.planTaskKey(s.task.id),
          GameState.goalKey(s.goal.id),
          GameState.sessionKey(s.block.id, today),
        });
        // Legacy ledger key shapes are kept.
        expect(b.game.state.projectLedger.keys, {
          'task:${s.task.id}',
          'target:${s.goal.id}',
          'session:${s.block.id}|2026-01-05',
        });
        expect(b.gameEvents, isEmpty, reason: 'remote awards are silent');

        // Further syncs, and another device of the same user, add nothing.
        await b.sync();
        final c = device('C');
        await c.sync();
        expect(b.xp, expected);
        expect(c.xp, expected);
        expect(c.gameEvents, isEmpty);
      },
    );

    test(
      'a time block deleted on another device drops its session XP',
      () async {
        final a = device('A');
        final s = await seed(a);
        expect(a.xp, GameRules.sessionXp);
        await a.sync();
        final b = device('B');
        await b.sync();
        expect(b.xp, GameRules.sessionXp);

        clock.advance();
        await b.projects.deleteTimeBlock(s.block.id);
        await pumpEventQueue();
        expect(b.xp, 0);
        await b.sync();
        expect(
          server
              .projectRecords(ProjectResource.timeBlocks)[s.block.id]!
              .isDeleted,
          isTrue,
        );
        await a.sync();
        expect(a.xp, 0);
        expect(a.projects.data.timeBlocks, isEmpty);
        expect(a.projects.data.isAttended(s.block.id, today), isFalse);
      },
    );

    test('an un-done plan task on another device removes the XP', () async {
      final a = device('A');
      final s = await seed(a, attend: false);
      await a.projects.setPlanTaskDone(s.task.id, true);
      await a.sync();
      final b = device('B');
      await b.sync();
      expect(b.xp, GameRules.planTaskXp);

      clock.advance();
      await b.projects.setPlanTaskDone(s.task.id, false);
      await pumpEventQueue();
      await b.sync();
      await a.sync();
      expect(a.xp, 0);
      expect(b.xp, 0);
    });
  });

  group('account switch', () {
    test('first login adopts projects created before any account', () async {
      final a = device('A');
      final s = await seed(a);
      await a.queue.clear(); // pre-sync data: nothing queued

      expect(await a.engine.prepareForUser('u1'), AccountChange.claimed);
      expect(
        a.queue.entries.map((e) => e.type).toSet(),
        containsAll([
          SyncEntityType.project,
          SyncEntityType.goal,
          SyncEntityType.timeBlock,
          SyncEntityType.planTask,
          SyncEntityType.consistentAction,
          SyncEntityType.sessionMark,
        ]),
      );
      await a.engine.sync('u1');
      expect(server.projectRecords(ProjectResource.projects).keys, [
        s.project.id,
      ]);
      expect(server.projectRecords(ProjectResource.sessionMarks), hasLength(1));
    });

    test(
      "a different user never receives the previous user's projects",
      () async {
        final serverU2 = FakeHabitQuestApi();
        final a = device('A');
        final s = await seed(a);
        await a.sync(user: 'u1');
        clock.advance();
        await a.projects.createProject(name: 'Unsynced');
        a.remoteProjectEvents.clear();

        a.api = serverU2;
        expect(await a.engine.prepareForUser('u2'), AccountChange.switched);
        await a.engine.sync('u2');

        expect(serverU2.projectRecords(ProjectResource.projects), isEmpty);
        expect(a.projects.data.projects, isEmpty);
        expect(a.projectRepo.getProjectRecord(s.project.id), isNull);
        // Announced as deletions so notifications are cancelled.
        expect(
          a.remoteProjectEvents
              .where((e) => e.type == ProjectChangeType.deleted)
              .map((e) => e.kind)
              .toSet(),
          containsAll([
            ProjectEntityKind.project,
            ProjectEntityKind.goal,
            ProjectEntityKind.timeBlock,
            ProjectEntityKind.consistentAction,
          ]),
        );
        for (final r in ProjectResource.values) {
          expect(a.meta.projectsCursor('u1', r.function), isNull);
        }
      },
    );
  });
}
