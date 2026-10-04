import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/features/game/game_providers.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/quest/quest_screen.dart';

import '../../helpers/fixtures.dart';
import '../../helpers/test_app.dart';

/// Monday 2026-01-05, 09:00.
DateTime clock() => DateTime(2026, 1, 5, 9);

/// Pumps 100 ms frames until [finder] matches (or [max] elapses).
Future<void> pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  Duration max = const Duration(seconds: 6),
}) async {
  var waited = Duration.zero;
  while (finder.evaluate().isEmpty && waited < max) {
    await tester.pump(const Duration(milliseconds: 100));
    waited += const Duration(milliseconds: 100);
  }
}

void main() {
  Future<void> pumpApp(WidgetTester tester, {GameState? game}) =>
      pumpHabitQuestApp(
        tester,
        repository: InMemoryHabitRepository(habits: [habit(id: 'h1')]),
        clock: clock,
        overrides: [
          if (game != null)
            gameRepositoryProvider.overrideWithValue(
              InMemoryGameRepository(game),
            ),
        ],
      );

  testWidgets('a check-in on the Habits screen floats "+N XP"', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('checkin-h1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    // 10 XP + 1 streak day.
    expect(find.text('+11 XP'), findsOneWidget);

    // Queued: the Perfect Day bonus follows once the first float is done.
    await pumpUntilFound(tester, find.text('+25 XP'));
    expect(find.text('+25 XP'), findsOneWidget);
    expect(find.text('+11 XP'), findsNothing);

    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('xp-float')), findsNothing);
  });

  testWidgets('an unlocked achievement shows a toast', (tester) async {
    await pumpApp(tester);

    await tester.tap(find.byKey(const ValueKey('checkin-h1')));
    await tester.pump();
    await pumpUntilFound(tester, find.text('First Step'));
    expect(find.byKey(const ValueKey('achievement-toast')), findsOneWidget);
    expect(find.text('Achievement unlocked!'), findsOneWidget);
    expect(find.text('👣'), findsOneWidget);

    // Toasts are queued one at a time; all are gone once settled.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('achievement-toast')), findsNothing);
  });

  testWidgets('a level-up shows confetti and the level-up dialog', (
    tester,
  ) async {
    await pumpApp(
      tester,
      game: GameState(checkInLedger: const {'seed|2025-12-01': 90}),
    );
    expect(find.text('Lv 1 · Sprout'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('checkin-h1')));
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(const ValueKey('level-up-dialog')));
    expect(find.byKey(const ValueKey('confetti')), findsOneWidget);
    expect(find.text('Level up!'), findsOneWidget);
    expect(find.text('Level 2'), findsOneWidget);
    expect(find.text('You are now a Sprout!'), findsOneWidget);

    // The dialog waits for the player; confetti finishes on its own.
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('level-up-dialog')), findsOneWidget);
    expect(find.byKey(const ValueKey('confetti')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('level-up-dismiss')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('level-up-dialog')), findsNothing);
    expect(find.text('Lv 2 · Sprout'), findsOneWidget);
  });

  testWidgets('reduced motion skips the confetti', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpApp(
      tester,
      game: GameState(checkInLedger: const {'seed|2025-12-01': 95}),
    );

    await tester.tap(find.byKey(const ValueKey('checkin-h1')));
    await tester.pump();
    await pumpUntilFound(tester, find.byKey(const ValueKey('level-up-dialog')));
    expect(find.text('Level up!'), findsOneWidget);
    expect(find.byKey(const ValueKey('confetti')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('level-up-dismiss')));
    await tester.pumpAndSettle();
  });

  testWidgets('the level chip shows in the header and opens the Quest tab', (
    tester,
  ) async {
    await pumpApp(
      tester,
      // 350 XP → level 3 (Seeker), 50/300.
      game: GameState(
        checkInLedger: const {'seed|2025-12-01': 350},
        maxLevelReached: 3,
      ),
    );

    final chip = find.byKey(const ValueKey('level-chip'));
    expect(chip, findsOneWidget);
    expect(find.text('Lv 3 · Seeker'), findsOneWidget);
    final ring = tester.widget<CircularProgressIndicator>(
      find.descendant(
        of: chip,
        matching: find.byType(CircularProgressIndicator),
      ),
    );
    expect(ring.value, closeTo(50 / 300, 1e-9));

    await tester.tap(chip);
    await tester.pumpAndSettle();
    expect(find.byType(QuestScreen), findsOneWidget);
    expect(find.text('Level 3'), findsOneWidget);
  });
}
