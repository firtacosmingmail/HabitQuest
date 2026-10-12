import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/router/auth_redirect.dart';
import 'package:habit_quest/data/remote/fake_account_api.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/session.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/login_screen.dart';
import 'package:habit_quest/features/auth/oauth/fake_oauth_sign_in.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/auth/splash_screen.dart';
import 'package:habit_quest/features/habit_details/habit_details_screen.dart';
import 'package:habit_quest/features/habits/habits_screen.dart';
import 'package:habit_quest/features/profile/profile_screen.dart';
import 'package:habit_quest/features/quest/quest_screen.dart';

import '../../helpers/test_app.dart';

String path(ProviderContainer container) => container
    .read(routerProvider)
    .routerDelegate
    .currentConfiguration
    .uri
    .toString();

void main() {
  group('authRedirect', () {
    final signedIn = SignedIn(testSession);
    const out = SignedOut();
    const unknown = AuthUnknown();
    Uri u(String s) => Uri.parse(s);

    test('signed out → /login, keeping deep links', () {
      expect(authRedirect(out, u('/habits')), '/login');
      expect(authRedirect(out, u('/quest')), '/login?from=%2Fquest');
      expect(authRedirect(out, u('/login')), isNull);
      expect(
        authRedirect(out, u('/splash?from=%2Fquest')),
        '/login?from=%2Fquest',
      );
    });

    test('loading → splash', () {
      expect(authRedirect(unknown, u('/habits')), '/splash');
      expect(authRedirect(unknown, u('/splash')), isNull);
      expect(
        authRedirect(unknown, u('/habits/h1')),
        '/splash?from=%2Fhabits%2Fh1',
      );
    });

    test('signed in leaves the gate for /habits or the wanted page', () {
      expect(authRedirect(signedIn, u('/login')), '/habits');
      expect(authRedirect(signedIn, u('/splash')), '/habits');
      expect(authRedirect(signedIn, u('/login?from=%2Fquest')), '/quest');
      expect(authRedirect(signedIn, u('/habits')), isNull);
      // No open redirects.
      expect(
        authRedirect(signedIn, u('/login?from=https://evil.example')),
        '/habits',
      );
      expect(authRedirect(signedIn, u('/login?from=//evil')), '/habits');
    });
  });

  group('router gate (widgets)', () {
    testWidgets('signed out at launch → login screen', (tester) async {
      final c = await pumpHabitQuestApp(
        tester,
        signedIn: false,
        overrides: [
          authApiProvider.overrideWithValue(FakeAuthApi()),
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byType(HabitsScreen), findsNothing);
      expect(path(c), '/login');
    });

    testWidgets('splash while the session loads, then the app', (tester) async {
      final store = _SlowStore(testSession);
      final c = await pumpHabitQuestApp(
        tester,
        signedIn: false,
        initialLocation: '/habits/abc',
        overrides: [
          authApiProvider.overrideWithValue(FakeAuthApi()),
          sessionStoreProvider.overrideWithValue(store),
          authControllerProvider.overrideWith(
            () => AuthController(proactiveRefresh: false),
          ),
        ],
      );
      expect(find.byType(SplashScreen), findsOneWidget);
      expect(path(c), '/splash?from=%2Fhabits%2Fabc');

      store.release();
      await tester.pumpAndSettle();
      expect(find.byType(SplashScreen), findsNothing);
      expect(path(c), '/habits/abc');
      expect(find.byType(HabitDetailsScreen), findsOneWidget);
    });

    testWidgets('login → /habits; logout from Quest → Profile → /login', (
      tester,
    ) async {
      final api = FakeAuthApi()..addUser('hero@example.com', 'secret1');
      final store = InMemorySessionStore();
      final c = await pumpHabitQuestApp(
        tester,
        signedIn: false,
        overrides: [
          authApiProvider.overrideWithValue(api),
          accountApiProvider.overrideWithValue(FakeAccountApi()),
          sessionStoreProvider.overrideWithValue(store),
          authControllerProvider.overrideWith(
            () => AuthController(proactiveRefresh: false),
          ),
          backendConfigOverride,
        ],
      );
      expect(find.byType(LoginScreen), findsOneWidget);

      await tester.enterText(
        find.byKey(const ValueKey('auth-email')),
        'hero@example.com',
      );
      await tester.enterText(
        find.byKey(const ValueKey('auth-password')),
        'secret1',
      );
      await tester.tap(find.byKey(const ValueKey('auth-submit')));
      await tester.pumpAndSettle();
      expect(path(c), '/habits');
      expect(find.byType(HabitsScreen), findsOneWidget);
      expect(store.session, isNotNull);

      // Logout: cancel first, then confirm.
      await tester.tap(find.text('Quest'));
      await tester.pumpAndSettle();
      expect(find.byType(QuestScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('profile-button')));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('logout-button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('logout-dialog')), findsOneWidget);
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileScreen), findsOneWidget);
      expect(store.session, isNotNull);

      await tester.tap(find.byKey(const ValueKey('logout-button')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('confirm-logout')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(store.session, isNull);
      expect(api.calls.last, 'logout');
    });

    testWidgets('a session expiring mid-use sends the user to login', (
      tester,
    ) async {
      final c = await pumpHabitQuestApp(tester);
      expect(find.byType(HabitsScreen), findsOneWidget);
      await c.read(authControllerProvider.notifier).logout();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
    });

    for (final provider in OAuthProvider.values) {
      testWidgets('tap ${provider.label} → signed in via the fake → /habits', (
        tester,
      ) async {
        final api = FakeAuthApi();
        final store = InMemorySessionStore();
        final c = await pumpHabitQuestApp(
          tester,
          signedIn: false,
          overrides: [
            authApiProvider.overrideWithValue(api),
            sessionStoreProvider.overrideWithValue(store),
            oauthSignInProvider.overrideWithValue(FakeOAuthSignIn()),
            authControllerProvider.overrideWith(
              () => AuthController(proactiveRefresh: false),
            ),
            backendConfigOverride,
          ],
        );
        expect(find.byType(LoginScreen), findsOneWidget);
        await tester.tap(find.byKey(ValueKey('oauth-${provider.wire}')));
        await tester.pumpAndSettle();
        expect(path(c), '/habits');
        expect(find.byType(HabitsScreen), findsOneWidget);
        expect(api.lastOAuth?.provider, provider.wire);
        expect(store.session?.user.email, '${provider.wire}-user@example.com');
      });
    }
  });
}

/// A session store whose read completes when [release] is called.
class _SlowStore extends InMemorySessionStore {
  _SlowStore(super.session);

  final _gate = Completer<void>();

  void release() => _gate.complete();

  @override
  Future<Session?> read() async {
    await _gate.future;
    return super.read();
  }
}
