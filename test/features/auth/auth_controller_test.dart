import 'dart:convert';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/session.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final t0 = DateTime.utc(2026, 10, 7, 9);

Session sessionExpiringAt(DateTime exp, {String n = 'saved'}) => Session(
  accessToken: 'access-$n',
  refreshToken: 'refresh-$n',
  expiresAt: exp,
  user: const AuthUser(id: 'u1', email: 'hero@example.com'),
);

ProviderContainer makeContainer({
  required FakeAuthApi api,
  required SessionStore store,
  required DateTime Function() clock,
}) {
  final c = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(api),
      sessionStoreProvider.overrideWithValue(store),
      clockProvider.overrideWithValue(clock),
    ],
  );
  // Keep the controller alive (it is not auto-dispose, but listen anyway).
  c.listen(authControllerProvider, (_, _) {});
  return c;
}

void main() {
  group('restore', () {
    test('no stored session → unknown, then signedOut', () async {
      final c = makeContainer(
        api: FakeAuthApi(now: () => t0),
        store: InMemorySessionStore(),
        clock: () => t0,
      );
      addTearDown(c.dispose);
      expect(c.read(authControllerProvider), isA<AuthUnknown>());
      await pumpEventQueue();
      final s = c.read(authControllerProvider);
      expect(s, isA<SignedOut>());
      expect((s as SignedOut).reason, isNull);
    });

    test('stored session → signedIn without a network call', () async {
      final api = FakeAuthApi(now: () => t0);
      final saved = sessionExpiringAt(t0.add(const Duration(hours: 1)));
      final c = makeContainer(
        api: api,
        store: InMemorySessionStore(saved),
        clock: () => t0,
      );
      addTearDown(c.dispose);
      await pumpEventQueue();
      expect(c.read(authControllerProvider.notifier).session, saved);
      expect(api.calls, isEmpty);
    });
  });

  group('login / register / logout', () {
    late FakeAuthApi api;
    late InMemorySessionStore store;
    late ProviderContainer c;

    setUp(() async {
      api = FakeAuthApi(now: () => t0)..addUser('hero@example.com', 'secret1');
      store = InMemorySessionStore();
      c = makeContainer(api: api, store: store, clock: () => t0);
      await pumpEventQueue();
    });

    tearDown(() => c.dispose());

    test('login stores the session and signs in', () async {
      await c
          .read(authControllerProvider.notifier)
          .login(email: ' hero@example.com ', password: 'secret1');
      final s = c.read(authControllerProvider);
      expect(s, isA<SignedIn>());
      expect(store.session, (s as SignedIn).session);
    });

    test('bad credentials throw and stay signed out', () async {
      await expectLater(
        c
            .read(authControllerProvider.notifier)
            .login(email: 'hero@example.com', password: 'nope'),
        throwsA(isA<ApiException>()),
      );
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(store.session, isNull);
    });

    test('register signs in, or reports needsConfirmation', () async {
      final ctrl = c.read(authControllerProvider.notifier);
      final r = await ctrl.register(email: 'new@example.com', password: 'abcdef');
      expect(r.needsConfirmation, isFalse);
      expect(c.read(authControllerProvider), isA<SignedIn>());

      await ctrl.logout();
      api.requireConfirmation = true;
      final r2 = await ctrl.register(
        email: 'other@example.com',
        password: 'abcdef',
      );
      expect(r2.needsConfirmation, isTrue);
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(store.session, isNull);
    });

    test('logout clears the store and calls the server', () async {
      final ctrl = c.read(authControllerProvider.notifier);
      await ctrl.login(email: 'hero@example.com', password: 'secret1');
      final token = ctrl.session!.accessToken;
      await ctrl.logout();
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(store.session, isNull);
      expect(api.calls.last, 'logout');
      expect(api.isAccessTokenLive(token), isFalse);
    });

    test('logout works offline', () async {
      final ctrl = c.read(authControllerProvider.notifier);
      await ctrl.login(email: 'hero@example.com', password: 'secret1');
      api.offline = true;
      await ctrl.logout();
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(store.session, isNull);
    });
  });

  group('proactive refresh (fake_async)', () {
    test('refreshes ~60s before expiry and keeps refreshing', () {
      fakeAsync((async) {
        DateTime now() => t0.add(async.elapsed);
        final api = FakeAuthApi(now: now);
        final saved = api.issueSession('hero@example.com');
        final store = InMemorySessionStore(saved);
        final c = makeContainer(api: api, store: store, clock: now);
        async.flushMicrotasks();
        expect(c.read(authControllerProvider.notifier).session, saved);

        // 1h token: nothing before 59 minutes.
        async.elapse(const Duration(minutes: 58, seconds: 59));
        expect(api.calls, isEmpty);

        async.elapse(const Duration(seconds: 2));
        expect(api.calls, ['refresh']);
        final fresh = c.read(authControllerProvider.notifier).session!;
        expect(fresh.accessToken, isNot(saved.accessToken));
        expect(store.session, fresh);

        // The next one is scheduled from the new expiry.
        async.elapse(const Duration(minutes: 59, seconds: 1));
        expect(api.calls, ['refresh', 'refresh']);
        c.dispose();
        expect(async.pendingTimers, isEmpty);
      });
    });

    test('an already expired stored session is refreshed at once', () {
      fakeAsync((async) {
        DateTime now() => t0.add(async.elapsed);
        final api = FakeAuthApi(now: now);
        final saved = api.issueSession('hero@example.com');
        final expired = Session(
          accessToken: saved.accessToken,
          refreshToken: saved.refreshToken,
          expiresAt: t0.subtract(const Duration(minutes: 5)),
          user: saved.user,
        );
        final c = makeContainer(
          api: api,
          store: InMemorySessionStore(expired),
          clock: now,
        );
        async.flushMicrotasks();
        async.elapse(Duration.zero);
        expect(api.calls, ['refresh']);
        expect(c.read(authControllerProvider), isA<SignedIn>());
        c.dispose();
      });
    });

    test('a rejected refresh signs out with a reason', () {
      fakeAsync((async) {
        DateTime now() => t0.add(async.elapsed);
        final api = FakeAuthApi(now: now);
        final saved = api.issueSession('hero@example.com');
        final store = InMemorySessionStore(saved);
        final c = makeContainer(api: api, store: store, clock: now);
        async.flushMicrotasks();
        api.revokeAll();
        async.elapse(const Duration(hours: 1));
        final s = c.read(authControllerProvider);
        expect(s, isA<SignedOut>());
        expect(
          (s as SignedOut).reason,
          AuthController.sessionExpiredMessage,
        );
        expect(store.session, isNull);
        c.dispose();
      });
    });

    test('offline refresh keeps the session and retries after 30s', () {
      fakeAsync((async) {
        DateTime now() => t0.add(async.elapsed);
        final api = FakeAuthApi(now: now);
        final saved = api.issueSession('hero@example.com');
        final c = makeContainer(
          api: api,
          store: InMemorySessionStore(saved),
          clock: now,
        );
        async.flushMicrotasks();
        api.offline = true;
        async.elapse(const Duration(minutes: 59, seconds: 1));
        expect(api.calls, ['refresh']);
        expect(c.read(authControllerProvider), isA<SignedIn>());

        api.offline = false;
        async.elapse(AuthController.retryDelay);
        expect(api.calls, ['refresh', 'refresh']);
        expect(
          c.read(authControllerProvider.notifier).session!.accessToken,
          isNot(saved.accessToken),
        );
        c.dispose();
      });
    });

    test('logout cancels the refresh timer', () {
      fakeAsync((async) {
        DateTime now() => t0.add(async.elapsed);
        final api = FakeAuthApi(now: now);
        final c = makeContainer(
          api: api,
          store: InMemorySessionStore(api.issueSession('hero@example.com')),
          clock: now,
        );
        async.flushMicrotasks();
        c.read(authControllerProvider.notifier).logout();
        async.flushMicrotasks();
        expect(async.pendingTimers, isEmpty);
        async.elapse(const Duration(hours: 2));
        expect(api.calls, ['logout']);
        c.dispose();
      });
    });
  });

  group('HabitQuestApi through the AuthController (MockClient server)', () {
    late List<http.Request> requests;
    late bool refreshAccepted;
    late String validToken;
    late InMemorySessionStore store;
    late ProviderContainer c;

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    setUp(() async {
      requests = [];
      refreshAccepted = true;
      validToken = 'access-new';
      store = InMemorySessionStore(
        sessionExpiringAt(t0.add(const Duration(hours: 1)), n: 'old'),
      );
      final client = MockClient((r) async {
        requests.add(r);
        final fn = r.url.pathSegments[2];
        if (fn == 'auth-refresh') {
          if (!refreshAccepted) {
            return json({
              'error': {'code': 'invalid_refresh_token', 'message': 'x'},
            }, 401);
          }
          return json({
            'session': {
              'accessToken': 'access-new',
              'refreshToken': 'refresh-new',
              'expiresAt':
                  t0.add(const Duration(hours: 2)).millisecondsSinceEpoch ~/
                  1000,
              'user': {'id': 'u1', 'email': 'hero@example.com'},
            },
          });
        }
        if (r.headers['authorization'] != 'Bearer $validToken') {
          return json({
            'error': {'code': 'unauthorized', 'message': 'expired'},
          }, 401);
        }
        return json({'items': [], 'serverTime': '2026-10-07T10:00:00.000Z'});
      });
      c = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(client),
          backendConfigProvider.overrideWithValue(
            const BackendConfig(supabaseUrl: 'https://p.co', anonKey: 'anon'),
          ),
          sessionStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => t0),
          authControllerProvider.overrideWith(
            () => AuthController(proactiveRefresh: false),
          ),
        ],
      );
      c.listen(authControllerProvider, (_, _) {});
      await pumpEventQueue();
    });

    tearDown(() => c.dispose());

    test('401 → refresh → retry succeeds and stores the new session',
        () async {
      final page = await c.read(habitQuestApiProvider).listHabits();
      expect(page.items, isEmpty);
      expect(
        requests.map((r) => r.url.pathSegments.last),
        ['habits', 'auth-refresh', 'habits'],
      );
      expect(requests.first.headers['authorization'], 'Bearer access-old');
      expect(requests.last.headers['authorization'], 'Bearer access-new');
      expect(store.session!.accessToken, 'access-new');
    });

    test('concurrent 401s share a single refresh', () async {
      final api = c.read(habitQuestApiProvider);
      await Future.wait([api.listHabits(), api.listCheckIns()]);
      expect(
        requests.where((r) => r.url.pathSegments.last == 'auth-refresh'),
        hasLength(1),
      );
    });

    test('refresh failure signs out and surfaces the 401', () async {
      refreshAccepted = false;
      await expectLater(
        c.read(habitQuestApiProvider).listHabits(),
        throwsA(isA<ApiException>().having((e) => e.isUnauthorized, 'u', true)),
      );
      expect(c.read(authControllerProvider), isA<SignedOut>());
      expect(store.session, isNull);
      expect(
        requests.map((r) => r.url.pathSegments.last),
        ['habits', 'auth-refresh'],
      );
    });

    test('an expired token is refreshed before the request', () async {
      c.dispose();
      store.session = sessionExpiringAt(t0, n: 'old'); // expired
      c = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            MockClient((r) async {
              requests.add(r);
              return r.url.pathSegments.last == 'auth-refresh'
                  ? json({
                      'session': {
                        'accessToken': 'access-new',
                        'refreshToken': 'refresh-new',
                        'expiresAt': 1891364500,
                        'user': {'id': 'u1', 'email': 'e@x.y'},
                      },
                    })
                  : json({'items': [], 'serverTime': '2026-10-07T10:00:00Z'});
            }),
          ),
          backendConfigProvider.overrideWithValue(
            const BackendConfig(supabaseUrl: 'https://p.co', anonKey: 'anon'),
          ),
          sessionStoreProvider.overrideWithValue(store),
          clockProvider.overrideWithValue(() => t0),
          authControllerProvider.overrideWith(
            () => AuthController(proactiveRefresh: false),
          ),
        ],
      );
      requests.clear();
      await c.read(habitQuestApiProvider).listHabits();
      expect(
        requests.map((r) => r.url.pathSegments.last),
        ['auth-refresh', 'habits'],
      );
      expect(requests.last.headers['authorization'], 'Bearer access-new');
    });
  });
}
