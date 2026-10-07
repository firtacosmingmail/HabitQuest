import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/models/check_in.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_habit_quest_api.dart';
import 'package:habit_quest/data/remote/remote_models.dart';
import 'package:habit_quest/data/sync/change_recorder.dart';
import 'package:habit_quest/features/game/game_events.dart';
import 'package:habit_quest/features/game/game_rules.dart';
import 'package:habit_quest/features/game/game_state.dart';
import 'package:habit_quest/features/sync/remote_mapping.dart';
import 'package:habit_quest/features/sync/sync_engine.dart';

import '../../helpers/fixtures.dart';
import 'sync_harness.dart';

void main() {
  late TestClock clock;
  late FakeHabitQuestApi server;

  final today = d(2026, 1, 5);
  final yesterday = d(2026, 1, 4);

  setUp(() {
    clock = TestClock();
    server = FakeHabitQuestApi();
  });

  Device device(String name) => Device(name, clock: clock, api: server);

  group('push then pull', () {
    test('a new device receives habits and check-ins', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);

      final report = await a.sync();
      expect(report.pushed, 2);
      expect(a.queue.isEmpty, isTrue);
      expect(server.habits.keys, [h.id]);
      expect(server.checkIns.keys, [RemoteCheckIn.idFor(h.id, today)]);
      expect(server.gameState, isNotNull);

      final b = device('B');
      await b.sync();
      expect(b.repo.getHabit(h.id)!.name, 'Read');
      expect(b.repo.getHabit(h.id)!.startDate, h.startDate);
      expect(b.repo.getCompletions().isCompleted(h.id, today), isTrue);
      // Applying remote data emits no XP-awarding completion events.
      expect(b.completionEvents, isEmpty);
      expect(b.queue.isEmpty, isTrue);
    });

    test('habits are pushed before check-ins, through batch endpoints',
        () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await a.sync();
      final posts = server.calls.where((c) => c.startsWith('POST')).toList();
      expect(posts, ['POST habits/batch', 'POST check-ins/batch']);
    });

    test('the habit round-trips through the contract mapping', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      final back = habitFromRemote(habitToRemote(h));
      expect(back, h);
      expect(back.updatedAt, h.updatedAt);
    });
  });

  group('queue', () {
    test('coalesces per entity: the latest local change wins', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.service.updateHabit(h.copyWith(name: 'Read more'));
      await a.toggle(h.id, today);
      await a.toggle(h.id, today);
      await a.toggle(h.id, today);
      final types = a.queue.entries.map((e) => e.type).toList();
      expect(types.where((t) => t == SyncEntityType.habit), hasLength(1));
      expect(types.where((t) => t == SyncEntityType.checkIn), hasLength(1));

      await a.sync();
      expect(server.habits[h.id]!.name, 'Read more');
      expect(server.checkIns.values.single.completed, isTrue);
    });

    test('a change made during a push stays queued', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      final entry = a.queue.entryFor(SyncEntityType.habit, h.id)!;
      await a.service.updateHabit(h.copyWith(name: 'Newer'));
      await a.queue.ack(entry); // stale ack
      expect(a.queue.entryFor(SyncEntityType.habit, h.id), isNotNull);
    });

    test('un-checking syncs as completed: false', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await a.sync();
      await a.check(h.id, today, false);
      await a.sync();
      expect(server.checkIns.values.single.completed, isFalse);

      final b = device('B');
      await b.sync();
      expect(b.repo.getCompletions().isCompleted(h.id, today), isFalse);
    });
  });

  group('last-write-wins', () {
    test('a newer remote edit replaces an older local one', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      await a.sync();
      await b.sync();

      // B edits offline first, A edits later and syncs first.
      clock.advance();
      await b.service.updateHabit(b.repo.getHabit(h.id)!.copyWith(name: 'B'));
      clock.advance();
      await a.service.updateHabit(a.repo.getHabit(h.id)!.copyWith(name: 'A'));
      await a.sync();
      await b.sync(); // B's older push loses, the pull brings A's edit

      expect(server.habits[h.id]!.name, 'A');
      expect(b.repo.getHabit(h.id)!.name, 'A');
      expect(b.queue.isEmpty, isTrue);
    });

    test('a newer local edit wins over an older remote one', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      await a.sync();
      await b.sync();

      clock.advance();
      await a.service.updateHabit(a.repo.getHabit(h.id)!.copyWith(name: 'A'));
      clock.advance();
      await b.service.updateHabit(b.repo.getHabit(h.id)!.copyWith(name: 'B'));
      await a.sync();
      await b.sync();
      await a.sync();

      expect(server.habits[h.id]!.name, 'B');
      expect(a.repo.getHabit(h.id)!.name, 'B');
    });

    test('equal updatedAt keeps the local copy', () async {
      final a = device('A');
      final h = await a.createHabit('Local');
      await a.sync();
      server.seedHabit(habitToRemote(h.copyWith(name: 'Remote twin')));
      await a.sync();
      expect(a.repo.getHabit(h.id)!.name, 'Local');
    });

    test('check-ins: the newest toggle wins across devices', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      await a.sync();
      await b.sync();
      await a.check(h.id, yesterday); // older
      await b.check(h.id, yesterday); // newer (also done)
      await b.check(h.id, yesterday, false); // newest: undone
      await a.sync();
      await b.sync();
      await a.sync();
      expect(a.repo.getCompletions().isCompleted(h.id, yesterday), isFalse);
      expect(b.repo.getCompletions().isCompleted(h.id, yesterday), isFalse);
    });
  });

  group('tombstones', () {
    test('a deletion syncs and hides the habit and its check-ins', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await a.sync();
      await b.sync();
      expect(b.repo.getHabits(), hasLength(1));

      await a.service.deleteHabit(h.id);
      expect(a.repo.getHabit(h.id), isNull);
      expect(a.repo.getHabitRecord(h.id)!.isDeleted, isTrue,
          reason: 'kept as a tombstone until pushed');
      await a.sync();
      expect(server.habits[h.id]!.isDeleted, isTrue);

      final removed = <String>[];
      b.service.remoteHabitChanges.listen((e) => removed.add(e.habit.id));
      await b.sync();
      expect(b.repo.getHabits(), isEmpty);
      expect(b.repo.getCompletions().totalFor(h.id), 0);
      expect(removed, [h.id]);
      // The check-in's XP is gone on both devices, never celebrated on B.
      expect(b.xp, 0);
      expect(a.xp, 0);
      expect(b.gameEvents.whereType<XpLost>(), isEmpty);
    });
  });

  group('offline → online', () {
    test('changes wait in the queue and go out once online', () async {
      final a = device('A');
      server.offline = true;
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await expectLater(
        a.sync(),
        throwsA(isA<ApiException>().having((e) => e.isNetwork, 'net', true)),
      );
      expect(a.queue.length, greaterThanOrEqualTo(2));
      expect(a.repo.getHabit(h.id), isNotNull, reason: 'UI never waits');

      server.offline = false;
      await a.sync();
      expect(a.queue.isEmpty, isTrue);
      expect(server.habits, contains(h.id));
    });

    test('a failure mid-run keeps everything not acknowledged', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      // Habits go through, then the check-in batch hits a network error.
      server.failNextWith = null;
      final api = _FailCheckInsOnce(server);
      a.api = api;
      await expectLater(a.sync(), throwsA(isA<ApiException>()));
      expect(a.queue.entryFor(SyncEntityType.habit, h.id), isNull);
      expect(
        a.queue.entryFor(SyncEntityType.checkIn, CheckIn.keyFor(h.id, today)),
        isNotNull,
      );
      await a.sync();
      expect(a.queue.isEmpty, isTrue);
    });
  });

  group('error isolation', () {
    test('a refused entity is kept and reported, the rest syncs', () async {
      final picky = PickyApi();
      final a = Device('A', clock: clock, api: picky);
      final good = await a.createHabit('Good');
      final bad = await a.createHabit('BAD');
      await a.check(good.id, today);
      await a.check(bad.id, today);

      final report = await a.sync();
      expect(picky.habits.keys, [good.id]);
      expect(picky.checkIns.keys, [RemoteCheckIn.idFor(good.id, today)]);
      expect(report.issues.map((i) => i.id), containsAll([
        bad.id,
        CheckIn.keyFor(bad.id, today),
      ]));
      expect(a.queue.failed, hasLength(2));
      expect(a.queue.entryFor(SyncEntityType.habit, bad.id)!.lastError,
          contains('invalid_input'));

      // Fixing the habit clears its error and lets its check-in through.
      await a.service.updateHabit(a.repo.getHabit(bad.id)!.copyWith(
        name: 'Fixed',
      ));
      final again = await a.sync();
      expect(again.issues, isEmpty);
      expect(a.queue.isEmpty, isTrue);
      expect(picky.checkIns, hasLength(2));
    });
  });

  group('cursor', () {
    test('pulls only what changed since the last serverTime', () async {
      final a = device('A');
      await a.createHabit('Read');
      await a.sync();
      expect(a.meta.habitsCursor('u1'), isNotNull);
      expect(a.meta.checkInsCursor('u1'), isNotNull);

      final quiet = await a.sync();
      expect(quiet.pulledHabits, 0);

      final other = habitToRemote(
        (await device('B').createHabit('Remote')),
      );
      server.seedHabit(other);
      final next = await a.sync();
      expect(next.pulledHabits, 1);
      expect(a.repo.getHabit(other.id), isNotNull);
      expect(a.meta.lastSyncedAt('u1'), isNotNull);
    });

    test('cursors are per user', () async {
      final a = device('A');
      await a.sync(user: 'u1');
      expect(a.meta.habitsCursor('u1'), isNotNull);
      expect(a.meta.habitsCursor('u2'), isNull);
    });
  });

  group('XP is never counted twice', () {
    int singleCheckInXp() => GameRules.checkInReward(1) + GameRules.perfectDayXp;

    test('device A checks in offline and syncs; B pulls it: no extra XP',
        () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.sync();
      final b = device('B');
      await b.sync();

      server.offline = true;
      await a.check(h.id, today);
      expect(a.xp, singleCheckInXp());
      server.offline = false;
      await a.sync();

      await b.sync();
      expect(b.xp, a.xp);
      expect(b.repo.getCompletions().isCompleted(h.id, today), isTrue);
      expect(b.xpGainedEvents(), 0, reason: 'remote awards are not celebrated');

      // More syncs in any order change nothing.
      await b.sync();
      await a.sync();
      await b.sync();
      expect(a.xp, singleCheckInXp());
      expect(b.xp, singleCheckInXp());
      expect(server.gameState!.state['checkIns'], hasLength(1));
    });

    test('B pulls the check-in before A pushed its game state', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.sync();
      final b = device('B');
      await b.sync();

      await a.check(h.id, today);
      // Simulate A's game-state upload failing after its check-in went out.
      a.api = _FailGameStatePut(server);
      await expectLater(a.sync(), throwsA(isA<ApiException>()));

      await b.sync(); // grants the pulled check-in silently, once
      expect(b.xp, singleCheckInXp());
      expect(b.xpGainedEvents(), 0);

      a.api = server;
      await a.sync();
      await b.sync();
      expect(a.xp, singleCheckInXp());
      expect(b.xp, singleCheckInXp());
    });

    test('toggling on/off/on across a sync does not farm XP', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await a.sync();
      await b.sync();
      expect(b.xp, singleCheckInXp());

      // B: off then on again, then sync; A toggles too.
      await b.toggle(h.id, today);
      expect(b.xp, 0);
      await b.toggle(h.id, today);
      await b.sync();
      await a.toggle(h.id, today);
      await a.toggle(h.id, today);
      await a.sync();
      await b.sync();
      await a.sync();

      expect(a.xp, singleCheckInXp());
      expect(b.xp, singleCheckInXp());
      expect(a.repo.getCompletions().isCompleted(h.id, today), isTrue);
    });

    test('an un-check on another device removes the XP everywhere', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await a.sync();
      await b.sync();
      await b.check(h.id, today, false);
      await b.sync();
      await a.sync();
      expect(a.xp, 0);
      expect(b.xp, 0);
      expect(a.gameEvents.whereType<XpLost>(), isEmpty,
          reason: 'remote changes never fire game events');
    });

    test('two devices awarding different days both keep their XP', () async {
      final a = device('A');
      final b = device('B');
      final h = await a.createHabit('Read');
      // Created yesterday so both days are scheduled.
      await a.service.updateHabit(h.copyWith(startDate: yesterday));
      await a.sync();
      await b.sync();

      server.offline = true;
      await a.check(h.id, yesterday);
      await b.check(h.id, today);
      final xpA = a.xp;
      final xpB = b.xp;
      server.offline = false;

      await a.sync();
      await b.sync();
      await a.sync();

      expect(a.xp, b.xp);
      expect(a.xp, greaterThanOrEqualTo(xpA + xpB));
      final ledger = a.game.state.checkInLedger.keys;
      expect(ledger, containsAll([
        GameState.checkInKey(h.id, yesterday),
        GameState.checkInKey(h.id, today),
      ]));
      expect(ledger, hasLength(2));
    });

    test('achievements merge as a union keeping the earliest unlock',
        () async {
      final early = DateTime.utc(2025, 1, 1);
      final late = DateTime.utc(2026, 1, 1);
      final merged = GameState.merge(
        GameState(
          unlocked: {'first_habit': late},
          checkInLedger: const {'h|2026-01-01': 11},
          maxLevelReached: 2,
        ),
        GameState(
          unlocked: {'first_habit': early, 'first_checkin': late},
          checkInLedger: const {'h|2026-01-01': 11, 'h|2026-01-02': 12},
          perfectDayLedger: const {'2026-01-02': 25},
          bestStreakEver: 3,
        ),
      );
      expect(merged.unlocked, {'first_habit': early, 'first_checkin': late});
      expect(merged.xp, 11 + 12 + 25);
      expect(merged.maxLevelReached, 2);
      expect(merged.bestStreakEver, 3);
    });

    test('remote level-ups and achievements are not celebrated', () async {
      final a = device('A');
      final h = await a.createHabit('Read');
      await a.check(h.id, today);
      await a.sync();
      final b = device('B');
      await b.sync();
      expect(b.game.state.unlocked.keys, containsAll(a.game.state.unlocked.keys));
      expect(b.gameEvents, isEmpty);
    });
  });

  group('account switch', () {
    test('first login adopts data created before any account', () async {
      final a = device('A');
      final h = await a.createHabit('Offline habit');
      await a.check(h.id, today);
      // Simulate pre-sync data: nothing queued.
      await a.queue.clear();

      expect(await a.engine.prepareForUser('u1'), AccountChange.claimed);
      await a.engine.sync('u1');
      expect(server.habits, contains(h.id));
      expect(server.checkIns, hasLength(1));
      expect(server.gameState, isNotNull);
    });

    test('a different user never receives the previous user\'s data',
        () async {
      final serverU2 = FakeHabitQuestApi();
      final a = device('A');
      final h = await a.createHabit('Mine');
      await a.check(h.id, today);
      await a.sync(user: 'u1');
      await a.createHabit('Unsynced');

      serverU2.seedHabit(habitToRemote(
        (await device('X').createHabit('Theirs')),
      ));
      a.api = serverU2;
      expect(await a.engine.prepareForUser('u2'), AccountChange.switched);
      await a.engine.sync('u2');

      expect(serverU2.habits.values.map((r) => r.name), ['Theirs']);
      expect(a.repo.getHabits().map((x) => x.name), ['Theirs']);
      expect(a.xp, 0);
      expect(a.meta.ownerUserId, 'u2');
    });

    test('the same user signing in again keeps local data', () async {
      final a = device('A');
      await a.createHabit('Mine');
      await a.sync(user: 'u1');
      expect(await a.engine.prepareForUser('u1'), AccountChange.none);
      expect(a.repo.getHabits(), hasLength(1));
    });
  });
}

