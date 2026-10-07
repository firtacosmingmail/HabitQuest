import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/api_exception.dart';
import '../../data/remote/auth_api.dart';
import '../../data/remote/authenticated_transport.dart';
import '../../data/remote/session.dart';
import '../../domain/providers.dart';
import 'auth_providers.dart';
import 'session_store.dart';

/// Where the user stands with the backend.
sealed class AuthState {
  const AuthState();
}

/// The saved session is still being read (show a splash).
final class AuthUnknown extends AuthState {
  const AuthUnknown();
}

final class SignedOut extends AuthState {
  /// Why the user was signed out involuntarily (e.g. expired session), to
  /// show on the login screen; `null` after a normal logout or first launch.
  final String? reason;

  const SignedOut({this.reason});
}

final class SignedIn extends AuthState {
  final Session session;

  const SignedIn(this.session);
}

/// Owns the auth session: restores it at launch, signs in/up/out, refreshes
/// the access token ~[refreshMargin] before it expires and on demand after
/// a 401 (see [AuthenticatedTransport]).
///
/// A refresh rejected by the server signs the user out; a refresh that fails
/// because the device is offline keeps the session and retries later
/// (offline-first: local data stays usable).
///
/// Logout keeps local hive data on the device (for now).
class AuthController extends Notifier<AuthState>
    implements AccessTokenProvider {
  /// [preloadedSession] starts signed in without reading the [SessionStore]
  /// (tests). [proactiveRefresh] turns the refresh timer off (tests that do
  /// not want a pending timer).
  AuthController({this.preloadedSession, this.proactiveRefresh = true});

  final Session? preloadedSession;
  final bool proactiveRefresh;

  /// Refresh this long before `expiresAt`.
  static const refreshMargin = Duration(seconds: 60);

  /// Retry delay for a proactive refresh that failed for a transient reason.
  static const retryDelay = Duration(seconds: 30);

  /// Message shown on the login screen after an involuntary sign-out.
  static const sessionExpiredMessage =
      'Your session expired. Please log in again.';

  Timer? _timer;
  Future<Session?>? _inflightRefresh;
  Future<void>? _restoring;

  AuthApi get _api => ref.read(authApiProvider);
  SessionStore get _store => ref.read(sessionStoreProvider);
  DateTime _now() => ref.read(clockProvider)();

  @override
  AuthState build() {
    ref.onDispose(() => _timer?.cancel());
    final preloaded = preloadedSession;
    if (preloaded != null) {
      _schedule(preloaded);
      return SignedIn(preloaded);
    }
    _restoring = Future.microtask(_restore);
    return const AuthUnknown();
  }

  /// The current session, if signed in.
  Session? get session => switch (state) {
    SignedIn(:final session) => session,
    _ => null,
  };

  // Public API ----------------------------------------------------------------

  /// Throws [ApiException] (e.g. `invalid_credentials`).
  Future<void> login({required String email, required String password}) async {
    final s = await _api.login(email: email.trim(), password: password);
    await _signIn(s);
  }

  /// Signs in when the server returns a session; otherwise the result has
  /// `needsConfirmation`. Throws [ApiException] (e.g. `email_taken`).
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final result = await _api.register(
      email: email.trim(),
      password: password,
      displayName: displayName,
    );
    final s = result.session;
    if (s != null) await _signIn(s);
    return result;
  }

  /// Signs out locally right away (clearing the stored session), then tells
  /// the server best-effort; works offline.
  Future<void> logout() async {
    final current = session;
    _timer?.cancel();
    await _store.clear();
    if (ref.mounted) state = const SignedOut();
    if (current != null) {
      try {
        await _api.logout(current.accessToken);
      } catch (_) {
        // Offline or already revoked: the local session is gone anyway.
      }
    }
  }

  /// Refreshes the session now (deduplicated while one is in flight).
  /// Returns the new session, or `null` when signed out (including because
  /// the server rejected the refresh token). Rethrows transient failures
  /// (network, 5xx, rate limiting) without signing out.
  Future<Session?> refreshSession() =>
      _inflightRefresh ??= _doRefresh().whenComplete(
        () => _inflightRefresh = null,
      );

  // AccessTokenProvider -------------------------------------------------------

  @override
  Future<String?> accessToken() async {
    if (state is AuthUnknown) await _restoring;
    final s = session;
    if (s == null) return null;
    if (s.isExpiredAt(_now(), leeway: const Duration(seconds: 10))) {
      return (await refreshSession())?.accessToken;
    }
    return s.accessToken;
  }

  @override
  Future<String?> refreshAfterUnauthorized(String rejectedToken) async {
    final s = session;
    if (s == null) return null;
    // Someone refreshed while this request was in flight: just retry.
    if (s.accessToken != rejectedToken) return s.accessToken;
    return (await refreshSession())?.accessToken;
  }

  // Internals -----------------------------------------------------------------

  Future<void> _restore() async {
    Session? saved;
    try {
      saved = await _store.read();
    } catch (_) {
      saved = null;
    }
    if (!ref.mounted || state is! AuthUnknown) return; // e.g. logged in
    if (saved == null) {
      state = const SignedOut();
      return;
    }
    // Signed in straight away, even offline; an expired token is refreshed
    // by the timer (delay 0) or on first use.
    state = SignedIn(saved);
    _schedule(saved);
  }

  Future<void> _signIn(Session s) async {
    try {
      await _store.write(s);
    } catch (_) {
      // Storage unavailable (e.g. web without WebCrypto): stay signed in
      // for this run.
    }
    if (!ref.mounted) return;
    state = SignedIn(s);
    _schedule(s);
  }

  Future<Session?> _doRefresh() async {
    final before = session;
    if (before == null) return null;
    try {
      final fresh = await _api.refresh(before.refreshToken);
      if (!ref.mounted) return null;
      final now = session;
      // Logged out (or in as someone else) while refreshing: drop it.
      if (now == null || now.refreshToken != before.refreshToken) return now;
      await _signIn(fresh);
      return fresh;
    } on ApiException catch (e) {
      if (_isTransient(e)) rethrow;
      if (ref.mounted && session?.refreshToken == before.refreshToken) {
        await _signOutLocally();
      }
      return null;
    }
  }

  static bool _isTransient(ApiException e) {
    final status = e.status;
    return e.isNetwork ||
        status == null ||
        status >= 500 ||
        e.code == ApiException.rateLimited;
  }

  Future<void> _signOutLocally() async {
    _timer?.cancel();
    await _store.clear();
    if (ref.mounted) state = const SignedOut(reason: sessionExpiredMessage);
  }

  void _schedule(Session s) {
    _timer?.cancel();
    if (!proactiveRefresh) return;
    var delay = s.expiresAt.difference(_now()) - refreshMargin;
    if (delay.isNegative) delay = Duration.zero;
    _timer = Timer(delay, _refreshInBackground);
  }

  Future<void> _refreshInBackground() async {
    try {
      await refreshSession();
    } on ApiException {
      if (!ref.mounted || session == null) return;
      _timer?.cancel();
      _timer = Timer(retryDelay, _refreshInBackground);
    } catch (_) {
      // Unexpected error (e.g. a malformed response): retry later too.
      if (!ref.mounted || session == null) return;
      _timer?.cancel();
      _timer = Timer(retryDelay, _refreshInBackground);
    }
  }
}
