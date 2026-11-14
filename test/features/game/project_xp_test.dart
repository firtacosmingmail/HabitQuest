import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/game/achievements.dart';
import 'package:habit_quest/features/game/game_engine.dart';
import 'package:habit_quest/features/game/game_events.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_rules.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/domain/project_service.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/session_mark.dart';
import 'package:habit_quest/features/projects/models/target.dart';

import '../projects/helpers.dart';

DateTime d(int y, int m, int day) => DateTime(y, m, day);

/// Friday 13 Nov 2026, 10:00.
final clock = DateTime(2026, 11, 13, 10);

/// Mon–Fri.
const monFri = {1, 2, 3, 4, 5};

/// p1 → t1 (deadline 30 Nov) with plan tasks k1, k2 and a Mon–Fri action a1
/// starting 2 Nov (so sessions exist on past weekdays).
ProjectRecords seed({TargetStatus t1Status = TargetStatus.notStarted}) =>
    ProjectRecords(
      projects: [project('p1')],
      targets: [target('t1', deadline: d(2026, 11, 30), status: t1Status)],
      planTasks: [task('k1', 0), task('k2', 1)],
      actions: [weekly('a1', days: monFri, startDate: d(2026, 11, 2))],
    );

PlanTask task(String id, int position, {bool done = false}) => PlanTask(
  id: id,
  targetId: 't1',
  title: 'Task $id',
  done: done,
  position: position,
  createdAt: createdOn(2026, 11, 1),
);

class Harness {
  final InMemoryProjectRepository projectRepo;
  final ProjectService projects;
  final GameEngine engine;
  final List<GameEvent> events = [];

  Harness._(this.projectRepo, this.projects, this.engine) {
    engine.events.listen(events.add);
  }

  factory Harness({
    ProjectRecords records = const ProjectRecords(),
    GameState initial = GameState.empty,
  }) {
    final projectRepo = InMemoryProjectRepository(seed: records);
    var ids = 0;
    final projects = ProjectService(
      projectRepo,
      now: () => clock,
      idGenerator: () => 'new${++ids}',
    );
    final service = HabitService(InMemoryHabitRepository(), now: () => clock);
    final engine = GameEngine(
      service: service,
      repository: InMemoryGameRepository(initial),
      projects: projects,
      now: () => clock,
    )..start();
    addTearDown(() async {
      await engine.dispose();
      await projects.dispose();
    });
    return Harness._(projectRepo, projects, engine);
  }

  int get xp => engine.state.xp;

  Future<void> run(Future<void> Function(ProjectService s) op) async {
    await op(projects);
    await pumpEventQueue();
  }

  List<T> eventsOf<T extends GameEvent>() => events.whereType<T>().toList();

  bool unlocked(String id) => engine.state.unlocked.containsKey(id);
}

