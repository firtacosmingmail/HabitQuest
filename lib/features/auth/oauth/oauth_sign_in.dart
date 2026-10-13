import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/widgets.dart';

import 'oauth_config.dart';

export 'oauth_config.dart' show OAuthConfig, OAuthPlatform, OAuthProvider;

/// An ID token from Google or Apple, ready for `auth-oauth`.
class OAuthCredential {
  final OAuthProvider provider;
  final String idToken;

  /// The RAW nonce (Apple); its SHA-256 went to the provider.
  final String? nonce;

  const OAuthCredential({
    required this.provider,
    required this.idToken,
    this.nonce,
  });
}

/// The user closed the provider sheet: not an error, show nothing.
class OAuthCancelled implements Exception {
  final OAuthProvider provider;
  const OAuthCancelled(this.provider);

  @override
  String toString() => 'OAuthCancelled(${provider.wire})';
}

/// The client IDs for [provider] are placeholders in this build.
/// Also thrown when the provider SDK reports a configuration error; then
/// [code] / [message] carry the SDK's error so the UI can show it.
class OAuthNotConfigured implements Exception {
  final OAuthProvider provider;

  /// The SDK error code (e.g. `providerConfigurationError`), if any.
  final String? code;

  /// The SDK error description, if any.
  final String? message;

  const OAuthNotConfigured(this.provider, {this.code, this.message});

  @override
  String toString() => code == null
      ? 'OAuthNotConfigured(${provider.wire})'
      : 'OAuthNotConfigured(${provider.wire}) [$code] ${message ?? ''}'.trim();
}

/// The provider SDK failed (no ID token, platform error, ...).
class OAuthFailure implements Exception {
  final OAuthProvider provider;
  final String message;

  /// The SDK error code (e.g. `unknownError`), if any.
  final String? code;

  const OAuthFailure(this.provider, this.message, {this.code});

  @override
  String toString() => code == null
      ? 'OAuthFailure(${provider.wire}): $message'
      : 'OAuthFailure(${provider.wire}) [$code]: $message';
}

/// Gets an ID token from the native Google / Apple SDKs. The app sends it
/// to the `auth-oauth` Edge Function (never to Supabase Auth directly).
///
/// Real implementation: `PlatformOAuthSignIn`; tests use `FakeOAuthSignIn`.
abstract interface class OAuthSignIn {
  OAuthConfig get config;

  /// Whether a button for [provider] should be shown on this platform.
  bool isAvailable(OAuthProvider provider);

  /// Runs the provider's sign-in UI. Throws [OAuthCancelled],
  /// [OAuthNotConfigured] or [OAuthFailure].
  Future<OAuthCredential> signIn(OAuthProvider provider);

  /// Google on web cannot be started from our own button (Google Identity
  /// Services renders its own); this returns that button, or `null` when the
  /// app's own button + [signIn] are used. Its results arrive on
  /// [webCredentials].
  Widget? googleWebButton();

  /// Credentials from [googleWebButton] (web only; empty elsewhere).
  Stream<OAuthCredential> get webCredentials;

  /// Forgets the provider account locally (best effort, on logout).
  Future<void> signOut();
}

// Apple nonce ------------------------------------------------------------------

const _nonceChars =
    '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz-._';

/// A random nonce from a cryptographically secure generator.
String generateNonce({int length = 32, Random? random}) {
  final r = random ?? Random.secure();
  return List.generate(
    length,
    (_) => _nonceChars[r.nextInt(_nonceChars.length)],
  ).join();
}

/// Lower-case hex SHA-256 of [nonce]: what Apple receives (and embeds in the
/// ID token); Supabase hashes the raw nonce the same way to compare.
String sha256OfNonce(String nonce) =>
    sha256.convert(utf8.encode(nonce)).toString();
