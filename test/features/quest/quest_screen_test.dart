import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/game/achievements.dart';
import 'package:habit_quest/features/game/game_providers.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/quest/quest_screen.dart';

import '../../helpers/test_app.dart';

DateTime clock() => DateTime(2026, 1, 5, 9);

void main() {
  Future<void> pumpQuest(WidgetTester tester, GameState state) async {
    tester.view.physicalSize = const Size(420, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await pumpHabitQuestApp(
      tester,
      clock: clock,
      initialLocation: '/quest',
      overrides: [
        gameRepositoryProvider.overrideWithValue(InMemoryGameRepository(state)),
      ],
    );
  }

  testWidgets('renders profile, stats and locked/unlocked badges', (
    tester,
  ) async {
    await pumpQuest(
      tester,
      GameState(
        // 150 + 155 + 25 = 330 XP → level 3 (starts at 300), 30/300.
        checkInLedger: const {'a|2026-01-01': 150, 'a|2026-01-02': 155},
        perfectDayLedger: const {'2026-01-02': 25},
        unlocked: {
          AchievementIds.firstCheckIn: DateTime(2026, 1, 2, 10),
          AchievementIds.firstPerfectDay: DateTime(2026, 1, 2, 10),
        },
        bestStreakEver: 2,
        maxLevelReached: 3,
      ),
    );

    expect(find.byType(QuestScreen), findsOneWidget);
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('Seeker'), findsOneWidget);
    expect(find.text('🧭'), findsWidgets);
    expect(find.text('30 / 300 XP'), findsOneWidget);
    expect(find.text('330 XP total'), findsOneWidget);
    final bar = tester.widget<LinearProgressIndicator>(
      find.byKey(const ValueKey('xp-bar')),
    );
    expect(bar.value, closeTo(0.1, 1e-9));

    String statValue(String key) => tester
        .widgetList<Text>(
          find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Text),
          ),
        )
        .map((t) => t.data)
        .join('|');
    expect(statValue('stat-check-ins'), contains('|2|'));
    expect(statValue('stat-best-streak'), contains('|2|'));
    expect(statValue('stat-perfect-days'), contains('|1|'));

    expect(find.text('2/${achievementCatalog.length}'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('badge-unlocked-first_check_in')),
      findsOneWidget,
    );
    expect(find.text('Jan 2, 2026'), findsNWidgets(2));
    expect(
      find.byKey(const ValueKey('badge-locked-streak_100')),
      findsOneWidget,
    );
    expect(find.text('Keep a habit going 100 times in a row.'), findsOneWidget);
    expect(find.byIcon(Icons.lock_rounded), findsNWidgets(10));

    expect(find.text('How to earn XP'), findsOneWidget);
    expect(find.text('10 XP for every check-in'), findsOneWidget);
    expect(find.text('+1 XP per streak period, up to +10'), findsOneWidget);
    expect(find.textContaining('+25 XP for a Perfect Day'), findsOneWidget);
  });

  testWidgets('tapping a badge opens its details sheet', (tester) async {
    await pumpQuest(
      tester,
      GameState(unlocked: {AchievementIds.firstHabit: DateTime(2026, 1, 3)}),
    );

    expect(find.text('Level 1'), findsOneWidget);
    expect(find.text('Sprout'), findsOneWidget);
    expect(find.text('0 / 100 XP'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('badge-unlocked-first_habit')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('achievement-sheet')), findsOneWidget);
    expect(find.text('Created your first habit.'), findsOneWidget);
    expect(find.text('Unlocked Jan 3, 2026'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('achievement-sheet')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('badge-locked-streak_7')));
    await tester.pumpAndSettle();
    expect(find.text('Locked'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('achievement-sheet')),
        matching: find.text('Keep a habit going 7 times in a row.'),
      ),
      findsOneWidget,
    );
  });
}
