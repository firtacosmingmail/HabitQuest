import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/consistent_action.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/target.dart';
import 'package:habit_quest/features/projects/projects_providers.dart';
import 'package:habit_quest/features/projects/ui/action_form_sheet.dart';
import 'package:habit_quest/features/projects/ui/project_details_screen.dart';
import 'package:habit_quest/features/projects/ui/projects_screen.dart';
import 'package:habit_quest/features/projects/ui/target_editor_screen.dart';

import '../../helpers/test_app.dart';
import 'helpers.dart';

/// Wednesday 18 Nov 2026, 09:00.
DateTime clock() => DateTime(2026, 11, 18, 9);

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// p1 "Content business": t1 "5 videos" (due 30 Nov, in progress, plan 1/2
/// done, a1 Mon–Fri 10:00–13:00) and t3 "Old cut" (done, a3 Mon–Fri
/// 10:00–11:00, which would clash with a1 if reopened).
/// p2 "Side gig" (archived): t2 "Side target" (due 31 Dec, a2 Mon–Fri
/// 09:00–10:00).
InMemoryProjectRepository seededRepo() => InMemoryProjectRepository(
  seed: ProjectRecords(
    projects: [
      project('p1', name: 'Content business'),
      project('p2', name: 'Side gig', archived: true),
    ],
    targets: [
      target(
        't1',
        title: '5 videos',
        deadline: DateTime(2026, 11, 30),
        status: TargetStatus.inProgress,
      ),
      target(
        't3',
        title: 'Old cut',
        deadline: DateTime(2026, 11, 30),
        status: TargetStatus.done,
      ),
      target(
        't2',
        projectId: 'p2',
        title: 'Side target',
        deadline: DateTime(2026, 12, 31),
      ),
    ],
    planTasks: [
      PlanTask(
        id: 'k1',
        targetId: 't1',
        title: '5 scripts',
        done: true,
        createdAt: createdOn(2026, 11, 1),
      ),
      PlanTask(
        id: 'k2',
        targetId: 't1',
        title: '5 recordings',
        position: 1,
        createdAt: createdOn(2026, 11, 1),
      ),
    ],
    actions: [
      weekly(
        'a1',
        targetId: 't1',
        days: monFri,
        created: createdOn(2026, 11, 1),
      ),
      weekly(
        'a3',
        targetId: 't3',
        days: monFri,
        end: '11:00',
        created: createdOn(2026, 11, 1),
      ),
      weekly(
        'a2',
        targetId: 't2',
        days: monFri,
        start: '09:00',
        end: '10:00',
        created: createdOn(2026, 11, 1),
      ),
    ],
  ),
);

