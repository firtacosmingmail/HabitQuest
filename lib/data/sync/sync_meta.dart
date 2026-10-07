import 'string_store.dart';

/// Persistent sync bookkeeping (hive box `sync_meta`):
///
/// * the user id that owns the local data ([ownerUserId]; `null` = data
///   created before any login, i.e. "anonymous");
/// * per user: the delta cursors (the `serverTime` of the last pull of
///   habits and of check-ins) and the time of the last successful sync.
class SyncMeta {
  static const boxName = 'sync_meta';
  static const _owner = 'owner';

  final StringStore _store;

  SyncMeta(this._store);

  String? get ownerUserId => _store.get(_owner);

  Future<void> setOwner(String userId) => _store.put(_owner, userId);

  DateTime? habitsCursor(String userId) => _date('habitsCursor:$userId');
  DateTime? checkInsCursor(String userId) => _date('checkInsCursor:$userId');
  DateTime? lastSyncedAt(String userId) => _date('lastSyncedAt:$userId');

  Future<void> setHabitsCursor(String userId, DateTime t) =>
      _store.put('habitsCursor:$userId', t.toUtc().toIso8601String());

  Future<void> setCheckInsCursor(String userId, DateTime t) =>
      _store.put('checkInsCursor:$userId', t.toUtc().toIso8601String());

  Future<void> setLastSyncedAt(String userId, DateTime t) =>
      _store.put('lastSyncedAt:$userId', t.toUtc().toIso8601String());

  /// Forgets every cursor and the owner (account switch: the next sync is
  /// a full pull).
  Future<void> clear() => _store.clear();

  DateTime? _date(String key) {
    final s = _store.get(key);
    return s == null ? null : DateTime.tryParse(s);
  }
}
