import 'api_exception.dart';
import 'json_utils.dart';

/// The signed-in user.
class AuthUser {
  final String id;
  final String email;

  const AuthUser({required this.id, required this.email});

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
    id: readString(json, 'id'),
    email: json['email'] as String? ?? '',
  );

  Map<String, dynamic> toJson() => {'id': id, 'email': email};

  @override
  bool operator ==(Object other) =>
      other is AuthUser && other.id == id && other.email == email;

  @override
  int get hashCode => Object.hash(id, email);
}

/// An auth session as returned by `auth-register`/`auth-login`/`auth-refresh`.
class Session {
  final String accessToken;
  final String refreshToken;

  /// When [accessToken] expires (UTC). Serialised as epoch seconds.
  final DateTime expiresAt;
  final AuthUser user;

  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  factory Session.fromJson(Map<String, dynamic> json) {
    final exp = json['expiresAt'];
    if (exp is! num) {
      throw const ApiException(
        code: ApiException.badResponse,
        message: 'Session.expiresAt missing',
      );
    }
    final user = json['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException(
        code: ApiException.badResponse,
        message: 'Session.user missing',
      );
    }
    return Session(
      accessToken: readString(json, 'accessToken'),
      refreshToken: readString(json, 'refreshToken'),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        (exp * 1000).round(),
        isUtc: true,
      ),
      user: AuthUser.fromJson(user),
    );
  }

  Map<String, dynamic> toJson() => {
    'accessToken': accessToken,
    'refreshToken': refreshToken,
    'expiresAt': expiresAt.millisecondsSinceEpoch ~/ 1000,
    'user': user.toJson(),
  };

  /// Whether the access token is expired (or expires within [leeway]).
  bool isExpiredAt(DateTime now, {Duration leeway = Duration.zero}) =>
      !now.add(leeway).isBefore(expiresAt);

  @override
  bool operator ==(Object other) =>
      other is Session &&
      other.accessToken == accessToken &&
      other.refreshToken == refreshToken &&
      other.expiresAt == expiresAt &&
      other.user == user;

  @override
  int get hashCode => Object.hash(accessToken, refreshToken, expiresAt, user);

  @override
  String toString() => 'Session(user: ${user.email}, expiresAt: $expiresAt)';
}
