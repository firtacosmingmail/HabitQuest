import 'api_exception.dart';
import 'auth_api.dart';
import 'session.dart';

/// In-memory [AuthApi] mimicking the auth Edge Functions: accounts, token
/// issuing, refresh-token rotation and revocation.
class FakeAuthApi implements AuthApi {
  FakeAuthApi({
    DateTime Function()? now,
    this.tokenTtl = const Duration(hours: 1),
    this.requireConfirmation = false,
  }) : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  /// Lifetime of issued access tokens.
  Duration tokenTtl;

  /// When true, `register` answers `needsConfirmation` and `login` throws
  /// `email_not_confirmed` until [confirm] is called.
  bool requireConfirmation;

  /// When true every call throws a `network_error`.
  bool offline = false;

  /// Thrown (once) by the next call, after recording it in [calls].
  ApiException? failNextWith;

  /// Calls in order: `register`, `login`, `refresh`, `logout`.
  final List<String> calls = [];

  final _passwords = <String, String>{};
  final _userIds = <String, String>{};
  final _confirmed = <String>{};
  final _liveRefreshTokens = <String, String>{}; // refresh -> email
  final _liveAccessTokens = <String>{};
  var _counter = 0;

  /// Adds an account directly.
  void addUser(String email, String password, {bool confirmed = true}) {
    final key = email.toLowerCase();
    _passwords[key] = password;
    _userIds[key] = 'user-${_userIds.length + 1}';
    if (confirmed) _confirmed.add(key);
  }

  void confirm(String email) => _confirmed.add(email.toLowerCase());

  /// Invalidates every refresh token (e.g. password changed elsewhere).
  void revokeAll() {
    _liveRefreshTokens.clear();
    _liveAccessTokens.clear();
  }

  /// Whether [accessToken] was issued and not revoked.
  bool isAccessTokenLive(String accessToken) =>
      _liveAccessTokens.contains(accessToken);

  /// Mints a session for [email] (the account is created if needed).
  Session issueSession(String email) {
    final key = email.toLowerCase();
    if (!_userIds.containsKey(key)) addUser(email, 'password123');
    _counter++;
    final access = 'access-$_counter';
    final refresh = 'refresh-$_counter';
    _liveAccessTokens.add(access);
    _liveRefreshTokens[refresh] = key;
    final exp = _now().toUtc().add(tokenTtl);
    return Session(
      accessToken: access,
      refreshToken: refresh,
      // Epoch seconds on the wire.
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        exp.millisecondsSinceEpoch ~/ 1000 * 1000,
        isUtc: true,
      ),
      user: AuthUser(id: _userIds[key]!, email: key),
    );
  }

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    _enter('register');
    final key = email.toLowerCase();
    if (!key.contains('@')) {
      throw const ApiException(
        status: 400,
        code: ApiException.invalidInput,
        message: 'Invalid email',
      );
    }
    if (password.length < 6) {
      throw const ApiException(
        status: 400,
        code: ApiException.weakPassword,
        message: 'Password should be at least 6 characters',
      );
    }
    if (_passwords.containsKey(key)) {
      throw const ApiException(
        status: 409,
        code: ApiException.emailTaken,
        message: 'Email already registered',
      );
    }
    addUser(key, password, confirmed: !requireConfirmation);
    if (requireConfirmation) return const RegisterResult.needsConfirmation();
    return RegisterResult.signedIn(issueSession(key));
  }

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    _enter('login');
    final key = email.toLowerCase();
    if (_passwords[key] != password) {
      throw const ApiException(
        status: 401,
        code: ApiException.invalidCredentials,
        message: 'Invalid login credentials',
      );
    }
    if (!_confirmed.contains(key)) {
      throw const ApiException(
        status: 403,
        code: ApiException.emailNotConfirmed,
        message: 'Email not confirmed',
      );
    }
    return issueSession(key);
  }

  /// ID tokens the fake `auth-oauth` rejects with `invalid_token`.
  final rejectedIdTokens = <String>{};

  /// Providers the fake answers `provider_disabled` for.
  final disabledProviders = <String>{};

  /// Last `auth-oauth` call: provider, idToken, nonce.
  ({String provider, String idToken, String? nonce})? lastOAuth;

  @override
  Future<Session> oauth({
    required String provider,
    required String idToken,
    String? nonce,
  }) async {
    _enter('oauth');
    lastOAuth = (provider: provider, idToken: idToken, nonce: nonce);
    if (disabledProviders.contains(provider)) {
      throw const ApiException(
        status: 400,
        code: ApiException.providerDisabled,
        message: 'Provider is not enabled',
      );
    }
    if (rejectedIdTokens.contains(idToken)) {
      throw const ApiException(
        status: 401,
        code: ApiException.invalidToken,
        message: 'The sign-in token was rejected',
      );
    }
    // One account per provider in the fake.
    return issueSession('$provider-user@example.com');
  }

  @override
  Future<Session> refresh(String refreshToken) async {
    _enter('refresh');
    final email = _liveRefreshTokens.remove(refreshToken); // rotation
    if (email == null) {
      throw const ApiException(
        status: 401,
        code: ApiException.invalidRefreshToken,
        message: 'Invalid refresh token',
      );
    }
    return issueSession(email);
  }

  @override
  Future<void> logout(String accessToken) async {
    _enter('logout');
    if (!_liveAccessTokens.remove(accessToken)) {
      throw const ApiException(
        status: 401,
        code: ApiException.unauthorized,
        message: 'Invalid token',
      );
    }
  }

  void _enter(String call) {
    calls.add(call);
    if (offline) {
      throw const ApiException(
        code: ApiException.networkError,
        message: 'Offline (fake)',
      );
    }
    final fail = failNextWith;
    if (fail != null) {
      failNextWith = null;
      throw fail;
    }
  }
}
