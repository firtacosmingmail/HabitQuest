import 'api_exception.dart';
import 'api_transport.dart';
import 'auth_api.dart';
import 'session.dart';

/// [AuthApi] over HTTP (Edge Functions `auth-*`).
class HttpAuthApi implements AuthApi {
  final ApiTransport transport;

  HttpAuthApi(this.transport);

  @override
  Future<RegisterResult> register({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final json = await transport.sendForObject(
      'POST',
      'auth-register',
      body: {
        'email': email,
        'password': password,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
      },
    );
    final session = json['session'];
    if (session is Map<String, dynamic>) {
      return RegisterResult.signedIn(Session.fromJson(session));
    }
    if (json['needsConfirmation'] == true) {
      return const RegisterResult.needsConfirmation();
    }
    throw const ApiException(
      code: ApiException.badResponse,
      message: 'auth-register returned neither a session nor '
          'needsConfirmation.',
    );
  }

  @override
  Future<Session> login({
    required String email,
    required String password,
  }) async {
    final json = await transport.sendForObject(
      'POST',
      'auth-login',
      body: {'email': email, 'password': password},
    );
    return _session(json);
  }

  @override
  Future<Session> refresh(String refreshToken) async {
    final json = await transport.sendForObject(
      'POST',
      'auth-refresh',
      body: {'refreshToken': refreshToken},
    );
    return _session(json);
  }

  @override
  Future<void> logout(String accessToken) async {
    await transport.send('POST', 'auth-logout', accessToken: accessToken);
  }

  static Session _session(Map<String, dynamic> json) {
    final session = json['session'];
    if (session is Map<String, dynamic>) return Session.fromJson(session);
    throw const ApiException(
      code: ApiException.badResponse,
      message: 'Expected a session from the server.',
    );
  }
}
