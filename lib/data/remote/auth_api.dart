import 'session.dart';

/// Outcome of `auth-register`: either a [session], or
/// [needsConfirmation] when the project requires email confirmation.
class RegisterResult {
  final Session? session;
  final bool needsConfirmation;

  const RegisterResult.signedIn(Session this.session)
    : needsConfirmation = false;

  const RegisterResult.needsConfirmation()
    : session = null,
      needsConfirmation = true;
}

/// The auth Edge Functions (`auth-register`, `auth-login`, `auth-refresh`,
/// `auth-logout`). All methods throw [ApiException] on failure.
abstract interface class AuthApi {
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  });

  /// Throws `invalid_credentials` (401) or `email_not_confirmed` (403).
  Future<Session> login({required String email, required String password});

  /// `auth-oauth`: exchanges a Google/Apple ID token (and Apple's raw
  /// [nonce]) for a session. [provider] is `google` or `apple`. Throws
  /// `invalid_token` (401) or `provider_disabled` (400).
  Future<Session> oauth({
    required String provider,
    required String idToken,
    String? nonce,
  });

  /// Throws `invalid_refresh_token` (401) when the refresh token is dead.
  Future<Session> refresh(String refreshToken);

  /// Revokes the session server-side.
  Future<void> logout(String accessToken);
}
