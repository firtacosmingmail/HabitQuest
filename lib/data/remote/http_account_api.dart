import 'account_api.dart';
import 'authenticated_transport.dart';

/// [AccountApi] over HTTP (Edge Functions `profile`,
/// `auth-change-password`, `account-delete`).
class HttpAccountApi implements AccountApi {
  final AuthenticatedTransport transport;

  HttpAccountApi(this.transport);

  @override
  Future<AccountProfile> getProfile() async =>
      AccountProfile.fromJson(await transport.sendForObject('GET', 'profile'));

  @override
  Future<AccountProfile> updateDisplayName(String displayName) async =>
      AccountProfile.fromJson(
        await transport.sendForObject(
          'PUT',
          'profile',
          body: {'displayName': displayName.trim()},
        ),
      );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await transport.send(
      'POST',
      'auth-change-password',
      body: {'currentPassword': currentPassword, 'newPassword': newPassword},
    );
  }

  @override
  Future<void> deleteAccount() async {
    await transport.send(
      'POST',
      'account-delete',
      body: {'confirm': deleteConfirmationWord},
    );
  }
}
