import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/habit_details/habit_details_screen.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/features/habits/habit_form_screen.dart';
import 'package:habit_quest/features/habits/widgets/streak_flame.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Monday 2026-01-05, 09:00.
DateTime clock() => DateTime(2026, 1, 5, 9);

void main() {
  testWidgets('empty state offers to create the first habit', (tester) async {
    await pumpHabitQuestApp(tester, clock: clock);

    expect(find.text('Good morning ☀️'), findsOneWidget);
    expect(find.text('🌱'), findsOneWidget);
    expect(find.text('Your quest begins here'), findsOneWidget);
    expect(find.byKey(const ValueKey('new-habit-fab')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('empty-create-habit')));
    await tester.pumpAndSettle();
    expect(find.byType(HabitFormScreen), findsOneWidget);
    expect(find.text('New habit'), findsOneWidget);
  });

  testWidgets('lists due habits under Today and the rest under Other habits', (
    tester,
  ) async {
    final repo = InMemoryHabitRepository(
      habits: [
        habit(id: 'daily', name: 'Drink water'),
        // Tuesdays only: not due on Monday.
        habit(id: 'tue', name: 'Yoga', schedule: WeekdaysSchedule({2, 4})),
        habit(id: 'old', name: 'Old habit', archived: true),
      ],
    );
    await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    expect(find.text('Today'), findsOneWidget);
    expect(find.text('Other habits'), findsOneWidget);
    expect(find.text('0/1 done'), findsOneWidget);
    expect(find.byKey(const ValueKey('checkin-daily')), findsOneWidget);
    expect(find.byKey(const ValueKey('checkin-tue')), findsNothing);
    expect(find.text('Tue · Thu'), findsOneWidget);
    expect(find.text('Every day'), findsOneWidget);

    // Archived habits are tucked away in a collapsed section.
    expect(find.text('Archived (1)'), findsOneWidget);
    expect(find.text('Old habit'), findsNothing);
    await tester.ensureVisible(find.text('Archived (1)'));
    await tester.tap(find.text('Archived (1)'));
    await tester.pumpAndSettle();
    expect(find.text('Old habit'), findsOneWidget);
  });

  testWidgets('check-in toggles completion and updates progress and streak', (
    tester,
  ) async {
    final repo = InMemoryHabitRepository(
      habits: [habit(id: 'h1')],
      completions: {
        'h1': [d(2026, 1, 3), d(2026, 1, 4)],
      },
    );
    await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    expect(find.text('2 days'), findsOneWidget);
    expect(find.text('0/1 done'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkin-h1')));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('h1', d(2026, 1, 5)), isTrue);
    expect(find.text('1/1 done'), findsOneWidget);
    expect(find.text('3 days'), findsOneWidget);
    expect(find.textContaining('Perfect day'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkin-h1')));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('h1', d(2026, 1, 5)), isFalse);
    expect(find.text('0/1 done'), findsOneWidget);
    expect(find.text('2 days'), findsOneWidget);
  });

  testWidgets('times-per-week card shows weekly progress and a week streak', (
    tester,
  ) async {
    final repo = InMemoryHabitRepository(
      habits: [
        habit(
          id: 'w',
          schedule: TimesPerWeekSchedule(3),
          startDate: d(2025, 12, 1),
        ),
      ],
      completions: {
        // Previous week fully done → 1-week streak.
        'w': [d(2025, 12, 29), d(2025, 12, 30), d(2025, 12, 31)],
      },
    );
    await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    expect(find.text('3× per week · 0/3 this week'), findsOneWidget);
    final flame = tester.widget<StreakFlame>(find.byType(StreakFlame));
    expect(flame.streak, 1);
    expect(find.text('1 wk'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkin-w')));
    await tester.pumpAndSettle();
    expect(find.text('3× per week · 1/3 this week'), findsOneWidget);
  });

  testWidgets('tapping a card opens its details route', (tester) async {
    final repo = InMemoryHabitRepository(habits: [habit(id: 'h1')]);
    await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    await tester.tap(find.text('Drink water'));
    await tester.pumpAndSettle();
    final details = tester.widget<HabitDetailsScreen>(
      find.byType(HabitDetailsScreen),
    );
    expect(details.habitId, 'h1');
  });

  testWidgets('FAB opens the create form', (tester) async {
    final repo = InMemoryHabitRepository(habits: [habit(id: 'h1')]);
    await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    await tester.tap(find.byKey(const ValueKey('new-habit-fab')));
    await tester.pumpAndSettle();
    final form = tester.widget<HabitFormScreen>(find.byType(HabitFormScreen));
    expect(form.habitId, isNull);
  });

  testWidgets('streak flame grows with the streak', (tester) async {
    await tester.pumpWidget(
      wrapForTest(
        const Column(
          children: [
            StreakFlame(key: ValueKey('cold'), streak: 0),
            StreakFlame(key: ValueKey('hot'), streak: 30),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final cold = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('cold')),
        matching: find.text('🔥'),
      ),
    );
    final hot = tester.getSize(
      find.descendant(
        of: find.byKey(const ValueKey('hot')),
        matching: find.text('🔥'),
      ),
    );
    expect(hot.height, greaterThan(cold.height));
    expect(find.text('0 days'), findsOneWidget);
    expect(find.text('30 days'), findsOneWidget);
  });
}
