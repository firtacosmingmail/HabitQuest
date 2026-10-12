import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb, kReleaseMode;

import '../../../core/config/env.dart';

/// The platforms that matter for social sign-in.
enum OAuthPlatform { ios, macos, android, web, other }

/// The platform this build runs on.
OAuthPlatform currentOAuthPlatform() {
  if (kIsWeb) return OAuthPlatform.web;
  return switch (defaultTargetPlatform) {
    TargetPlatform.iOS => OAuthPlatform.ios,
    TargetPlatform.macOS => OAuthPlatform.macos,
    TargetPlatform.android => OAuthPlatform.android,
    _ => OAuthPlatform.other,
  };
}

/// The social providers the backend accepts (`auth-oauth`).
enum OAuthProvider {
  google('google', 'Google'),
  apple('apple', 'Apple');

  const OAuthProvider(this.wire, this.label);

  /// Value sent to the server.
  final String wire;

  /// Display name.
  final String label;
}

/// The OAuth client IDs compiled into this build (the [OAuthIds] of the
/// selected [AppEnv], with `--dart-define` overrides) plus the platform.
class OAuthConfig {
  final OAuthIds ids;
  final OAuthPlatform platform;

  const OAuthConfig({required this.ids, required this.platform});

  /// No IDs at all (tests, or a fresh checkout).
  const OAuthConfig.unconfigured({this.platform = OAuthPlatform.other})
    : ids = const OAuthIds();

  /// Pure resolution: a non-empty define replaces the env value.
  factory OAuthConfig.resolve({
    String envDefine = '',
    String googleIosClientId = '',
    String googleWebClientId = '',
    String appleServiceId = '',
    String appleRedirectUri = '',
    required bool isRelease,
    required OAuthPlatform platform,
    Map<AppEnv, OAuthIds> envs = oauthEnvs,
  }) {
    final base =
        envs[selectAppEnv(envDefine: envDefine, isRelease: isRelease)]!;
    String pick(String override, String fallback) =>
        override.trim().isNotEmpty ? override.trim() : fallback.trim();
    return OAuthConfig(
      platform: platform,
      ids: OAuthIds(
        googleIosClientId: pick(googleIosClientId, base.googleIosClientId),
        googleWebClientId: pick(googleWebClientId, base.googleWebClientId),
        appleServiceId: pick(appleServiceId, base.appleServiceId),
        appleRedirectUri: pick(appleRedirectUri, base.appleRedirectUri),
      ),
    );
  }

  /// Reads `ENV`, `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`,
  /// `APPLE_SERVICE_ID` and `APPLE_REDIRECT_URI`.
  factory OAuthConfig.fromEnvironment() => OAuthConfig.resolve(
    envDefine: const String.fromEnvironment('ENV'),
    googleIosClientId: const String.fromEnvironment('GOOGLE_IOS_CLIENT_ID'),
    googleWebClientId: const String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    appleServiceId: const String.fromEnvironment('APPLE_SERVICE_ID'),
    appleRedirectUri: const String.fromEnvironment('APPLE_REDIRECT_URI'),
    isRelease: kReleaseMode,
    platform: currentOAuthPlatform(),
  );

  /// Empty or an obvious template value ("YOUR_...", "<...>").
  static bool isPlaceholder(String value) {
    final v = value.trim();
    return v.isEmpty ||
        v.toUpperCase().startsWith('YOUR_') ||
        v.contains('<') ||
        v.toUpperCase().contains('PLACEHOLDER');
  }

  bool get isApplePlatform =>
      platform == OAuthPlatform.ios || platform == OAuthPlatform.macos;

  /// The Google client ID google_sign_in needs on this platform: the iOS
  /// client on iOS/macOS, the web client on web (Android passes the web
  /// client as `serverClientId` instead, see [googleServerClientId]).
  String? get googleClientId => switch (platform) {
    OAuthPlatform.ios || OAuthPlatform.macos => _real(ids.googleIosClientId),
    OAuthPlatform.web => _real(ids.googleWebClientId),
    _ => null,
  };

  /// `serverClientId` (the web client) on Android, so the ID token's
  /// audience is the web client registered in Supabase.
  String? get googleServerClientId =>
      platform == OAuthPlatform.android ? _real(ids.googleWebClientId) : null;

  /// Whether Google sign-in has the IDs it needs on this platform.
  bool get googleConfigured => switch (platform) {
    OAuthPlatform.ios || OAuthPlatform.macos => googleClientId != null,
    OAuthPlatform.android => googleServerClientId != null,
    OAuthPlatform.web => googleClientId != null,
    OAuthPlatform.other => false,
  };

  /// Apple's web flow (Android and web): Services ID + return URL.
  bool get appleWebFlowConfigured =>
      _real(ids.appleServiceId) != null && _real(ids.appleRedirectUri) != null;

  /// Native on iOS/macOS; the web flow elsewhere only when configured.
  bool get appleConfigured => isApplePlatform
      ? true
      : (platform == OAuthPlatform.android || platform == OAuthPlatform.web) &&
            appleWebFlowConfigured;

  bool configured(OAuthProvider p) => switch (p) {
    OAuthProvider.google => googleConfigured,
    OAuthProvider.apple => appleConfigured,
  };

  static String? _real(String v) => isPlaceholder(v) ? null : v.trim();
}
