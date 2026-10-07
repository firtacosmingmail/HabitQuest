import 'dart:async';
import 'dart:convert';

import 'change_recorder.dart';
import 'string_store.dart';

/// One pending local change. The queue stores *which* entity changed, not a
/// payload: the push always sends the entity's current local record, so
/// several edits of the same entity coalesce into one entry and the latest
/// local change wins.
class SyncQueueEntry {
  final SyncEntityType type;
  final String id;

  /// Bumped on every new local change of the entity; an acknowledgement only
  /// removes the entry if no newer change was recorded in the meantime.
  final int seq;
  final DateTime queuedAt;

  /// Failed (non-network) push attempts since the last local change.
  final int attempts;

  /// The last push error for this entity (kept and reported, never blocks
  /// other entries); `null` if none.
  final String? lastError;

  const SyncQueueEntry({
    required this.type,
    required this.id,
    required this.seq,
    required this.queuedAt,
    this.attempts = 0,
    this.lastError,
  });

  String get key => keyFor(type, id);

  static String keyFor(SyncEntityType type, String id) => '${type.name}:$id';

  bool get hasError => lastError != null;

  Map<String, dynamic> toJson() => {
        'type': type.name,
        'id': id,
        'seq': seq,
        'queuedAt': queuedAt.toUtc().toIso8601String(),
        'attempts': attempts,
        'lastError': lastError,
      };

  factory SyncQueueEntry.fromJson(Map<String, dynamic> json) => SyncQueueEntry(
        type: SyncEntityType.values.byName(json['type'] as String),
        id: json['id'] as String,
        seq: (json['seq'] as num).toInt(),
        queuedAt: DateTime.parse(json['queuedAt'] as String),
        attempts: (json['attempts'] as num?)?.toInt() ?? 0,
        lastError: json['lastError'] as String?,
      );

  @override
  String toString() =>
      'SyncQueueEntry($key, seq $seq${hasError ? ', error: $lastError' : ''})';
}

/// The persistent queue of local changes waiting to be pushed (hive box
/// `sync_queue`), coalesced per entity. Survives restarts.
class SyncQueue implements ChangeRecorder {
  static const boxName = 'sync_queue';

  final StringStore _store;
  final DateTime Function() _now;
  final Map<String, SyncQueueEntry> _entries = {};
  final _changes = StreamController<void>.broadcast();
  int _seq = 0;

  SyncQueue(this._store, {DateTime Function()? now})
      : _now = now ?? DateTime.now {
    for (final k in _store.keys) {
      try {
        final e = SyncQueueEntry.fromJson(
          jsonDecode(_store.get(k)!) as Map<String, dynamic>,
        );
        _entries[e.key] = e;
        if (e.seq > _seq) _seq = e.seq;
      } on Object {
        // Unreadable entry: drop it rather than block the queue.
        _store.delete(k);
      }
    }
  }

  /// Emits after every recorded local change (drives the debounced sync).
  Stream<void> get changes => _changes.stream;

  /// Pending entries, oldest change first.
  List<SyncQueueEntry> get entries =>
      _entries.values.toList()..sort((a, b) => a.seq.compareTo(b.seq));

  List<SyncQueueEntry> entriesOf(SyncEntityType type) =>
      entries.where((e) => e.type == type).toList();

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;

  /// Entries whose last push failed with a non-network error.
  List<SyncQueueEntry> get failed =>
      entries.where((e) => e.hasError).toList();

  SyncQueueEntry? entryFor(SyncEntityType type, String id) =>
      _entries[SyncQueueEntry.keyFor(type, id)];

  /// Records (or coalesces) a local change; resets any previous error.
  @override
  Future<void> recordChange(SyncEntityType type, String id) async {
    final e = SyncQueueEntry(
      type: type,
      id: id,
      seq: ++_seq,
      queuedAt: _now(),
    );
    _entries[e.key] = e;
    await _store.put(e.key, jsonEncode(e.toJson()));
    _changes.add(null);
  }

  /// Removes [entry] once the server acknowledged it, unless the entity
  /// changed again since (then the newer entry stays queued).
  Future<void> ack(SyncQueueEntry entry) async {
    final current = _entries[entry.key];
    if (current == null || current.seq != entry.seq) return;
    _entries.remove(entry.key);
    await _store.delete(entry.key);
  }

  /// Keeps [entry] queued with [error] (reported in the sync status).
  Future<void> markFailed(SyncQueueEntry entry, String error) async {
    final current = _entries[entry.key];
    if (current == null || current.seq != entry.seq) return;
    final e = SyncQueueEntry(
      type: current.type,
      id: current.id,
      seq: current.seq,
      queuedAt: current.queuedAt,
      attempts: current.attempts + 1,
      lastError: error,
    );
    _entries[e.key] = e;
    await _store.put(e.key, jsonEncode(e.toJson()));
  }

  /// Drops everything (account switch).
  Future<void> clear() async {
    _entries.clear();
    await _store.clear();
  }

  Future<void> close() async {
    await _changes.close();
    await _store.close();
  }
}