/// Delegates to [inner] but fails the first check-in batch with a network
/// error.
class _FailCheckInsOnce extends _Delegating {
  bool _failed = false;

  _FailCheckInsOnce(super.inner);

  @override
  Future<List<BatchItemResult<RemoteCheckIn>>> batchCheckIns(
    List<RemoteCheckIn> checkIns,
  ) {
    if (!_failed) {
      _failed = true;
      throw const ApiException(code: ApiException.networkError, message: 'x');
    }
    return inner.batchCheckIns(checkIns);
  }
}

class _FailGameStatePut extends _Delegating {
  _FailGameStatePut(super.inner);

  @override
  Future<WriteResult<RemoteGameState>> putGameState(RemoteGameState state) =>
      throw const ApiException(code: ApiException.networkError, message: 'x');
}

class _Delegating extends FakeHabitQuestApi {
  final FakeHabitQuestApi inner;

  _Delegating(this.inner);

  @override
  Future<DeltaPage<RemoteHabit>> listHabits({DateTime? since}) =>
      inner.listHabits(since: since);

  @override
  Future<List<BatchItemResult<RemoteHabit>>> batchHabits(
    List<RemoteHabit> habits,
  ) =>
      inner.batchHabits(habits);

  @override
  Future<WriteResult<RemoteHabit>> putHabit(RemoteHabit habit) =>
      inner.putHabit(habit);

  @override
  Future<DeltaPage<RemoteCheckIn>> listCheckIns({
    DateTime? since,
    String? habitId,
  }) =>
      inner.listCheckIns(since: since, habitId: habitId);

  @override
  Future<List<BatchItemResult<RemoteCheckIn>>> batchCheckIns(
    List<RemoteCheckIn> checkIns,
  ) =>
      inner.batchCheckIns(checkIns);

  @override
  Future<WriteResult<RemoteCheckIn>> putCheckIn(RemoteCheckIn checkIn) =>
      inner.putCheckIn(checkIn);

  @override
  Future<GameStateSnapshot> getGameState() => inner.getGameState();

  @override
  Future<WriteResult<RemoteGameState>> putGameState(RemoteGameState state) =>
      inner.putGameState(state);
}
