// End-to-end flows through the full app (router, shell, game engine):
// whichever screen a check-in comes from, streaks, XP and the calendar must
// agree, because every screen goes through HabitService.toggleCompletion.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/game/game_providers.dart';
import 'package:habit_quest/features/habit_details/widgets/habit_month_calendar.dart';
import 'package:habit_quest/features/habits/widgets/habit_card.dart';

import '../helpers/fixtures.dart';
import '../helpers/test_app.dart';

/// Monday 2026-01-05, 09:00.
DateTime clock() => DateTime(2026, 1, 5, 9);

Finder key(String k) => find.byKey(ValueKey(k));

void main() {
  Future<ProviderContainer> pumpApp(
    WidgetTester tester, {
    InMemoryHabitRepository? repo,
  }) {
    tester.view.physicalSize = const Size(900, 2200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return pumpHabitQuestApp(tester, repository: repo, clock: clock);
  }

  Future<void> goToTab(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool cardCompleted(WidgetTester tester, String id) =>
      tester.widget<HabitCard>(key('habit-card-$id')).completed;

  String text(WidgetTester tester, String k) =>
      tester.widget<Text>(key(k)).data!;

  testWidgets('create a habit, check in: XP, streak and Quest profile update',
      (tester) async {
    final repo = InMemoryHabitRepository();
    final c = await pumpApp(tester, repo: repo);

    await tester.tap(key('empty-create-habit'));
    await tester.pumpAndSettle();
    await tester.enterText(key('habit-name'), 'Stretch');
    await tester.tap(key('save-habit'));
    await tester.pumpAndSettle();

    final id = repo.getHabits().single.id;
    expect(key('habit-card-$id'), findsOneWidget);
    expect(text(tester, 'today-progress'), '0/1 done');

    await tester.tap(key('checkin-$id'));
    await tester.pumpAndSettle();

    expect(cardCompleted(tester, id), isTrue);
    expect(text(tester, 'today-progress'), '1/1 done');
    expect(c.read(streakProvider(id))!.current, 1);
    expect(
      find.descendant(of: key('habit-card-$id'), matching: find.text('1 day')),
      findsOneWidget,
    );
    // 10 XP + 1 streak day, plus 25 for the Perfect Day (only habit due).
    final profile = c.read(gameProfileProvider);
    expect(profile.xp, 36);
    expect(profile.stats.totalCheckIns, 1);
    expect(profile.stats.perfectDays, 1);

    await goToTab(tester, 'Quest');
    expect(text(tester, 'hero-xp'), '36 / 100 XP');
    expect(
      find.descendant(of: key('stat-check-ins'), matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'check-ins from the calendar and the details screen show up on the '
      'Habits screen and in the Quest profile', (tester) async {
    final repo = InMemoryHabitRepository(
      habits: [habit(id: 'h1', startDate: d(2026, 1, 1))],
    );
    final c = await pumpApp(tester, repo: repo);

    // Today, from the Calendar tab (today is selected by default).
    await goToTab(tester, 'Calendar');
    await tester.tap(key('calendar-toggle-h1'));
    await tester.pumpAndSettle();
    expect(text(tester, 'calendar-selected-progress'), '⭐ Perfect!');
    expect(key('perfect-day-2026-01-05'), findsOneWidget);
    expect(c.read(gameProfileProvider).xp, 36);

    // Back on Habits: checked in, streak 1.
    await goToTab(tester, 'Habits');
    expect(cardCompleted(tester, 'h1'), isTrue);
    expect(text(tester, 'today-progress'), '1/1 done');

    // Yesterday, from the details heatmap: the streak grows to 2.
    c.read(routerProvider).push('/habits/h1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(habitCalendarDayKey(d(2026, 1, 4))));
    await tester.pumpAndSettle();
    expect(repo.getCompletions().isCompleted('h1', d(2026, 1, 4)), isTrue);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: key('habit-card-h1'), matching: find.text('2 days')),
      findsOneWidget,
    );

    // Jan 4: streak 1 → 11 XP + 25 Perfect Day.
    final profile = c.read(gameProfileProvider);
    expect(profile.xp, 72);
    expect(profile.stats.totalCheckIns, 2);
    expect(profile.stats.perfectDays, 2);
    expect(profile.stats.bestStreakEver, 2);

    // The calendar shows the past Perfect Day too.
    await goToTab(tester, 'Calendar');
    expect(key('perfect-day-2026-01-04'), findsOneWidget);

    await goToTab(tester, 'Quest');
    expect(text(tester, 'hero-xp'), '72 / 100 XP');
    expect(
      find.descendant(of: key('stat-perfect-days'), matching: find.text('2')),
      findsOneWidget,
    );
  });

  testWidgets('un-checking reverses XP, and toggling again cannot farm XP',
      (tester) async {
    final repo = InMemoryHabitRepository(
      habits: [habit(id: 'h1', startDate: d(2026, 1, 1))],
    );
    final c = await pumpApp(tester, repo: repo);

    await tester.tap(key('checkin-h1'));
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 36);

    // Undo today from the details screen.
    c.read(routerProvider).push('/habits/h1');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(habitCalendarDayKey(d(2026, 1, 5))));
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 0);
    expect(c.read(gameProfileProvider).stats.totalCheckIns, 0);
    expect(c.read(gameProfileProvider).stats.perfectDays, 0);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(cardCompleted(tester, 'h1'), isFalse);
    expect(text(tester, 'today-progress'), '0/1 done');

    // On again from the calendar, off again from Habits: never more than
    // the one check-in is worth.
    await goToTab(tester, 'Calendar');
    await tester.tap(key('calendar-toggle-h1'));
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 36);

    await goToTab(tester, 'Habits');
    await tester.tap(key('checkin-h1'));
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 0);
    expect(repo.getCompletions().totalFor('h1'), 0);
  });
}
