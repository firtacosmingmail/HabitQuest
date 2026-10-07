import 'package:hive_ce/hive.dart';

/// A tiny persistent string map, so the sync queue and sync metadata can be
/// backed by hive (app) or memory (tests).
abstract interface class StringStore {
  String? get(String key);
  Iterable<String> get keys;
  Future<void> put(String key, String value);
  Future<void> delete(String key);
  Future<void> clear();
  Future<void> close();
}

class MemoryStringStore implements StringStore {
  final Map<String, String> data;

  MemoryStringStore([Map<String, String>? initial]) : data = {...?initial};

  @override
  String? get(String key) => data[key];

  @override
  Iterable<String> get keys => data.keys.toList();

  @override
  Future<void> put(String key, String value) async => data[key] = value;

  @override
  Future<void> delete(String key) async => data.remove(key);

  @override
  Future<void> clear() async => data.clear();

  @override
  Future<void> close() async {}
}

class HiveStringStore implements StringStore {
  final Box<String> _box;

  HiveStringStore._(this._box);

  static Future<HiveStringStore> open(String boxName) async =>
      HiveStringStore._(await Hive.openBox<String>(boxName));

  @override
  String? get(String key) => _box.get(key);

  @override
  Iterable<String> get keys => _box.keys.cast<String>().toList();

  @override
  Future<void> put(String key, String value) => _box.put(key, value);

  @override
  Future<void> delete(String key) => _box.delete(key);

  @override
  Future<void> clear() async => _box.clear();

  @override
  Future<void> close() => _box.close();
}
