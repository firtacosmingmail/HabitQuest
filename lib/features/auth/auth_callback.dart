import '../../core/router/app_routes.dart';

/// The app's URL scheme (registered in Info.plist and AndroidManifest.xml).
const appUrlScheme = 'habitquest';

/// The deep link host the email confirmation pages open:
/// `habitquest://auth-callback?status=confirmed|error&reason=...`.
const authCallbackHost = 'auth-callback';

/// The outcome of an email confirmation, carried by the
/// `/auth-callback?status=confirmed|error&reason=expired|invalid|missing`
/// deep link and shown on the login screen (or as a snackbar when signed in).
class AuthCallbackResult {
  final bool confirmed;

  /// `expired`, `invalid` or `missing` for errors (anything else is treated
  /// as `invalid`); null when [confirmed].
  final String? reason;

  const AuthCallbackResult.confirmed() : confirmed = true, reason = null;

  const AuthCallbackResult.error(String this.reason) : confirmed = false;

  /// Reads `status` / `reason` from [params]; null when there is no `status`.
  static AuthCallbackResult? fromQuery(Map<String, String> params) {
    final status = params['status'];
    if (status == null) return null;
    if (status == 'confirmed') return const AuthCallbackResult.confirmed();
    final reason = params['reason'];
    return AuthCallbackResult.error(
      const {'expired', 'invalid', 'missing'}.contains(reason)
          ? reason!
          : 'invalid',
    );
  }

  Map<String, String> toQuery() => {
    'status': confirmed ? 'confirmed' : 'error',
    'reason': ?reason,
  };

  String get emoji => confirmed
      ? '🎉'
      : switch (reason) {
          'expired' => '⏳',
          'missing' => '🧭',
          _ => '🦉',
        };

  String get title => confirmed
      ? 'Email confirmed, please log in'
      : switch (reason) {
          'expired' => 'That confirmation link has expired',
          'missing' => 'That confirmation link is incomplete',
          _ => "That confirmation link didn't work",
        };

  String get message => confirmed
      ? 'Your quest is ready to begin. Log in to start building your streaks.'
      : switch (reason) {
          'expired' =>
            'Links only last a little while and work just once. '
                'If you already confirmed, just log in; otherwise sign up '
                'again for a fresh link.',
          'missing' =>
            'The link is missing its code. Open it from your email again, '
                'or sign up again for a fresh link.',
          _ =>
            'It may have been used already or copied incompletely. '
                'Try logging in, or sign up again for a fresh link.',
        };

  /// One line for a snackbar (signed-in case).
  String get snackText => confirmed ? 'Email confirmed 🎉' : '$emoji $title';

  @override
  bool operator ==(Object other) =>
      other is AuthCallbackResult &&
      other.confirmed == confirmed &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(confirmed, reason);
}

/// Maps the platform deep link `habitquest://auth-callback?...` (go_router
/// sees it with host `auth-callback` and path `/`) to the in-app location
/// `/auth-callback?...`. Returns null for every other URI.
String? deepLinkLocation(Uri uri) {
  if (uri.host != authCallbackHost) return null;
  if (uri.scheme.isNotEmpty && uri.scheme != appUrlScheme) return null;
  return Uri(
    path: AppRoutes.authCallback,
    queryParameters: uri.queryParameters.isEmpty ? null : uri.queryParameters,
  ).toString();
}

/// `/login` carrying the confirmation outcome of [callbackLocation] (an
/// `/auth-callback?...` location).
String loginWithCallback(Uri callbackLocation) {
  final result = AuthCallbackResult.fromQuery(callbackLocation.queryParameters);
  if (result == null) return AppRoutes.login;
  return Uri(
    path: AppRoutes.login,
    queryParameters: result.toQuery(),
  ).toString();
}
