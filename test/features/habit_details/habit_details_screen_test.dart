import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/features/habit_details/habit_details_screen.dart';
import 'package:habit_quest/features/habit_details/widgets/habit_month_calendar.dart';
import 'package:habit_quest/features/habits/habit_form_screen.dart';
import 'package:habit_quest/features/habits/habits_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

DateTime clock() => DateTime(2026, 1, 10, 9, 30); // Saturday

Finder statText(String tileKey, String text) => find.descendant(
      of: find.byKey(ValueKey(tileKey)),
      matching: find.text(text),
    );

void main() {
  late InMemoryHabitRepository repo;

  setUp(() {
    // Daily since Jan 1, done Jan 1–4 and 6–9 (missed Jan 5); today (10) open.
    repo = InMemoryHabitRepository(
      habits: [
        habit(startDate: d(2026, 1, 1)).copyWith(
          reminderTime: const ReminderTime(hour: 8, minute: 30),
        ),
      ],
      completions: {
        'h1': [
          ...range(d(2026, 1, 1), d(2026, 1, 4)),
          ...range(d(2026, 1, 6), d(2026, 1, 9)),
        ],
      },
    );
  });

  Future<void> pumpDetails(WidgetTester tester, {String id = 'h1'}) async {
    tester.view.physicalSize = const Size(420, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHabitQuestApp(
      tester,
      repository: repo,
      clock: clock,
      initialLocation: '/habits/$id',
    );
  }

  testWidgets('renders header and stats', (tester) async {
    await pumpDetails(tester);

    expect(find.byType(HabitDetailsScreen), findsOneWidget);
    expect(find.text('💧'), findsWidgets);
    expect(find.text('Drink water'), findsOneWidget);
    expect(find.text('Every day'), findsOneWidget);
    expect(find.byKey(const ValueKey('habit-reminder')), findsOneWidget);
    expect(find.text('8:30 AM'), findsOneWidget);

    expect(statText('stat-current-streak', '4 days'), findsOneWidget);
    expect(statText('stat-best-streak', '4 days'), findsOneWidget);
    expect(statText('stat-total', '8'), findsOneWidget);
    expect(statText('stat-rate', '89%'), findsOneWidget); // 8 / 9
    expect(find.text('January 2026'), findsOneWidget);
  });

  testWidgets('toggling a past day updates the streak', (tester) async {
    await pumpDetails(tester);

    await tester.tap(find.byKey(habitCalendarDayKey(d(2026, 1, 5))));
    await tester.pumpAndSettle();

    expect(repo.getCompletions().isCompleted('h1', d(2026, 1, 5)), isTrue);
    expect(statText('stat-current-streak', '9 days'), findsOneWidget);
    expect(statText('stat-best-streak', '9 days'), findsOneWidget);
    expect(statText('stat-total', '9'), findsOneWidget);
    expect(statText('stat-rate', '100%'), findsOneWidget);

    // Undo it again.
    await tester.tap(find.byKey(habitCalendarDayKey(d(2026, 1, 5))));
    await tester.pumpAndSettle();
    expect(statText('stat-current-streak', '4 days'), findsOneWidget);
  });

  testWidgets('today can be checked in, future days are disabled',
      (tester) async {
    await pumpDetails(tester);

    await tester.tap(find.byKey(habitCalendarDayKey(d(2026, 1, 11))));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('h1', d(2026, 1, 11)), isFalse);

    await tester.tap(find.byKey(habitCalendarDayKey(d(2026, 1, 10))));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('h1', d(2026, 1, 10)), isTrue);
    expect(statText('stat-current-streak', '5 days'), findsOneWidget);
  });

  testWidgets('month navigation shows earlier months down to the start',
      (tester) async {
    repo = InMemoryHabitRepository(habits: [
      habit(
        schedule: TimesPerWeekSchedule(3),
        startDate: d(2025, 12, 15),
      ),
    ]);
    await pumpDetails(tester);

    expect(find.text('3× per week'), findsOneWidget);
    expect(statText('stat-current-streak', '0 weeks'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('calendar-prev')));
    await tester.pumpAndSettle();
    expect(find.text('December 2025'), findsOneWidget);

    // Before the start date: disabled.
    await tester.tap(find.byKey(habitCalendarDayKey(d(2025, 12, 10))));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().totalFor('h1'), 0);

    await tester.tap(find.byKey(habitCalendarDayKey(d(2025, 12, 16))));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('h1', d(2025, 12, 16)), isTrue);
    expect(statText('stat-total', '1'), findsOneWidget);

    // Can't go before the start month.
    final prev = tester.widget<IconButton>(
      find.byKey(const ValueKey('calendar-prev')),
    );
    expect(prev.onPressed, isNull);

    await tester.tap(find.byKey(const ValueKey('calendar-next')));
    await tester.pumpAndSettle();
    expect(find.text('January 2026'), findsOneWidget);
  });

  testWidgets('edit navigates to the edit form', (tester) async {
    await pumpDetails(tester);
    await tester.tap(find.byKey(const ValueKey('habit-edit')));
    await tester.pumpAndSettle();
    expect(
      tester.widget<HabitFormScreen>(find.byType(HabitFormScreen)).habitId,
      'h1',
    );
  });

  testWidgets('archive and unarchive', (tester) async {
    await pumpDetails(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('habit-archive')));
    await tester.tap(find.byKey(const ValueKey('habit-archive')));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1')!.archived, isTrue);
    expect(find.byKey(const ValueKey('habit-archived')), findsOneWidget);
    expect(find.text('Unarchive'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('habit-archive')));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1')!.archived, isFalse);
    expect(find.text('Archive'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation, then goes back to /habits',
      (tester) async {
    await pumpDetails(tester);

    await tester.ensureVisible(find.byKey(const ValueKey('habit-delete')));
    await tester.tap(find.byKey(const ValueKey('habit-delete')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);

    // Cancel keeps it.
    await tester.tap(find.byKey(const ValueKey('delete-cancel')));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1'), isNotNull);

    await tester.tap(find.byKey(const ValueKey('habit-delete')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('delete-confirm')));
    await tester.pumpAndSettle();

    expect(repo.getHabit('h1'), isNull);
    expect(repo.getCompletions().totalFor('h1'), 0);
    expect(find.byType(HabitDetailsScreen), findsNothing);
    expect(find.byType(HabitsScreen), findsOneWidget);
  });

  testWidgets('unknown id shows the not-found state', (tester) async {
    await pumpDetails(tester, id: 'missing');

    expect(find.byKey(const ValueKey('habit-not-found')), findsOneWidget);
    expect(find.text('Habit not found'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('back-to-habits')));
    await tester.pumpAndSettle();
    expect(find.byType(HabitsScreen), findsOneWidget);
  });

  testWidgets('renders in dark mode without errors', (tester) async {
    tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
    addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
    await pumpDetails(tester);
    expect(find.text('Drink water'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
