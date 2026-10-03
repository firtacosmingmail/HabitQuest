import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/features/calendar/calendar_screen.dart';
import 'package:habit_quest/features/habit_details/habit_details_screen.dart';
import 'package:habit_quest/features/habits/habit_form_screen.dart';
import 'package:habit_quest/features/habits/habits_screen.dart';
import 'package:habit_quest/features/quest/quest_screen.dart';

import 'helpers/test_app.dart';

void main() {
  testWidgets('shell shows three tabs and switches between them',
      (tester) async {
    await pumpHabitQuestApp(tester);
    expect(find.byType(HabitsScreen), findsOneWidget);
    expect(find.byType(NavigationBar), findsOneWidget);

    await tester.tap(find.text('Calendar'));
    await tester.pumpAndSettle();
    expect(find.byType(CalendarScreen), findsOneWidget);

    await tester.tap(find.text('Quest'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestScreen), findsOneWidget);
  });

  testWidgets('/habits/new opens the create form', (tester) async {
    final c = await pumpHabitQuestApp(tester);
    c.read(routerProvider).push('/habits/new');
    await tester.pumpAndSettle();
    final form = tester.widget<HabitFormScreen>(find.byType(HabitFormScreen));
    expect(form.habitId, isNull);
    expect(find.byType(NavigationBar), findsNothing); // full screen
  });

  testWidgets('/habits/:id and /habits/:id/edit resolve', (tester) async {
    final c = await pumpHabitQuestApp(tester);
    final router = c.read(routerProvider);

    router.push('/habits/abc');
    await tester.pumpAndSettle();
    expect(
      tester.widget<HabitDetailsScreen>(find.byType(HabitDetailsScreen)).habitId,
      'abc',
    );

    router.push('/habits/abc/edit');
    await tester.pumpAndSettle();
    expect(
      tester.widget<HabitFormScreen>(find.byType(HabitFormScreen)).habitId,
      'abc',
    );
  });

  testWidgets('"/" redirects to /habits', (tester) async {
    final c = await pumpHabitQuestApp(tester, initialLocation: '/');
    expect(
      c.read(routerProvider).routerDelegate.currentConfiguration.uri.path,
      '/habits',
    );
    expect(find.byType(HabitsScreen), findsOneWidget);
    expect(GoRouter.of(tester.element(find.byType(HabitsScreen))), isNotNull);
  });
}
