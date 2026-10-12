import 'json_utils.dart';

/// The signed-in user's profile (`GET /profile`).
class AccountProfile {
  final String id;
  final String email;
  final String? displayName;

  /// When the account was created ("member since"), UTC.
  final DateTime? createdAt;

  /// Sign-in methods, e.g. `['email']`, `['google']`.
  final List<String> providers;

  /// Whether the account has a password (an `email` identity); social
  /// accounts (Google/Apple) do not, so they cannot change it.
  final bool hasPassword;

  const AccountProfile({
    required this.id,
    required this.email,
    this.displayName,
    this.createdAt,
    this.providers = const ['email'],
    this.hasPassword = true,
  });

  factory AccountProfile.fromJson(Map<String, dynamic> json) {
    final providers = json['providers'];
    return AccountProfile(
      id: readString(json, 'id'),
      email: json['email'] as String? ?? '',
      displayName: json['displayName'] as String?,
      createdAt: parseTimestampOrNull(json['createdAt'], 'createdAt'),
      providers: providers is List
          ? [
              for (final p in providers)
                if (p is String) p,
            ]
          : const [],
      hasPassword: json['hasPassword'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'email': email,
    'displayName': displayName,
    'createdAt': createdAt == null ? null : formatTimestamp(createdAt!),
    'providers': providers,
    'hasPassword': hasPassword,
  };

  AccountProfile copyWith({String? displayName}) => AccountProfile(
    id: id,
    email: email,
    displayName: displayName ?? this.displayName,
    createdAt: createdAt,
    providers: providers,
    hasPassword: hasPassword,
  );
}

/// The account Edge Functions (`profile`, `auth-change-password`,
/// `account-delete`) for the signed-in user. Every method throws
/// [ApiException] on failure (`isNetwork` when offline).
abstract interface class AccountApi {
  Future<AccountProfile> getProfile();

  /// Trimmed, 1–50 characters; throws `invalid_input` (400) otherwise.
  Future<AccountProfile> updateDisplayName(String displayName);

  /// Throws `invalid_credentials` (401) for a wrong [currentPassword],
  /// `weak_password` / `same_password` (400) and `no_password` (409, social
  /// accounts). The server revokes the existing sessions on success.
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });

  /// Deletes the account and all of its data on the server (irreversible).
  Future<void> deleteAccount();
}

/// The exact confirmation word `account-delete` requires.
const deleteConfirmationWord = 'DELETE';
