/// Riverpod providers for the game engine.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/providers.dart';
import 'achievements.dart';
import 'game_engine.dart';
import 'game_events.dart';
import 'game_profile.dart';
import 'game_repository.dart';

/// Game storage. `main.dart` overrides it with a [HiveGameRepository];
/// without an override (tests) the state lives in memory.
final gameRepositoryProvider = Provider<GameRepository>(
  (ref) => InMemoryGameRepository(),
);

/// The single, started [GameEngine]. Read eagerly at app launch (see
/// `app.dart`) so no check-in is missed.
final gameEngineProvider = Provider<GameEngine>((ref) {
  final engine = GameEngine(
    service: ref.watch(habitServiceProvider),
    repository: ref.watch(gameRepositoryProvider),
    now: ref.watch(clockProvider),
  )..start();
  ref.onDispose(engine.dispose);
  return engine;
});

/// The player's profile (xp, level, progress, title, achievements, stats),
/// updated after every engine change.
final gameProfileProvider = NotifierProvider<GameProfileNotifier, GameProfile>(
  GameProfileNotifier.new,
);

class GameProfileNotifier extends Notifier<GameProfile> {
  @override
  GameProfile build() {
    final engine = ref.watch(gameEngineProvider);
    final sub = engine.stateChanges.listen(
      (s) => state = GameProfile.fromState(s),
    );
    ref.onDispose(sub.cancel);
    return engine.profile;
  }
}

/// All achievements in display order (locked and unlocked).
final achievementsCatalogProvider = Provider<List<Achievement>>(
  (ref) => achievementCatalog,
);

/// Broadcast stream of [GameEvent]s (XpGained, XpLost, LevelUp,
/// AchievementUnlocked) for celebrations. Subscribe with
/// `ref.read(gameEventsProvider).listen(...)` and cancel on dispose.
final gameEventsProvider = Provider<Stream<GameEvent>>(
  (ref) => ref.watch(gameEngineProvider).events,
);
