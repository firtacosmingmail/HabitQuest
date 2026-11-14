import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/features/game/game_providers.dart';
import 'package:habit_quest/features/projects/data/project_repository.dart';
import 'package:habit_quest/features/projects/models/plan_task.dart';
import 'package:habit_quest/features/projects/models/target.dart';

import '../../helpers/test_app.dart';
import 'helpers.dart';

/// Wednesday 18 Nov 2026, 09:00.
DateTime clock() => DateTime(2026, 11, 18, 9);

const monFri = {1, 2, 3, 4, 5};

Finder key(String k) => find.byKey(ValueKey(k));

/// p1 "Content": t1 "5 videos" (in progress, due 30 Nov), plan task k1
/// (open, due today), action a1 Mon–Fri 10:00–13:00.
InMemoryProjectRepository seededRepo() => InMemoryProjectRepository(
  seed: ProjectRecords(
    projects: [project('p1', name: 'Content')],
    targets: [
      target(
        't1',
        title: '5 videos',
        deadline: DateTime(2026, 11, 30),
        status: TargetStatus.inProgress,
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
    ],
    actions: [
      weekly(
        'a1',
        targetId: 't1',
        days: monFri,
        created: createdOn(2026, 11, 1),
      ),
    ],
  ),
);

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

/// Scrolls [f] into view, taps it and lets the frame with the first
/// celebration render (without settling, which would run it to the end).
Future<void> tapAndPump(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  Future<ProviderContainer> pump(
    WidgetTester tester, {
    required String location,
  }) {
    tester.view.physicalSize = const Size(900, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    return pumpHabitQuestApp(
      tester,
      projectRepository: seededRepo(),
      clock: clock,
      initialLocation: location,
    );
  }

  testWidgets('project details: attending a session floats "+15 XP"', (
    tester,
  ) async {
    final c = await pump(tester, location: '/projects/p1');
    await tapAndPump(tester, key('attend-a1|2026-11-17'));
    expect(find.text('+15 XP'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 15);

    // Un-attending takes it back quietly.
    await tapAndPump(tester, key('attend-a1|2026-11-17'));
    expect(key('xp-float'), findsNothing);
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 0);
  });

  testWidgets('project details: target done floats "+50 XP" and toasts '
      'the achievements', (tester) async {
    final c = await pump(tester, location: '/projects/p1');
    await tester.tap(key('status-chip-t1'));
    await tester.pumpAndSettle();
    await tapAndPump(tester, key('status-option-done').last);
    expect(find.text('+50 XP'), findsOneWidget);

    await pumpUntilFound(tester, find.text('Bullseye'));
    expect(key('achievement-toast'), findsOneWidget);
    expect(find.text('🎯'), findsOneWidget);
    // Every target of p1 is done: the project badge follows.
    await pumpUntilFound(tester, find.text('Mission Complete'));
    expect(find.text('🏆'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 50);
  });

  testWidgets('target editor: finishing a plan task floats "+10 XP"', (
    tester,
  ) async {
    final c = await pump(tester, location: '/projects/p1/targets/t1');
    await tapAndPump(tester, key('plan-task-done-k1'));
    expect(find.text('+10 XP'), findsOneWidget);
    await pumpUntilFound(tester, find.text('Checked Off'));
    expect(key('achievement-toast'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 10);
  });

  testWidgets('calendar: checking off the day\'s task floats "+10 XP"', (
    tester,
  ) async {
    final c = await pump(tester, location: '/calendar');
    await tapAndPump(tester, key('calendar-task-check-k1'));
    expect(find.text('+10 XP'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 10);
  });

  testWidgets('calendar session sheet: attending floats "+15 XP" above the '
      'sheet', (tester) async {
    final c = await pump(tester, location: '/calendar');
    await tester.tap(key('calendar-mode-work-split'));
    await tester.pumpAndSettle();
    final block = key('session-block-a1|2026-11-16');
    await tester.ensureVisible(block);
    await tester.pumpAndSettle();
    await tester.tap(block);
    await tester.pumpAndSettle();
    expect(key('session-sheet'), findsOneWidget);

    await tester.tap(key('session-sheet-attend'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('+15 XP'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(c.read(gameProfileProvider).xp, 15);
  });
}
