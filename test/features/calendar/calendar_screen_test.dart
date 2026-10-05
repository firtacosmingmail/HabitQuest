import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/features/calendar/calendar_screen.dart';
import 'package:habit_quest/features/habit_details/habit_details_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Thursday, 15 October 2026.
DateTime clock() => DateTime(2026, 10, 15, 9, 30);

Finder dayCell(int y, int m, int day) => find.byKey(ValueKey(
    'calendar-day-$y-${m.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}'));

Finder perfectMarker(int y, int m, int day) => find.byKey(ValueKey(
    'perfect-day-$y-${m.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}'));

String monthTitle(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('calendar-month-title')))
    .data!;

String selectedTitle(WidgetTester tester) => tester
    .widget<Text>(find.byKey(const ValueKey('calendar-selected-title')))
    .data!;

/// Drink water: daily. Read: Mon/Wed/Fri. Both from 1 Sep 2026.
/// Oct 1 (Thu): water done → Perfect Day (only water is due).
/// Oct 2 (Fri): water done, read not → 1/2.
InMemoryHabitRepository seededRepo() => InMemoryHabitRepository(
      habits: [
        habit(id: 'water', name: 'Drink water', startDate: d(2026, 9, 1)),
        habit(
          id: 'read',
          name: 'Read a chapter',
          schedule: WeekdaysSchedule({1, 3, 5}),
          startDate: d(2026, 9, 1),
        ),
      ],
      completions: {
        'water': [d(2026, 10, 1), d(2026, 10, 2)],
      },
    );

