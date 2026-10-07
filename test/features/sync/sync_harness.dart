import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/habit.dart';
import 'package:habit_quest/data/remote/habit_quest_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/data/sync/sync_meta.dart';
import 'package:habit_quest/data/sync/sync_queue.dart';
import 'package:habit_quest/domain/habit_events.dart';
import 'package:habit_quest/domain/habit_service.dart';
import 'package:habit_quest/features/game/game_engine.dart';
import 'package:habit_quest/features/game/game_events.dart';
import 'package:habit_quest/features/game/game_repository.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/sync/sync_engine.dart';

/// Monday 5 Jan 2026, 10:00 local.
final start = DateTime(2026, 1, 5, 10);

/// A shared, controllable wall clock (all devices and the server).
class TestClock {
  DateTime now = start;

  DateTime call() => now;

  void advance([Duration d = const Duration(minutes: 1)]) => now = now.add(d);
}

/// One app install: repositories recording into a queue, the service, the
/// game engine and a sync engine pointed at [api].
class Device {
  final String name;
  final TestClock clock;
  HabitQuestApi api;
  final StringStore queueStore;
  final StringStore metaStore;
  late final SyncQueue queue;
  late final SyncMeta meta;
  late final InMemoryHabitRepository repo;
  late final HabitService service;
  late final InMemoryGameRepository gameRepo;
  late final GameEngine game;
  final List<GameEvent> gameEvents = [];
  final List<CompletionEvent> completionEvents = [];

  Device(
    this.name, {
    required this.clock,
    required this.api,
    StringStore? queueStore,
    StringStore? metaStore,
  }) : queueStore = queueStore ?? MemoryStringStore(),
       metaStore = metaStore ?? MemoryStringStore() {
    queue = SyncQueue(this.queueStore, now: clock.call);
    meta = SyncMeta(this.metaStore);
    repo = InMemoryHabitRepository(recorder: queue, now: clock.call);
    service = HabitService(repo, now: clock.call, idGenerator: _ids);
    gameRepo = InMemoryGameRepository(GameState.empty, queue);
    game = GameEngine(service: service, repository: gameRepo, now: clock.call)
      ..start();
    game.events.listen(gameEvents.add);
    service.completionEvents.listen(completionEvents.add);
    addTearDown(game.dispose);
  }

  int _n = 0;
  String _ids() => '$name-habit-${_n++}';

  SyncEngine get engine => SyncEngine(
    api: api,
    service: service,
    game: game,
    queue: queue,
    meta: meta,
    now: clock.call,
  );

  int get xp => game.state.xp;

  /// Signs in as [user] (account handling) and syncs.
  Future<SyncReport> sync({String user = 'u1'}) async {
    clock.advance();
    await pumpEventQueue();
    await engine.prepareForUser(user);
    final report = await engine.sync(user);
    await pumpEventQueue();
    return report;
  }

  Future<Habit> createHabit(String name) async {
    clock.advance();
    final h = await service.createHabit(
      name: name,
      emoji: '⭐',
      colorValue: 0xFF7C4DFF,
    );
    await pumpEventQueue();
    return h;
  }

  Future<void> check(String habitId, DateTime date, [bool done = true]) async {
    clock.advance();
    await service.setCompletion(habitId, date, done);
    await pumpEventQueue();
  }

  Future<void> toggle(String habitId, DateTime date) async {
    clock.advance();
    await service.toggleCompletion(habitId, date);
    await pumpEventQueue();
  }

  int xpGainedEvents() => gameEvents.whereType<XpGained>().length;
}
