import 'api_exception.dart';
import 'habit_quest_api.dart';
import 'remote_models.dart';

/// In-memory [HabitQuestApi] that behaves like the Edge Functions for a
/// single signed-in user: strict last-write-wins on `updatedAt`, soft-delete
/// tombstones, `since` delta pulls on a server-side change time, atomic
/// check-in batches that fail with `habit_not_found`, and 404s.
///
/// For tests: inject failures with [offline] / [failNextWith], inspect
/// [calls], seed rows with [seedHabit] / [seedCheckIn] (bypassing LWW).
class FakeHabitQuestApi implements HabitQuestApi {
  FakeHabitQuestApi({DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final DateTime Function() _now;

  final _habits = <String, _Row<RemoteHabit>>{};
  final _checkIns = <String, _Row<RemoteCheckIn>>{};
  _Row<RemoteGameState>? _gameState;
  DateTime? _lastServerTime;

  /// When true every call throws a `network_error` [ApiException].
  bool offline = false;

  /// Thrown (once) by the next call, after recording it in [calls].
  ApiException? failNextWith;

  /// Every call as `"<method> <function>[/<id>]"`, e.g. `PUT habits/h1`.
  final List<String> calls = [];

  /// Max items per batch, as on the server.
  static const maxBatch = 500;

  // Inspection --------------------------------------------------------------

  /// Stored habits by id (tombstones included).
  Map<String, RemoteHabit> get habits =>
      {for (final e in _habits.entries) e.key: e.value.item};

  /// Stored check-ins by id (tombstones included).
  Map<String, RemoteCheckIn> get checkIns =>
      {for (final e in _checkIns.entries) e.key: e.value.item};

  RemoteGameState? get gameState => _gameState?.item;

  /// Stores a habit as if another device had written it (no LWW).
  void seedHabit(RemoteHabit habit) =>
      _habits[habit.id] = _Row(habit, _tick());

  void seedCheckIn(RemoteCheckIn checkIn) =>
      _checkIns[checkIn.id] = _Row(checkIn, _tick());

  void seedGameState(RemoteGameState state) =>
      _gameState = _Row(state, _tick());

  // Habits ------------------------------------------------------------------

  @override
  Future<DeltaPage<RemoteHabit>> listHabits({DateTime? since}) async {
    _enter('GET habits');
    return _list(_habits, since, (_) => true);
  }

  @override
  Future<RemoteHabit?> getHabit(String id) async {
    _enter('GET habits/$id');
    return _habits[id]?.item;
  }

  @override
  Future<WriteResult<RemoteHabit>> putHabit(RemoteHabit habit) async {
    _enter('PUT habits/${habit.id}');
    return _upsert(_habits, habit);
  }

  @override
  Future<WriteResult<RemoteHabit>> deleteHabit(
    String id, {
    required DateTime updatedAt,
  }) async {
    _enter('DELETE habits/$id');
    final row = _habits[id];
    if (row == null) throw _notFound;
    final t = updatedAt.toUtc();
    return _upsert(
      _habits,
      row.item.copyWith(updatedAt: t, deletedAt: () => t),
    );
  }

  @override
  Future<List<BatchItemResult<RemoteHabit>>> batchHabits(
    List<RemoteHabit> habits,
  ) async {
    _enter('POST habits/batch');
    _checkBatchSize(habits.length);
    return [
      for (final h in habits)
        _toBatch(h.id, _upsert(_habits, h)),
    ];
  }

  // Check-ins ---------------------------------------------------------------

  @override
  Future<DeltaPage<RemoteCheckIn>> listCheckIns({
    DateTime? since,
    String? habitId,
  }) async {
    _enter('GET check-ins');
    return _list(
      _checkIns,
      since,
      (c) => habitId == null || c.habitId == habitId,
    );
  }

  @override
  Future<RemoteCheckIn?> getCheckIn(String id) async {
    _enter('GET check-ins/$id');
    return _checkIns[id]?.item;
  }

  @override
  Future<WriteResult<RemoteCheckIn>> putCheckIn(RemoteCheckIn checkIn) async {
    _enter('PUT check-ins/${checkIn.id}');
    _requireHabits([checkIn]);
    return _upsert(_checkIns, checkIn);
  }

  @override
  Future<WriteResult<RemoteCheckIn>> deleteCheckIn(
    String id, {
    required DateTime updatedAt,
  }) async {
    _enter('DELETE check-ins/$id');
    final row = _checkIns[id];
    if (row == null) throw _notFound;
    final t = updatedAt.toUtc();
    return _upsert(
      _checkIns,
      row.item.copyWith(updatedAt: t, deletedAt: () => t),
    );
  }

  @override
  Future<List<BatchItemResult<RemoteCheckIn>>> batchCheckIns(
    List<RemoteCheckIn> checkIns,
  ) async {
    _enter('POST check-ins/batch');
    _checkBatchSize(checkIns.length);
    _requireHabits(checkIns); // atomic: nothing written on failure
    return [
      for (final c in checkIns) _toBatch(c.id, _upsert(_checkIns, c)),
    ];
  }

  // Game state --------------------------------------------------------------

  @override
  Future<GameStateSnapshot> getGameState() async {
    _enter('GET game-state');
    return GameStateSnapshot(item: _gameState?.item, serverTime: _tick());
  }

  @override
  Future<WriteResult<RemoteGameState>> putGameState(
    RemoteGameState state,
  ) async {
    _enter('PUT game-state');
    final current = _gameState;
    if (current != null && !state.updatedAt.isAfter(current.item.updatedAt)) {
      return WriteResult(item: current.item, applied: false);
    }
    _gameState = _Row(state, _tick());
    return WriteResult(item: state, applied: true);
  }

  @override
  Future<void> deleteGameState() async {
    _enter('DELETE game-state');
    _gameState = null;
  }

  // Internals ---------------------------------------------------------------

  static const _notFound = ApiException(
    status: 404,
    code: ApiException.notFound,
    message: 'Not found',
  );

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

  /// Strictly increasing server clock (like `server_updated_at`).
  DateTime _tick() {
    var t = _now().toUtc();
    final last = _lastServerTime;
    if (last != null && !t.isAfter(last)) {
      t = last.add(const Duration(milliseconds: 1));
    }
    return _lastServerTime = t;
  }

  DeltaPage<T> _list<T extends RemoteEntity>(
    Map<String, _Row<T>> table,
    DateTime? since,
    bool Function(T) where,
  ) {
    final rows =
        table.values
            .where((r) => since == null || r.serverUpdatedAt.isAfter(since))
            .where((r) => where(r.item))
            .toList()
          ..sort((a, b) => a.serverUpdatedAt.compareTo(b.serverUpdatedAt));
    return DeltaPage(
      items: [for (final r in rows) r.item],
      serverTime: _tick(),
    );
  }

  WriteResult<T> _upsert<T extends RemoteEntity>(
    Map<String, _Row<T>> table,
    T incoming,
  ) {
    final current = table[incoming.id];
    if (current != null &&
        !incoming.updatedAt.isAfter(current.item.updatedAt)) {
      return WriteResult(item: current.item, applied: false);
    }
    table[incoming.id] = _Row(incoming, _tick());
    return WriteResult(item: incoming, applied: true);
  }

  void _requireHabits(List<RemoteCheckIn> checkIns) {
    for (final c in checkIns) {
      if (!_habits.containsKey(c.habitId)) {
        throw ApiException(
          status: 409,
          code: ApiException.habitNotFound,
          message: 'Habit ${c.habitId} does not exist',
        );
      }
    }
  }

  void _checkBatchSize(int n) {
    if (n > maxBatch) {
      throw const ApiException(
        status: 400,
        code: ApiException.invalidInput,
        message: 'Too many items',
      );
    }
  }

  static BatchItemResult<T> _toBatch<T>(String id, WriteResult<T> r) =>
      BatchItemResult(id: id, applied: r.applied, item: r.item);
}

class _Row<T> {
  final T item;
  final DateTime serverUpdatedAt;

  _Row(this.item, this.serverUpdatedAt);
}