void main() {
  group('rules', () {
    test('amounts', () {
      expect(GameRules.planTaskXp, 10);
      expect(GameRules.sessionXp, 15);
      expect(GameRules.targetDoneXp, 50);
    });

    test('keys and the session key parser', () {
      expect(GameState.planTaskKey('k1'), 'task:k1');
      expect(GameState.targetKey('t1'), 'target:t1');
      final key = GameState.sessionKey('a|1', d(2026, 11, 3));
      expect(key, 'session:a|1|2026-11-03');
      expect(GameState.parseSessionKey(key), ('a|1', d(2026, 11, 3)));
      expect(GameState.parseSessionKey('task:k1'), isNull);
      expect(GameState.parseSessionKey('session:nodate'), isNull);
    });

    test('the projects ledger counts in XP, JSON and merge', () {
      final a = GameState(
        checkInLedger: const {'h|2026-11-01': 11},
        projectLedger: const {'task:k1': 10, 'target:t1': 50},
      );
      expect(a.xp, 71);
      expect(a.projectXp, 60);
      expect(a.planTasksDone, 1);
      expect(a.targetsDone, 1);
      expect(GameState.fromJson(a.toJson()), a);
      expect(a.toJson()['projects'], {'task:k1': 10, 'target:t1': 50});
      // Older states have no `projects` key.
      expect(GameState.fromJson(const {'checkIns': {}}).projectLedger, isEmpty);
      final b = GameState(
        projectLedger: const {'task:k1': 10, 'session:a1|2026-11-03': 15},
      );
      final m = GameState.merge(a, b);
      expect(m.projectLedger, {
        'task:k1': 10,
        'target:t1': 50,
        'session:a1|2026-11-03': 15,
      });
      expect(m.xp, 11 + 10 + 50 + 15);
    });
  });

  group('plan tasks', () {
    test(
      'finishing a task grants 10 XP once; un-checking takes it back',
      () async {
        final h = Harness(records: seed());
        await h.run((s) => s.setPlanTaskDone('k1', true));
        expect(h.xp, 10);
        final gained = h.eventsOf<XpGained>().single;
        expect(gained.amount, 10);
        expect(gained.reason, XpReason.planTask);
        expect(gained.projectId, 'p1');

        await h.run((s) => s.setPlanTaskDone('k1', false));
        expect(h.xp, 0);
        expect(h.eventsOf<XpLost>().single.amount, 10);
      },
    );

    test('toggling on and off any number of times nets 0', () async {
      final h = Harness(records: seed());
      for (var i = 0; i < 5; i++) {
        await h.run((s) => s.setPlanTaskDone('k1', true));
        await h.run((s) => s.setPlanTaskDone('k1', false));
      }
      expect(h.xp, 0);
      await h.run((s) => s.setPlanTaskDone('k1', true));
      expect(h.xp, 10);
    });

    test('renaming or reordering a done task changes nothing', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setPlanTaskDone('k1', true));
      await h.run((s) => s.reorderPlanTasks('t1', ['k2', 'k1']));
      await h.run(
        (s) => s.updatePlanTask(s.data.planTask('k1')!.copyWith(title: 'x')),
      );
      expect(h.xp, 10);
      expect(h.eventsOf<XpGained>(), hasLength(1));
    });

    test('deleting a done task removes its XP', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setPlanTaskDone('k1', true));
      await h.run((s) => s.deletePlanTask('k1'));
      expect(h.xp, 0);
      expect(h.eventsOf<XpLost>().single.reason, XpReason.projectItemDeleted);
    });
  });

  group('sessions', () {
    test('attending grants 15 XP; un-attending takes it back', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 12), true));
      expect(h.xp, 15);
      final gained = h.eventsOf<XpGained>().single;
      expect(gained.reason, XpReason.session);
      expect(gained.date, d(2026, 11, 12));
      expect(gained.projectId, 'p1');

      await h.run((s) => s.toggleSessionAttended('a1', d(2026, 11, 12)));
      expect(h.xp, 0);
      await h.run((s) => s.toggleSessionAttended('a1', d(2026, 11, 12)));
      await h.run((s) => s.toggleSessionAttended('a1', d(2026, 11, 12)));
      expect(h.xp, 0);
    });

    test('each session day earns separately', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 12), true));
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 13), true));
      expect(h.xp, 30);
      expect(h.engine.state.sessionsAttended, 2);
    });

    test('deleting the action removes the XP of all its sessions', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 11), true));
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 12), true));
      await h.run((s) => s.deleteAction('a1'));
      expect(h.xp, 0);
      expect(h.eventsOf<XpLost>().single.amount, 30);
    });
  });

  group('targets', () {
    test('done grants 50 XP; back from done takes it back', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.inProgress));
      expect(h.xp, 0);
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      expect(h.xp, 50);
      expect(h.eventsOf<XpGained>().single.reason, XpReason.target);

      await h.run((s) => s.setTargetStatus('t1', TargetStatus.inProgress));
      expect(h.xp, 0);
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.notStarted));
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      expect(h.xp, 50);
    });

    test('a target created as done earns too', () async {
      final h = Harness(records: ProjectRecords(projects: [project('p1')]));
      await h.run(
        (s) => s.createTarget(
          projectId: 'p1',
          title: 'Ship',
          deadline: d(2026, 12, 1),
          status: TargetStatus.done,
        ),
      );
      expect(h.xp, 50);
    });

    test('deleting the project removes every project XP it held', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setPlanTaskDone('k1', true));
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 12), true));
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      expect(h.xp, 75);
      await h.run((s) => s.deleteProject('p1'));
      expect(h.xp, 0);
      expect(h.engine.state.projectLedger, isEmpty);
    });

    test('archiving a project keeps its XP', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      await h.run((s) => s.archiveProject('p1'));
      expect(h.xp, 50);
    });
  });

  group('achievements', () {
    test('first task, first target and a completed project', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setPlanTaskDone('k1', true));
      expect(h.unlocked(AchievementIds.firstPlanTask), isTrue);
      expect(h.unlocked(AchievementIds.firstTargetDone), isFalse);

      // A second, unfinished target: the project is not complete yet.
      await h.run(
        (s) => s.createTarget(
          projectId: 'p1',
          title: 'Second',
          deadline: d(2026, 12, 20),
        ),
      );
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      expect(h.unlocked(AchievementIds.firstTargetDone), isTrue);
      expect(h.unlocked(AchievementIds.projectComplete), isFalse);

      await h.run((s) => s.setTargetStatus('new1', TargetStatus.done));
      expect(h.unlocked(AchievementIds.projectComplete), isTrue);
      final names = h
          .eventsOf<AchievementUnlocked>()
          .map((e) => e.achievement.id)
          .toList();
      expect(names, [
        AchievementIds.firstPlanTask,
        AchievementIds.firstTargetDone,
        AchievementIds.projectComplete,
      ]);
    });

    test('achievements stay unlocked after undo and fire only once', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.inProgress));
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      expect(h.unlocked(AchievementIds.firstTargetDone), isTrue);
      expect(
        h.eventsOf<AchievementUnlocked>().where(
          (e) => e.achievement.id == AchievementIds.firstTargetDone,
        ),
        hasLength(1),
      );
    });

    test('5 targets done unlocks Sharpshooter', () async {
      final h = Harness(
        records: ProjectRecords(
          projects: [project('p1')],
          targets: [
            for (var i = 1; i <= 5; i++)
              target('t$i', deadline: d(2026, 12, i)),
          ],
        ),
      );
      for (var i = 1; i <= 4; i++) {
        await h.run((s) => s.setTargetStatus('t$i', TargetStatus.done));
      }
      expect(h.unlocked(AchievementIds.targets5), isFalse);
      await h.run((s) => s.setTargetStatus('t5', TargetStatus.done));
      expect(h.unlocked(AchievementIds.targets5), isTrue);
      expect(h.xp, 250);
    });

    test('10 sessions attended unlocks In the Zone', () async {
      final h = Harness(records: seed());
      // Weekdays 2–13 Nov: 10 sessions.
      final days = [
        for (var day = 2; day <= 13; day++)
          if (d(2026, 11, day).weekday <= 5) d(2026, 11, day),
      ];
      expect(days, hasLength(10));
      for (final day in days.take(9)) {
        await h.run((s) => s.setSessionAttended('a1', day, true));
      }
      expect(h.unlocked(AchievementIds.sessions10), isFalse);
      await h.run((s) => s.setSessionAttended('a1', days.last, true));
      expect(h.unlocked(AchievementIds.sessions10), isTrue);
      expect(h.xp, 150);
    });

    test('a level-up can come from project XP', () async {
      final h = Harness(
        records: seed(),
        initial: const GameState(checkInLedger: {'h|2026-11-01': 95}),
      );
      await h.run((s) => s.setPlanTaskDone('k1', true));
      expect(h.eventsOf<LevelUp>().single.newLevel, 2);
    });
  });

  group('sync reconciliation', () {
    test('a pulled done task / target / attended session gets its base XP '
        'silently, once', () async {
      final h = Harness(records: seed());
      final pulled = ProjectRecords(
        targets: [
          target('t1', deadline: d(2026, 11, 30), status: TargetStatus.done),
        ],
        planTasks: [task('k1', 0, done: true)],
        sessionMarks: [
          SessionMark(
            actionId: 'a1',
            date: d(2026, 11, 12),
            attended: true,
            updatedAt: clock,
          ),
        ],
      );
      await h.projects.applyRemote(pulled);
      await h.engine.reconcileSynced(appliedProjects: pulled);
      await pumpEventQueue();
      expect(h.xp, 75);
      expect(h.events, isEmpty);
      expect(h.unlocked(AchievementIds.firstTargetDone), isTrue);

      // Pulled again (cursor overlap) or merged with the same server state:
      // still counted once.
      await h.engine.reconcileSynced(
        remote: h.engine.state,
        appliedProjects: pulled,
      );
      expect(h.xp, 75);
    });

    test('a task already granted on another device is not doubled', () async {
      final h = Harness(records: seed());
      final pulled = ProjectRecords(planTasks: [task('k1', 0, done: true)]);
      await h.projects.applyRemote(pulled);
      await h.engine.reconcileSynced(
        remote: const GameState(projectLedger: {'task:k1': 10}),
        appliedProjects: pulled,
      );
      expect(h.xp, 10);
    });

    test('undone or deleted on another device: the grant is dropped', () async {
      final h = Harness(records: seed());
      await h.run((s) => s.setPlanTaskDone('k1', true));
      await h.run((s) => s.setTargetStatus('t1', TargetStatus.done));
      await h.run((s) => s.setSessionAttended('a1', d(2026, 11, 12), true));
      expect(h.xp, 75);

      final later = clock.add(const Duration(hours: 1));
      await h.projects.applyRemote(
        ProjectRecords(
          planTasks: [task('k1', 0).copyWith(updatedAt: later)],
          targets: [
            target(
              't1',
              deadline: d(2026, 11, 30),
              status: TargetStatus.inProgress,
            ).copyWith(updatedAt: later),
          ],
          sessionMarks: [
            SessionMark(
              actionId: 'a1',
              date: d(2026, 11, 12),
              attended: false,
              updatedAt: later,
            ),
          ],
        ),
      );
      // The other device's (older) game state still lists the grants.
      await h.engine.reconcileSynced(
        remote: const GameState(
          projectLedger: {
            'task:k1': 10,
            'target:t1': 50,
            'session:a1|2026-11-12': 15,
          },
        ),
      );
      expect(h.xp, 0);
      expect(h.events.whereType<XpLost>(), isEmpty);
    });

    test(
      'grants for records this device has not pulled yet are kept',
      () async {
        final h = Harness();
        await h.engine.reconcileSynced(
          remote: const GameState(
            projectLedger: {
              'task:other': 10,
              'target:other': 50,
              'session:otherAction|2026-11-12': 15,
            },
          ),
        );
        expect(h.xp, 75);
      },
    );
  });
}
