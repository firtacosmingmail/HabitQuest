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
import 'package:habit_quest/features/projects/models/target.dart';
import 'package:habit_quest/features/sync/remote_mapping.dart';
import 'package:habit_quest/features/sync/sync_engine.dart';

import 'sync_harness.dart';

/// Projects sync (projects, targets, plan tasks, consistent actions,
/// session marks), mirroring `sync_engine_test.dart` with the same fakes.
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

  /// A project → target → plan task + weekday action, with today's session
  /// marked attended (when [attend]).
  Future<
    ({Project project, Target target, PlanTask task, ConsistentAction action})
  >
  seed(Device dev, {bool attend = true}) async {
    clock.advance();
    final p = await dev.projects.createProject(name: 'Content');
    final t = await dev.projects.createTarget(
      projectId: p.id,
      title: '5 videos',
      deadline: DateTime(2026, 1, 31),
    );
    final task = await dev.projects.addPlanTask(
      targetId: t.id,
      title: 'Scripts',
    );
    final a = await dev.projects.createAction(
      targetId: t.id,
      startTime: const ClockTime(6, 0),
      endTime: const ClockTime(7, 0),
      recurrence: WeeklyRecurrence({1, 2, 3, 4, 5}),
    );
    if (attend) await dev.projects.setSessionAttended(a.id, today, true);
    await pumpEventQueue();
    return (project: p, target: t, task: task, action: a);
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
        'POST targets/batch',
        'POST plan-tasks/batch',
        'POST consistent-actions/batch',
        'POST session-marks/batch',
      ]);
      expect(report.pushed, 5);
      expect(report.issues, isEmpty);
      expect(a.queue.isEmpty, isTrue);
      expect(server.projectRecords(ProjectResource.projects).keys, [
        s.project.id,
      ]);
      expect(server.projectRecords(ProjectResource.sessionMarks).keys, [
        SessionMark.keyFor(s.action.id, today),
      ]);
    });

    test('a second device receives every record, announced on '
        'remoteChanges, without queueing them', () async {
      final a = device('A');
      final s = await seed(a);
      await a.sync();

      final b = device('B');
      final report = await b.sync();
      expect(report.pulledProjectRecords, 5);
      final data = b.projects.data;
      expect(data.project(s.project.id)!.name, 'Content');
      expect(data.target(s.target.id)!.deadline, DateTime(2026, 1, 31));
      expect(data.planTask(s.task.id)!.title, 'Scripts');
      expect(data.action(s.action.id), s.action);
      expect(data.isAttended(s.action.id, today), isTrue);
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
      expect(back.actions.single, s.action);
    });

    test('a child whose parent the server refused stays queued and is '
        'reported; the rest syncs', () async {
      final a = device('A');
      final good = await seed(a, attend: false);
      // A record the server refuses (blank name), saved past the service.
      clock.advance();
      final bad = Project(id: 'bad-project', name: ' ', createdAt: clock());
      await a.projectRepo.save(ProjectRecords(projects: [bad]));
      final orphan = Target(
        id: 'orphan-target',
        projectId: bad.id,
        title: 'Orphan',
        deadline: DateTime(2026, 2, 1),
        createdAt: clock(),
      );
      await a.projectRepo.save(ProjectRecords(targets: [orphan]));

      final report = await a.sync();
      expect({for (final i in report.issues) i.id}, {bad.id, orphan.id});
      expect(
        report.issues.firstWhere((i) => i.id == orphan.id).message,
        startsWith(ApiException.parentNotFound),
      );
      expect(server.projectRecords(ProjectResource.projects).keys, [
        good.project.id,
      ]);
      expect(server.projectRecords(ProjectResource.targets).keys, [
        good.target.id,
      ]);
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
          ProjectResource.targets,
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
        expect(b.projects.data.actions, isEmpty);
        // Kept locally as tombstones (sync), hidden from the UI.
        expect(b.projectRepo.getProjectRecord(s.project.id)!.isDeleted, isTrue);
        expect(
          {
            for (final e in b.remoteProjectEvents)
              if (e.type == ProjectChangeType.deleted) e.kind,
          },
          {
            ProjectEntityKind.project,
            ProjectEntityKind.target,
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
      await b.projects.setSessionAttended(s.action.id, today, false);
      await b.sync();
      await a.sync();
      expect(a.projects.data.isAttended(s.action.id, today), isFalse);
      expect(
        a.remoteProjectEvents.where(
          (e) => e.kind == ProjectEntityKind.sessionMark,
        ),
        hasLength(1),
      );
    });

    test('overlapping actions merged from two devices are tolerated', () async {
      final a = device('A');
      final s = await seed(a, attend: false);
      await a.sync();
      final b = device('B');
      await b.sync();
      // Both offline-create a clashing block on the same target.
      clock.advance();
      await a.projects.createAction(
        targetId: s.target.id,
        startTime: const ClockTime(8, 0),
        endTime: const ClockTime(9, 0),
        recurrence: WeeklyRecurrence({1}),
      );
      await b.projects.createAction(
        targetId: s.target.id,
        startTime: const ClockTime(8, 30),
        endTime: const ClockTime(9, 30),
        recurrence: WeeklyRecurrence({1}),
      );
      await a.sync();
      final report = await b.sync();
      expect(report.issues, isEmpty);
      expect(b.projects.data.actions, hasLength(3));
    });
  });

  group('cursor', () {
    test('a re-sync pulls nothing new; cursors are per resource', () async {
      final a = device('A');
      await seed(a);
      await a.sync();
      final b = device('B');
      expect((await b.sync()).pulledProjectRecords, 5);
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
        await other.projects.setTargetStatus(s.target.id, TargetStatus.done);
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
            GameRules.planTaskXp + GameRules.targetDoneXp + GameRules.sessionXp;
        expect(b.xp, expected);
        expect(b.game.state.projectLedger.keys, {
          GameState.planTaskKey(s.task.id),
          GameState.targetKey(s.target.id),
          GameState.sessionKey(s.action.id, today),
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
          SyncEntityType.target,
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
