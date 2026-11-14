import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/calendar/calendar_screen.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/projects_providers.dart';
import 'package:habit_quest/features/projects/ui/target_editor_screen.dart';
import 'package:habit_quest/features/projects/ui/work_split_view.dart';

import '../../helpers/test_app.dart';
import '../projects/helpers.dart';

/// Wednesday 18 Nov 2026, 09:00 (week of Mon 16 – Sun 22 Nov).
DateTime clock() => DateTime(2026, 11, 18, 9);

Finder key(String k) => find.byKey(ValueKey(k));
Finder block(String actionId, String day) =>
    key('session-block-$actionId|$day');

/// p1 "Content": t1 "5 videos" (due Fri 27 Nov, a1 Mon–Fri 10:00–13:00),
/// t5 "Teaser" (due Fri 20 Nov, no blocks). Tasks: k1 due Wed 18 Nov
/// (open), k2 due Fri 20 Nov (done).
/// p2 "Fitness": t2 "Run 10k" (due 31 Dec, a2 Tue/Thu 18:00–19:00).
/// p3 "Old" (archived): t4 (a4 Mon 07:00–08:00, task k4 due 19 Nov).
InMemoryProjectRepository seededRepo() => InMemoryProjectRepository(
  seed: ProjectRecords(
    projects: [
      project('p1', name: 'Content'),
      project('p2', name: 'Fitness'),
      project('p3', name: 'Old', archived: true),
    ],
    targets: [
      target('t1', title: '5 videos', deadline: DateTime(2026, 11, 27)),
      target('t5', title: 'Teaser', deadline: DateTime(2026, 11, 20)),
      target(
        't2',
        projectId: 'p2',
        title: 'Run 10k',
        deadline: DateTime(2026, 12, 31),
      ),
      target(
        't4',
        projectId: 'p3',
        title: 'Archived goal',
        deadline: DateTime(2026, 12, 31),
      ),
    ],
    planTasks: [
      PlanTask(
        id: 'k1',
        targetId: 't1',
        title: 'Write script 1',
        deliveryDate: DateTime(2026, 11, 18),
        createdAt: createdOn(2026, 11, 1),
      ),
      PlanTask(
        id: 'k2',
        targetId: 't1',
        title: 'Record intro',
        deliveryDate: DateTime(2026, 11, 20),
        done: true,
        position: 1,
        createdAt: createdOn(2026, 11, 1),
      ),
      PlanTask(
        id: 'k4',
        targetId: 't4',
        title: 'Hidden task',
        deliveryDate: DateTime(2026, 11, 19),
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
        'a2',
        targetId: 't2',
        days: {2, 4},
        start: '18:00',
        end: '19:00',
        created: createdOn(2026, 11, 1),
      ),
      weekly(
        'a4',
        targetId: 't4',
        days: {1},
        start: '07:00',
        end: '08:00',
        created: createdOn(2026, 11, 1),
      ),
    ],
  ),
);

String weekTitle(WidgetTester tester) =>
    tester.widget<Text>(key('work-split-week-title')).data!;

