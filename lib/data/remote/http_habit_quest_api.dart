import 'api_exception.dart';
import 'authenticated_transport.dart';
import 'habit_quest_api.dart';
import 'json_utils.dart';
import 'remote_models.dart';

/// [HabitQuestApi] over HTTP (Edge Functions `habits`, `check-ins`,
/// `game-state`).
class HttpHabitQuestApi implements HabitQuestApi {
  final AuthenticatedTransport transport;

  HttpHabitQuestApi(this.transport);

  static const _habits = 'habits';
  static const _checkIns = 'check-ins';
  static const _gameState = 'game-state';

  // Habits ------------------------------------------------------------------

  @override
  Future<DeltaPage<RemoteHabit>> listHabits({DateTime? since}) => _list(
    _habits,
    RemoteHabit.fromJson,
    {if (since != null) 'since': formatTimestamp(since)},
  );

  @override
  Future<RemoteHabit?> getHabit(String id) =>
      _get(_habits, id, RemoteHabit.fromJson);

  @override
  Future<WriteResult<RemoteHabit>> putHabit(RemoteHabit habit) =>
      _put(_habits, habit, RemoteHabit.fromJson);

  @override
  Future<WriteResult<RemoteHabit>> deleteHabit(
    String id, {
    required DateTime updatedAt,
  }) => _delete(_habits, id, updatedAt, RemoteHabit.fromJson);

  @override
  Future<List<BatchItemResult<RemoteHabit>>> batchHabits(
    List<RemoteHabit> habits,
  ) => _batch(_habits, habits, RemoteHabit.fromJson);

  // Check-ins ---------------------------------------------------------------

  @override
  Future<DeltaPage<RemoteCheckIn>> listCheckIns({
    DateTime? since,
    String? habitId,
  }) => _list(_checkIns, RemoteCheckIn.fromJson, {
    if (since != null) 'since': formatTimestamp(since),
    'habitId': ?habitId,
  });

  @override
  Future<RemoteCheckIn?> getCheckIn(String id) =>
      _get(_checkIns, id, RemoteCheckIn.fromJson);

  @override
  Future<WriteResult<RemoteCheckIn>> putCheckIn(RemoteCheckIn checkIn) =>
      _put(_checkIns, checkIn, RemoteCheckIn.fromJson);

  @override
  Future<WriteResult<RemoteCheckIn>> deleteCheckIn(
    String id, {
    required DateTime updatedAt,
  }) => _delete(_checkIns, id, updatedAt, RemoteCheckIn.fromJson);

  @override
  Future<List<BatchItemResult<RemoteCheckIn>>> batchCheckIns(
    List<RemoteCheckIn> checkIns,
  ) => _batch(_checkIns, checkIns, RemoteCheckIn.fromJson);

  // Game state --------------------------------------------------------------

  @override
  Future<GameStateSnapshot> getGameState() async {
    final json = await transport.sendForObject('GET', _gameState);
    final item = json['item'];
    return GameStateSnapshot(
      item: item is Map<String, dynamic>
          ? RemoteGameState.fromJson(item)
          : null,
      serverTime: parseTimestamp(json['serverTime'], 'serverTime'),
    );
  }

  @override
  Future<WriteResult<RemoteGameState>> putGameState(
    RemoteGameState state,
  ) async {
    final json = await transport.sendForObject(
      'PUT',
      _gameState,
      body: state.toJson(),
    );
    return _writeResult(json, RemoteGameState.fromJson);
  }

  @override
  Future<void> deleteGameState() async {
    await transport.send('DELETE', _gameState);
  }

  // Helpers -----------------------------------------------------------------

  Future<DeltaPage<T>> _list<T>(
    String function,
    T Function(Map<String, dynamic>) fromJson,
    Map<String, String> query,
  ) async {
    final json = await transport.sendForObject('GET', function, query: query);
    return DeltaPage(
      items: readObjectList(json, 'items').map(fromJson).toList(),
      serverTime: parseTimestamp(json['serverTime'], 'serverTime'),
    );
  }

  Future<T?> _get<T>(
    String function,
    String id,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    try {
      return fromJson(
        await transport.sendForObject('GET', function, path: [id]),
      );
    } on ApiException catch (e) {
      if (e.status == 404 && e.code == ApiException.notFound) return null;
      rethrow;
    }
  }

  Future<WriteResult<T>> _put<T extends RemoteEntity>(
    String function,
    T entity,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final json = await transport.sendForObject(
      'PUT',
      function,
      path: [entity.id],
      body: entity.toJson(),
    );
    return _writeResult(json, fromJson);
  }

  Future<WriteResult<T>> _delete<T>(
    String function,
    String id,
    DateTime updatedAt,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    final json = await transport.sendForObject(
      'DELETE',
      function,
      path: [id],
      query: {'updatedAt': formatTimestamp(updatedAt)},
    );
    return _writeResult(json, fromJson);
  }

  Future<List<BatchItemResult<T>>> _batch<T extends RemoteEntity>(
    String function,
    List<T> items,
    T Function(Map<String, dynamic>) fromJson,
  ) async {
    if (items.isEmpty) return const [];
    final json = await transport.sendForObject(
      'POST',
      function,
      path: ['batch'],
      body: {
        'items': [for (final i in items) i.toJson()],
      },
    );
    return [
      for (final r in readObjectList(json, 'results'))
        BatchItemResult(
          id: readString(r, 'id'),
          applied: r['applied'] as bool? ?? false,
          item: fromJson(readObject(r, 'item')),
        ),
    ];
  }

  static WriteResult<T> _writeResult<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) fromJson,
  ) => WriteResult(
    item: fromJson(readObject(json, 'item')),
    applied: json['applied'] as bool? ?? false,
  );
}
