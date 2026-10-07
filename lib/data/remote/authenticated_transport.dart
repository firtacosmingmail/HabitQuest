import 'api_exception.dart';
import 'api_transport.dart';

/// Supplies access tokens to [AuthenticatedTransport]; implemented by the
/// `AuthController`.
abstract interface class AccessTokenProvider {
  /// A usable access token (refreshed first if it is about to expire), or
  /// `null` when signed out.
  Future<String?> accessToken();

  /// Called once after the server rejected [rejectedToken] with 401.
  /// Refreshes the session (unless it was already refreshed meanwhile) and
  /// returns the new token, or `null` if the refresh failed and the user was
  /// signed out.
  Future<String?> refreshAfterUnauthorized(String rejectedToken);
}

/// Wraps [ApiTransport] with the user's bearer token: on a 401
/// `unauthorized` it refreshes the session once and retries the request
/// once.
class AuthenticatedTransport {
  final ApiTransport transport;
  final AccessTokenProvider tokens;

  AuthenticatedTransport({required this.transport, required this.tokens});

  static const _signedOut = ApiException(
    status: 401,
    code: ApiException.unauthorized,
    message: 'You are signed out.',
  );

  Future<Object?> send(
    String method,
    String function, {
    List<String> path = const [],
    Map<String, String>? query,
    Object? body,
  }) async {
    final token = await tokens.accessToken();
    if (token == null) throw _signedOut;
    try {
      return await transport.send(
        method,
        function,
        path: path,
        query: query,
        body: body,
        accessToken: token,
      );
    } on ApiException catch (e) {
      if (!e.isUnauthorized) rethrow;
      final fresh = await tokens.refreshAfterUnauthorized(token);
      if (fresh == null) rethrow;
      return transport.send(
        method,
        function,
        path: path,
        query: query,
        body: body,
        accessToken: fresh,
      );
    }
  }

  Future<Map<String, dynamic>> sendForObject(
    String method,
    String function, {
    List<String> path = const [],
    Map<String, String>? query,
    Object? body,
  }) async {
    final result = await send(
      method,
      function,
      path: path,
      query: query,
      body: body,
    );
    if (result is Map<String, dynamic>) return result;
    throw const ApiException(
      code: ApiException.badResponse,
      message: 'Expected a JSON object from the server.',
    );
  }
}
