import 'dart:convert';

import 'package:hive_ce/hive.dart';

import 'game_state.dart';

/// Persistence boundary for the game state.
///
/// Implementations: [HiveGameRepository] (app) and [InMemoryGameRepository]
/// (tests, and the default when `gameRepositoryProvider` is not overridden).
abstract interface class GameRepository {
  /// The stored state ([GameState.empty] if nothing is stored yet).
  GameState load();

  Future<void> save(GameState state);

  Future<void> close();
}

/// Non-persistent [GameRepository].
class InMemoryGameRepository implements GameRepository {
  GameState _state;

  InMemoryGameRepository([GameState initial = GameState.empty])
    : _state = initial;

  @override
  GameState load() => _state;

  @override
  Future<void> save(GameState state) async => _state = state;

  @override
  Future<void> close() async {}
}

/// [GameRepository] backed by a hive_ce box (`game`), storing the state as a
/// single JSON string under the key `state`. Call `Hive.initFlutter()` (app)
/// or `Hive.init(path)` (tests) before [open].
class HiveGameRepository implements GameRepository {
  static const boxName = 'game';
  static const stateKey = 'state';

  final Box<String> _box;

  HiveGameRepository._(this._box);

  /// Opens (or creates) the box. [boxPrefix] lets tests isolate data.
  static Future<HiveGameRepository> open({String boxPrefix = ''}) async =>
      HiveGameRepository._(await Hive.openBox<String>('$boxPrefix$boxName'));

  @override
  GameState load() {
    final s = _box.get(stateKey);
    if (s == null) return GameState.empty;
    try {
      return GameState.fromJson(jsonDecode(s) as Map<String, dynamic>);
    } on Object {
      // Corrupt data must never crash the app; start over.
      return GameState.empty;
    }
  }

  @override
  Future<void> save(GameState state) =>
      _box.put(stateKey, jsonEncode(state.toJson()));

  @override
  Future<void> close() => _box.close();
}
