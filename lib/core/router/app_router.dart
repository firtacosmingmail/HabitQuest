import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/calendar/calendar_screen.dart';
import '../../features/habit_details/habit_details_screen.dart';
import '../../features/habits/habit_form_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/quest/quest_screen.dart';
import '../widgets/message_view.dart';
import 'app_routes.dart';
import 'app_shell.dart';

/// Builds the app's router. Detail and form routes are pushed on the root
/// navigator (full screen, above the bottom navigation).
GoRouter createRouter({String initialLocation = AppRoutes.habits}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    errorBuilder: (context, state) => Scaffold(
      appBar: AppBar(),
      body: MessageView(
        key: const ValueKey('route-not-found'),
        emoji: '🧭',
        title: 'Lost on the quest map',
        message: 'There is nothing at “${state.uri.path}”.',
        action: FilledButton.icon(
          onPressed: () => context.go(AppRoutes.habits),
          icon: const Icon(Icons.arrow_back_rounded),
          label: const Text('Back to habits'),
        ),
      ),
    ),
    routes: [
      GoRoute(path: '/', redirect: (_, _) => AppRoutes.habits),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.habits,
              builder: (_, _) => const HabitsScreen(),
              routes: [
                // 'new' must come before ':id'.
                GoRoute(
                  path: 'new',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, _) => const HabitFormScreen(),
                ),
                GoRoute(
                  path: ':id',
                  parentNavigatorKey: rootNavigatorKey,
                  builder: (_, state) =>
                      HabitDetailsScreen(habitId: state.pathParameters['id']!),
                  routes: [
                    GoRoute(
                      path: 'edit',
                      parentNavigatorKey: rootNavigatorKey,
                      builder: (_, state) => HabitFormScreen(
                        habitId: state.pathParameters['id']!,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.calendar,
              builder: (_, _) => const CalendarScreen(),
            ),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(
              path: AppRoutes.quest,
              builder: (_, _) => const QuestScreen(),
            ),
          ]),
        ],
      ),
    ],
  );
}

/// The app's [GoRouter]; override in tests to start elsewhere.
final routerProvider = Provider<GoRouter>((ref) {
  final router = createRouter();
  ref.onDispose(router.dispose);
  return router;
});
