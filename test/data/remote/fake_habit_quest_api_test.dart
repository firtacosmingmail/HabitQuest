import 'package:flutter_test/flutter_test.dart';
import 'package:habit_quest/data/remote/api_exception.dart';
import 'package:habit_quest/data/remote/fake_habit_quest_api.dart';
import 'package:habit_quest/data/remote/remote_models.dart';

final t0 = DateTime.utc(2026, 10, 7, 9);

RemoteHabit habit(String id, DateTime updatedAt, {String name = 'Read'}) =>
    RemoteHabit(
      id: id,
      name: name,
      emoji: '📚',
      color: 0xFF7C4DFF,
      schedule: const {'type': 'daily'},
      createdAt: t0,
      updatedAt: updatedAt,
    );

void main() {
  late DateTime now;
  late FakeHabitQuestApi api;

  setUp(() {
    now = t0;
    api = FakeHabitQuestApi(now: () => now);
  });

  test(
    'last-write-wins: strictly newer applies, equal/older does not',
    () async {
      final v1 = habit('h1', t0);
      expect((await api.putHabit(v1)).applied, isTrue);

      final same = await api.putHabit(habit('h1', t0, name: 'Same time'));
      expect(same.applied, isFalse);
      expect(same.item.name, 'Read');

      final older = await api.putHabit(
        habit('h1', t0.subtract(const Duration(seconds: 1)), name: 'Old'),
      );
      expect(older.applied, isFalse);

      final newer = await api.putHabit(
        habit('h1', t0.add(const Duration(seconds: 1)), name: 'New'),
      );
      expect(newer.applied, isTrue);
      expect(api.habits['h1']!.name, 'New');
    },
  );

  test(
    'soft delete leaves a tombstone; stale writes cannot resurrect',
    () async {
      await api.putHabit(habit('h1', t0));
      final del = await api.deleteHabit(
        'h1',
        updatedAt: t0.add(const Duration(minutes: 1)),
      );
      expect(del.applied, isTrue);
      expect(del.item.isDeleted, isTrue);
      expect((await api.getHabit('h1'))!.isDeleted, isTrue);

      final stale = await api.putHabit(
        habit('h1', t0.add(const Duration(seconds: 30))),
      );
      expect(stale.applied, isFalse);
      expect(stale.item.isDeleted, isTrue);

      // Undelete with a newer write.
      final undelete = await api.putHabit(
        habit('h1', t0.add(const Duration(minutes: 2))),
      );
      expect(undelete.applied, isTrue);
      expect(api.habits['h1']!.isDeleted, isFalse);

      await expectLater(
        api.deleteHabit('nope', updatedAt: t0),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 404)),
      );
    },
  );

  test(
    'since returns only rows changed after the cursor, incl. tombstones',
    () async {
      await api.putHabit(habit('h1', t0));
      final first = await api.listHabits();
      expect(first.items.map((h) => h.id), ['h1']);

      now = t0.add(const Duration(minutes: 1));
      await api.putHabit(habit('h2', now));
      await api.deleteHabit('h1', updatedAt: now);
      final delta = await api.listHabits(since: first.serverTime);
      expect(delta.items.map((h) => h.id), ['h2', 'h1']);
      expect(delta.items.last.isDeleted, isTrue);

      // serverTime is 5 s behind (like the server), so an immediate pull
      // repeats the rows written within that overlap...
      final repeat = await api.listHabits(since: delta.serverTime);
      expect(repeat.items.map((h) => h.id), ['h2', 'h1']);
      expect(
        repeat.serverTime,
        now
            .subtract(FakeHabitQuestApi.serverTimeOverlap)
            .add(const Duration(milliseconds: 3)),
      );

      // ...and once the overlap has passed nothing comes back.
      now = now.add(const Duration(seconds: 10));
      final later = await api.listHabits(since: repeat.serverTime);
      expect(later.items.map((h) => h.id), ['h2', 'h1']);
      final none = await api.listHabits(since: later.serverTime);
      expect(none.items, isEmpty);
    },
  );

  test(
    'batches: at most 500 items, all-or-nothing 400 naming the index',
    () async {
      await expectLater(
        api.batchHabits([for (var i = 0; i < 501; i++) habit('h$i', t0)]),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.code, 'code', ApiException.invalidInput),
        ),
      );
      expect(api.habits, isEmpty);

      final ok = await api.batchHabits([
        for (var i = 0; i < 500; i++) habit('h$i', t0),
      ]);
      expect(ok, hasLength(500));

      await expectLater(
        api.batchHabits([
          habit('a', t0.add(const Duration(hours: 1))),
          habit('b', t0, name: '   '),
        ]),
        throwsA(
          isA<ApiException>()
              .having((e) => e.status, 'status', 400)
              .having((e) => e.message, 'message', startsWith('items[1]')),
        ),
      );
      expect(api.habits.containsKey('a'), isFalse, reason: 'nothing written');
      await expectLater(
        api.putHabit(habit('c', t0, name: 'x' * 201)),
        throwsA(isA<ApiException>().having((e) => e.status, 'status', 400)),
      );
    },
  );

  test('check-ins need their habit; batches are atomic', () async {
    final c = RemoteCheckIn(
      habitId: 'h1',
      date: DateTime(2026, 10, 7),
      completed: true,
      updatedAt: t0,
    );
    expect(c.id, 'h1_2026-10-07');
    await expectLater(
      api.putCheckIn(c),
      throwsA(
        isA<ApiException>().having((e) => e.code, 'code', 'habit_not_found'),
      ),
    );
    await api.putHabit(habit('h1', t0));
    final other = RemoteCheckIn(
      habitId: 'ghost',
      date: DateTime(2026, 10, 7),
      completed: true,
      updatedAt: t0,
    );
    await expectLater(
      api.batchCheckIns([c, other]),
      throwsA(isA<ApiException>()),
    );
    expect(api.checkIns, isEmpty);

    final res = await api.batchCheckIns([c]);
    expect(res.single.applied, isTrue);
    expect(
      (await api.listCheckIns(habitId: 'h1')).items.single.id,
      'h1_2026-10-07',
    );
    expect((await api.listCheckIns(habitId: 'h2')).items, isEmpty);
  });

  test('game state LWW and delete', () async {
    final s1 = RemoteGameState(state: const {'xp': 10}, updatedAt: t0);
    expect((await api.putGameState(s1)).applied, isTrue);
    final stale = await api.putGameState(
      RemoteGameState(state: const {'xp': 5}, updatedAt: t0),
    );
    expect(stale.applied, isFalse);
    expect(stale.item.state, {'xp': 10});
    expect((await api.getGameState()).item, s1);
    await api.deleteGameState();
    expect((await api.getGameState()).item, isNull);
  });

  test('offline and injected failures', () async {
    api.offline = true;
    await expectLater(
      api.listHabits(),
      throwsA(isA<ApiException>().having((e) => e.isNetwork, 'net', true)),
    );
    api.offline = false;
    api.failNextWith = const ApiException(
      status: 500,
      code: 'internal_error',
      message: 'boom',
    );
    await expectLater(api.listHabits(), throwsA(isA<ApiException>()));
    expect((await api.listHabits()).items, isEmpty);
    expect(api.calls, ['GET habits', 'GET habits', 'GET habits']);
  });
}
