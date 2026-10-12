import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/remote/account_api.dart';
import '../../data/remote/api_exception.dart';
import '../../domain/providers.dart';
import '../auth/auth_providers.dart';
import '../game/game_providers.dart';
import '../notifications/notifications_providers.dart';
import '../sync/sync_providers.dart';
import 'local_data_wiper.dart';

final localDataWiperProvider = Provider<LocalDataWiper>(
  (ref) => LocalDataWiper(
    service: ref.watch(habitServiceProvider),
    game: ref.watch(gameEngineProvider),
    queue: ref.watch(syncQueueProvider),
    meta: ref.watch(syncMetaProvider),
    scheduler: ref.watch(notificationSchedulerProvider),
  ),
);

/// The Profile screen's state: the server profile, loaded when the screen
/// opens (disposed when it closes).
final profileControllerProvider =
    AsyncNotifierProvider.autoDispose<ProfileController, AccountProfile>(
      ProfileController.new,
    );

/// Thrown by [ProfileController.deleteAccount] when the device is offline.
class OfflineException implements Exception {
  const OfflineException();

  static const message = 'You need to be online to delete your account.';

  @override
  String toString() => message;
}

class ProfileController extends AsyncNotifier<AccountProfile> {
  AccountApi get _api => ref.read(accountApiProvider);

  @override
  Future<AccountProfile> build() => ref.read(accountApiProvider).getProfile();

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_api.getProfile);
  }

  /// Saves a new display name. Throws [ApiException].
  Future<void> rename(String displayName) async {
    final updated = await _api.updateDisplayName(displayName.trim());
    if (ref.mounted) state = AsyncData(updated);
  }

  /// Changes the password, then signs in again with it: the server revokes
  /// the existing sessions when the password changes. Throws [ApiException].
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final auth = ref.read(authControllerProvider.notifier);
    final email = state.value?.email ?? auth.session?.user.email ?? '';
    await _api.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
    await auth.login(email: email, password: newPassword);
  }

  /// Deletes the account on the server and wipes the local data. Call
  /// [finishAccountDeletion] afterwards to sign out. Throws
  /// [OfflineException] when offline, [ApiException] otherwise.
  Future<void> deleteAccount() async {
    if (!await ref.read(connectivityMonitorProvider).isOnline()) {
      throw const OfflineException();
    }
    try {
      await _api.deleteAccount();
    } on ApiException catch (e) {
      if (e.isNetwork) throw const OfflineException();
      rethrow;
    }
    await ref.read(localDataWiperProvider).wipe();
  }

  /// Clears the session; the auth gate then shows the login screen with
  /// "Your account was deleted".
  Future<void> finishAccountDeletion() =>
      ref.read(authControllerProvider.notifier).signOutAfterAccountDeletion();
}

/// Up to two initials from [displayName] (or the email's local part).
String initialsFor(String? displayName, String email) {
  final source = (displayName ?? '').trim().isNotEmpty
      ? displayName!.trim()
      : email.split('@').first;
  final words = source
      .split(RegExp(r'[\s._\-+]+'))
      .where((w) => w.isNotEmpty)
      .toList();
  if (words.isEmpty) return '?';
  String first(String w) => String.fromCharCode(w.runes.first).toUpperCase();
  return words.length == 1
      ? first(words.first)
      : '${first(words.first)}${first(words[1])}';
}

/// "Email & password", "Google", "Apple"... for the sign-in providers.
String signInMethodLabel(List<String> providers) {
  if (providers.isEmpty) return 'Email & password';
  String label(String p) => switch (p) {
    'email' => 'Email & password',
    'google' => 'Google',
    'apple' => 'Apple',
    _ => p.isEmpty ? p : '${p[0].toUpperCase()}${p.substring(1)}',
  };
  return providers.map(label).join(' · ');
}

/// An emoji for the main sign-in provider.
String signInMethodEmoji(List<String> providers) =>
    switch (providers.isEmpty ? 'email' : providers.first) {
      'google' => '🌐',
      'apple' => '🍎',
      _ => '✉️',
    };
