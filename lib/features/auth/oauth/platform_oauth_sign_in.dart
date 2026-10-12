import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' hide generateNonce;

import 'google_web_button_stub.dart'
    if (dart.library.js_interop) 'google_web_button_web.dart';
import 'oauth_sign_in.dart';

/// [OAuthSignIn] backed by google_sign_in and sign_in_with_apple.
///
/// Google: the iOS client ID on iOS, the web client ID as `serverClientId`
/// on Android (so the ID token's audience is the web client) and as
/// `clientId` on web. Apple: native on iOS/macOS, Apple's web flow (Services
/// ID + return URL) on Android and web. A fresh random nonce per Apple
/// sign-in: its SHA-256 goes to Apple, the raw value to the server.
class PlatformOAuthSignIn implements OAuthSignIn {
  PlatformOAuthSignIn(this.config);

  @override
  final OAuthConfig config;

  Future<void>? _googleInit;
  final _webCredentials = StreamController<OAuthCredential>.broadcast();

  @override
  bool isAvailable(OAuthProvider provider) => config.configured(provider);

  @override
  Stream<OAuthCredential> get webCredentials {
    if (config.platform == OAuthPlatform.web && config.googleConfigured) {
      unawaited(_initGoogle());
    }
    return _webCredentials.stream;
  }

  @override
  Widget? googleWebButton() {
    if (config.platform != OAuthPlatform.web || !config.googleConfigured) {
      return null;
    }
    return FutureBuilder<void>(
      future: _initGoogle(),
      builder: (context, snap) => snap.connectionState == ConnectionState.done
          ? (buildGoogleWebButton(minimumWidth: 280) ?? const SizedBox.shrink())
          : const SizedBox(height: 44),
    );
  }

  @override
  Future<OAuthCredential> signIn(OAuthProvider provider) {
    if (!config.configured(provider)) {
      throw OAuthNotConfigured(provider);
    }
    return switch (provider) {
      OAuthProvider.google => _google(),
      OAuthProvider.apple => _apple(),
    };
  }

  @override
  Future<void> signOut() async {
    if (_googleInit == null) return;
    try {
      await GoogleSignIn.instance.signOut();
    } catch (_) {
      // Best effort.
    }
  }

  // Google ----------------------------------------------------------------------

  Future<void> _initGoogle() => _googleInit ??= _doInitGoogle();

  Future<void> _doInitGoogle() async {
    final g = GoogleSignIn.instance;
    await g.initialize(
      clientId: config.googleClientId,
      serverClientId: config.googleServerClientId,
    );
    if (config.platform == OAuthPlatform.web) {
      g.authenticationEvents.listen(
        (event) {
          if (event is! GoogleSignInAuthenticationEventSignIn) return;
          final token = event.user.authentication.idToken;
          if (token == null || token.isEmpty) {
            _webCredentials.addError(
              const OAuthFailure(OAuthProvider.google, 'No ID token'),
            );
            return;
          }
          _webCredentials.add(
            OAuthCredential(provider: OAuthProvider.google, idToken: token),
          );
        },
        onError: (Object e) {
          if (e is GoogleSignInException &&
              e.code == GoogleSignInExceptionCode.canceled) {
            return;
          }
          _webCredentials.addError(
            OAuthFailure(OAuthProvider.google, e.toString()),
          );
        },
      );
    }
  }

  Future<OAuthCredential> _google() async {
    try {
      await _initGoogle();
      final g = GoogleSignIn.instance;
      if (!g.supportsAuthenticate()) {
        // Web: only the rendered button can sign in.
        throw const OAuthFailure(
          OAuthProvider.google,
          'Use the Google button on this platform',
        );
      }
      final account = await g.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw const OAuthFailure(OAuthProvider.google, 'No ID token');
      }
      return OAuthCredential(provider: OAuthProvider.google, idToken: token);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const OAuthCancelled(OAuthProvider.google);
      }
      if (e.code == GoogleSignInExceptionCode.clientConfigurationError ||
          e.code == GoogleSignInExceptionCode.providerConfigurationError) {
        throw const OAuthNotConfigured(OAuthProvider.google);
      }
      throw OAuthFailure(OAuthProvider.google, e.description ?? e.code.name);
    }
  }

  // Apple -----------------------------------------------------------------------

  Future<OAuthCredential> _apple() async {
    final rawNonce = generateNonce();
    try {
      final useWebFlow = !config.isApplePlatform;
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: sha256OfNonce(rawNonce),
        webAuthenticationOptions: useWebFlow
            ? WebAuthenticationOptions(
                clientId: config.ids.appleServiceId,
                redirectUri: Uri.parse(config.ids.appleRedirectUri),
              )
            : null,
      );
      final token = credential.identityToken;
      if (token == null || token.isEmpty) {
        throw const OAuthFailure(OAuthProvider.apple, 'No identity token');
      }
      return OAuthCredential(
        provider: OAuthProvider.apple,
        idToken: token,
        nonce: rawNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const OAuthCancelled(OAuthProvider.apple);
      }
      throw OAuthFailure(OAuthProvider.apple, e.message);
    } on SignInWithAppleNotSupportedException catch (e) {
      throw OAuthFailure(OAuthProvider.apple, e.message);
    } on SignInWithAppleException catch (e) {
      throw OAuthFailure(OAuthProvider.apple, e.toString());
    }
  }
}
