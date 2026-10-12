import 'dart:async';

import 'package:flutter/widgets.dart';

import 'oauth_sign_in.dart';

/// Scripted [OAuthSignIn] for tests: no SDKs, no UI.
class FakeOAuthSignIn implements OAuthSignIn {
  FakeOAuthSignIn({
    this.available = const {OAuthProvider.google, OAuthProvider.apple},
    OAuthConfig? config,
  }) : config = config ?? const OAuthConfig.unconfigured();

  @override
  final OAuthConfig config;

  /// Providers whose buttons show.
  Set<OAuthProvider> available;

  /// The next [signIn] throws this (once), e.g. [OAuthCancelled].
  Object? failNextWith;

  /// Providers in the order [signIn] was called.
  final List<OAuthProvider> calls = [];

  int signOuts = 0;

  /// Token returned for each provider.
  String idTokenFor(OAuthProvider p) => 'fake-${p.wire}-id-token';

  /// Raw nonce returned with Apple credentials.
  static const appleNonce = 'fake-raw-nonce';

  final _web = StreamController<OAuthCredential>.broadcast();

  /// Simulates a sign-in from the Google web button.
  void emitWebCredential(OAuthCredential c) => _web.add(c);

  @override
  bool isAvailable(OAuthProvider provider) => available.contains(provider);

  @override
  Future<OAuthCredential> signIn(OAuthProvider provider) async {
    calls.add(provider);
    final fail = failNextWith;
    if (fail != null) {
      failNextWith = null;
      throw fail;
    }
    if (!available.contains(provider)) throw OAuthNotConfigured(provider);
    return OAuthCredential(
      provider: provider,
      idToken: idTokenFor(provider),
      nonce: provider == OAuthProvider.apple ? appleNonce : null,
    );
  }

  @override
  Widget? googleWebButton() => null;

  @override
  Stream<OAuthCredential> get webCredentials => _web.stream;

  @override
  Future<void> signOut() async => signOuts++;
}
