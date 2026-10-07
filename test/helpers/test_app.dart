import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/app.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/theme/app_theme.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/session.dart';
import 'package:habit_quest/data/repositories/habit_repository.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/session_store.dart';

/// A session that never expires during a test.
final testSession = Session(
  accessToken: 'test-access',
  refreshToken: 'test-refresh',
  expiresAt: DateTime.utc(2100),
  user: const AuthUser(id: 'test-user', email: 'hero@example.com'),
);

/// A configured backend (tests have no SUPABASE_ANON_KEY dart-define).
final backendConfigOverride = backendConfigProvider.overrideWithValue(
  const BackendConfig(
    supabaseUrl: BackendConfig.defaultSupabaseUrl,
    anonKey: 'test-anon-key',
  ),
);

/// Overrides that start the app signed in as [session] (no storage read,
/// no refresh timer) on a [FakeAuthApi] and an [InMemorySessionStore].
List<Override> signedInOverrides({Session? session, FakeAuthApi? authApi}) {
  final s = session ?? testSession;
  return [
    authApiProvider.overrideWithValue(authApi ?? FakeAuthApi()),
    sessionStoreProvider.overrideWithValue(InMemorySessionStore(s)),
    authControllerProvider.overrideWith(
      () => AuthController(preloadedSession: s, proactiveRefresh: false),
    ),
  ];
}

/// Pumps the full app (router + shell + auth gate) on an in-memory
/// repository. Starts signed in unless [signedIn] is false (then pass your
/// own auth overrides in [overrides]).
Future<ProviderContainer> pumpHabitQuestApp(
  WidgetTester tester, {
  HabitRepository? repository,
  DateTime Function()? clock,
  String initialLocation = '/habits',
  List<Override> overrides = const [],
  bool signedIn = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      ...overrides,
      if (signedIn) ...signedInOverrides(),
      habitRepositoryProvider.overrideWithValue(
        repository ?? InMemoryHabitRepository(),
      ),
      if (clock != null) clockProvider.overrideWithValue(clock),
      routerProvider.overrideWith(
        (ref) => createAppRouter(ref, initialLocation: initialLocation),
      ),
    ],
  );
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
  List<Override> overrides = const [],
}) {
  return ProviderScope(
    overrides: [
      ...overrides,
      habitRepositoryProvider.overrideWithValue(
        repository ?? InMemoryHabitRepository(),
      ),
      if (clock != null) clockProvider.overrideWithValue(clock),
    ],
    child: MaterialApp(theme: AppTheme.light, home: child),
  );
}
