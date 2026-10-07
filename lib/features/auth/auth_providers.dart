/// Riverpod wiring for the backend: config → HTTP → auth → data API.
///
/// Tests typically override [authApiProvider] (with `FakeAuthApi`),
/// [sessionStoreProvider] (with `InMemorySessionStore`) and/or
/// [authControllerProvider] (e.g. `AuthController(preloadedSession: ...)`
/// to start signed in), and [habitQuestApiProvider] (with
/// `FakeHabitQuestApi`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../core/config/backend_config.dart';
import '../../data/remote/api_transport.dart';
import '../../data/remote/auth_api.dart';
import '../../data/remote/authenticated_transport.dart';
import '../../data/remote/habit_quest_api.dart';
import '../../data/remote/http_auth_api.dart';
import '../../data/remote/http_habit_quest_api.dart';
import 'auth_controller.dart';
import 'session_store.dart';

export 'auth_controller.dart';

/// The shared HTTP client.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Unauthenticated JSON transport to the Edge Functions.
final apiTransportProvider = Provider<ApiTransport>(
  (ref) => ApiTransport(
    client: ref.watch(httpClientProvider),
    config: ref.watch(backendConfigProvider),
  ),
);

final authApiProvider = Provider<AuthApi>(
  (ref) => HttpAuthApi(ref.watch(apiTransportProvider)),
);

final sessionStoreProvider = Provider<SessionStore>(
  (ref) => SecureSessionStore(),
);

/// The auth session state machine (unknown → signedIn / signedOut).
final authControllerProvider = NotifierProvider<AuthController, AuthState>(
  AuthController.new,
);

/// The data API for the signed-in user (tokens + 401 refresh/retry handled).
final habitQuestApiProvider = Provider<HabitQuestApi>(
  (ref) => HttpHabitQuestApi(
    AuthenticatedTransport(
      transport: ref.watch(apiTransportProvider),
      tokens: ref.watch(authControllerProvider.notifier),
    ),
  ),
);
