import '../../data/sync/sync_meta.dart';
import '../../data/sync/sync_queue.dart';
import '../../domain/habit_service.dart';
import '../game/game_engine.dart';
import '../notifications/scheduler/notification_scheduler.dart';

/// Removes everything the app keeps on the device for an account: habits
/// and check-ins, the game state, the sync queue, the sync cursors and the
/// owner marker (both in `sync_meta`), and every scheduled reminder. Used
/// after the account was deleted on the server.
class LocalDataWiper {
  final HabitService service;
  final GameEngine game;
  final SyncQueue queue;
  final SyncMeta meta;
  final NotificationScheduler scheduler;

  LocalDataWiper({
    required this.service,
    required this.game,
    required this.queue,
    required this.meta,
    required this.scheduler,
  });

  Future<void> wipe() async {
    // Announced as deletions, so the reminders of those habits are
    // cancelled by the notifications controller too.
    await service.clearLocalData();
    await game.resetSilently();
    // Last, so nothing recorded by the steps above survives.
    await queue.clear();
    await meta.clear();
    try {
      final pending = await scheduler.pendingIds();
      if (pending.isNotEmpty) await scheduler.cancel(pending);
    } catch (_) {
      // Notifications unavailable (e.g. permission revoked): nothing to do.
    }
  }
}
