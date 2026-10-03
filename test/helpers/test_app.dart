import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/app.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/theme/app_theme.dart';
import 'package:habit_quest/data/repositories/habit_repository.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';

/// Pumps the full app (router + shell) on an in-memory repository.
Future<ProviderContainer> pumpHabitQuestApp(
  WidgetTester tester, {
  HabitRepository? repository,
  DateTime Function()? clock,
  String initialLocation = '/habits',
}) async {
  final container = ProviderContainer(overrides: [
    habitRepositoryProvider
        .overrideWithValue(repository ?? InMemoryHabitRepository()),
    if (clock != null) clockProvider.overrideWithValue(clock),
    routerProvider.overrideWith((ref) {
      final router = createRouter(initialLocation: initialLocation);
      ref.onDispose(router.dispose);
      return router;
    }),
  ]);
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const HabitQuestApp(),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

/// Wraps a single widget with the app theme and a ProviderScope.
Widget wrapForTest(
  Widget child, {
  HabitRepository? repository,
  DateTime Function()? clock,
}) {
  return ProviderScope(
    overrides: [
      habitRepositoryProvider
          .overrideWithValue(repository ?? InMemoryHabitRepository()),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ],
    child: MaterialApp(theme: AppTheme.light, home: child),
  );
}
