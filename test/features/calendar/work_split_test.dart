import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/calendar/calendar_screen.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/session.dart';
import 'package:habit_quest/features/projects/models/time_block.dart';
import 'package:habit_quest/features/projects/models/goal.dart';
import 'package:habit_quest/features/projects/ui/project_details_screen.dart';
import 'package:habit_quest/features/projects/projects_providers.dart';
import 'package:habit_quest/features/projects/ui/work_split_view.dart';

import '../../helpers/test_app.dart';
import '../projects/helpers.dart';

/// Wednesday 18 Nov 2026, 09:00 (week of Mon 16 – Sun 22 Nov).
DateTime clock() => DateTime(2026, 11, 18, 9);

Finder key(String k) => find.byKey(ValueKey(k));
Finder block(String timeBlockId, String day) =>
    key('session-block-$timeBlockId|$day');

/// p1 "Content": open-ended block a1 "Filming" Mon–Fri 10:00–13:00; goals
/// t1 "5 videos" (due Fri 27 Nov) and t5 "Teaser" (due Fri 20 Nov). Tasks:
/// k1 due Wed 18 Nov (open), k2 due Fri 20 Nov (done).
/// p2 "Fitness": unlabelled block a2 Tue/Thu 18:00–19:00; goal t2 "Run 10k"
/// (due 31 Dec).
/// p3 "Old" (archived): block a4 Mon 07:00–08:00; goal t4 with task k4 due
/// 19 Nov.
InMemoryProjectRepository seededRepo({
  List<Goal> extraGoals = const [],
  List<TimeBlock> extraBlocks = const [],
}) => InMemoryProjectRepository(
  seed: ProjectRecords(
    projects: [
      project('p1', name: 'Content'),
      project('p2', name: 'Fitness'),
      project('p3', name: 'Old', archived: true),
    ],
    goals: [
      goal('t1', title: '5 videos', deadline: DateTime(2026, 11, 27)),
      goal('t5', title: 'Teaser', deadline: DateTime(2026, 11, 20)),
      goal(
        't2',
        projectId: 'p2',
        title: 'Run 10k',
        deadline: DateTime(2026, 12, 31),
      ),
      goal(
        't4',
        projectId: 'p3',
        title: 'Archived goal',
        deadline: DateTime(2026, 12, 31),
      ),
      ...extraGoals,
    ],
    planTasks: [
      PlanTask(
        id: 'k1',
        goalId: 't1',
        title: 'Write script 1',
        deliveryDate: DateTime(2026, 11, 18),
        createdAt: createdOn(2026, 11, 1),
      ),
      PlanTask(
        id: 'k2',
        goalId: 't1',
        title: 'Record intro',
        deliveryDate: DateTime(2026, 11, 20),
        done: true,
        position: 1,
        createdAt: createdOn(2026, 11, 1),
      ),
      PlanTask(
        id: 'k4',
        goalId: 't4',
        title: 'Hidden task',
        deliveryDate: DateTime(2026, 11, 19),
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
        days: {2, 4},
        start: '18:00',
        end: '19:00',
        created: createdOn(2026, 11, 1),
      ),
      weekly(
        'a4',
        projectId: 'p3',
        days: {1},
        start: '07:00',
        end: '08:00',
        created: createdOn(2026, 11, 1),
      ),
      ...extraBlocks,
    ],
  ),
);

/// Adds an early block in the week of 16 Nov only (a6: Mon 04:00–05:00,
/// ends 22 Nov) and a late one in the week of 23 Nov only (a7: Wed
/// 21:00–22:30, from 23 Nov until 29 Nov).
InMemoryProjectRepository outOfHoursRepo() => seededRepo(
  extraBlocks: [
    weekly(
      'a6',
      label: 'Early',
      days: {1},
      start: '04:00',
      end: '05:00',
      endDate: DateTime(2026, 11, 22),
      created: createdOn(2026, 11, 1),
    ),
    weekly(
      'a7',
      label: 'Late',
      days: {3},
      start: '21:00',
      end: '22:30',
      endDate: DateTime(2026, 11, 29),
      created: createdOn(2026, 11, 23),
    ),
  ],
);

/// The hour labels shown, e.g. [6, 7, …, 20].
List<int> visibleHours(WidgetTester tester) => [
  for (var h = 0; h <= 24; h++)
    if (tester.any(key('work-split-hour-$h'))) h,
];

List<int> hours(int from, int to) => [for (var h = from; h <= to; h++) h];

String weekTitle(WidgetTester tester) =>
    tester.widget<Text>(key('work-split-week-title')).data!;

