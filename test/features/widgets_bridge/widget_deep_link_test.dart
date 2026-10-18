// Regression test for the widget deep-link replay bug (Android, Galaxy S24
// Ultra): after opening the Quotes screen from the Daily quote widget, going
// back and opening the app again from the launcher showed Quotes again.
//
// Cause: the widget link replaced the whole route stack with `/quotes`, so
// Back had nothing to pop, Android 12+ moved the still-alive activity to the
// background showing Quotes, and the launcher resumed it there. A widget
// link must now be consumed by one navigation that stacks Quotes on Habits.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/router/app_routes.dart';
import 'package:habit_quest/features/habits/habits_screen.dart';
import 'package:habit_quest/features/quotes/quotes_screen.dart';
import 'package:habit_quest/features/widgets_bridge/widget_constants.dart';

import '../../helpers/test_app.dart';

/// Delivers [link] the way the engine does for a platform deep link
/// (Android `onNewIntent`, iOS `openURL`).
Future<void> openPlatformLink(WidgetTester tester, String link) async {
  final message = SystemChannels.navigation.codec.encodeMethodCall(
    MethodCall('pushRouteInformation', {'location': link, 'state': null}),
  );
  await tester.binding.defaultBinaryMessenger
      .handlePlatformMessage('flutter/navigation', message, (_) {});
  await tester.pumpAndSettle();
}

/// The app goes to the background and comes back (launcher start that
/// resumes the same activity).
Future<void> backgroundAndResume(WidgetTester tester) async {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('quote widget link opens Quotes once; Back and a later launch '
      'show Habits', (tester) async {
    final c = await pumpHabitQuestApp(tester);
    final router = c.read(routerProvider);

    await openPlatformLink(tester, WidgetConstants.quotesUri);
    expect(find.byType(QuotesScreen), findsOneWidget);
    expect(router.state.uri.path, AppRoutes.habitsQuotes);
    // Habits is underneath: Back pops to it instead of leaving the app.
    expect(router.canPop(), isTrue);

    final popped = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(popped, isTrue, reason: 'Back is handled in the app');
    expect(find.byType(QuotesScreen), findsNothing);
    expect(find.byType(HabitsScreen), findsOneWidget);

    // Background + launcher start: the link is not replayed.
    await backgroundAndResume(tester);
    expect(find.byType(QuotesScreen), findsNothing);
    expect(router.state.uri.path, AppRoutes.habits);
  });

  testWidgets('a second widget tap while the app is open works again',
      (tester) async {
    final c = await pumpHabitQuestApp(tester);
    final router = c.read(routerProvider);

    await openPlatformLink(tester, WidgetConstants.quotesUri);
    await openPlatformLink(tester, WidgetConstants.quotesUri);
    expect(find.byType(QuotesScreen), findsOneWidget);
    expect(router.state.uri.path, AppRoutes.habitsQuotes);

    // Header / "Open HabitQuest" link from Quotes: back to Habits.
    await openPlatformLink(tester, WidgetConstants.openUri);
    expect(find.byType(QuotesScreen), findsNothing);
    expect(router.state.uri.path, AppRoutes.habits);
    expect(router.canPop(), isFalse);
  });

  testWidgets('cold start from the quote widget stacks Quotes on Habits',
      (tester) async {
    final c = await pumpHabitQuestApp(
      tester,
      initialLocation: WidgetConstants.quotesUri,
    );
    final router = c.read(routerProvider);
    expect(find.byType(QuotesScreen), findsOneWidget);
    expect(router.canPop(), isTrue);
    router.pop();
    await tester.pumpAndSettle();
    expect(router.state.uri.path, AppRoutes.habits);
  });
}
