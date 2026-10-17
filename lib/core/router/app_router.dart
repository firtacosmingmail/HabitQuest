import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/auth_callback.dart';
import '../../features/auth/auth_providers.dart';
import '../../features/auth/login_screen.dart';
import '../../features/auth/splash_screen.dart';
import '../../features/calendar/calendar_screen.dart';
import '../../features/habit_details/habit_details_screen.dart';
import '../../features/habits/habit_form_screen.dart';
import '../../features/habits/habits_screen.dart';
import '../../features/notifications/in_app_reminder.dart';
import '../../features/profile/profile_screen.dart';
import '../../features/quest/quest_screen.dart';
import '../../features/quotes/quotes_screen.dart';
import '../../features/quotes/saved_quotes_screen.dart';
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
///
/// The email confirmation deep link `habitquest://auth-callback?...` is
/// mapped to `/auth-callback?...`. Signed out it lands on the login screen
/// with the outcome; signed in, [onAuthCallback] is called (default: a
/// snackbar on [appScaffoldMessengerKey]) and the user stays where they were.
GoRouter createRouter({
  String initialLocation = AppRoutes.habits,
  AuthState Function()? authState,
  Listenable? refreshListenable,
  void Function(AuthCallbackResult result)? onAuthCallback,
}) {
  final rootNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'root');
  late final GoRouter router;

  // Signed in: report the outcome and stay on the current page.
  String authCallbackWhileSignedIn(Uri uri) {
    final result = AuthCallbackResult.fromQuery(uri.queryParameters);
    if (result != null) (onAuthCallback ?? showAuthCallbackSnackBar)(result);
    final current = router.routerDelegate.currentConfiguration;
    if (current.isEmpty) return AppRoutes.habits;
    final location = current.uri;
    final path = location.path;
    if (path == AppRoutes.authCallback ||
        path == AppRoutes.login ||
        path == AppRoutes.splash) {
      return AppRoutes.habits;
    }
    return location.toString();
  }

  router = GoRouter(
    navigatorKey: rootNavigatorKey,
    initialLocation: initialLocation,
    refreshListenable: refreshListenable,
    redirect: (context, state) {
      final deepLink = deepLinkLocation(state.uri);
      if (deepLink != null) return deepLink;
      if (authState == null) return null;
      return authRedirect(authState(), state.uri);
    },
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
        builder: (_, state) => LoginScreen(
          // Keyed so a new confirmation outcome rebuilds the screen state.
          key: ValueKey('login-${state.uri.query}'),
          callback: AuthCallbackResult.fromQuery(state.uri.queryParameters),
        ),
      ),
      GoRoute(path: AppRoutes.splash, builder: (_, _) => const SplashScreen()),
      // Full screen above the bottom navigation (from the Quest header).
      GoRoute(
        path: AppRoutes.profile,
        builder: (_, _) => const ProfileScreen(),
      ),
      // Full screen (from the Habits quote card, Profile and the widgets).
      GoRoute(
        path: AppRoutes.quotes,
        builder: (_, _) => const QuotesScreen(),
        routes: [
          GoRoute(path: 'saved', builder: (_, _) => const SavedQuotesScreen()),
        ],
      ),
      // Never rendered: signed out the auth gate sends it to /login with the
      // outcome; signed in (or without a gate) this redirect handles it.
      GoRoute(
        path: AppRoutes.authCallback,
        redirect: (_, state) => authState?.call() is SignedIn
            ? authCallbackWhileSignedIn(state.uri)
            : loginWithCallback(state.uri),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
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
                    builder: (_, state) => HabitDetailsScreen(
                      habitId: state.pathParameters['id']!,
                    ),
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
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.calendar,
                builder: (_, _) => const CalendarScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: AppRoutes.quest,
                builder: (_, _) => const QuestScreen(),
              ),
            ],
          ),
        ],
      ),
    ],
  );
  return router;
}

/// Shows the email confirmation outcome as an app-wide snackbar (after the
/// current frame, since this runs during routing).
void showAuthCallbackSnackBar(AuthCallbackResult result) {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    appScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        key: const ValueKey('auth-callback-snackbar'),
        content: Text(result.snackText),
      ),
    );
  });
  WidgetsBinding.instance.ensureVisualUpdate();
}

/// Builds the app router with the auth gate wired to
/// [authControllerProvider] (go_router's `refreshListenable` follows it).
GoRouter createAppRouter(Ref ref, {String initialLocation = AppRoutes.habits}) {
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