void main() {
  late InMemoryProjectRepository repo;

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    String location = '/calendar',
    Size size = const Size(900, 2200),
    InMemoryProjectRepository Function() seed = seededRepo,
  }) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    repo = seed();
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
      // Labelled with the block label, else the project name.
      expect(
        find.descendant(
          of: block('a1', '2026-11-16'),
          matching: find.text('Filming'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: block('a2', '2026-11-17'),
          matching: find.text('Fitness'),
        ),
        findsOneWidget,
      );

      // 06:00–20:00 share the grid: 10:00–13:00 is 3 of 14 hour rows;
      // 18:00 starts 8 rows below 10:00.
      final grid = tester.getRect(key('work-split-grid'));
      final hour = grid.height / 14;
      final mon = tester.getRect(block('a1', '2026-11-17'));
      final tue = tester.getRect(block('a2', '2026-11-17'));
      expect(mon.top - grid.top, closeTo(4 * hour, 0.5));
      expect(mon.height, closeTo(3 * hour, 0.5));
      expect(tue.top - mon.top, closeTo(8 * hour, 0.5));
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
      // The block is open-ended: a goal deadline (27 Nov) does not stop it.
      await tester.tap(key('work-split-next-week'));
      await tester.pumpAndSettle();
      expect(weekTitle(tester), '30 Nov – 6 Dec 2026');
      expect(block('a1', '2026-11-30'), findsOneWidget);
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

    testWidgets(
      'tapping a past block marks it attended and opens the project',
      (tester) async {
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

        await tester.tap(key('session-sheet-open-project'));
        await tester.pumpAndSettle();
        expect(find.byType(ProjectDetailsScreen), findsOneWidget);
        expect(find.text('Content'), findsWidgets);
      },
    );

    testWidgets('a future block cannot be marked yet', (tester) async {
      await pump(tester);
      await openWorkSplit(tester);
      await tapVisible(tester, block('a2', '2026-11-19'));
      expect(key('session-sheet'), findsOneWidget);
      expect(key('session-sheet-attend'), findsNothing);
      expect(key('session-sheet-open-project'), findsOneWidget);
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

  group('work split hour range', () {
    /// The Calendar body's scroll position (strips + grid scroll together).
    ScrollPosition bodyScroll(WidgetTester tester) => tester
        .state<ScrollableState>(
          find.descendant(
            of: key('work-split-body-scroll'),
            matching: find.byType(Scrollable),
          ),
        )
        .position;

    /// The grid has no scroll of its own.
    void expectNoGridScroll() => expect(
      find.descendant(
        of: key('work-split-grid'),
        matching: find.byType(Scrollable),
      ),
      findsNothing,
    );

    void expectFits(WidgetTester tester) {
      expectNoGridScroll();
      expect(bodyScroll(tester).maxScrollExtent, 0);
      final view = tester.getRect(key('work-split-view'));
      final grid = tester.getRect(key('work-split-grid'));
      expect(grid.bottom, lessThanOrEqualTo(view.bottom + 0.5));
    }

    double gridHeight(WidgetTester tester) =>
        tester.getSize(key('work-split-grid')).height;

    test('auto range: 06–20, extended to the floor/ceil of the sessions', () {
      final data = outOfHoursRepo().getData();
      List<Session> week(DateTime monday) => workSplitSessions(
        data,
        weekStart: monday,
        today: DateTime(2026, 11, 18),
      );
      expect(workSplitAutoRange(const []), (start: 6, end: 20));
      expect(workSplitAutoRange(week(DateTime(2026, 11, 16))), (
        start: 4,
        end: 20,
      ));
      expect(workSplitAutoRange(week(DateTime(2026, 11, 23))), (
        start: 6,
        end: 23,
      ));
      expect(workSplitVisibleRange(const [], earlier: 8, later: 6), (
        start: 0,
        end: 24,
      ));
    });

    testWidgets('shows 06:00–20:00 by default, without vertical scroll', (
      tester,
    ) async {
      await pump(tester);
      await openWorkSplit(tester);
      expect(visibleHours(tester), hours(6, 20));
      expectFits(tester);
      expect(key('work-split-collapse'), findsNothing);
    });

    for (final size in const [Size(320, 568), Size(1366, 1024)]) {
      testWidgets('fits without scrolling at $size', (tester) async {
        await pump(tester, size: size);
        await openWorkSplit(tester);
        expect(tester.takeException(), isNull);
        expectFits(tester);
        final grid = tester.getRect(key('work-split-grid'));
        expect(grid.height / 14, greaterThanOrEqualTo(workSplitMinHourHeight));
      });
    }

    testWidgets('fits the project details card', (tester) async {
      await pump(tester, location: '/projects/p1', size: const Size(900, 2600));
      expectNoGridScroll();
      final card = tester.getRect(key('project-work-split'));
      final grid = tester.getRect(key('work-split-grid'));
      expect(grid.bottom, lessThanOrEqualTo(card.bottom));
      expect(grid.height, closeTo(projectWorkSplitGridHeight, 0.5));
      expect(visibleHours(tester), hours(6, 20));
    });

    testWidgets('expanding grows the project card at the same row height', (
      tester,
    ) async {
      await pump(tester, location: '/projects/p1', size: const Size(900, 2600));
      final card = tester.getSize(key('project-work-split')).height;
      final grid = gridHeight(tester);
      final row = grid / 14;
      final blockHeight = tester.getRect(block('a1', '2026-11-17')).height;

      await tapVisible(tester, key('work-split-expand-later'));
      expect(visibleHours(tester), hours(6, 22));
      expect(gridHeight(tester), closeTo(grid + 2 * row, 0.5));
      expect(
        tester.getSize(key('project-work-split')).height,
        closeTo(card + 2 * row, 0.5),
      );
      expect(
        tester.getRect(block('a1', '2026-11-17')).height,
        closeTo(blockHeight, 0.5),
      );
      expectNoGridScroll();

      await tapVisible(tester, key('work-split-collapse'));
      expect(gridHeight(tester), closeTo(grid, 0.5));
      expect(
        tester.getSize(key('project-work-split')).height,
        closeTo(card, 0.5),
      );
    });

    testWidgets('extends automatically per week and animates', (tester) async {
      await pump(tester, seed: outOfHoursRepo);
      await openWorkSplit(tester);
      // This week: a 04:00 block.
      expect(visibleHours(tester), hours(4, 20));
      final early = tester.getRect(block('a6', '2026-11-16'));
      final grid = tester.getRect(key('work-split-grid'));
      expect(early.top, closeTo(grid.top, 0.5));
      expectFits(tester);

      // Next week: a block until 22:30, so until 23:00 (from 06:00).
      await tester.tap(key('work-split-next-week'));
      await tester.pump();
      await tester.pump(workSplitAnimationDuration ~/ 2);
      // Mid-animation the rows are between the two layouts.
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pumpAndSettle();
      expect(visibleHours(tester), hours(6, 23));
      expectFits(tester);

      // The week after: back to 06:00–20:00 (never smaller).
      await tester.tap(key('work-split-next-week'));
      await tester.pumpAndSettle();
      expect(visibleHours(tester), hours(6, 20));
    });

    testWidgets('expand buttons reveal hours; Reset and week change collapse', (
      tester,
    ) async {
      await pump(tester);
      await openWorkSplit(tester);
      final fitted = gridHeight(tester);
      final row = fitted / 14;
      final blockBefore = tester.getRect(block('a1', '2026-11-17')).height;

      await tester.tap(key('work-split-expand-earlier'));
      await tester.pump();
      await tester.pump(workSplitAnimationDuration ~/ 2);
      // The grid grows smoothly.
      expect(tester.hasRunningAnimations, isTrue);
      expect(gridHeight(tester), inExclusiveRange(fitted, fitted + 2 * row));
      await tester.pumpAndSettle();
      expect(visibleHours(tester), hours(4, 20));
      // Same row height, more hours: a taller grid; the body scrolls.
      expect(gridHeight(tester), closeTo(fitted + 2 * row, 0.5));
      expect(
        tester.getRect(block('a1', '2026-11-17')).height,
        closeTo(blockBefore, 0.5),
      );
      expect(bodyScroll(tester).maxScrollExtent, closeTo(2 * row, 0.5));
      expectNoGridScroll();
      for (var i = 0; i < 2; i++) {
        await tapVisible(tester, key('work-split-expand-earlier'));
      }
      expect(visibleHours(tester), hours(0, 20));
      expect(
        tester.widget<TextButton>(key('work-split-expand-earlier')).onPressed,
        isNull,
      );
      for (var i = 0; i < 2; i++) {
        await tapVisible(tester, key('work-split-expand-later'));
      }
      expect(visibleHours(tester), hours(0, 24));
      expect(gridHeight(tester), closeTo(24 * row, 0.5));
      // "Later" scrolls the new bottom hours into view.
      final pos = bodyScroll(tester);
      expect(pos.pixels, closeTo(pos.maxScrollExtent, 0.5));
      expect(
        tester.widget<TextButton>(key('work-split-expand-later')).onPressed,
        isNull,
      );

      await tapVisible(tester, key('work-split-collapse'));
      expect(visibleHours(tester), hours(6, 20));
      expect(gridHeight(tester), closeTo(fitted, 0.5));
      expectFits(tester);
      expect(key('work-split-collapse'), findsNothing);

      // A manual expansion is reset when the week changes.
      await tester.tap(key('work-split-expand-later'));
      await tester.pumpAndSettle();
      expect(visibleHours(tester), hours(6, 22));
      await tester.tap(key('work-split-next-week'));
      await tester.pumpAndSettle();
      expect(visibleHours(tester), hours(6, 20));
      expect(gridHeight(tester), closeTo(fitted, 0.5));
      expectFits(tester);
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

    testWidgets('"Open project" from the project\'s own card stays there', (
      tester,
    ) async {
      await pump(tester, location: '/projects/p1', size: const Size(900, 2600));
      await tapVisible(tester, block('a1', '2026-11-16'));
      await tester.tap(key('session-sheet-open-project'));
      await tester.pumpAndSettle();
      expect(key('session-sheet'), findsNothing);
      expect(
        find.byType(ProjectDetailsScreen, skipOffstage: false),
        findsOneWidget,
      );
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