void main() {
  late InMemoryProjectRepository repo;

  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    String initialLocation = '/projects',
  }) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = seededRepo();
    return pumpHabitQuestApp(
      tester,
      projectRepository: repo,
      clock: clock,
      initialLocation: initialLocation,
    );
  }

  group('projects list', () {
    testWidgets('the Projects tab lists active and archived projects with '
        'their targets\' progress', (tester) async {
      await pumpHabitQuestApp(tester, clock: clock);
      await tester.tap(
        find.descendant(
          of: find.byType(NavigationBar),
          matching: find.text('Projects'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ProjectsScreen), findsOneWidget);
      expect(key('empty-create-project'), findsOneWidget);
    });

    testWidgets('shows targets, status and plan progress; archived section', (
      tester,
    ) async {
      await pumpApp(tester);
      expect(key('project-card-p1'), findsOneWidget);
      expect(find.text('5 videos'), findsOneWidget);
      expect(find.text('In progress'), findsOneWidget);
      expect(find.text('1/2 tasks'), findsOneWidget);
      expect(find.text('1 of 2 targets done'), findsOneWidget);
      expect(find.text('Archived'), findsOneWidget);
      expect(key('project-card-p2'), findsOneWidget);
      expect(find.text('Side gig'), findsOneWidget);
    });

    testWidgets('create, rename, archive and delete a project', (tester) async {
      await pumpApp(tester);
      final service = ProviderScope.containerOf(
        tester.element(find.byType(ProjectsScreen)),
      ).read(projectServiceProvider);

      // Create.
      await tester.tap(key('new-project-fab'));
      await tester.pumpAndSettle();
      await tester.enterText(key('text-dialog-field'), '  Garden  ');
      await tester.tap(key('text-dialog-ok'));
      await tester.pumpAndSettle();
      final garden = service.data.projects.singleWhere(
        (p) => p.name == 'Garden',
      );
      expect(key('project-card-${garden.id}'), findsOneWidget);

      // Rename.
      await tapVisible(tester, key('project-menu-${garden.id}'));
      await tester.tap(key('project-rename'));
      await tester.pumpAndSettle();
      await tester.enterText(key('text-dialog-field'), 'Veggie garden');
      await tester.tap(key('text-dialog-ok'));
      await tester.pumpAndSettle();
      expect(find.text('Veggie garden'), findsOneWidget);
      expect(service.data.project(garden.id)!.name, 'Veggie garden');

      // Archive.
      await tapVisible(tester, key('project-menu-${garden.id}'));
      await tester.tap(key('project-archive'));
      await tester.pumpAndSettle();
      expect(service.data.project(garden.id)!.archived, isTrue);

      // Delete (confirmed).
      await tapVisible(tester, key('project-menu-${garden.id}'));
      await tester.tap(key('project-delete'));
      await tester.pumpAndSettle();
      await tester.tap(key('confirm-dialog-ok'));
      await tester.pumpAndSettle();
      expect(service.data.project(garden.id), isNull);
      expect(find.text('Veggie garden'), findsNothing);
    });

    testWidgets('tapping a project opens its details', (tester) async {
      await pumpApp(tester);
      await tester.tap(find.text('Content business'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<ProjectDetailsScreen>(find.byType(ProjectDetailsScreen))
            .projectId,
        'p1',
      );
      expect(find.byType(NavigationBar), findsNothing);
    });
  });

  group('project details', () {
    testWidgets('targets with deadline, status chip, progress, placeholder', (
      tester,
    ) async {
      await pumpApp(tester, initialLocation: '/projects/p1');
      expect(key('target-tile-t1'), findsOneWidget);
      expect(find.textContaining('Due in 12 days'), findsOneWidget);
      expect(key('status-chip-t1'), findsOneWidget);
      expect(find.text('1/2 tasks'), findsOneWidget);
      expect(key('work-split-placeholder'), findsOneWidget);
    });

    testWidgets('the status chip sets the status manually', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      await tester.tap(key('status-chip-t1'));
      await tester.pumpAndSettle();
      await tester.tap(key('status-option-done').last);
      await tester.pumpAndSettle();
      expect(
        c.read(projectServiceProvider).data.target('t1')!.status,
        TargetStatus.done,
      );
    });

    testWidgets('reopening a done target that would clash is refused', (
      tester,
    ) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      await tester.tap(key('status-chip-t3'));
      await tester.pumpAndSettle();
      await tester.tap(key('status-option-inProgress').last);
      await tester.pumpAndSettle();
      expect(key('overlap-dialog'), findsOneWidget);
      expect(find.textContaining('"5 videos"'), findsOneWidget);
      expect(
        c.read(projectServiceProvider).data.target('t3')!.status,
        TargetStatus.done,
      );
    });

    testWidgets('marks today\'s and past sessions attended, not future ones', (
      tester,
    ) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      final service = c.read(projectServiceProvider);

      // Today (Wed 18 Nov) and yesterday can be marked.
      final today = key('attend-a1|2026-11-18');
      expect(today, findsOneWidget);
      await tapVisible(tester, today);
      expect(service.isAttended('a1', DateTime(2026, 11, 18)), isTrue);

      await tapVisible(tester, key('attend-a1|2026-11-17'));
      expect(service.isAttended('a1', DateTime(2026, 11, 17)), isTrue);

      // Tapping again un-marks.
      await tapVisible(tester, today);
      expect(service.isAttended('a1', DateTime(2026, 11, 18)), isFalse);

      // Tomorrow is upcoming: no attend button.
      expect(key('attend-a1|2026-11-19'), findsNothing);
      expect(key('upcoming-a1|2026-11-19'), findsOneWidget);
      // Done target t3: past sessions listed, no upcoming ones.
      expect(key('upcoming-a3|2026-11-19'), findsNothing);
    });

    testWidgets('unknown project shows not found', (tester) async {
      await pumpApp(tester, initialLocation: '/projects/nope');
      expect(key('project-not-found'), findsOneWidget);
    });
  });

  group('target editor', () {
    testWidgets('creates a target, then edits plan and status', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      final service = c.read(projectServiceProvider);
      await tester.tap(key('new-target-fab'));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TargetEditorScreen>(find.byType(TargetEditorScreen))
            .targetId,
        isNull,
      );

      await tester.enterText(key('target-title'), 'Launch shop');
      await tester.tap(key('status-inProgress'));
      await tester.pumpAndSettle();
      await tester.tap(key('save-target'));
      await tester.pumpAndSettle();

      final t = service.data
          .targetsOf('p1')
          .singleWhere((t) => t.title == 'Launch shop');
      expect(t.status, TargetStatus.inProgress);
      expect(t.deadline, DateTime(2026, 12, 18)); // default: today + 30
      final editor = tester.widget<TargetEditorScreen>(
        find.byType(TargetEditorScreen),
      );
      expect(editor.targetId, t.id);

      // Plan: add a task, check it off, remove it.
      await tapVisible(tester, key('add-plan-task'));
      await tester.enterText(key('plan-task-title'), 'Product photos');
      await tester.tap(key('plan-task-save'));
      await tester.pumpAndSettle();
      final task = service.data.planTasksOf(t.id).single;
      expect(task.title, 'Product photos');
      expect(find.text('0/1 tasks'), findsOneWidget);

      await tapVisible(tester, key('plan-task-done-${task.id}'));
      expect(service.data.planTask(task.id)!.done, isTrue);
      expect(find.text('1/1 tasks'), findsOneWidget);
      // Status is never changed automatically.
      expect(service.data.target(t.id)!.status, TargetStatus.inProgress);

      // Edit the task title.
      await tapVisible(tester, find.text('Product photos'));
      await tester.enterText(key('plan-task-title'), 'Photos');
      await tester.tap(key('plan-task-save'));
      await tester.pumpAndSettle();
      expect(service.data.planTask(task.id)!.title, 'Photos');

      await tapVisible(tester, key('plan-task-delete-${task.id}'));
      expect(service.data.planTasksOf(t.id), isEmpty);

      // Edit title + status.
      await tester.enterText(key('target-title'), 'Launch the shop');
      await tester.tap(key('status-done'));
      await tester.pumpAndSettle();
      await tapVisible(tester, key('save-target'));
      final saved = service.data.target(t.id)!;
      expect(saved.title, 'Launch the shop');
      expect(saved.status, TargetStatus.done);
    });

    testWidgets('a refused target edit shows the clash and saves nothing', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        initialLocation: '/projects/p1/targets/t3',
      );
      await tester.tap(key('status-notStarted'));
      await tester.pumpAndSettle();
      await tapVisible(tester, key('save-target'));
      expect(key('target-save-error'), findsOneWidget);
      expect(
        find.textContaining('"5 videos" (Content business)'),
        findsOneWidget,
      );
      expect(
        c.read(projectServiceProvider).data.target('t3')!.status,
        TargetStatus.done,
      );
    });
  });

  group('consistent actions', () {
    testWidgets('a clashing time block is BLOCKED with the clash named', (
      tester,
    ) async {
      final c = await pumpApp(
        tester,
        initialLocation: '/projects/p1/targets/t1',
      );
      final service = c.read(projectServiceProvider);
      await tapVisible(tester, key('add-action'));
      expect(find.byType(ActionFormSheet), findsOneWidget);

      // Default 09:00–10:00 Mon–Fri clashes with the archived project's a2.
      expect(key('live-clashes'), findsOneWidget);
      expect(find.textContaining('“Side target” (Side gig)'), findsOneWidget);

      await tapVisible(tester, key('save-action'));
      // Still open, message names the target and times; nothing saved.
      expect(find.byType(ActionFormSheet), findsOneWidget);
      expect(key('action-save-error'), findsOneWidget);
      expect(
        find.textContaining('"Side target" (Side gig), Mon–Fri 09:00–10:00'),
        findsOneWidget,
      );
      expect(service.data.actionsOf('t1').map((a) => a.id), ['a1']);

      // Saturdays only: no clash, saves and closes.
      for (var d = 1; d <= 5; d++) {
        await tapVisible(tester, key('action-weekday-$d'));
      }
      await tapVisible(tester, key('action-weekday-6'));
      expect(key('live-clashes'), findsNothing);
      await tapVisible(tester, key('save-action'));
      expect(find.byType(ActionFormSheet), findsNothing);
      final added = service.data
          .actionsOf('t1')
          .singleWhere((a) => a.id != 'a1');
      expect(added.recurrence, WeeklyRecurrence({6}));
      expect(added.startTime, defaultActionStart);
      expect(key('action-tile-${added.id}'), findsOneWidget);
    });

    testWidgets('days of the month and no days', (tester) async {
      final c = await pumpApp(
        tester,
        initialLocation: '/projects/p1/targets/t1',
      );
      await tapVisible(tester, key('add-action'));
      await tapVisible(tester, find.byKey(const ValueKey('mode-monthly')));
      // Default {1}: 1 Dec 2026 is after the deadline and 1 Nov is before
      // today, so no session at all → no clash. Pick the 28th too.
      await tapVisible(tester, key('action-monthday-28'));
      await tapVisible(tester, key('action-monthday-1'));
      await tapVisible(tester, key('save-action'));
      final added = c
          .read(projectServiceProvider)
          .data
          .actionsOf('t1')
          .singleWhere((a) => a.id != 'a1');
      expect(added.recurrence, MonthlyRecurrence({28}));
    });

    testWidgets('list → details → new target → back shows it everywhere', (
      tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(find.text('Content business'));
      await tester.pumpAndSettle();
      await tester.tap(key('new-target-fab'));
      await tester.pumpAndSettle();
      await tester.enterText(key('target-title'), 'Podcast');
      await tester.tap(key('save-target'));
      await tester.pumpAndSettle();
      await tapVisible(tester, key('add-plan-task'));
      await tester.enterText(key('plan-task-title'), 'Mic');
      await tester.tap(key('plan-task-save'));
      await tester.pumpAndSettle();

      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ProjectDetailsScreen), findsOneWidget);
      expect(find.text('Podcast'), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(ProjectsScreen), findsOneWidget);
      expect(find.text('Podcast'), findsOneWidget);
      expect(find.text('0/1 tasks'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('routes resolve', (tester) async {
      final c = await pumpApp(tester);
      c.read(routerProvider).push('/projects/p1/targets/new');
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TargetEditorScreen>(find.byType(TargetEditorScreen))
            .projectId,
        'p1',
      );
    });
  });
}
