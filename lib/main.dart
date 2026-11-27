import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_ce_flutter/hive_ce_flutter.dart';

import 'app.dart';
import 'data/repositories/hive_habit_repository.dart';
import 'data/sync/string_store.dart';
import 'data/sync/sync_meta.dart';
import 'data/sync/sync_queue.dart';
import 'domain/providers.dart';
import 'features/ads/ads_bootstrap.dart';
import 'features/game/game_providers.dart';
import 'features/game/game_repository.dart';
import 'features/notifications/notifications_bootstrap.dart';
import 'features/projects/data/hive_project_repository.dart';
import 'features/projects/data/projects_storage_migration.dart';
import 'features/projects/notifications/project_notification_settings.dart';
import 'features/projects/notifications/project_notifications_providers.dart';
import 'features/projects/projects_providers.dart';
import 'features/quotes/quotes_providers.dart';
import 'features/sync/sync_bootstrap.dart';
import 'features/sync/sync_providers.dart';
import 'features/widgets_bridge/widget_bridge_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  // The persistent sync queue records every local write of the
  // repositories (see docs in README "Sync").
  final queueStore = await HiveStringStore.open(SyncQueue.boxName);
  final metaStore = await HiveStringStore.open(SyncMeta.boxName);
  // One-time conversion of pre-rework projects data (targets → goals,
  // target time blocks → project time blocks), including the pending sync
  // entries and the pull cursors. Must run before the queue loads.
  await migrateHiveProjectsStorage(syncQueue: queueStore, syncMeta: metaStore);
  final queue = SyncQueue(queueStore);
  final meta = SyncMeta(metaStore);
  final repository = await HiveHabitRepository.open(recorder: queue);
  final gameRepository = await HiveGameRepository.open(recorder: queue);
  // Projects (docs/PROJECTS.md), synced like habits.
  final projectRepository = await HiveProjectRepository.open(recorder: queue);
  // Projects notification toggles (device-local, Settings screen).
  final projectNotificationSettings = ProjectNotificationSettingsStore(
    await HiveStringStore.open(ProjectNotificationSettingsStore.boxName),
  );
  // Today's quote and the saved quotes, for offline use.
  final quotesCache = QuotesCache(
    await HiveStringStore.open(QuotesCache.boxName),
  );

  runApp(
    ProviderScope(
      overrides: [
        habitRepositoryProvider.overrideWithValue(repository),
        gameRepositoryProvider.overrideWithValue(gameRepository),
        projectRepositoryProvider.overrideWithValue(projectRepository),
        syncQueueProvider.overrideWithValue(queue),
        syncMetaProvider.overrideWithValue(meta),
        quotesCacheProvider.overrideWithValue(quotesCache),
        projectNotificationSettingsStoreProvider
            .overrideWithValue(projectNotificationSettings),
      ],
      // Home-screen widgets: snapshot writer + queued widget check-offs
      // (no-op on web; see docs/WIDGETS.md).
      child: const WidgetBridgeBootstrap(
        child: NotificationsBootstrap(
          child: SyncBootstrap(child: AdsBootstrap(child: HabitQuestApp())),
        ),
      ),
    ),
  );
}
