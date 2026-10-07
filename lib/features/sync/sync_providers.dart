/// Riverpod wiring for offline-first sync.
///
/// `main.dart` overrides [syncQueueProvider] and [syncMetaProvider] with
/// hive-backed instances (the same queue is the repositories'
/// `ChangeRecorder`). Tests override them with memory-backed ones, plus
/// [connectivityMonitorProvider] (`FakeConnectivityMonitor`) and
/// `habitQuestApiProvider` (`FakeHabitQuestApi`).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/backend_config.dart';
import '../../data/sync/string_store.dart';
import '../../data/sync/sync_meta.dart';
import '../../data/sync/sync_queue.dart';
import '../../domain/providers.dart';
import '../auth/auth_providers.dart';
import '../game/game_providers.dart';
import 'connectivity.dart';
import 'sync_controller.dart';
import 'sync_engine.dart';

export 'sync_controller.dart';

final syncQueueProvider = Provider<SyncQueue>(
  (ref) => SyncQueue(MemoryStringStore(), now: ref.watch(clockProvider)),
);

final syncMetaProvider = Provider<SyncMeta>(
  (ref) => SyncMeta(MemoryStringStore()),
);

/// connectivity_plus + a reachability probe of Supabase's auth health
/// endpoint.
final connectivityMonitorProvider = Provider<ConnectivityMonitor>((ref) {
  final config = ref.watch(backendConfigProvider);
  final base = config.functionsBaseUri;
  final monitor = PlusConnectivityMonitor(
    client: ref.watch(httpClientProvider),
    probeUri: config.isConfigured
        ? base.replace(path: '/auth/v1/health')
        : null,
    probeHeaders: {'apikey': config.anonKey},
  );
  ref.onDispose(monitor.dispose);
  return monitor;
});

final syncEngineProvider = Provider<SyncEngine>(
  (ref) => SyncEngine(
    api: ref.watch(habitQuestApiProvider),
    service: ref.watch(habitServiceProvider),
    game: ref.watch(gameEngineProvider),
    queue: ref.watch(syncQueueProvider),
    meta: ref.watch(syncMetaProvider),
    now: ref.watch(clockProvider),
  ),
);

/// Sync status + triggers. Started by `SyncBootstrap` (in `main.dart`).
final syncControllerProvider = NotifierProvider<SyncController, SyncStatus>(
  SyncController.new,
);
