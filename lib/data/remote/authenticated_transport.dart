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
///
/// Requests sent with `allowAnonymous: true` (the public `GET /quotes`
/// reads, see "Signed-out reads" in `supabase/API.md`) go out with **no
/// `Authorization` header at all** when there is no session, or when the
/// rejected token could not be refreshed (the user was signed out). The
/// anon key is never sent as a bearer token: the server answers that with
/// 401.
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
    bool allowAnonymous = false,
  }) async {
    final token = await tokens.accessToken();
    if (token == null) {
      if (!allowAnonymous) throw _signedOut;
      return transport.send(
        method,
        function,
        path: path,
        query: query,
        body: body,
      );
    }
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
      if (fresh == null) {
        if (!allowAnonymous) rethrow;
        // Signed out by the failed refresh: retry once without a token.
        return transport.send(
          method,
          function,
          path: path,
          query: query,
          body: body,
        );
      }
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
    bool allowAnonymous = false,
  }) async {
    final result = await send(
      method,
      function,
      path: path,
      query: query,
      body: body,
      allowAnonymous: allowAnonymous,
    );
    if (result is Map<String, dynamic>) return result;
    throw const ApiException(
      code: ApiException.badResponse,
      message: 'Expected a JSON object from the server.',
    );
  }
}
