import 'package:fake_async/fake_async.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_auth_api.dart';
import 'package:habit_quest/data/remote/fake_habit_quest_api.dart';
import 'package:habit_quest/data/repositories/in_memory_habit_repository.dart';
import 'package:habit_quest/data/sync/string_store.dart';
import 'package:habit_quest/data/sync/sync_meta.dart';
import 'package:habit_quest/data/sync/sync_queue.dart';
import 'package:habit_quest/domain/providers.dart';
import 'package:habit_quest/features/auth/auth_providers.dart';
import 'package:habit_quest/features/auth/session_store.dart';
import 'package:habit_quest/features/sync/connectivity.dart';
import 'package:habit_quest/features/sync/sync_providers.dart';

import '../../helpers/test_app.dart';

void main() {
  late FakeHabitQuestApi server;
  late FakeConnectivityMonitor connectivity;
  late SyncQueue queue;

  final now = DateTime(2026, 1, 5, 10);

  ProviderContainer make({bool signedIn = true}) {
    server = FakeHabitQuestApi();
    connectivity = FakeConnectivityMonitor();
    queue = SyncQueue(MemoryStringStore());
    final container = ProviderContainer(
      overrides: [
        if (signedIn)
          ...signedInOverrides()
        else ...[
          authApiProvider.overrideWithValue(FakeAuthApi()),
          sessionStoreProvider.overrideWithValue(InMemorySessionStore()),
        ],
        habitRepositoryProvider.overrideWithValue(
          InMemoryHabitRepository(recorder: queue),
        ),
        clockProvider.overrideWithValue(() => now),
        syncQueueProvider.overrideWithValue(queue),
        syncMetaProvider.overrideWithValue(SyncMeta(MemoryStringStore())),
        connectivityMonitorProvider.overrideWithValue(connectivity),
        habitQuestApiProvider.overrideWithValue(server),
      ],
    );
    addTearDown(container.dispose);
    // Build the engine graph up front (as app.dart does at launch).
    container.read(syncEngineProvider);
    return container;
  }

  SyncStatus status(ProviderContainer c) => c.read(syncControllerProvider);

  test('syncs at start when signed in', () {
    fakeAsync((async) {
      final c = make();
      c
          .read(habitServiceProvider)
          .createHabit(name: 'Read', emoji: '📚', colorValue: 1);
      async.flushMicrotasks();
      c.read(syncControllerProvider.notifier).start();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(server.habits, hasLength(1));
      expect(status(c).phase, SyncPhase.synced);
      expect(status(c).lastSyncedAt, now);
      expect(status(c).pending, 0);
    });
  });

  test('never syncs while signed out', () {
    fakeAsync((async) {
      final c = make(signedIn: false);
      c.read(syncControllerProvider.notifier).start();
      async.elapse(const Duration(minutes: 10));
      c.read(syncControllerProvider.notifier).syncNow();
      async.flushMicrotasks();
      expect(server.calls, isEmpty);
      expect(status(c).phase, SyncPhase.signedOut);
    });
  });

  test('offline → online: waits, then syncs when connectivity returns', () {
    fakeAsync((async) {
      final c = make();
      connectivity.online = false;
      c.read(syncControllerProvider.notifier).start();
      async.elapse(Duration.zero);
      expect(status(c).phase, SyncPhase.offline);
      expect(server.calls, isEmpty);

      connectivity.online = true;
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(server.calls, isNotEmpty);
      expect(status(c).phase, SyncPhase.synced);
    });
  });

  test('local changes trigger a debounced sync', () {
    fakeAsync((async) {
      final c = make();
      c.read(syncControllerProvider.notifier).start();
      async.elapse(Duration.zero);
      final before = server.calls.length;

      final service = c.read(habitServiceProvider);
      service.createHabit(name: 'Read', emoji: '📚', colorValue: 1);
      async.flushMicrotasks();
      expect(status(c).pending, greaterThan(0));
      async.elapse(SyncController.debounce ~/ 2);
      expect(server.calls.length, before, reason: 'still debouncing');
      async.elapse(SyncController.debounce);
      async.flushMicrotasks();
      expect(server.habits, hasLength(1));
      expect(status(c).pending, 0);
    });
  });

  test('network errors retry with exponential backoff', () {
    expect(SyncController.backoffFor(1), SyncController.minBackoff);
    expect(SyncController.backoffFor(2), SyncController.minBackoff * 2);
    expect(SyncController.backoffFor(30), SyncController.maxBackoff);

    fakeAsync((async) {
      final c = make();
      server.offline = true; // the interface is up but the API is not
      c.read(syncControllerProvider.notifier).start();
      async.elapse(Duration.zero);
      expect(status(c).phase, SyncPhase.offline);

      server.offline = false;
      async.elapse(SyncController.minBackoff);
      async.flushMicrotasks();
      expect(status(c).phase, SyncPhase.synced);
    });
  });

  test('a session error stops without a retry loop', () {
    fakeAsync((async) {
      final c = make();
      server.failNextWith = const ApiException(
        status: 401,
        code: ApiException.unauthorized,
        message: 'expired',
      );
      c.read(syncControllerProvider.notifier).syncNow();
      async.flushMicrotasks();
      expect(status(c).phase, SyncPhase.error);
      expect(status(c).message, 'Please log in again');
      final calls = server.calls.length;
      async.elapse(const Duration(minutes: 30));
      expect(server.calls.length, calls);
    });
  });

  test('429 rate_limited backs off: local changes wait for the retry', () {
    fakeAsync((async) {
      final c = make();
      c.read(syncControllerProvider.notifier).start();
      async.elapse(Duration.zero);
      async.flushMicrotasks();
      expect(status(c).phase, SyncPhase.synced);

      server.failNextWith = const ApiException(
        status: 429,
        code: ApiException.rateLimited,
        message: 'Too many requests',
      );
      c
          .read(habitServiceProvider)
          .createHabit(name: 'Read', emoji: '📚', colorValue: 1);
      async.flushMicrotasks();
      async.elapse(SyncController.debounce);
      async.flushMicrotasks();
      expect(status(c).phase, SyncPhase.error);
      expect(server.habits, isEmpty);
      final calls = server.calls.length;

      // More local changes while backing off do not trigger a run.
      c
          .read(habitServiceProvider)
          .createHabit(name: 'Walk', emoji: '🚶', colorValue: 2);
      async.flushMicrotasks();
      async.elapse(SyncController.debounce);
      expect(server.calls.length, calls, reason: 'held by the backoff');

      // The backoff retry (5 s after the failure) then syncs everything.
      async.elapse(SyncController.minBackoff);
      async.flushMicrotasks();
      expect(server.habits, hasLength(2));
      expect(status(c).phase, SyncPhase.synced);
    });
  });
}
