import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/router/app_routes.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';
import 'package:habit_quest/features/projects/projects_providers.dart';
import 'package:habit_quest/features/projects/ui/goal_editor_screen.dart';
import 'package:habit_quest/features/projects/ui/project_details_screen.dart';
import 'package:habit_quest/features/projects/ui/projects_screen.dart';
import 'package:habit_quest/features/projects/ui/time_block_form_sheet.dart';

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

/// p1 "Content business": time block a1 "Filming" Mon–Fri 10:00–13:00
/// (open-ended); goals t1 "5 videos" (due 30 Nov, in progress, plan 1/2
/// done) and t3 "Old cut" (done).
/// p2 "Side gig" (archived): time block a2 "Admin" Mon–Fri 09:00–10:00;
/// goal t2 "Side target" (due 31 Dec).
InMemoryProjectRepository seededRepo() => InMemoryProjectRepository(
  seed: ProjectRecords(
    projects: [
      project('p1', name: 'Content business'),
      project('p2', name: 'Side gig', archived: true),
    ],
    goals: [
      goal(
        't1',
        title: '5 videos',
        deadline: DateTime(2026, 11, 30),
        status: GoalStatus.inProgress,
      ),
      goal(
        't3',
        title: 'Old cut',
        deadline: DateTime(2026, 11, 30),
        status: GoalStatus.done,
      ),
      goal(
        't2',
        projectId: 'p2',
        title: 'Side target',
        deadline: DateTime(2026, 12, 31),
      ),
    ],
    planTasks: [
      PlanTask(
        id: 'k1',
        goalId: 't1',
        title: '5 scripts',
        done: true,
        createdAt: createdOn(2026, 11, 1),
      ),
      PlanTask(
        id: 'k2',
        goalId: 't1',
        title: '5 recordings',
        position: 1,
        createdAt: createdOn(2026, 11, 1),
      ),
    ],
    timeBlocks: [
      weekly(
        'a1',
        label: 'Filming',
        days: monFri,
        created: createdOn(2026, 11, 1),
      ),
      weekly(
        'a2',
        projectId: 'p2',
        label: 'Admin',
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

    testWidgets('shows goals, status and plan progress; archived section', (
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
    testWidgets('goals with deadline, status chip, progress; time blocks', (
      tester,
    ) async {
      await pumpApp(tester, initialLocation: '/projects/p1');
      expect(key('target-tile-t1'), findsOneWidget);
      expect(find.textContaining('Due in 12 days'), findsOneWidget);
      expect(key('status-chip-t1'), findsOneWidget);
      expect(find.text('1/2 tasks'), findsOneWidget);
      expect(key('action-tile-a1'), findsOneWidget);
      expect(find.textContaining('Filming · '), findsOneWidget);
      expect(find.textContaining('Ongoing'), findsOneWidget);
      // Only this project's blocks.
      expect(key('action-tile-a2'), findsNothing);
      expect(key('work-split-view'), findsOneWidget);
    });

    testWidgets('the status chip sets the status manually', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      await tester.tap(key('status-chip-t1'));
      await tester.pumpAndSettle();
      await tester.tap(key('status-option-done').last);
      await tester.pumpAndSettle();
      expect(
        c.read(projectServiceProvider).data.goal('t1')!.status,
        GoalStatus.done,
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
      // Goals do not cut off the project's block: sessions continue past
      // every goal deadline (30 Nov).
      expect(service.data.timeBlocksOf('p1').single.isOpenEnded, isTrue);
    });

    testWidgets('unknown project shows not found', (tester) async {
      await pumpApp(tester, initialLocation: '/projects/nope');
      expect(key('project-not-found'), findsOneWidget);
    });
  });

  group('goal editor', () {
    testWidgets('creates a goal, then edits plan and status', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      final service = c.read(projectServiceProvider);
      await tester.tap(key('new-target-fab'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<GoalEditorScreen>(find.byType(GoalEditorScreen)).goalId,
        isNull,
      );

      await tester.enterText(key('target-title'), 'Launch shop');
      await tester.tap(key('status-inProgress'));
      await tester.pumpAndSettle();
      await tester.tap(key('save-target'));
      await tester.pumpAndSettle();

      final t = service.data
          .goalsOf('p1')
          .singleWhere((t) => t.title == 'Launch shop');
      expect(t.status, GoalStatus.inProgress);
      expect(t.deadline, DateTime(2026, 12, 18)); // default: today + 30
      final editor = tester.widget<GoalEditorScreen>(
        find.byType(GoalEditorScreen),
      );
      expect(editor.goalId, t.id);

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
      expect(service.data.goal(t.id)!.status, GoalStatus.inProgress);

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
      final saved = service.data.goal(t.id)!;
      expect(saved.title, 'Launch the shop');
      expect(saved.status, GoalStatus.done);
    });

    testWidgets('consistent actions: add, edit and remove text items', (
      tester,
    ) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1/goals/t1');
      final service = c.read(projectServiceProvider);
      expect(find.text('Consistent actions'), findsOneWidget);

      await tapVisible(tester, key('add-consistent-action'));
      await tester.enterText(
        key('consistent-action-text'),
        '  Post one short a day  ',
      );
      await tester.tap(key('consistent-action-save'));
      await tester.pumpAndSettle();
      final added = service.data.consistentActionsOf('t1').single;
      expect(added.text, 'Post one short a day');
      expect(key('consistent-action-${added.id}'), findsOneWidget);

      // A blank text is refused in the dialog.
      await tapVisible(tester, key('add-consistent-action'));
      await tester.tap(key('consistent-action-save'));
      await tester.pumpAndSettle();
      expect(find.text('Write something'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(service.data.consistentActionsOf('t1'), hasLength(1));

      // A second one goes to the end.
      await tapVisible(tester, key('add-consistent-action'));
      await tester.enterText(key('consistent-action-text'), 'Reply to fans');
      await tester.tap(key('consistent-action-save'));
      await tester.pumpAndSettle();
      expect(service.data.consistentActionsOf('t1').map((a) => a.text), [
        'Post one short a day',
        'Reply to fans',
      ]);

      // Tap to edit.
      await tapVisible(tester, find.text('Post one short a day'));
      await tester.enterText(key('consistent-action-text'), 'Post two shorts');
      await tester.tap(key('consistent-action-save'));
      await tester.pumpAndSettle();
      expect(service.data.consistentAction(added.id)!.text, 'Post two shorts');
      expect(find.text('Post two shorts'), findsOneWidget);

      await tapVisible(tester, key('consistent-action-delete-${added.id}'));
      expect(service.data.consistentActionsOf('t1').map((a) => a.text), [
        'Reply to fans',
      ]);
      expect(find.text('Post two shorts'), findsNothing);
    });
  });

  group('time blocks', () {
    testWidgets('adding a clashing time block on the project details screen '
        'is BLOCKED with the project and label named', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      final service = c.read(projectServiceProvider);
      await tapVisible(tester, key('add-action'));
      expect(find.byType(TimeBlockFormSheet), findsOneWidget);
      expect(find.text('For “Content business”.'), findsOneWidget);

      // Default 09:00–10:00 Mon–Fri clashes with the archived project's
      // "Admin" block (touching a1 at 10:00 is fine).
      expect(key('live-clashes'), findsOneWidget);
      expect(find.textContaining('“Side gig” (Admin)'), findsOneWidget);

      await tester.enterText(key('block-label'), 'Editing');
      await tapVisible(tester, key('save-action'));
      // Still open, message names the project, label and times; nothing
      // saved.
      expect(find.byType(TimeBlockFormSheet), findsOneWidget);
      expect(key('action-save-error'), findsOneWidget);
      expect(
        find.textContaining('"Side gig" (Admin), Mon–Fri 09:00–10:00'),
        findsOneWidget,
      );
      expect(service.data.timeBlocksOf('p1').map((b) => b.id), ['a1']);

      // Saturdays only: no clash, saves and closes.
      for (var d = 1; d <= 5; d++) {
        await tapVisible(tester, key('action-weekday-$d'));
      }
      await tapVisible(tester, key('action-weekday-6'));
      expect(key('live-clashes'), findsNothing);
      await tapVisible(tester, key('save-action'));
      expect(find.byType(TimeBlockFormSheet), findsNothing);
      final added = service.data
          .timeBlocksOf('p1')
          .singleWhere((b) => b.id != 'a1');
      expect(added.projectId, 'p1');
      expect(added.label, 'Editing');
      expect(added.recurrence, WeeklyRecurrence({6}));
      expect(added.startTime, defaultBlockStart);
      expect(added.endTime, defaultBlockEnd);
      expect(added.isOpenEnded, isTrue);
      expect(key('action-tile-${added.id}'), findsOneWidget);
      expect(find.textContaining('Editing · '), findsOneWidget);
    });

    testWidgets('a block touching another (10:00) does not clash; tapping a '
        'tile edits the block', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      // Free 09:00–10:00: the default 09:00–10:00 only touches a1.
      await c.read(projectServiceProvider).deleteTimeBlock('a2');
      await tester.pumpAndSettle();
      await tapVisible(tester, key('add-action'));
      expect(key('live-clashes'), findsNothing);
      // Editing an existing block opens the form with its values.
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();
      await tapVisible(tester, find.textContaining('Filming · '));
      expect(find.text('Edit time block'), findsOneWidget);
      expect(
        tester.widget<TextField>(key('block-label')).controller!.text,
        'Filming',
      );
    });

    testWidgets('days of the month, open-ended', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      final service = c.read(projectServiceProvider);
      await tapVisible(tester, key('add-action'));
      await tapVisible(tester, find.byKey(const ValueKey('mode-monthly')));
      // Default {1}: open-ended, so 1 Dec 2026 (a Tuesday) clashes with the
      // archived project's Mon–Fri 09:00–10:00 block.
      expect(key('live-clashes'), findsOneWidget);
      await tapVisible(tester, key('action-monthday-28'));
      await tapVisible(tester, key('action-monthday-1'));
      // The 28th also falls on a weekday eventually.
      expect(key('live-clashes'), findsOneWidget);
      await tester.tapAt(Offset.zero);
      await tester.pumpAndSettle();

      await service.deleteTimeBlock('a2');
      await tester.pumpAndSettle();
      await tapVisible(tester, key('add-action'));
      await tapVisible(tester, find.byKey(const ValueKey('mode-monthly')));
      await tapVisible(tester, key('action-monthday-28'));
      await tapVisible(tester, key('action-monthday-1'));
      expect(key('live-clashes'), findsNothing);
      await tapVisible(tester, key('save-action'));
      final added = service.data
          .timeBlocksOf('p1')
          .singleWhere((b) => b.id != 'a1');
      expect(added.recurrence, MonthlyRecurrence({28}));
      expect(added.endDate, isNull);
    });

    testWidgets('deleting a time block (confirmed) removes it', (tester) async {
      final c = await pumpApp(tester, initialLocation: '/projects/p1');
      await tapVisible(tester, key('action-delete-a1'));
      await tester.tap(key('confirm-dialog-ok'));
      await tester.pumpAndSettle();
      expect(c.read(projectServiceProvider).data.timeBlock('a1'), isNull);
      expect(key('action-tile-a1'), findsNothing);
      expect(key('attend-a1|2026-11-18'), findsNothing);
    });
  });

  group('navigation', () {
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
      c.read(routerProvider).push('/projects/p1/goals/new');
      await tester.pumpAndSettle();
      final created = tester.widget<GoalEditorScreen>(
        find.byType(GoalEditorScreen),
      );
      expect(created.projectId, 'p1');
      expect(created.goalId, isNull);

      c.read(routerProvider).push('/projects/p1/goals/t1');
      await tester.pumpAndSettle();
      final edited = tester.widget<GoalEditorScreen>(
        find.byType(GoalEditorScreen).last,
      );
      expect(edited.goalId, 't1');
      expect(find.text('5 videos'), findsWidgets);
      expect(AppRoutes.goalEditor('p1', 't1'), '/projects/p1/goals/t1');
      expect(AppRoutes.newGoal('p1'), '/projects/p1/goals/new');
    });
  });
}