Future<InMemoryHabitRepository> pumpCalendar(
  WidgetTester tester, {
  InMemoryHabitRepository? repo,
}) async {
  tester.view.physicalSize = const Size(900, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repository = repo ?? seededRepo();
  await pumpHabitQuestApp(
    tester,
    repository: repository,
    clock: clock,
    initialLocation: '/calendar',
  );
  expect(find.byType(CalendarScreen), findsOneWidget);
  return repository;
}

Future<void> tapDay(WidgetTester tester, int y, int m, int day) async {
  await tester.tap(dayCell(y, m, day));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('renders the current month with Monday-first weeks',
      (tester) async {
    await pumpCalendar(tester);

    expect(monthTitle(tester), 'October 2026');
    for (var day = 1; day <= 31; day++) {
      expect(dayCell(2026, 10, day), findsOneWidget, reason: 'day $day');
    }
    expect(dayCell(2026, 9, 30), findsNothing);
    expect(dayCell(2026, 11, 1), findsNothing);

    // Weekday header starts on Monday; Oct 1 2026 (a Thursday) sits under
    // "Thu", Oct 5 (a Monday) under "Mon".
    final headers = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final xs = [for (final h in headers) tester.getCenter(find.text(h)).dx];
    expect(xs, orderedEquals([...xs]..sort()));
    expect(tester.getCenter(dayCell(2026, 10, 1)).dx, closeTo(xs[3], 1));
    expect(tester.getCenter(dayCell(2026, 10, 5)).dx, closeTo(xs[0], 1));

    // Today is selected by default.
    expect(selectedTitle(tester), 'Today');
  });

  testWidgets('shows a Perfect Day marker and the month summary',
      (tester) async {
    await pumpCalendar(tester);

    expect(perfectMarker(2026, 10, 1), findsOneWidget);
    expect(perfectMarker(2026, 10, 2), findsNothing);
    expect(perfectMarker(2026, 10, 14), findsNothing);
    expect(find.text('⭐ 1 Perfect Day this month'), findsOneWidget);
  });

  testWidgets('selecting a day lists the habits due that day', (tester) async {
    await pumpCalendar(tester);

    await tapDay(tester, 2026, 10, 2); // Friday: both due
    expect(selectedTitle(tester), 'Friday, Oct 2');
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Read a chapter'), findsOneWidget);
    expect(find.text('💧'), findsNWidgets(2));
    expect(find.text('1/2 done'), findsOneWidget);

    await tapDay(tester, 2026, 10, 1); // Thursday: only water
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Read a chapter'), findsNothing);
    expect(find.text('⭐ Perfect!'), findsOneWidget);
  });

  testWidgets('prompts to create a habit when there are none',
      (tester) async {
    await pumpCalendar(tester, repo: InMemoryHabitRepository());

    expect(find.byKey(const ValueKey('calendar-no-habits')), findsOneWidget);
    expect(find.text('Create a habit'), findsOneWidget);
    expect(find.textContaining('No Perfect Days yet'), findsOneWidget);
  });

  testWidgets('shows friendly text when nothing is due', (tester) async {
    // Only due on Mondays; "today" is a Thursday.
    await pumpCalendar(
      tester,
      repo: InMemoryHabitRepository(habits: [
        habit(
          id: 'gym',
          name: 'Gym',
          schedule: WeekdaysSchedule({1}),
          startDate: d(2026, 9, 1),
        ),
      ]),
    );

    expect(find.byKey(const ValueKey('calendar-empty-day')), findsOneWidget);
    expect(find.textContaining('Nothing due'), findsOneWidget);
    expect(find.textContaining('No Perfect Days yet'), findsOneWidget);
  });

  testWidgets('toggling a past day updates progress and the Perfect Day',
      (tester) async {
    final repo = await pumpCalendar(tester);

    await tapDay(tester, 2026, 10, 2);
    final toggle = find.byKey(const ValueKey('calendar-toggle-read'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(repo.getCompletions().isCompleted('read', d(2026, 10, 2)), isTrue);
    expect(find.text('⭐ Perfect!'), findsOneWidget);
    expect(perfectMarker(2026, 10, 2), findsOneWidget);
    expect(find.text('⭐ 2 Perfect Days this month'), findsOneWidget);

    // And back off again.
    await tester.tap(toggle);
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('read', d(2026, 10, 2)), isFalse);
    expect(find.text('1/2 done'), findsOneWidget);
    expect(perfectMarker(2026, 10, 2), findsNothing);
  });

  testWidgets('today can be checked in', (tester) async {
    final repo = await pumpCalendar(tester);

    final toggle = find.byKey(const ValueKey('calendar-toggle-water'));
    await tester.ensureVisible(toggle);
    await tester.tap(toggle);
    await tester.pumpAndSettle();

    expect(repo.getCompletions().isCompleted('water', d(2026, 10, 15)), isTrue);
    expect(perfectMarker(2026, 10, 15), findsOneWidget); // Thursday: water only
  });

  testWidgets('future days are read-only', (tester) async {
    final repo = await pumpCalendar(tester);

    await tapDay(tester, 2026, 10, 16); // Friday: both due
    expect(selectedTitle(tester), 'Tomorrow');
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Read a chapter'), findsOneWidget);
    expect(find.text('Soon'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('calendar-selected-progress')),
        findsNothing);

    final toggle = find.byKey(const ValueKey('calendar-toggle-water'));
    expect(tester.widget<IconButton>(toggle).onPressed, isNull);
    await tester.ensureVisible(toggle);
    await tester.tap(toggle, warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('water', d(2026, 10, 16)), isFalse);
  });

  testWidgets('month navigation and the Today button', (tester) async {
    await pumpCalendar(tester);
    final todayButton = find.byKey(const ValueKey('calendar-today-button'));
    final next = find.byKey(const ValueKey('calendar-next-month'));
    final prev = find.byKey(const ValueKey('calendar-prev-month'));

    // Already on today: the button is disabled.
    expect(tester.widget<ButtonStyleButton>(todayButton).onPressed, isNull);

    await tester.tap(next);
    await tester.pumpAndSettle();
    expect(monthTitle(tester), 'November 2026');
    expect(dayCell(2026, 11, 30), findsOneWidget);
    expect(selectedTitle(tester), 'Sunday, Nov 1');

    await tester.tap(prev);
    await tester.pumpAndSettle();
    await tester.tap(prev);
    await tester.pumpAndSettle();
    expect(monthTitle(tester), 'September 2026');
    expect(dayCell(2026, 9, 30), findsOneWidget);

    await tester.tap(todayButton);
    await tester.pumpAndSettle();
    expect(monthTitle(tester), 'October 2026');
    expect(selectedTitle(tester), 'Today');
    expect(tester.widget<ButtonStyleButton>(todayButton).onPressed, isNull);
  });

  testWidgets('swiping changes the month', (tester) async {
    await pumpCalendar(tester);

    await tester.fling(dayCell(2026, 10, 14), const Offset(-300, 0), 1000);
    await tester.pumpAndSettle();
    expect(monthTitle(tester), 'November 2026');

    await tester.fling(dayCell(2026, 11, 11), const Offset(300, 0), 1000);
    await tester.pumpAndSettle();
    expect(monthTitle(tester), 'October 2026');
  });

  testWidgets('tapping a habit name opens its details', (tester) async {
    await pumpCalendar(tester);

    await tester.tap(find.byKey(const ValueKey('calendar-habit-name-water')));
    await tester.pumpAndSettle();
    final details =
        tester.widget<HabitDetailsScreen>(find.byType(HabitDetailsScreen));
    expect(details.habitId, 'water');
  });

  testWidgets('renders in dark mode', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpCalendar(tester);
    expect(perfectMarker(2026, 10, 1), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
