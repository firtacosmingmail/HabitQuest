/// An error from the backend (or from reaching it).
///
/// [status] is the HTTP status, or `null` when the server could not be
/// reached ([code] is then [networkError]). [code] is the contract's
/// `error.code` (e.g. `unauthorized`, `email_taken`, `not_found`).
class ApiException implements Exception {
  final int? status;
  final String code;
  final String message;

  const ApiException({this.status, required this.code, required this.message});

  // Codes from the shared API contract.
  static const unauthorized = 'unauthorized';
  static const invalidCredentials = 'invalid_credentials';
  static const invalidRefreshToken = 'invalid_refresh_token';
  static const emailTaken = 'email_taken';
  static const emailNotConfirmed = 'email_not_confirmed';
  static const invalidInput = 'invalid_input';
  static const weakPassword = 'weak_password';
  static const samePassword = 'same_password';
  static const noPassword = 'no_password';
  static const notFound = 'not_found';
  static const habitNotFound = 'habit_not_found';
  static const rateLimited = 'rate_limited';
  static const internalError = 'internal_error';

  // Client-side codes.
  static const networkError = 'network_error';
  static const badResponse = 'bad_response';
  static const notConfigured = 'not_configured';

  /// The server could not be reached (offline, DNS, CORS, timeout...).
  bool get isNetwork => code == networkError;

  /// The access token is missing, invalid or expired.
  bool get isUnauthorized => status == 401 && code == unauthorized;

  @override
  String toString() => 'ApiException($status, $code): $message';
}