void main() {
  late InMemoryProjectRepository repo;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String location = '/calendar',
    Size size = const Size(900, 2200),
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = seededRepo();
    return pumpHabitQuestApp(
      tester,
      projectRepository: repo,
      clock: clock,
      initialLocation: location,
    );
  }

  Future<void> openWorkSplit(WidgetTester tester) async {
    await tester.tap(key('calendar-mode-work-split'));
    await tester.pumpAndSettle();
  }

  Future<void> tapVisible(WidgetTester tester, Finder f) async {
    await tester.ensureVisible(f);
    await tester.pumpAndSettle();
    await tester.tap(f);
    await tester.pumpAndSettle();
  }

  group('Month | Work split toggle', () {
    testWidgets('Month is the default; the toggle switches views', (
      tester,
    ) async {
      await pump(tester);
      expect(find.byType(CalendarScreen), findsOneWidget);
      expect(key('calendar-month-title'), findsOneWidget);
      expect(find.byType(WorkSplitView), findsNothing);

      await openWorkSplit(tester);
      expect(find.byType(WorkSplitView), findsOneWidget);
      expect(key('calendar-month-title'), findsNothing);
      expect(weekTitle(tester), '16 – 22 Nov 2026');

      await tester.tap(key('calendar-mode-month'));
      await tester.pumpAndSettle();
      expect(key('calendar-month-title'), findsOneWidget);
      expect(find.byType(WorkSplitView), findsNothing);
    });
  });

  group('work split', () {
    testWidgets('renders a block per session at its time, per project', (
      tester,
    ) async {
      await pump(tester);
      await openWorkSplit(tester);

      for (final d in ['16', '17', '18', '19', '20']) {
        expect(block('a1', '2026-11-$d'), findsOneWidget, reason: d);
      }
      expect(block('a1', '2026-11-21'), findsNothing);
      expect(block('a2', '2026-11-17'), findsOneWidget);
      expect(block('a2', '2026-11-19'), findsOneWidget);
      expect(block('a2', '2026-11-18'), findsNothing);
      // Archived projects are hidden on the Calendar tab.
      expect(block('a4', '2026-11-16'), findsNothing);
      expect(find.text('5 videos'), findsWidgets);

      // 10:00–13:00 is 3 hour rows tall; 18:00 starts 8 rows below 10:00.
      final mon = tester.getRect(block('a1', '2026-11-17'));
      final tue = tester.getRect(block('a2', '2026-11-17'));
      expect(mon.height, closeTo(3 * workSplitHourHeight, 0.5));
      expect(tue.top - mon.top, closeTo(8 * workSplitHourHeight, 0.5));
      expect(tue.left, mon.left);
      // Wednesday is one column right of Tuesday.
      final wed = tester.getRect(block('a1', '2026-11-18'));
      expect(wed.left, greaterThan(mon.left));
    });

    testWidgets('arrows, swipe and Today change the week', (tester) async {
      await pump(tester);
      await openWorkSplit(tester);
      final today = tester.widget<TextButton>(key('work-split-today'));
      expect(today.onPressed, isNull);

      await tester.tap(key('work-split-next-week'));
      await tester.pumpAndSettle();
      expect(weekTitle(tester), '23 – 29 Nov 2026');
      expect(block('a1', '2026-11-27'), findsOneWidget);
      // After the deadline (27 Nov) there are no more sessions.
      await tester.tap(key('work-split-next-week'));
      await tester.pumpAndSettle();
      expect(weekTitle(tester), '30 Nov – 6 Dec 2026');
      expect(block('a1', '2026-11-30'), findsNothing);
      expect(block('a2', '2026-12-01'), findsOneWidget);

      await tester.tap(key('work-split-today'));
      await tester.pumpAndSettle();
      expect(weekTitle(tester), '16 – 22 Nov 2026');

      await tester.fling(
        key('work-split-week-title'),
        const Offset(-400, 0),
        1000,
      );
      await tester.pumpAndSettle();
      expect(weekTitle(tester), '23 – 29 Nov 2026');
      await tester.tap(key('work-split-prev-week'));
      await tester.pumpAndSettle();
      expect(weekTitle(tester), '16 – 22 Nov 2026');
    });

    testWidgets('deadlines show as markers in the day headers', (tester) async {
      await pump(tester);
      await openWorkSplit(tester);
      expect(key('deadline-marker-2026-11-20'), findsOneWidget);
      expect(key('deadline-marker-2026-11-18'), findsNothing);
      await tester.tap(key('work-split-next-week'));
      await tester.pumpAndSettle();
      expect(key('deadline-marker-2026-11-27'), findsOneWidget);
    });

    testWidgets('tapping a past block marks it attended and opens the target', (
      tester,
    ) async {
      final c = await pump(tester);
      await openWorkSplit(tester);

      await tapVisible(tester, block('a1', '2026-11-16'));
      expect(key('session-sheet'), findsOneWidget);
      await tester.tap(key('session-sheet-attend'));
      await tester.pumpAndSettle();
      expect(
        c
            .read(projectServiceProvider)
            .data
            .isAttended('a1', DateTime(2026, 11, 16)),
        isTrue,
      );
      expect(find.textContaining('Attended'), findsOneWidget);

      await tester.tap(key('session-sheet-open-target'));
      await tester.pumpAndSettle();
      expect(find.byType(TargetEditorScreen), findsOneWidget);
    });

    testWidgets('a future block cannot be marked yet', (tester) async {
      await pump(tester);
      await openWorkSplit(tester);
      await tapVisible(tester, block('a2', '2026-11-19'));
      expect(key('session-sheet'), findsOneWidget);
      expect(key('session-sheet-attend'), findsNothing);
      expect(key('session-sheet-open-target'), findsOneWidget);
    });

    for (final dark in [false, true]) {
      testWidgets('lays out on a small phone (${dark ? 'dark' : 'light'})', (
        tester,
      ) async {
        tester.platformDispatcher.platformBrightnessTestValue = dark
            ? Brightness.dark
            : Brightness.light;
        addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
        await pump(tester, size: const Size(320, 568));
        await openWorkSplit(tester);
        expect(tester.takeException(), isNull);
        expect(block('a1', '2026-11-18'), findsOneWidget);
      });
    }

    testWidgets('lays out on a tablet', (tester) async {
      await pump(tester, size: const Size(1366, 1024));
      await openWorkSplit(tester);
      expect(tester.takeException(), isNull);
      expect(tester.getSize(key('work-split-view')).width, greaterThan(900));
    });
  });

  group('month view: plan task delivery', () {
    testWidgets('markers on delivery days; archived projects are hidden', (
      tester,
    ) async {
      await pump(tester);
      expect(key('task-marker-2026-11-18'), findsOneWidget);
      expect(key('task-marker-2026-11-20'), findsOneWidget);
      expect(key('task-marker-2026-11-19'), findsNothing);
      // Perfect-day stars / rings are untouched (no habits here).
      expect(key('calendar-day-2026-11-18'), findsOneWidget);
    });

    testWidgets('the day lists its tasks and checks one off', (tester) async {
      final c = await pump(tester);
      // Today (18 Nov) is selected.
      expect(key('calendar-task-k1'), findsOneWidget);
      expect(key('calendar-task-k2'), findsNothing);
      await tapVisible(tester, key('calendar-task-check-k1'));
      expect(c.read(projectServiceProvider).data.planTask('k1')!.done, isTrue);

      await tapVisible(tester, key('calendar-day-2026-11-20'));
      expect(key('calendar-task-k2'), findsOneWidget);
      expect(find.text('Record intro'), findsOneWidget);
      await tapVisible(tester, key('calendar-day-2026-11-19'));
      expect(key('calendar-day-tasks'), findsNothing);
    });
  });

  group('project details', () {
    testWidgets('shows the work split filtered to the project', (tester) async {
      await pump(tester, location: '/projects/p1', size: const Size(900, 2600));
      expect(key('work-split-view'), findsOneWidget);
      expect(block('a1', '2026-11-16'), findsOneWidget);
      expect(block('a2', '2026-11-17'), findsNothing);
      expect(key('deadline-marker-2026-11-20'), findsOneWidget);
    });

    testWidgets('an archived project still shows its own blocks', (
      tester,
    ) async {
      await pump(tester, location: '/projects/p3', size: const Size(900, 2600));
      expect(block('a4', '2026-11-16'), findsOneWidget);
      expect(block('a1', '2026-11-16'), findsNothing);
    });
  });
}
