import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/router/app_router.dart';
import 'package:habit_quest/core/router/auth_redirect.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/features/auth/auth_callback.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/login_screen.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/habits/habits_screen.dart';
import 'package:habit_quest/features/quest/quest_screen.dart';

import '../../helpers/test_app.dart';

String location(ProviderContainer c) =>
    c.read(routerProvider).routerDelegate.currentConfiguration.uri.toString();

final signedOutOverrides = [
  authApiProvider.overrideWithValue(FakeAuthApi()),
  sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
];

void main() {
  group('AuthCallbackResult / deep link mapping', () {
    test('parses status and reason', () {
      expect(
        AuthCallbackResult.fromQuery({'status': 'confirmed'}),
        const AuthCallbackResult.confirmed(),
      );
      expect(
        AuthCallbackResult.fromQuery({'status': 'error', 'reason': 'expired'}),
        const AuthCallbackResult.error('expired'),
      );
      expect(
        AuthCallbackResult.fromQuery({'status': 'error', 'reason': 'weird'}),
        const AuthCallbackResult.error('invalid'),
      );
      expect(AuthCallbackResult.fromQuery({}), isNull);
    });

    test('maps habitquest://auth-callback to /auth-callback', () {
      expect(
        deepLinkLocation(
          Uri.parse('habitquest://auth-callback?status=confirmed'),
        ),
        '/auth-callback?status=confirmed',
      );
      expect(
        deepLinkLocation(
          Uri.parse('habitquest://auth-callback/?status=error&reason=expired'),
        ),
        '/auth-callback?status=error&reason=expired',
      );
      expect(deepLinkLocation(Uri.parse('/habits')), isNull);
      expect(deepLinkLocation(Uri.parse('https://evil/auth-callback')), isNull);
    });

    test('the auth gate lets /auth-callback through to /login', () {
      const out = SignedOut();
      expect(
        authRedirect(out, Uri.parse('/auth-callback?status=confirmed')),
        '/login?status=confirmed',
      );
      expect(
        authRedirect(
          out,
          Uri.parse(
            '/splash?from=%2Fauth-callback%3Fstatus%3Derror%26reason%3Dexpired',
          ),
        ),
        '/login?status=error&reason=expired',
      );
      expect(authRedirect(out, Uri.parse('/login?status=confirmed')), isNull);
      expect(
        authRedirect(SignedIn(testSession), Uri.parse('/auth-callback')),
        isNull,
      );
    });
  });

  group('/auth-callback route (widgets)', () {
    testWidgets('confirmed → login screen with "Email confirmed"', (
      tester,
    ) async {
      final c = await pumpHabitQuestApp(
        tester,
        signedIn: false,
        initialLocation: '/auth-callback?status=confirmed',
        overrides: signedOutOverrides,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(location(c), '/login?status=confirmed');
      expect(
        find.byKey(const ValueKey('auth-callback-confirmed')),
        findsOneWidget,
      );
      expect(find.text('Email confirmed, please log in'), findsOneWidget);
    });

    testWidgets('error → login screen with a friendly error', (tester) async {
      await pumpHabitQuestApp(
        tester,
        signedIn: false,
        initialLocation: '/auth-callback?status=error&reason=expired',
        overrides: signedOutOverrides,
      );
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(find.byKey(const ValueKey('auth-callback-error')), findsOneWidget);
      expect(find.text('That confirmation link has expired'), findsOneWidget);
    });

    testWidgets('signed out: the platform deep link passes the gate', (
      tester,
    ) async {
      final c = await pumpHabitQuestApp(
        tester,
        signedIn: false,
        overrides: signedOutOverrides,
      );
      expect(location(c), '/login');
      expect(
        find.byKey(const ValueKey('auth-callback-confirmed')),
        findsNothing,
      );

      // What the engine delivers for habitquest://auth-callback?...
      c
          .read(routerProvider)
          .go('habitquest://auth-callback?status=error&reason=invalid');
      await tester.pumpAndSettle();
      expect(location(c), '/login?status=error&reason=invalid');
      expect(find.byKey(const ValueKey('auth-callback-error')), findsOneWidget);
      expect(find.text("That confirmation link didn't work"), findsOneWidget);
    });

    testWidgets('signed in: snackbar and stays in the app', (tester) async {
      final c = await pumpHabitQuestApp(tester, initialLocation: '/quest');
      expect(find.byType(QuestScreen), findsOneWidget);

      c.read(routerProvider).go('habitquest://auth-callback?status=confirmed');
      await tester.pumpAndSettle();
      expect(location(c), '/quest');
      expect(find.byType(QuestScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
      expect(
        find.byKey(const ValueKey('auth-callback-snackbar')),
        findsOneWidget,
      );
      expect(find.text('Email confirmed 🎉'), findsOneWidget);
    });

    testWidgets('signed in at launch: snackbar on /habits', (tester) async {
      final c = await pumpHabitQuestApp(
        tester,
        initialLocation: '/auth-callback?status=error&reason=expired',
      );
      expect(location(c), '/habits');
      expect(find.byType(HabitsScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('auth-callback-snackbar')),
        findsOneWidget,
      );
    });
  });
}
