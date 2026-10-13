import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:habit_quest/core/config/env.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/features/auth/auth_messages.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/oauth/fake_oauth_sign_in.dart';
import 'package:habit_quest/features/auth/oauth/platform_oauth_sign_in.dart';
import 'package:habit_quest/features/auth/session_store.dart';

void main() {
  group('Google SDK errors', () {
    test('null description → code shown, never "null"', () {
      final e = mapGoogleSignInException(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
        ),
      );
      expect(e, isA<OAuthFailure>());
      final f = e as OAuthFailure;
      expect(f.code, 'unknownError');
      final msg = friendlyAuthError(f, provider: OAuthProvider.google);
      expect(msg, contains('unknownError'));
      expect(msg, isNot(contains('null')));
    });

    test('"null" description string is treated as missing', () {
      final f =
          mapGoogleSignInException(
                const GoogleSignInException(
                  code: GoogleSignInExceptionCode.unknownError,
                  description: 'null',
                ),
              )
              as OAuthFailure;
      expect(f.message, isNot('null'));
    });

    test('28444 → "not set up correctly" with the code', () {
      final f = mapGoogleSignInException(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.unknownError,
          description: '[28444] Developer console is not set up correctly.',
        ),
      );
      expect(
        friendlyAuthError(f),
        "Google sign-in isn't set up correctly for this app (unknownError: "
        '[28444] Developer console is not set up correctly.).',
      );
    });

    test('configuration errors keep code and description', () {
      final e = mapGoogleSignInException(
        const GoogleSignInException(
          code: GoogleSignInExceptionCode.providerConfigurationError,
          description: 'bad client',
        ),
      );
      expect(e, isA<OAuthNotConfigured>());
      expect(
        friendlyAuthError(e),
        "Google sign-in isn't set up correctly for this app "
        '(providerConfigurationError: bad client).',
      );
    });

    test('canceled → OAuthCancelled', () {
      expect(
        mapGoogleSignInException(
          const GoogleSignInException(code: GoogleSignInExceptionCode.canceled),
        ),
        isA<OAuthCancelled>(),
      );
    });

    test('describe logs type, code, description and details', () {
      expect(
        describeGoogleSignInException(
          const GoogleSignInException(
            code: GoogleSignInExceptionCode.interrupted,
            description: 'd',
            details: 'x',
          ),
        ),
        'GoogleSignIn failed: GoogleSignInException code=interrupted '
        'description=d details=x',
      );
    });
  });

  group('Apple nonce', () {
    test('SHA-256 of the raw nonce, lower-case hex', () {
      // Known vectors.
      expect(
        sha256OfNonce('abc'),
        'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
      );
      expect(
        sha256OfNonce(''),
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855',
      );
      final raw = generateNonce();
      expect(sha256OfNonce(raw), hasLength(64));
      expect(sha256OfNonce(raw), isNot(raw));
    });

    test('random nonces: length, charset, unique', () {
      final a = generateNonce();
      final b = generateNonce();
      expect(a, hasLength(32));
      expect(a, isNot(b));
      expect(RegExp(r'^[0-9A-Za-z\-._]+$').hasMatch(a), isTrue);
      expect(generateNonce(length: 8, random: Random(1)), hasLength(8));
    });
  });

  group('OAuthConfig', () {
    const ios = 'ios-id.apps.googleusercontent.com';
    const web = 'web-id.apps.googleusercontent.com';
    OAuthConfig cfg(OAuthPlatform p, {OAuthIds ids = const OAuthIds()}) =>
        OAuthConfig.resolve(
          isRelease: false,
          platform: p,
          envs: {AppEnv.dev: ids, AppEnv.prod: ids},
        );

    test('placeholders (empty) hide Google everywhere and Apple off Apple '
        'platforms', () {
      for (final p in OAuthPlatform.values) {
        expect(cfg(p).googleConfigured, isFalse, reason: '$p');
      }
      expect(cfg(OAuthPlatform.ios).appleConfigured, isTrue);
      expect(cfg(OAuthPlatform.macos).appleConfigured, isTrue);
      expect(cfg(OAuthPlatform.android).appleConfigured, isFalse);
      expect(cfg(OAuthPlatform.web).appleConfigured, isFalse);
      expect(OAuthConfig.isPlaceholder('YOUR_WEB_CLIENT_ID'), isTrue);
      expect(OAuthConfig.isPlaceholder('<web client>'), isTrue);
      expect(OAuthConfig.isPlaceholder(web), isFalse);
    });

    test('client IDs per platform: iOS client on iOS, web client as '
        'serverClientId on Android and clientId on web', () {
      const ids = OAuthIds(googleIosClientId: ios, googleWebClientId: web);
      final i = cfg(OAuthPlatform.ios, ids: ids);
      expect((i.googleClientId, i.googleServerClientId), (ios, null));
      final a = cfg(OAuthPlatform.android, ids: ids);
      expect((a.googleClientId, a.googleServerClientId), (null, web));
      final w = cfg(OAuthPlatform.web, ids: ids);
      expect((w.googleClientId, w.googleServerClientId), (web, null));
      expect([i, a, w].every((c) => c.googleConfigured), isTrue);
      // iOS needs its own client.
      expect(
        cfg(
          OAuthPlatform.ios,
          ids: const OAuthIds(googleWebClientId: web),
        ).googleConfigured,
        isFalse,
      );
    });

    test('Apple web flow needs the Services ID and the return URL', () {
      final half = cfg(
        OAuthPlatform.android,
        ids: const OAuthIds(appleServiceId: 'com.habitquest.signin'),
      );
      expect(half.appleConfigured, isFalse);
      final full = cfg(
        OAuthPlatform.web,
        ids: const OAuthIds(
          appleServiceId: 'com.habitquest.signin',
          appleRedirectUri: 'https://example.com/apple',
        ),
      );
      expect(full.appleConfigured, isTrue);
    });

    test('dart-define overrides win over env.dart', () {
      final c = OAuthConfig.resolve(
        googleWebClientId: ' $web ',
        isRelease: true,
        platform: OAuthPlatform.android,
      );
      expect(c.googleServerClientId, web);
    });

    test('the shipped env.dart sets the Google web client; the rest are '
        'placeholders (empty)', () {
      for (final ids in oauthEnvs.values) {
        expect(ids.googleIosClientId, isEmpty);
        expect(ids.googleWebClientId, endsWith('.apps.googleusercontent.com'));
        expect(ids.appleServiceId, isEmpty);
      }
    });

    test('real implementation refuses placeholder config without touching '
        'the SDK', () {
      final real = PlatformOAuthSignIn(cfg(OAuthPlatform.android));
      expect(real.isAvailable(OAuthProvider.google), isFalse);
      expect(
        () => real.signIn(OAuthProvider.google),
        throwsA(isA<OAuthNotConfigured>()),
      );
      expect(real.googleWebButton(), isNull);
    });
  });

  group('AuthController OAuth', () {
    late FakeAuthApi api;
    late InMemorySessionStore store;
    late FakeOAuthSignIn oauth;
    late ProviderContainer c;

    setUp(() {
      api = FakeAuthApi();
      store = InMemorySessionStore();
      oauth = FakeOAuthSignIn();
      c = ProviderContainer(
        overrides: [
          authApiProvider.overrideWithValue(api),
          sessionStoreProvider.overrideWithValue(store),
          oauthSignInProvider.overrideWithValue(oauth),
          authControllerProvider.overrideWith(
            () => AuthController(proactiveRefresh: false),
          ),
        ],
      );
      c.listen(authControllerProvider, (_, _) {});
    });
    tearDown(() => c.dispose());

    AuthController ctrl() => c.read(authControllerProvider.notifier);

    test('Google success: ID token to auth-oauth, session stored', () async {
      expect(await ctrl().signInWithGoogle(), isTrue);
      expect(api.calls, ['oauth']);
      expect(api.lastOAuth?.provider, 'google');
      expect(api.lastOAuth?.idToken, 'fake-google-id-token');
      expect(api.lastOAuth?.nonce, isNull);
      expect(c.read(authControllerProvider), isA<SignedIn>());
      expect(store.session?.user.email, 'google-user@example.com');
    });

    test('Apple success: the raw nonce goes to the server', () async {
      expect(await ctrl().signInWithApple(), isTrue);
      expect(api.lastOAuth?.provider, 'apple');
      expect(api.lastOAuth?.nonce, FakeOAuthSignIn.appleNonce);
      expect(c.read(authControllerProvider), isA<SignedIn>());
    });

    test('cancel: no server call, stays signed out, no error', () async {
      oauth.failNextWith = const OAuthCancelled(OAuthProvider.google);
      expect(await ctrl().signInWithGoogle(), isFalse);
      expect(api.calls, isEmpty);
      expect(store.session, isNull);
      expect(c.read(authControllerProvider), isNot(isA<SignedIn>()));
    });

    test('server rejects the token → invalid_token, friendly copy', () async {
      api.rejectedIdTokens.add('fake-apple-id-token');
      Object? error;
      try {
        await ctrl().signInWithApple();
      } catch (e) {
        error = e;
      }
      expect(error, isA<ApiException>());
      expect((error as ApiException).code, ApiException.invalidToken);
      expect(store.session, isNull);
      expect(
        friendlyAuthError(error, provider: OAuthProvider.apple),
        contains("Apple couldn't confirm"),
      );
    });

    test('provider disabled on the server and SDK failures', () async {
      api.disabledProviders.add('google');
      await expectLater(
        ctrl().signInWithGoogle(),
        throwsA(
          isA<ApiException>().having(
            (e) => e.code,
            'code',
            ApiException.providerDisabled,
          ),
        ),
      );
      oauth.failNextWith = const OAuthFailure(OAuthProvider.apple, 'boom');
      await expectLater(ctrl().signInWithApple(), throwsA(isA<OAuthFailure>()));
      expect(
        friendlyAuthError(const OAuthFailure(OAuthProvider.apple, 'boom')),
        "Couldn't sign in with Apple. Please try again.",
      );
    });

    test('placeholder config → "Google sign-in isn\'t set up yet"', () async {
      oauth.available = {OAuthProvider.apple};
      Object? error;
      try {
        await ctrl().signInWithGoogle();
      } catch (e) {
        error = e;
      }
      expect(error, isA<OAuthNotConfigured>());
      expect(oauth.calls, isEmpty);
      expect(api.calls, isEmpty);
      expect(friendlyAuthError(error!), "Google sign-in isn't set up yet.");
    });

    test('logout also signs out of the provider SDK', () async {
      await ctrl().signInWithGoogle();
      await ctrl().logout();
      expect(oauth.signOuts, 1);
      expect(c.read(authControllerProvider), isA<SignedOut>());
    });
  });
}
