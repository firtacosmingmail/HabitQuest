import 'account_api.dart';
import 'api_exception.dart';

/// In-memory [AccountApi] with the Edge Functions' rules: display name
/// 1–50 characters after trimming, password checks (`invalid_credentials`,
/// `weak_password`, `same_password`, `no_password`) and deletion.
///
/// For tests: [offline], [failNextWith], [calls]; [deleted] after
/// [deleteAccount].
class FakeAccountApi implements AccountApi {
  FakeAccountApi({AccountProfile? profile, this.password = 'password123'})
    : profile =
          profile ??
          AccountProfile(
            id: 'test-user',
            email: 'hero@example.com',
            displayName: 'Quest Hero',
            createdAt: DateTime.utc(2026, 3, 14),
          );

  AccountProfile profile;

  /// The current password (for [AccountProfile.hasPassword] accounts).
  String password;

  bool offline = false;
  bool deleted = false;

  /// Thrown (once) by the next call, after recording it in [calls].
  ApiException? failNextWith;

  /// `getProfile`, `updateDisplayName`, `changePassword`, `deleteAccount`.
  final List<String> calls = [];

  @override
  Future<AccountProfile> getProfile() async {
    _enter('getProfile');
    return profile;
  }

  @override
  Future<AccountProfile> updateDisplayName(String displayName) async {
    _enter('updateDisplayName');
    final name = displayName.trim();
    if (name.isEmpty || name.runes.length > 50) {
      throw const ApiException(
        status: 400,
        code: ApiException.invalidInput,
        message: 'displayName must be 1 to 50 characters',
      );
    }
    return profile = profile.copyWith(displayName: name);
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    _enter('changePassword');
    if (!profile.hasPassword) {
      throw const ApiException(
        status: 409,
        code: ApiException.noPassword,
        message: 'This account signs in without a password',
      );
    }
    if (newPassword.length < 6 || newPassword.length > 72) {
      throw const ApiException(
        status: 400,
        code: ApiException.weakPassword,
        message: 'Password should be at least 6 characters',
      );
    }
    if (newPassword == currentPassword) {
      throw const ApiException(
        status: 400,
        code: ApiException.samePassword,
        message: 'The new password must differ from the current one',
      );
    }
    if (currentPassword != password) {
      throw const ApiException(
        status: 401,
        code: ApiException.invalidCredentials,
        message: 'The current password is not correct',
      );
    }
    password = newPassword;
  }

  @override
  Future<void> deleteAccount() async {
    _enter('deleteAccount');
    deleted = true;
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
