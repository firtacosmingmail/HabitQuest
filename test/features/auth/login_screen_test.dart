import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/core/config/backend_config.dart';
import 'package:habit_quest/core/theme/app_theme.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/session.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/login_screen.dart';
import 'package:habit_quest/features/auth/oauth/fake_oauth_sign_in.dart';
import 'package:habit_quest/features/auth/session_store.dart';

import '../../helpers/test_app.dart';

/// Login that waits for [gate] before answering.
class _SlowAuthApi extends FakeAuthApi {
  final gate = Completer<void>();

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    await gate.future;
    return super.login(email: email, password: password);
  }
}

Future<ProviderContainer> pumpLogin(
  WidgetTester tester, {
  FakeAuthApi? api,
  InMemorySessionStore? store,
  List<Override> extra = const [],
  bool configured = true,
}) async {
  final container = ProviderContainer(
    overrides: [
      authApiProvider.overrideWithValue(api ?? FakeAuthApi()),
      sessionStoreProvider.overrideWithValue(store ?? InMemorySessionStore()),
      authControllerProvider.overrideWith(
        () => AuthController(proactiveRefresh: false),
      ),
      configured
          ? backendConfigOverride
          : backendConfigProvider.overrideWithValue(
              const BackendConfig(
                supabaseUrl: BackendConfig.defaultSupabaseUrl,
                anonKey: '',
              ),
            ),
      ...extra,
    ],
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: AppTheme.light, home: const LoginScreen()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Finder byKey(String k) => find.byKey(ValueKey(k));

Future<void> fill(WidgetTester tester, String key, String text) =>
    tester.enterText(byKey(key), text);

Future<void> submit(WidgetTester tester) async {
  await tester.ensureVisible(byKey('auth-submit'));
  await tester.tap(byKey('auth-submit'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the mascot welcome and login mode by default', (
    tester,
  ) async {
    await pumpLogin(tester);
    expect(find.byKey(const ValueKey('mascot')), findsOneWidget);
    expect(find.textContaining('Welcome back'), findsOneWidget);
    expect(byKey('auth-confirm'), findsNothing);
    expect(byKey('auth-name'), findsNothing);
    expect(byKey('auth-not-configured'), findsNothing);
  });

  testWidgets('validates email and password', (tester) async {
    final api = FakeAuthApi();
    await pumpLogin(tester, api: api);
    await submit(tester);
    expect(find.text('Enter your email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);

    await fill(tester, 'auth-email', 'not-an-email');
    await submit(tester);
    expect(find.text("That doesn't look like an email"), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('wrong password shows a friendly error', (tester) async {
    final api = FakeAuthApi()..addUser('hero@example.com', 'secret1');
    final c = await pumpLogin(tester, api: api);
    await fill(tester, 'auth-email', 'hero@example.com');
    await fill(tester, 'auth-password', 'wrong');
    await submit(tester);
    expect(byKey('auth-error'), findsOneWidget);
    expect(find.textContaining("don't match"), findsOneWidget);
    expect(c.read(authControllerProvider), isA<SignedOut>());
  });

  testWidgets('offline shows a connection message', (tester) async {
    final api = FakeAuthApi()..offline = true;
    await pumpLogin(tester, api: api);
    await fill(tester, 'auth-email', 'hero@example.com');
    await fill(tester, 'auth-password', 'secret1');
    await submit(tester);
    expect(find.textContaining("Can't reach the quest server"), findsOneWidget);
  });

  testWidgets('loading state disables the form, then signs in', (tester) async {
    final api = _SlowAuthApi()..addUser('hero@example.com', 'secret1');
    final store = InMemorySessionStore();
    final c = await pumpLogin(tester, api: api, store: store);
    await fill(tester, 'auth-email', 'hero@example.com');
    await fill(tester, 'auth-password', 'secret1');
    await tester.tap(byKey('auth-submit'));
    await tester.pump();
    expect(byKey('auth-loading'), findsOneWidget);
    expect(tester.widget<FilledButton>(byKey('auth-submit')).onPressed, isNull);
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: byKey('auth-email'),
              matching: find.byType(TextField),
            ),
          )
          .enabled,
      isFalse,
    );

    api.gate.complete();
    await tester.pumpAndSettle();
    expect(byKey('auth-loading'), findsNothing);
    expect(c.read(authControllerProvider), isA<SignedIn>());
    expect(store.session, isNotNull);
  });

  testWidgets('sign up: extra fields, password rules and match', (
    tester,
  ) async {
    final api = FakeAuthApi();
    final c = await pumpLogin(tester, api: api);
    await tester.tap(byKey('auth-mode-register'));
    await tester.pumpAndSettle();
    expect(byKey('auth-name'), findsOneWidget);
    expect(byKey('auth-confirm'), findsOneWidget);
    expect(find.textContaining('A new hero'), findsOneWidget);

    await fill(tester, 'auth-email', 'new@example.com');
    await fill(tester, 'auth-password', '123');
    await fill(tester, 'auth-confirm', '456');
    await submit(tester);
    expect(find.text('Use at least 6 characters'), findsOneWidget);
    expect(find.text("Passwords don't match"), findsOneWidget);
    expect(api.calls, isEmpty);

    await fill(tester, 'auth-name', 'Ann');
    await fill(tester, 'auth-password', 'secret1');
    await fill(tester, 'auth-confirm', 'secret1');
    await submit(tester);
    expect(api.calls, ['register']);
    expect(c.read(authControllerProvider), isA<SignedIn>());
  });

  testWidgets('sign up with a taken email', (tester) async {
    final api = FakeAuthApi()..addUser('hero@example.com', 'secret1');
    await pumpLogin(tester, api: api);
    await tester.tap(byKey('auth-mode-register'));
    await tester.pumpAndSettle();
    await fill(tester, 'auth-email', 'hero@example.com');
    await fill(tester, 'auth-password', 'secret1');
    await fill(tester, 'auth-confirm', 'secret1');
    await submit(tester);
    expect(find.textContaining('already belongs to a hero'), findsOneWidget);
  });

  testWidgets('sign up needing email confirmation', (tester) async {
    final api = FakeAuthApi(requireConfirmation: true);
    final c = await pumpLogin(tester, api: api);
    await tester.tap(byKey('auth-mode-register'));
    await tester.pumpAndSettle();
    await fill(tester, 'auth-email', 'new@example.com');
    await fill(tester, 'auth-password', 'secret1');
    await fill(tester, 'auth-confirm', 'secret1');
    await submit(tester);

    expect(byKey('auth-needs-confirmation'), findsOneWidget);
    expect(
      find.textContaining('confirmation link to new@example.com'),
      findsOneWidget,
    );
    expect(c.read(authControllerProvider), isA<SignedOut>());
    // Back in login mode with the email kept.
    expect(byKey('auth-confirm'), findsNothing);
    expect(find.text('new@example.com'), findsOneWidget);

    // Logging in before confirming is explained.
    await fill(tester, 'auth-password', 'secret1');
    await submit(tester);
    expect(find.textContaining('Confirm your email first'), findsOneWidget);
  });

  testWidgets('missing anon key shows a clear message and disables submit', (
    tester,
  ) async {
    await pumpLogin(tester, configured: false);
    expect(byKey('auth-not-configured'), findsOneWidget);
    expect(find.textContaining('SUPABASE_ANON_KEY'), findsOneWidget);
    expect(tester.widget<FilledButton>(byKey('auth-submit')).onPressed, isNull);
  });

  group('Google & Apple', () {
    testWidgets('buttons and the "or" divider show when configured', (
      tester,
    ) async {
      await pumpLogin(
        tester,
        extra: [oauthSignInProvider.overrideWithValue(FakeOAuthSignIn())],
      );
      expect(byKey('oauth-google'), findsOneWidget);
      expect(byKey('oauth-apple'), findsOneWidget);
      expect(find.text('Continue with Google'), findsOneWidget);
      expect(find.text('Sign in with Apple'), findsOneWidget);
      expect(byKey('google-g-logo'), findsOneWidget);
      expect(byKey('oauth-or-divider'), findsOneWidget);
      expect(byKey('oauth-not-configured-hint'), findsNothing);
      // Above the email form.
      expect(
        tester.getTopLeft(byKey('oauth-or-divider')).dy,
        lessThan(tester.getTopLeft(byKey('auth-email')).dy),
      );
    });

    testWidgets('hidden while the client IDs are placeholders (debug hint)', (
      tester,
    ) async {
      // The real implementation with the shipped (empty) env.dart IDs.
      await pumpLogin(
        tester,
        extra: [
          oauthConfigProvider.overrideWithValue(
            const OAuthConfig.unconfigured(platform: OAuthPlatform.android),
          ),
        ],
      );
      expect(byKey('oauth-google'), findsNothing);
      expect(byKey('oauth-apple'), findsNothing);
      expect(byKey('oauth-or-divider'), findsNothing);
      expect(byKey('oauth-not-configured-hint'), findsOneWidget);
    });

    testWidgets('only Google when Apple is not available', (tester) async {
      await pumpLogin(
        tester,
        extra: [
          oauthSignInProvider.overrideWithValue(
            FakeOAuthSignIn(available: {OAuthProvider.google}),
          ),
        ],
      );
      expect(byKey('oauth-google'), findsOneWidget);
      expect(byKey('oauth-apple'), findsNothing);
    });

    testWidgets('cancel is silent; rejected token shows a friendly error', (
      tester,
    ) async {
      final oauth = FakeOAuthSignIn()
        ..failNextWith = const OAuthCancelled(OAuthProvider.google);
      final api = FakeAuthApi()..rejectedIdTokens.add('fake-apple-id-token');
      final c = await pumpLogin(
        tester,
        api: api,
        extra: [oauthSignInProvider.overrideWithValue(oauth)],
      );
      await tester.tap(byKey('oauth-google'));
      await tester.pumpAndSettle();
      expect(byKey('auth-error'), findsNothing);
      expect(c.read(authControllerProvider), isA<SignedOut>());

      await tester.tap(byKey('oauth-apple'));
      await tester.pumpAndSettle();
      expect(byKey('auth-error'), findsOneWidget);
      expect(find.textContaining("Apple couldn't confirm"), findsOneWidget);
    });

    testWidgets('Google web button credentials sign in too', (tester) async {
      final oauth = FakeOAuthSignIn();
      final c = await pumpLogin(
        tester,
        extra: [oauthSignInProvider.overrideWithValue(oauth)],
      );
      oauth.emitWebCredential(
        const OAuthCredential(provider: OAuthProvider.google, idToken: 'web'),
      );
      await tester.pumpAndSettle();
      expect(c.read(authControllerProvider), isA<SignedIn>());
    });
  });

  testWidgets('shows why the user was signed out', (tester) async {
    final c = await pumpLogin(tester);
    // Simulate an involuntary sign-out (rejected refresh).
    final api = FakeAuthApi()..addUser('hero@example.com', 'secret1');
    c.updateOverrides([
      authApiProvider.overrideWithValue(api),
      sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
      authControllerProvider.overrideWith(
        () => AuthController(proactiveRefresh: false),
      ),
      backendConfigOverride,
    ]);
    final ctrl = c.read(authControllerProvider.notifier);
    await ctrl.login(email: 'hero@example.com', password: 'secret1');
    api.revokeAll();
    await ctrl.refreshSession();
    await tester.pumpAndSettle();
    expect(byKey('auth-signed-out-reason'), findsOneWidget);
    expect(find.textContaining('session expired'), findsOneWidget);
  });
}
