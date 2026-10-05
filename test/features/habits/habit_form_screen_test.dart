import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/theme/app_colors.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/models/habit_schedule.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/features/habits/habit_form_screen.dart';
import 'package:habit_quest/features/habits/habits_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

DateTime clock() => DateTime(2026, 1, 5, 9);

Finder key(String k) => find.byKey(ValueKey(k));

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('creates a habit through the form', (tester) async {
    final repo = InMemoryHabitRepository();
    await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    await tester.tap(key('empty-create-habit'));
    await tester.pumpAndSettle();

    await tester.enterText(key('habit-name'), '  Read a book  ');
    await tester.pump();
    // Live preview shows the name.
    expect(find.text('Read a book'), findsOneWidget);

    await tapVisible(tester, key('emoji-📚'));
    await tapVisible(tester, key('color-4'));
    await tapVisible(tester, find.text('Weekdays'));
    // Default Mon–Fri; drop Tuesday and Thursday.
    await tapVisible(tester, key('weekday-2'));
    await tapVisible(tester, key('weekday-4'));
    expect(find.text('Mon · Wed · Fri'), findsOneWidget); // preview

    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();

    expect(find.byType(HabitFormScreen), findsNothing);
    expect(find.byType(HabitsScreen), findsOneWidget);
    final habits = repo.getHabits();
    expect(habits, hasLength(1));
    final h = habits.single;
    expect(h.name, 'Read a book');
    expect(h.emoji, '📚');
    expect(h.colorValue, HabitPalette.colors[4].toARGB32());
    expect(h.schedule, WeekdaysSchedule({1, 3, 5}));
    expect(h.startDate, d(2026, 1, 5));
    expect(h.reminderTime, isNull);
    expect(find.text('Read a book'), findsOneWidget);
    expect(find.text('Mon · Wed · Fri'), findsOneWidget);
  });

  testWidgets('creates every-N-days and times-per-week schedules', (
    tester,
  ) async {
    final repo = InMemoryHabitRepository();
    await tester.pumpWidget(
      wrapForTest(const HabitFormScreen(), repository: repo, clock: clock),
    );
    await tester.pumpAndSettle();
    await tester.enterText(key('habit-name'), 'Stretch');

    await tapVisible(tester, find.text('Every N'));
    expect(find.text('Every 2 days'), findsWidgets);
    await tapVisible(tester, key('everyN-inc'));
    expect(find.text('Every 3 days'), findsWidgets);

    await tapVisible(tester, find.text('Per week'));
    await tapVisible(tester, key('times-dec'));
    await tapVisible(tester, key('times-dec'));
    expect(find.text('1× per week'), findsWidgets);
    // Minimum reached: the decrement button is disabled.
    final dec = tester.widget<IconButton>(key('times-dec'));
    expect(dec.onPressed, isNull);

    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();
    expect(repo.getHabits().single.schedule, TimesPerWeekSchedule(1));
  });

  testWidgets('shows validation errors and does not save', (tester) async {
    final repo = InMemoryHabitRepository();
    await tester.pumpWidget(
      wrapForTest(const HabitFormScreen(), repository: repo, clock: clock),
    );
    await tester.pumpAndSettle();

    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();
    expect(find.text('Give your habit a name'), findsOneWidget);

    await tester.enterText(key('habit-name'), 'x' * 41);
    await tester.pumpAndSettle();
    expect(find.text('Keep it under 40 characters'), findsOneWidget);

    await tester.enterText(key('habit-name'), 'Floss');
    await tester.pumpAndSettle();
    expect(find.text('Keep it under 40 characters'), findsNothing);

    await tapVisible(tester, find.text('Weekdays'));
    for (final day in [1, 2, 3, 4, 5]) {
      await tapVisible(tester, key('weekday-$day'));
    }
    expect(find.text('Pick at least one day'), findsOneWidget);

    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();
    expect(repo.getHabits(), isEmpty);
  });

  testWidgets('reminder time can be cleared', (tester) async {
    final h = Habit(
      id: 'h1',
      name: 'Meditate',
      emoji: '🧘',
      colorValue: HabitPalette.defaultColorValue,
      schedule: const DailySchedule(),
      reminderTime: const ReminderTime(hour: 8, minute: 30),
      createdAt: d(2026, 1, 1),
      startDate: d(2026, 1, 1),
    );
    final repo = InMemoryHabitRepository(habits: [h]);
    await tester.pumpWidget(
      wrapForTest(
        const HabitFormScreen(habitId: 'h1'),
        repository: repo,
        clock: clock,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('8:30 AM'), findsOneWidget);
    await tapVisible(tester, key('clear-reminder'));
    expect(find.text('No reminder'), findsOneWidget);

    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1')!.reminderTime, isNull);
  });

  testWidgets('edits an existing habit', (tester) async {
    final repo = InMemoryHabitRepository(habits: [habit(id: 'h1')]);
    final c = await pumpHabitQuestApp(tester, repository: repo, clock: clock);

    c.read(routerProvider).push('/habits/h1/edit');
    await tester.pumpAndSettle();
    expect(find.text('Edit habit'), findsOneWidget);
    expect(find.text('Save changes'), findsOneWidget);
    // Prefilled.
    expect(find.widgetWithText(TextFormField, 'Drink water'), findsOneWidget);

    await tester.enterText(key('habit-name'), 'Drink more water');
    await tapVisible(tester, find.text('Per week'));
    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();

    final edited = repo.getHabit('h1')!;
    expect(edited.name, 'Drink more water');
    expect(edited.schedule, TimesPerWeekSchedule(3));
    expect(edited.createdAt, d(2026, 1, 1));
    expect(find.byType(HabitsScreen), findsOneWidget);
    expect(find.text('Drink more water'), findsOneWidget);
  });

  testWidgets('archives and unarchives from the edit screen', (tester) async {
    final repo = InMemoryHabitRepository(habits: [habit(id: 'h1')]);
    final c = await pumpHabitQuestApp(tester, repository: repo, clock: clock);
    final router = c.read(routerProvider);

    router.push('/habits/h1/edit');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1')!.archived, isTrue);
    expect(find.text('Archived (1)'), findsOneWidget);

    router.push('/habits/h1/edit');
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Unarchive'));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1')!.archived, isFalse);
  });

  testWidgets('deletes a habit after confirmation', (tester) async {
    final repo = InMemoryHabitRepository(
      habits: [habit(id: 'h1')],
      completions: {
        'h1': [d(2026, 1, 4)],
      },
    );
    final c = await pumpHabitQuestApp(tester, repository: repo, clock: clock);
    final router = c.read(routerProvider);
    router.push('/habits/h1');
    await tester.pumpAndSettle();
    router.push('/habits/h1/edit');
    await tester.pumpAndSettle();

    // Cancel keeps it.
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Drink water”?'), findsOneWidget);
    await tester.tap(find.text('Keep it'));
    await tester.pumpAndSettle();
    expect(repo.getHabit('h1'), isNotNull);

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(key('confirm-delete'));
    await tester.pumpAndSettle();

    expect(repo.getHabit('h1'), isNull);
    expect(repo.getCompletions().totalFor('h1'), 0);
    expect(router.routerDelegate.currentConfiguration.uri.path, '/habits');
    expect(find.text('Your quest begins here'), findsOneWidget);
    expect(find.text('💧 Drink water deleted'), findsOneWidget);
  });

  testWidgets('editing an unknown habit shows the not-found state',
      (tester) async {
    final c = await pumpHabitQuestApp(tester, clock: clock);
    c.read(routerProvider).push('/habits/nope/edit');
    await tester.pumpAndSettle();
    expect(key('edit-habit-not-found'), findsOneWidget);
    expect(key('save-habit'), findsNothing);

    await tester.tap(find.text('Back to habits'));
    await tester.pumpAndSettle();
    expect(
      c.read(routerProvider).routerDelegate.currentConfiguration.uri.path,
      '/habits',
    );
  });
}
