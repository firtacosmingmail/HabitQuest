import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/remote/session.dart';

/// Persists the auth [Session] between launches.
abstract interface class SessionStore {
  /// The saved session, or `null` (also when it is unreadable).
  Future<Session?> read();

  Future<void> write(Session session);

  Future<void> clear();
}

/// [SessionStore] on `flutter_secure_storage`: Keychain on iOS,
/// EncryptedSharedPreferences/Keystore on Android, and on web an AES-GCM
/// encrypted value in localStorage via WebCrypto (which needs a secure
/// context: https or localhost).
class SecureSessionStore implements SessionStore {
  SecureSessionStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  static const key = 'habit_quest.session.v1';

  @override
  Future<Session?> read() async {
    try {
      final raw = await _storage.read(key: key);
      if (raw == null) return null;
      return Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      // Corrupt value, lost web encryption key, keychain error...: treat as
      // signed out and drop the unusable value.
      await clear();
      return null;
    }
  }

  @override
  Future<void> write(Session session) =>
      _storage.write(key: key, value: jsonEncode(session.toJson()));

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: key);
    } catch (_) {
      // Nothing more we can do; a later read() failing also signs out.
    }
  }
}

/// [SessionStore] in memory, for tests.
class InMemorySessionStore implements SessionStore {
  InMemorySessionStore([this.session]);

  Session? session;
  int writes = 0;

  @override
  Future<Session?> read() async => session;

  @override
  Future<void> write(Session session) async {
    writes++;
    this.session = session;
  }

  @override
  Future<void> clear() async => session = null;
}
