import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/habit_details/habit_details_screen.dart';
import '../../features/habits/habit_form_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/quest/quest_screen.dart';
import '../widgets/message_view.dart';
import 'app_routes.dart';
import 'app_shell.dart';
import 'auth_redirect.dart';

/// Builds the app's router. Detail and form routes are pushed on the root
/// navigator (full screen, above the bottom navigation).
///
/// With [authState], every navigation goes through the auth gate
/// ([authRedirect]); [refreshListenable] should notify when it changes.
/// Without it there is no gate (routing-only tests).
GoRouter createRouter({
  String initialLocation = AppRoutes.habits,
  AuthState Function()? authState,
  Listenable? refreshListenable,
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  return GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: authState == null
        ? null
        : (context, state) => authRedirect(authState(), state.uri),
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
      GoRoute(
        path: AppRoutes.login,
        builder: (_, _) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.splash,
        builder: (_, _) => const SplashScreen(),
      ),
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

/// Builds the app router with the auth gate wired to
/// [authControllerProvider] (go_router's `refreshListenable` follows it).
GoRouter createAppRouter(
  Ref ref, {
  String initialLocation = AppRoutes.habits,
}) {
  final auth = ValueNotifier<AuthState>(ref.read(authControllerProvider));
  ref.listen(authControllerProvider, (_, next) => auth.value = next);
  final router = createRouter(
    initialLocation: initialLocation,
    authState: () => auth.value,
    refreshListenable: auth,
  );
  ref.onDispose(() {
    router.dispose();
    auth.dispose();
  });
  return router;
}

/// The app's [GoRouter]; override in tests to start elsewhere (see
/// [createAppRouter]).
final routerProvider = Provider<GoRouter>((ref) => createAppRouter(ref));
