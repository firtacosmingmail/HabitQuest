/// An error from the backend, in the contract's
/// `{"error": {"code", "message"}}` format (see supabase/API.md). Copied in
/// spirit from the mobile app's lib/data/remote/api_exception.dart.
class ApiException implements Exception {
  /// HTTP status, or null when the server could not be reached.
  final int? status;
  final String code;
  final String message;

  const ApiException({this.status, required this.code, required this.message});

  static const unauthorized = 'unauthorized';
  static const forbidden = 'forbidden';
  static const invalidCredentials = 'invalid_credentials';
  static const invalidRefreshToken = 'invalid_refresh_token';
  static const dayTaken = 'day_taken';
  static const notFound = 'not_found';
  static const networkError = 'network_error';
  static const badResponse = 'bad_response';

  bool get isForbidden => status == 403 && code == forbidden;
  bool get isUnauthorized => status == 401;

  @override
  String toString() => 'ApiException($status, $code): $message';
}
